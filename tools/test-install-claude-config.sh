#!/usr/bin/env bash
# Test harness for tools/install-claude-config.sh.
# Run: bash tools/test-install-claude-config.sh
#
# Every run installs into a throwaway --prefix under mktemp, so nothing here
# can touch a real ~/.claude. Fixtures are throwaway vault folders and repos.

set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$TOOLS_DIR/install-claude-config.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" = "$actual" ]]; then echo "PASS: $desc"; PASS=$((PASS + 1))
  else echo "FAIL: $desc (expected [$expected], got [$actual])"; FAIL=$((FAIL + 1)); fi
  return $?
}
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then echo "PASS: $desc"; PASS=$((PASS + 1))
  else echo "FAIL: $desc (output does not contain [$needle])"; FAIL=$((FAIL + 1)); fi
  return $?
}
exists() { local p="$1"; [[ -e "$p" ]] && echo yes || echo no; return $?; }

test_dry_run_changes_nothing() {
  local p out; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --dry-run 2>&1); local st=$?
  assert_eq "dry run: exit 0" "0" "$st"
  assert_eq "dry run: nothing created" "no" "$(exists "$p/claude")"
  assert_contains "dry run: says what it would do" "would install" "$out"
  rm -rf "$p"
  return $?
}

test_fresh_install_copies_commands_skills_hooks() {
  local p out; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" 2>&1); local st=$?
  assert_eq "fresh install: exit 0" "0" "$st"
  assert_eq "installs /vault-log" "yes" "$(exists "$p/claude/commands/vault-log.md")"
  assert_eq "installs /vault-context" "yes" "$(exists "$p/claude/commands/vault-context.md")"
  assert_eq "installs /vault-populate" "yes" "$(exists "$p/claude/commands/vault-populate.md")"
  assert_eq "installs the conventions skill" "yes" "$(exists "$p/claude/skills/obsidian-vault-conventions/SKILL.md")"
  assert_eq "installs the post-merge hook template" "yes" "$(exists "$p/claude/hook-templates/post-merge")"
  assert_eq "installs the session-start hook template" "yes" "$(exists "$p/claude/hook-templates/session-start-vault-context")"
  assert_eq "installs the session-start .sh wrapper" "yes" "$(exists "$p/claude/hook-templates/session-start-vault-context.sh")"
  assert_eq "hook templates are executable" "yes" "$([[ -x "$p/claude/hook-templates/post-merge" ]] && echo yes || echo no)"
  assert_eq "test scripts are NOT installed" "no" "$(exists "$p/claude/hook-templates/test-post-merge.sh")"
  rm -rf "$p"
  return $?
}

test_second_run_is_idempotent() {
  local p out; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/claude" 2>&1)
  assert_contains "second run: reports unchanged" "unchanged" "$out"
  assert_eq "second run: nothing re-installed" "0" "$(printf '%s' "$out" | grep -c -E '^(installed|updated)')"
  rm -rf "$p"
  return $?
}

test_check_mode() {
  local p out st; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1); st=$?
  assert_eq "check on a fresh install: exit 0" "0" "$st"
  assert_contains "check on a fresh install: says current" "current" "$out"
  # an older installed copy: same file with a lower version stamp
  sed 's/version [0-9][0-9]*/version 1/' "$p/claude/commands/vault-log.md" > "$p/vl.tmp" && mv "$p/vl.tmp" "$p/claude/commands/vault-log.md"  # no sed -i: BSD and GNU differ
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1); st=$?
  assert_eq "check with an outdated command: exit 1" "1" "$st"
  assert_contains "check names the outdated command" "vault-log.md" "$out"
  assert_contains "check says outdated" "outdated" "$out"
  rm -f "$p/claude/commands/vault-context.md"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_contains "check reports a missing file" "missing" "$out"
  # a modified hook template (no stamp): byte compare
  echo "# local edit" >> "$p/claude/hook-templates/pre-commit"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_contains "check reports a modified hook template" "differs" "$out"
  rm -rf "$p"
  return $?
}

test_update_replaces_outdated_copy() {
  local p out; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  echo "stale" > "$p/claude/commands/vault-log.md"
  out=$(bash "$INSTALLER" --prefix "$p/claude" 2>&1)
  assert_contains "re-run reports the update" "updated" "$out"
  assert_eq "re-run restores the real content" "0" "$(grep -c '^stale$' "$p/claude/commands/vault-log.md")"
  rm -rf "$p"
  return $?
}

