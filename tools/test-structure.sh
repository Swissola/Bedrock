#!/usr/bin/env bash
# Repo-wide checks that no single hook's suite can make: that every script is valid, that
# every hook has a test suite, that the suites are wired into the runner, CI and the docs,
# and that nothing in the test scripts will break on macOS's old bash.
# Run: bash tools/test-structure.sh
#
# The rule behind most of this: a hook without a test suite, or a suite nobody runs, is a
# gap that grows quietly. These checks make adding either one a visible, failing step.

set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
HOOKS_DIR="$TOOLS_DIR/hook-templates"
PASS=0
FAIL=0
SKIPS=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" = "$actual" ]]; then echo "PASS: $desc"; PASS=$((PASS + 1))
  else echo "FAIL: $desc (expected [$expected], got [$actual])"; FAIL=$((FAIL + 1)); fi
  return 0
}
skip() { echo "SKIP: $1"; SKIPS=$((SKIPS + 1)); return 0; }

# Files that are hooks (everything in hook-templates except the test scripts).
hook_names() {
  local f
  for f in "$HOOKS_DIR"/*; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in test-*) ;; *) basename "$f" ;; esac
  done
  return 0
}

# Every suite in the repo: the files named test-* under tools/.
suite_files() {
  find "$TOOLS_DIR" -type f -name 'test-*' | sort
  return 0
}

shell_scripts() {
  local f
  for f in "$TOOLS_DIR"/*.sh "$HOOKS_DIR"/*; do
    [[ -f "$f" ]] || continue
    head -n1 "$f" 2>/dev/null | grep -q '^#!.*\(ba\)\?sh' && echo "$f"
  done
  return 0
}

rel() { echo "${1#"$ROOT"/}"; return 0; }

# --- every hook has a suite -----------------------------------------------------

test_every_hook_has_its_own_test_suite() {
  local h
  for h in $(hook_names); do
    assert_eq "hook '$h' has tools/hook-templates/test-$h.sh" "yes" "$([[ -f "$HOOKS_DIR/test-$h.sh" ]] && echo yes || echo no)"
  done
  return 0
}

test_every_suite_belongs_to_something_real() {
  local s name target
  for s in $(find "$HOOKS_DIR" -maxdepth 1 -type f -name 'test-*.sh' | sort); do
    name=$(basename "$s" .sh); target="${name#test-}"
    assert_eq "suite $(basename "$s") tests an existing hook ($target)" "yes" "$([[ -f "$HOOKS_DIR/$target" ]] && echo yes || echo no)"
  done
  return 0
}

test_the_installer_installs_exactly_the_hooks_that_exist() {
  local listed h missing=""
  listed=$(grep -E '^HOOKS=\(' "$TOOLS_DIR/install-claude-config.sh" | sed -E 's/^HOOKS=\((.*)\)/\1/')
  for h in $(hook_names); do
    case " $listed " in *" $h "*) ;; *) missing="$missing $h" ;; esac
  done
  assert_eq "every hook template is on the installer's HOOKS list (missing:${missing:- none})" "" "${missing# }"
  for h in $listed; do
    assert_eq "installer HOOKS entry '$h' exists in hook-templates" "yes" "$([[ -f "$HOOKS_DIR/$h" ]] && echo yes || echo no)"
  done
  return 0
}

# --- the suites are wired in --------------------------------------------------------

test_every_suite_is_run_by_the_runner_and_by_ci() {
  local s b
  for s in $(suite_files); do
    b=$(basename "$s")
    assert_eq "run-all-tests.sh runs $b" "yes" "$(grep -qF "$b" "$TOOLS_DIR/run-all-tests.sh" && echo yes || echo no)"
    # the PowerShell suite runs on its own Windows job, the rest on the shell matrix
    assert_eq "a CI workflow runs $b" "yes" "$(grep -rqF "$b" "$ROOT/.github/workflows" && echo yes || echo no)"
  done
  return 0
}

test_every_suite_is_described_in_the_testing_doc() {
  local s b
  for s in $(suite_files); do
    b=$(basename "$s")
    assert_eq "docs/testing.md describes $b" "yes" "$(grep -qF "$b" "$ROOT/docs/testing.md" 2>/dev/null && echo yes || echo no)"
  done
  return 0
}

# --- the scripts themselves are sound ---------------------------------------------------

test_every_shell_script_parses() {
  local f
  for f in $(shell_scripts); do
    assert_eq "bash -n $(rel "$f")" "ok" "$(bash -n "$f" 2>/dev/null && echo ok || echo "syntax error")"
  done
  return 0
}

test_every_script_has_a_shebang_and_lf_line_endings() {
  local f
  for f in $(shell_scripts); do
    assert_eq "$(rel "$f") has no carriage returns" "0" "$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')"
  done
  return 0
}

test_scripts_are_executable_in_git() {
  local f mode
  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then skip "executable bits (not a git checkout)"; return 0; fi
  for f in $(shell_scripts); do
    mode=$(git -C "$ROOT" ls-files -s -- "$f" | cut -d' ' -f1)
    if [[ -z "$mode" ]]; then skip "executable bit of $(rel "$f") (not tracked yet, git add it first)"; continue; fi
    assert_eq "$(rel "$f") is tracked as executable (100755)" "100755" "$mode"
  done
  return 0
}

test_gitattributes_forces_lf_for_every_script() {
  local f attr
  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then skip ".gitattributes eol (not a git checkout)"; return 0; fi
  for f in $(shell_scripts) "$TOOLS_DIR"/command-templates/test/*.mjs; do
    attr=$(git -C "$ROOT" check-attr eol -- "$f" | sed 's/.*: //')
    assert_eq "$(rel "$f") has eol=lf in .gitattributes" "lf" "$attr"
  done
  return 0
}

test_javascript_files_parse() {
  local f
  if ! command -v node >/dev/null 2>&1; then skip "node --check (node not installed)"; return 0; fi
  for f in "$TOOLS_DIR"/command-templates/test/*.mjs; do
    assert_eq "node --check $(rel "$f")" "ok" "$(node --check "$f" 2>/dev/null && echo ok || echo "syntax error")"
  done
  return 0
}

test_powershell_scripts_parse() {
  # SAFETY: this must only PARSE the scripts, never run them. (An earlier version passed the
  # path after `-Command`, which PowerShell appends to the command and executes: it ran the
  # installer against the real ~/.claude.) The parser lives in a small temp script run with
  # -File, and the target is only ever a parameter handed to Parser.ParseFile.
  local f ps checker target
  ps=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)
  if [[ -z "$ps" ]]; then skip "PowerShell parse check (no pwsh or powershell on PATH)"; return 0; fi
  checker=$(mktemp)
  mv "$checker" "$checker.ps1"; checker="$checker.ps1"
  cat > "$checker" <<'PSEOF'
param([string]$Path)
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
if ($errors.Count -eq 0) { 'ok' } else { "$($errors.Count) parse error(s): $($errors[0].Message)" }
PSEOF
  for f in "$TOOLS_DIR"/*.ps1; do
    target="$f"; command -v cygpath >/dev/null 2>&1 && target=$(cygpath -w "$f")
    assert_eq "$(rel "$f") parses" "ok" "$("$ps" -NoProfile -NonInteractive -File "$(command -v cygpath >/dev/null 2>&1 && cygpath -w "$checker" || echo "$checker")" "$target" 2>&1 | tr -d '\r' | tail -n 1)"
  done
  rm -f "$checker"
  return 0
}

test_the_example_wiki_config_is_valid_json_with_the_keys_the_script_reads() {
  local f="$TOOLS_DIR/wiki-publish.example.json"
  if ! command -v node >/dev/null 2>&1; then skip "wiki example JSON check (node not installed)"; return 0; fi
  assert_eq "wiki-publish.example.json is valid JSON with space and documents[].source" "ok" \
    "$(node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(c.space && Array.isArray(c.documents) && c.documents.every(d=>d.source)?0:1)' "$f" 2>/dev/null && echo ok || echo bad)"
  return 0
}

test_every_command_template_carries_a_version_stamp() {
  local f
  for f in "$TOOLS_DIR"/command-templates/*.md; do
    assert_eq "$(rel "$f") has a 'bedrock-template: <name>, version N' stamp" "yes" "$(grep -qE 'bedrock-template: [a-z-]+, version [0-9]+' "$f" && echo yes || echo no)"
  done
  return 0
}

# --- portability: the CI matrix includes macOS, whose /bin/bash is 3.2 -------------------

test_test_scripts_avoid_bash_4_only_features() {
  local f hits
  for f in "$HOOKS_DIR"/test-*.sh "$TOOLS_DIR"/test-*.sh; do
    [[ -f "$f" ]] || continue
    [[ "$f" = "$TOOLS_DIR/test-structure.sh" ]] && continue
    hits=$(grep -nE '(^|[^a-zA-Z_])(mapfile|readarray)([^a-zA-Z_]|$)|declare -A|local -A|\$\{[A-Za-z_]+(,,|\^\^)\}|[|]&|&>>|coproc|;;&|;&' "$f" | grep -v '^[0-9]*:[[:space:]]*#' || true)
    assert_eq "$(rel "$f") uses no bash 4+ only syntax" "" "$hits"
  done
  return 0
}

test_test_scripts_avoid_gnu_only_commands_without_a_fallback() {
  local f hits
  for f in "$HOOKS_DIR"/test-*.sh "$TOOLS_DIR"/test-*.sh; do
    [[ -f "$f" ]] || continue
    [[ "$f" = "$TOOLS_DIR/test-structure.sh" ]] && continue
    hits=$(grep -nE 'touch -d |readlink -f|date -d [^|]*$|sed -i [^.]' "$f" | grep -vE '\|\||^[0-9]+:[[:space:]]*#' || true)
    assert_eq "$(rel "$f") has no GNU-only touch -d / readlink -f / date -d / sed -i without a fallback" "" "$hits"
  done
  return 0
}

test_every_suite_cleans_up_after_itself_with_a_trap() {
  local f
  for f in "$HOOKS_DIR"/test-pre-push.sh "$HOOKS_DIR"/test-session-start-vault-check.sh "$HOOKS_DIR"/test-pre-commit.sh "$HOOKS_DIR"/test-post-merge.sh "$HOOKS_DIR"/test-session-start-vault-context.sh "$TOOLS_DIR"/test-setup-mcp.sh; do
    assert_eq "$(rel "$f") removes its fixtures from a trap, not only at the end of each test" "yes" "$(grep -qE '^trap cleanup EXIT' "$f" && echo yes || echo no)"
  done
  return 0
}

# --- mutation checks: configuration and workflow -------------------------------------------------

test_mutation_config_is_well_formed_and_every_mutant_applies() {
  local f="$TOOLS_DIR/mutation/mutants.txt" bad out
  assert_eq "tools/mutation/mutants.txt exists" "yes" "$([[ -f "$f" ]] && echo yes || echo no)"
  bad=$(grep -v '^[[:space:]]*\(#.*\)\?$' "$f" | awk -F'@@' 'NF != 5 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" { print NR": "$0 }')
  assert_eq "every mutant line has the five @@-separated fields" "" "$bad"
  assert_eq "mutant names are unique" "" "$(grep -v '^[[:space:]]*\(#.*\)\?$' "$f" | awk -F'@@' '{ print $2 }' | sort | uniq -d)"
  out=$(bash "$TOOLS_DIR/run-mutation-tests.sh" --check-applies 2>&1 | grep -v '^ok ' || true)
  assert_eq "every mutant changes its target, leaves valid bash, and has a suite" "$(echo "$out" | grep -c ' checked, 0 broken')" "1"
  return 0
}

test_the_manual_workflow_offers_exactly_the_mutation_groups() {
  local wf="$ROOT/.github/workflows/mutation-tests.yml" in_file in_wf
  in_file=$(bash "$TOOLS_DIR/run-mutation-tests.sh" --list | awk '{ print $1 }' | sort | tr '\n' ' ')
  in_wf=$(awk '/^      hook:/ { on = 1 } /^      jobs_per_group:/ { on = 0 } on && /^          - / { print $2 }' "$wf" | grep -v '^all$' | sort | tr '\n' ' ')
  assert_eq "the workflow's hook dropdown lists every group in mutants.txt, and nothing else" "$in_file" "$in_wf"
  assert_eq "the mutation workflow can only be started by hand (workflow_dispatch)" "1" "$(awk '/^on:/ { on = 1; next } /^[a-z]/ { on = 0 } on && /^  [a-z_]+:/ { n++ } END { print n }' "$wf")"
  assert_eq "...and that one trigger is workflow_dispatch" "yes" "$(grep -qE '^  workflow_dispatch:' "$wf" && echo yes || echo no)"
  assert_eq "no push, pull_request or schedule trigger" "no" "$(grep -qE '^  (push|pull_request|pull_request_target|schedule):' "$wf" && echo yes || echo no)"
  assert_eq "the normal test workflow does not run the mutation checks" "no" "$(grep -qF 'run-mutation-tests' "$ROOT/.github/workflows/shell-tests.yml" && echo yes || echo no)"
  assert_eq "docs/testing.md documents run-mutation-tests.sh" "yes" "$(grep -qF 'run-mutation-tests.sh' "$ROOT/docs/testing.md" 2>/dev/null && echo yes || echo no)"
  assert_eq "docs/testing.md documents the manual workflow" "yes" "$(grep -qF 'mutation-tests.yml' "$ROOT/docs/testing.md" 2>/dev/null && echo yes || echo no)"
  return 0
}

# --- shellcheck, advisory ---------------------------------------------------------------

# Reports error-level findings. Advisory unless STRUCTURE_SHELLCHECK_STRICT=1, in which case
# any finding fails the run (CI sets it). Run it locally without installing anything:
#   docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable -S error -x <scripts>
test_shellcheck_reports_no_errors() {
  local f out
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck (not installed here)"; return 0; fi
  for f in $(shell_scripts); do
    out=$(shellcheck -S error -x "$f" 2>&1 || true)
    if [[ -z "$out" ]]; then assert_eq "shellcheck (errors only) $(rel "$f")" "" "$out"
    elif [[ "${STRUCTURE_SHELLCHECK_STRICT:-0}" = "1" ]]; then assert_eq "shellcheck (errors only) $(rel "$f")" "" "$out"
    else echo "NOTE: shellcheck reports error-level findings in $(rel "$f") (advisory, set STRUCTURE_SHELLCHECK_STRICT=1 to enforce)"; fi
  done
  return 0
}

test_every_hook_has_its_own_test_suite
test_every_suite_belongs_to_something_real
test_the_installer_installs_exactly_the_hooks_that_exist
test_every_suite_is_run_by_the_runner_and_by_ci
test_every_suite_is_described_in_the_testing_doc
test_every_shell_script_parses
test_every_script_has_a_shebang_and_lf_line_endings
test_scripts_are_executable_in_git
test_gitattributes_forces_lf_for_every_script
test_javascript_files_parse
test_powershell_scripts_parse
test_the_example_wiki_config_is_valid_json_with_the_keys_the_script_reads
test_every_command_template_carries_a_version_stamp
test_test_scripts_avoid_bash_4_only_features
test_test_scripts_avoid_gnu_only_commands_without_a_fallback
test_every_suite_cleans_up_after_itself_with_a_trap
test_mutation_config_is_well_formed_and_every_mutant_applies
test_the_manual_workflow_offers_exactly_the_mutation_groups
test_shellcheck_reports_no_errors

echo "--- $PASS passed, $FAIL failed, $SKIPS skipped ---"
[[ "$FAIL" -eq 0 ]]