test_vault_root_file() {
  local p v out; p=$(mktemp -d); v=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" >/dev/null 2>&1
  assert_eq "--vault writes the vault-root file" "$v" "$(head -n1 "$p/claude/hook-configs/vault-root" 2>/dev/null | tr -d '\r')"
  # a different vault must not be silently overwritten
  local v2; v2=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v2" 2>&1)
  assert_eq "a different existing vault-root is not overwritten without --force" "$v" "$(head -n1 "$p/claude/hook-configs/vault-root" | tr -d '\r')"
  assert_contains "…and the installer says why" "--force" "$out"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v2" --force >/dev/null 2>&1
  assert_eq "--force replaces it" "$v2" "$(head -n1 "$p/claude/hook-configs/vault-root" | tr -d '\r')"
  rm -rf "$p" "$v" "$v2"
  return $?
}

test_nonexistent_vault_is_an_error() {
  local p out st; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$p/does-not-exist" 2>&1); st=$?
  assert_eq "nonexistent --vault: exit 2" "2" "$st"
  assert_contains "…with a clear message" "not a directory" "$out"
  rm -rf "$p"
  return $?
}

test_mcpvault_config_generated_once() {
  local p v cfg; p=$(mktemp -d); v=$(mktemp -d); cfg="$p/claude/hook-configs/obsidian-mcp-config.json"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault >/dev/null 2>&1
  assert_eq "mcpvault: hook MCP config written" "yes" "$(exists "$cfg")"
  assert_eq "mcpvault: config names the server obsidian" "1" "$(grep -c '"obsidian"' "$cfg" 2>/dev/null || echo 0)"
  assert_eq "mcpvault: config mentions mcpvault" "1" "$(grep -c 'mcpvault' "$cfg" 2>/dev/null || echo 0)"
  assert_eq "mcpvault: config is valid JSON (when jq is present)" "ok" "$(command -v jq >/dev/null 2>&1 && { jq -e . "$cfg" >/dev/null 2>&1 && echo ok || echo bad; } || echo ok)"
  echo '{"mine":true}' > "$cfg"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault >/dev/null 2>&1
  assert_eq "mcpvault: an existing MCP config is never overwritten" "1" "$(grep -c '"mine"' "$cfg")"
  rm -rf "$p" "$v"
  return $?
}

test_rest_api_backend_writes_no_config_and_explains() {
  local p v out; p=$(mktemp -d); v=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend rest-api 2>&1)
  assert_eq "rest-api: no MCP config generated (needs an API key)" "no" "$(exists "$p/claude/hook-configs/obsidian-mcp-config.json")"
  assert_contains "rest-api: points at the setup guide" "mcp-setup" "$out"
  rm -rf "$p" "$v"
  return $?
}

test_unknown_option_is_a_usage_error() {
  local out st; out=$(bash "$INSTALLER" --bogus 2>&1); st=$?
  assert_eq "unknown option: exit 2" "2" "$st"
  assert_contains "…prints usage" "Usage" "$out"
  return $?
}

test_never_touches_real_home_without_prefix_in_tests() {
  # Guard for this suite itself: every call above passes --prefix. This checks
  # the installer's dry run with no --prefix only reports, and writes nothing.
  local fakehome out; fakehome=$(mktemp -d)
  out=$(HOME="$fakehome" bash "$INSTALLER" --dry-run 2>&1)
  assert_eq "dry run without --prefix writes nothing under HOME" "no" "$(exists "$fakehome/.claude")"
  rm -rf "$fakehome"
  return $?
}

test_session_start_wrapper_uses_vault_root_file() {
  # End to end: install with --vault, then run the installed wrapper the way a
  # project's SessionStart hook would (no VAULT_ROOT in the environment).
  local p v repo out; p=$(mktemp -d); v=$(mktemp -d); repo=$(mktemp -d)
  git -C "$repo" init -q -b main; git -C "$repo" remote add origin "https://example.com/org/widget.git"
  mkdir -p "$v/repos/widget" "$v/daily-notes/alice"
  echo "REPODOC-MARKER" > "$v/repos/widget/index.md"
  printf '## Context for Future Sessions\nCTX-MARKER\n' > "$v/daily-notes/alice/2026-10-05-a.md"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" >/dev/null 2>&1
  out=$( cd "$repo" && printf '{"source":"startup"}' | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
  assert_contains "wrapper: finds the vault via the vault-root file" "REPODOC-MARKER" "$out"
  assert_contains "wrapper: loads the latest note's context" "CTX-MARKER" "$out"
  out=$( cd "$repo" && printf '{"source":"compact"}' | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
  assert_eq "wrapper: passes stdin through (compact still skipped)" "" "$out"
  rm -rf "$p" "$v" "$repo"
  return $?
}

test_no_skills_flag() {
  # The conventions skill describes the TEAM vault's layout (daily-notes/<author>/,
  # repos/<name>/) and triggers on any mcp__obsidian__* call, so a vault with a
  # different layout must be able to leave the skills out.
  local p out st; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --no-skills 2>&1); st=$?
  assert_eq "--no-skills: exit 0" "0" "$st"
  assert_eq "--no-skills: commands still installed" "yes" "$(exists "$p/claude/commands/vault-log.md")"
  assert_eq "--no-skills: hook templates still installed" "yes" "$(exists "$p/claude/hook-templates/post-merge")"
  assert_eq "--no-skills: no skills directory created" "no" "$(exists "$p/claude/skills")"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check --no-skills 2>&1); st=$?
  assert_eq "--check --no-skills: current without the skills (exit 0)" "0" "$st"
  assert_eq "--check --no-skills: skills not mentioned" "0" "$(printf '%s' "$out" | grep -c 'skills/')"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1); st=$?
  assert_eq "--check without --no-skills: missing skills are reported (exit 1)" "1" "$st"
  rm -rf "$p"
  return $?
}


# --- extended coverage -----------------------------------------------------------
#
# Added on top of the original scenarios. Same rules: every run installs into a
# throwaway --prefix, nothing touches a real ~/.claude.

SRC_HOOKS="post-merge pre-commit pre-push session-start-vault-check session-start-vault-context"

test_every_command_skill_and_hook_in_the_repo_is_installed_byte_for_byte() {
  local p f d name missing=0 differing=0 h; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  for f in "$TOOLS_DIR"/command-templates/*.md; do
    name=$(basename "$f")
    [[ -f "$p/claude/commands/$name" ]] || missing=$((missing + 1))
    cmp -s "$f" "$p/claude/commands/$name" || differing=$((differing + 1))
  done
  for d in "$TOOLS_DIR"/skill-templates/*/; do
    name=$(basename "$d")
    [[ -f "$p/claude/skills/$name/SKILL.md" ]] || missing=$((missing + 1))
    cmp -s "${d}SKILL.md" "$p/claude/skills/$name/SKILL.md" || differing=$((differing + 1))
  done
  for h in $SRC_HOOKS; do
    [[ -x "$p/claude/hook-templates/$h" ]] || missing=$((missing + 1))
    cmp -s "$TOOLS_DIR/hook-templates/$h" "$p/claude/hook-templates/$h" || differing=$((differing + 1))
  done
  assert_eq "every source command, skill and hook is installed (and hooks are executable)" "0" "$missing"
  assert_eq "every installed copy is byte-identical to its source" "0" "$differing"
  assert_eq "the session-start wrapper is executable" "yes" "$([[ -x "$p/claude/hook-templates/session-start-vault-context.sh" ]] && echo yes || echo no)"
  rm -rf "$p"
  return $?
}

test_invalid_backend_is_a_usage_error() {
  local p out st; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --backend nonsense 2>&1); st=$?
  assert_eq "bad --backend: exit 2" "2" "$st"
  assert_contains "bad --backend: names the allowed values" "rest-api or mcpvault" "$out"
  assert_eq "bad --backend: nothing installed" "no" "$(exists "$p/claude")"
  rm -rf "$p"
  return $?
}

test_empty_prefix_is_a_usage_error() {
  local out st; out=$(bash "$INSTALLER" --prefix "" --dry-run 2>&1); st=$?
  assert_eq "empty --prefix: exit 2" "2" "$st"
  assert_contains "empty --prefix: says so" "empty --prefix" "$out"
  return $?
}

test_help_prints_usage_and_exits_zero() {
  local out st h
  for h in -h --help; do
    out=$(bash "$INSTALLER" "$h" 2>&1); st=$?
    assert_eq "$h: exit 0" "0" "$st"
    assert_contains "$h: lists the options" "--no-skills" "$out"
  done
  return $?
}

test_option_order_does_not_matter() {
  local p v out st; p=$(mktemp -d); v=$(mktemp -d)
  out=$(bash "$INSTALLER" --no-skills --vault "$v" --backend mcpvault --prefix "$p/claude" 2>&1); st=$?
  assert_eq "options in a different order: exit 0" "0" "$st"
  assert_eq "options in a different order: vault-root written" "yes" "$(exists "$p/claude/hook-configs/vault-root")"
  rm -rf "$p" "$v"
  return $?
}

test_vault_root_is_idempotent_for_the_same_vault() {
  local p v out; p=$(mktemp -d); v=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" 2>&1)
  assert_contains "same vault again: reports unchanged" "unchanged $p/claude/hook-configs/vault-root" "$out"
  assert_eq "same vault again: still exactly one line in the file" "1" "$(wc -l < "$p/claude/hook-configs/vault-root" | tr -d ' ')"
  rm -rf "$p" "$v"
  return $?
}

test_crlf_in_an_existing_vault_root_file_still_counts_as_the_same_vault() {
  local p v out; p=$(mktemp -d); v=$(mktemp -d)
  mkdir -p "$p/claude/hook-configs"
  printf '%s\r\n' "$v" > "$p/claude/hook-configs/vault-root"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" 2>&1)
  assert_contains "CRLF vault-root: recognised as unchanged, not 'kept'" "unchanged" "$out"
  assert_eq "CRLF vault-root: no 'kept ... --force' complaint" "0" "$(printf '%s' "$out" | grep -c 'kept .*vault-root')"
  rm -rf "$p" "$v"
  return $?
}

test_dry_run_with_a_vault_reports_but_writes_nothing() {
  local p v out; p=$(mktemp -d); v=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault --dry-run 2>&1)
  assert_contains "dry run with vault: would write the vault-root file" "would write $p/claude/hook-configs/vault-root" "$out"
  assert_contains "dry run with vault, mcpvault: would write the MCP config" "would write $p/claude/hook-configs/obsidian-mcp-config.json" "$out"
  assert_eq "dry run with vault: nothing created under the prefix" "no" "$(exists "$p/claude")"
  rm -rf "$p" "$v"
  return $?
}

test_check_mode_never_writes_anything_even_with_a_vault() {
  local p v out st; p=$(mktemp -d); v=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault --check 2>&1); st=$?
  assert_eq "check on an empty prefix: exit 1 (everything missing)" "1" "$st"
  assert_eq "check: prefix not created" "no" "$(exists "$p/claude")"
  assert_contains "check: says it is check only" "check only" "$out"
  assert_contains "check: tells the user how to fix it" "Re-run without --check" "$out"
  rm -rf "$p" "$v"
  return $?
}

test_check_lists_every_missing_item_by_label() {
  local p out; p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_contains "check, empty prefix: a command is labelled" "missing  commands/vault-log.md" "$out"
  assert_contains "check, empty prefix: a skill is labelled" "missing  skills/obsidian-vault-conventions/SKILL.md" "$out"
  assert_contains "check, empty prefix: a hook is labelled" "missing  hook-templates/post-merge" "$out"
  assert_contains "check, empty prefix: the wrapper is labelled" "missing  hook-templates/session-start-vault-context.sh" "$out"
  rm -rf "$p"
  return $?
}

test_installed_copy_newer_than_the_repo_is_reported_as_differs_not_outdated() {
  local p out; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  sed 's/version [0-9][0-9]*/version 999/' "$p/claude/commands/vault-log.md" > "$p/vl.tmp" && mv "$p/vl.tmp" "$p/claude/commands/vault-log.md"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_contains "installed version 999 vs repo: reported as differs" "differs  commands/vault-log.md" "$out"
  assert_eq "installed version 999 vs repo: not called outdated" "0" "$(printf '%s' "$out" | grep -c 'outdated commands/vault-log.md')"
  rm -rf "$p"
  return $?
}

test_outdated_message_gives_both_version_numbers() {
  local p out src_ver; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  src_ver=$(grep -o 'bedrock-template: [a-z-]*, version [0-9]*' "$TOOLS_DIR/command-templates/vault-log.md" | head -n1 | sed -E 's/.*version //')
  sed 's/version [0-9][0-9]*/version 0/' "$p/claude/commands/vault-log.md" > "$p/vl.tmp" && mv "$p/vl.tmp" "$p/claude/commands/vault-log.md"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_contains "outdated: shows installed and repo versions" "outdated commands/vault-log.md (installed version 0, repo has $src_ver)" "$out"
  rm -rf "$p"
  return $?
}

test_update_keeps_a_replaced_hook_executable() {
  local p out; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  echo "stale" > "$p/claude/hook-templates/pre-push"
  chmod -x "$p/claude/hook-templates/pre-push"
  out=$(bash "$INSTALLER" --prefix "$p/claude" 2>&1)
  assert_contains "stale hook: reported as updated" "updated $p/claude/hook-templates/pre-push" "$out"
  assert_eq "stale hook: replaced with the real script" "0" "$(grep -c '^stale$' "$p/claude/hook-templates/pre-push")"
  assert_eq "stale hook: executable again" "yes" "$([[ -x "$p/claude/hook-templates/pre-push" ]] && echo yes || echo no)"
  rm -rf "$p"
  return $?
}

test_unwritable_destination_fails_loudly_with_exit_1() {
  local p out st; p=$(mktemp -d)
  echo "i am a file" > "$p/blocker"
  out=$(bash "$INSTALLER" --prefix "$p/blocker/claude" 2>&1); st=$?
  assert_eq "prefix below a regular file: exit 1" "1" "$st"
  assert_contains "prefix below a regular file: says which write failed" "FAILED to write" "$out"
  rm -rf "$p"
  return $?
}

test_no_skills_leaves_already_installed_skills_alone() {
  local p; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  bash "$INSTALLER" --prefix "$p/claude" --no-skills >/dev/null 2>&1
  assert_eq "--no-skills after a full install: the skill is still there" "yes" "$(exists "$p/claude/skills/obsidian-vault-conventions/SKILL.md")"
  rm -rf "$p"
  return $?
}

test_mcpvault_without_a_vault_writes_no_config() {
  local p; p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" --backend mcpvault >/dev/null 2>&1
  assert_eq "mcpvault with no --vault: no MCP config (there is no path to put in it)" "no" "$(exists "$p/claude/hook-configs/obsidian-mcp-config.json")"
  assert_eq "mcpvault with no --vault: no vault-root file either" "no" "$(exists "$p/claude/hook-configs/vault-root")"
  rm -rf "$p"
  return $?
}

test_mcpvault_config_points_at_the_vault_and_is_exact() {
  local p v cfg; p=$(mktemp -d); v=$(mktemp -d); cfg="$p/claude/hook-configs/obsidian-mcp-config.json"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault >/dev/null 2>&1
  assert_eq "mcpvault config: exact content, vault path last in args" \
    "{\"mcpServers\":{\"obsidian\":{\"command\":\"npx\",\"args\":[\"-y\",\"@bitbonsai/mcpvault@latest\",\"$v\"]}}}" \
    "$(cat "$cfg" 2>/dev/null)"
  rm -rf "$p" "$v"
  return $?
}

test_backslashes_in_a_windows_vault_path_are_normalised() {
  local p v wv; p=$(mktemp -d); v=$(mktemp -d)
  if ! command -v cygpath >/dev/null 2>&1; then
    echo "SKIP: backslash vault path (needs Git Bash's cygpath, so only meaningful on Windows)"
    rm -rf "$p" "$v"; return 0
  fi
  wv=$(cygpath -w "$v")
  bash "$INSTALLER" --prefix "$p/claude" --vault "$wv" >/dev/null 2>&1
  assert_eq "vault given as a Windows path: stored with forward slashes" "$(printf '%s' "$wv" | tr '\\' '/')" "$(head -n1 "$p/claude/hook-configs/vault-root" 2>/dev/null | tr -d '\r')"
  rm -rf "$p" "$v"
  return $?
}

test_vault_path_with_a_double_quote_is_not_written_into_the_json() {
  local p v cfg out; p=$(mktemp -d); cfg="$p/claude/hook-configs/obsidian-mcp-config.json"
  v="$p/va\"ult"
  if ! mkdir -p "$v" 2>/dev/null; then
    echo "SKIP: vault path containing a double quote (this filesystem cannot create one, e.g. Windows)"
    rm -rf "$p"; return 0
  fi
  out=$(bash "$INSTALLER" --prefix "$p/claude" --vault "$v" --backend mcpvault 2>&1)
  assert_eq "double quote in vault path: MCP config not written (it would be invalid JSON)" "no" "$(exists "$cfg")"
  assert_contains "double quote in vault path: says why" "contains a double quote" "$out"
  rm -rf "$p"
  return $?
}

test_wrapper_prefers_vault_root_from_the_environment_over_the_file() {
  local p v_file v_env repo out; p=$(mktemp -d); v_file=$(mktemp -d); v_env=$(mktemp -d); repo=$(mktemp -d)
  git -C "$repo" init -q -b main; git -C "$repo" remote add origin "https://example.com/org/widget.git"
  mkdir -p "$v_file/repos/widget" "$v_env/repos/widget"
  echo "FROM-FILE-VAULT" > "$v_file/repos/widget/index.md"
  echo "FROM-ENV-VAULT" > "$v_env/repos/widget/index.md"
  bash "$INSTALLER" --prefix "$p/claude" --vault "$v_file" >/dev/null 2>&1
  out=$( cd "$repo" && printf '{"source":"startup"}' | env VAULT_ROOT="$v_env" bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
  assert_contains "wrapper: VAULT_ROOT from the environment wins" "FROM-ENV-VAULT" "$out"
  assert_eq "wrapper: the vault-root file's vault is not used" "0" "$(printf '%s' "$out" | grep -c 'FROM-FILE-VAULT')"
  rm -rf "$p" "$v_file" "$v_env" "$repo"
  return $?
}

test_wrapper_reads_a_crlf_vault_root_file() {
  local p v repo out; p=$(mktemp -d); v=$(mktemp -d); repo=$(mktemp -d)
  git -C "$repo" init -q -b main; git -C "$repo" remote add origin "https://example.com/org/widget.git"
  mkdir -p "$v/repos/widget"; echo "CRLF-VAULT-DOC" > "$v/repos/widget/index.md"
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  mkdir -p "$p/claude/hook-configs"; printf '%s\r\n' "$v" > "$p/claude/hook-configs/vault-root"
  out=$( cd "$repo" && printf '{"source":"startup"}' | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
  assert_contains "wrapper: a CRLF vault-root file still resolves the vault" "CRLF-VAULT-DOC" "$out"
  rm -rf "$p" "$v" "$repo"
  return $?
}

test_wrapper_without_any_vault_root_is_silent() {
  local p repo out st; p=$(mktemp -d); repo=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  out=$( cd "$repo" && printf '{"source":"startup"}' | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 ); st=$?
  assert_eq "wrapper, no vault configured, outside any git repo: exit 0" "0" "$st"
  assert_eq "wrapper, no vault configured: prints nothing" "" "$out"
  rm -rf "$p" "$repo"
  return $?
}

test_dry_run_changes_nothing
test_no_skills_flag
test_fresh_install_copies_commands_skills_hooks
test_second_run_is_idempotent
test_check_mode
test_update_replaces_outdated_copy
test_vault_root_file
test_nonexistent_vault_is_an_error
test_mcpvault_config_generated_once
test_rest_api_backend_writes_no_config_and_explains
test_unknown_option_is_a_usage_error
test_never_touches_real_home_without_prefix_in_tests
test_session_start_wrapper_uses_vault_root_file
test_every_command_skill_and_hook_in_the_repo_is_installed_byte_for_byte
test_invalid_backend_is_a_usage_error
test_empty_prefix_is_a_usage_error
test_help_prints_usage_and_exits_zero
test_option_order_does_not_matter
test_vault_root_is_idempotent_for_the_same_vault
test_crlf_in_an_existing_vault_root_file_still_counts_as_the_same_vault
test_dry_run_with_a_vault_reports_but_writes_nothing
test_check_mode_never_writes_anything_even_with_a_vault
test_check_lists_every_missing_item_by_label
test_installed_copy_newer_than_the_repo_is_reported_as_differs_not_outdated
test_outdated_message_gives_both_version_numbers
test_update_keeps_a_replaced_hook_executable
test_unwritable_destination_fails_loudly_with_exit_1
test_no_skills_leaves_already_installed_skills_alone
test_mcpvault_without_a_vault_writes_no_config
test_mcpvault_config_points_at_the_vault_and_is_exact
test_backslashes_in_a_windows_vault_path_are_normalised
test_vault_path_with_a_double_quote_is_not_written_into_the_json
test_wrapper_prefers_vault_root_from_the_environment_over_the_file
test_wrapper_reads_a_crlf_vault_root_file
test_wrapper_without_any_vault_root_is_silent

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
