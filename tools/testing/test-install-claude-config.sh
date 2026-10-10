#!/usr/bin/env bash
# Test harness for tools/install-claude-config.sh.
# Run: bash tools/testing/test-install-claude-config.sh
#
# Every run installs into a throwaway --prefix under mktemp, so nothing here
# can touch a real ~/.claude. Fixtures are throwaway vault folders and repos.

set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$TOOLS_DIR/install-claude-config.sh"
PASS=0
FAIL=0
STARTUP_JSON='{"source":"startup"}'
UNCHANGED="unchanged"

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
  assert_contains "second run: reports unchanged" "$UNCHANGED" "$out"
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
  out=$( cd "$repo" && printf '%s' "$STARTUP_JSON" | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
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
  assert_contains "CRLF vault-root: recognised as unchanged, not 'kept'" "$UNCHANGED" "$out"
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
  out=$( cd "$repo" && printf '%s' "$STARTUP_JSON" | env VAULT_ROOT="$v_env" bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
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
  out=$( cd "$repo" && printf '%s' "$STARTUP_JSON" | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 )
  assert_contains "wrapper: a CRLF vault-root file still resolves the vault" "CRLF-VAULT-DOC" "$out"
  rm -rf "$p" "$v" "$repo"
  return $?
}

test_wrapper_without_any_vault_root_is_silent() {
  local p repo out st; p=$(mktemp -d); repo=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  out=$( cd "$repo" && printf '%s' "$STARTUP_JSON" | env -u VAULT_ROOT bash "$p/claude/hook-templates/session-start-vault-context.sh" 2>&1 ); st=$?
  assert_eq "wrapper, no vault configured, outside any git repo: exit 0" "0" "$st"
  assert_eq "wrapper, no vault configured: prints nothing" "" "$out"
  rm -rf "$p" "$repo"
  return $?
}

# --- --statusline -------------------------------------------------------------------------------

# A path node understands (Git Bash: /c/... becomes C:/...).
np() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$p"; else printf '%s' "$p"; fi
  return 0
}
# The statusLine command in a settings.json, or nothing.
sl_cmd() {
  local file; file="$(np "$1")"
  node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(j.statusLine?String(j.statusLine.command):"")' "$file"
  return 0
}
sl_keys() {
  local file; file="$(np "$1")"
  node -e 'process.stdout.write(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))).join(","))' "$file"
  return 0
}
count_backups() {
  local dir="$1"
  ls "$dir" 2>/dev/null | grep -c 'settings.json.bak-'
  return 0
}
need_node() { command -v node >/dev/null 2>&1 && return 0; echo "SKIP: $1 (node is not installed)"; return 1; }

test_statusline_is_opt_in() {
  local p out; need_node "statusline opt-in" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  printf '{"model":"widget-1"}\n' > "$p/claude/settings.json"
  out=$(bash "$INSTALLER" --prefix "$p/claude" 2>&1)
  assert_eq "no --statusline: the script is not installed" "no" "$(exists "$p/claude/statusline.mjs")"
  assert_eq "no --statusline: settings.json is untouched" '{"model":"widget-1"}' "$(cat "$p/claude/settings.json")"
  assert_eq "no --statusline: no backup is made" "0" "$(count_backups "$p/claude")"
  assert_eq "no --statusline: the output does not mention it" "0" "$(printf '%s' "$out" | grep -c -i 'statusline')"
  rm -rf "$p"
  return 0
}

test_statusline_install_copies_the_script_and_sets_settings() {
  local p out cmd; need_node "statusline install" || return 0
  p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline 2>&1); local st=$?
  assert_eq "statusline install: exit 0" "0" "$st"
  assert_eq "statusline install: the script is copied byte for byte" "yes" "$(cmp -s "$TOOLS_DIR/statusline/statusline.mjs" "$p/claude/statusline.mjs" && echo yes || echo no)"
  cmd=$(sl_cmd "$p/claude/settings.json")
  assert_contains "statusline install: the command runs node" "node " "$cmd"
  assert_contains "statusline install: the command names the installed script" "/claude/statusline.mjs" "$cmd"
  assert_eq "statusline install: the command is an absolute path, not ~" "0" "$(printf '%s' "$cmd" | grep -c '~')"
  assert_eq "statusline install: the command uses forward slashes only" "0" "$(printf '%s' "$cmd" | grep -c '\\')"
  assert_eq "statusline install: the command starts with an absolute path" "1" "$(printf '%s' "$cmd" | grep -c -E '^node "?(/|[A-Za-z]:/)')"
  assert_eq "statusline install: no backup when there was no settings.json" "0" "$(count_backups "$p/claude")"
  assert_contains "statusline install: tells you a new session is needed" "NEW Claude Code session" "$out"
  rm -rf "$p"
  return 0
}

test_statusline_second_run_changes_nothing() {
  local p out before; need_node "statusline idempotence" || return 0
  p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" --statusline >/dev/null 2>&1
  before=$(cat "$p/claude/settings.json")
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline 2>&1)
  assert_eq "statusline second run: settings.json is identical" "$before" "$(cat "$p/claude/settings.json")"
  assert_eq "statusline second run: nothing installed or updated" "0" "$(printf '%s' "$out" | grep -c -E '^(installed|updated)')"
  assert_eq "statusline second run: no backup" "0" "$(count_backups "$p/claude")"
  assert_contains "statusline second run: reports unchanged" "$UNCHANGED" "$out"
  rm -rf "$p"
  return 0
}

test_statusline_keeps_other_settings_and_backs_up() {
  local p orig; need_node "statusline preserves settings" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  orig='{"model":"widget-1","permissions":{"allow":["Bash(ls:*)"]},"env":{"A":"1"}}'
  printf '%s\n' "$orig" > "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --statusline >/dev/null 2>&1
  assert_eq "statusline with existing settings: every key is kept and statusLine is added last" "model,permissions,env,statusLine" "$(sl_keys "$p/claude/settings.json")"
  assert_eq "statusline with existing settings: one backup is made" "1" "$(count_backups "$p/claude")"
  assert_eq "statusline with existing settings: the backup is the original, byte for byte" "$orig" "$(cat "$p/claude"/settings.json.bak-*)"
  rm -rf "$p"
  return 0
}

test_statusline_keeps_a_different_status_line_unless_forced() {
  local p out orig; need_node "statusline different line" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  orig='{"statusLine":{"type":"command","command":"bash ~/other-line.sh"}}'
  printf '%s\n' "$orig" > "$p/claude/settings.json"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline 2>&1); local st=$?
  assert_eq "different statusLine: exit 0 (nothing the installer was able to do is outstanding)" "0" "$st"
  assert_eq "different statusLine: left exactly as it was" "$orig" "$(cat "$p/claude/settings.json")"
  assert_eq "different statusLine: no backup" "0" "$(count_backups "$p/claude")"
  assert_contains "different statusLine: says it was kept" "kept" "$out"
  assert_contains "different statusLine: points at --force" "--force" "$out"
  assert_contains "different statusLine: prints the snippet to switch by hand" '"statusLine"' "$out"
  assert_eq "different statusLine: the script is still copied" "yes" "$(exists "$p/claude/statusline.mjs")"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --force 2>&1)
  assert_contains "different statusLine with --force: the command is replaced" "statusline.mjs" "$(sl_cmd "$p/claude/settings.json")"
  assert_eq "different statusLine with --force: the old file is backed up" "1" "$(count_backups "$p/claude")"
  assert_eq "different statusLine with --force: the backup is the original" "$orig" "$(cat "$p/claude"/settings.json.bak-*)"
  rm -rf "$p"
  return 0
}

test_statusline_hand_installed_tilde_form_is_left_alone() {
  local p orig; need_node "statusline hand-installed" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  orig='{"statusLine":{"type":"command","command":"node ~/.claude/statusline.mjs"}}'
  printf '%s\n' "$orig" > "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --statusline --force >/dev/null 2>&1
  assert_eq "hand-installed ~ form: not rewritten, even with --force" "$orig" "$(cat "$p/claude/settings.json")"
  assert_eq "hand-installed ~ form: no backup" "0" "$(count_backups "$p/claude")"
  rm -rf "$p"
  return 0
}

test_statusline_invalid_json_is_never_touched() {
  local p out bad; need_node "statusline invalid JSON" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  bad='{"model": '
  printf '%s' "$bad" > "$p/claude/settings.json"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --force 2>&1); local st=$?
  assert_eq "invalid settings.json: exit 1 so the problem is not missed" "1" "$st"
  assert_eq "invalid settings.json: the file is untouched" "$bad" "$(cat "$p/claude/settings.json")"
  assert_eq "invalid settings.json: no backup and no temp file" "0" "$(ls "$p/claude" | grep -c -E 'bak-|tmp-')"
  assert_contains "invalid settings.json: says why and gives the snippet" "not valid JSON" "$out"
  assert_eq "invalid settings.json: the script is still copied" "yes" "$(exists "$p/claude/statusline.mjs")"
  rm -rf "$p"
  return 0
}

test_statusline_dry_run_writes_nothing() {
  local p out; need_node "statusline dry run" || return 0
  p=$(mktemp -d)
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --dry-run 2>&1); local st=$?
  assert_eq "statusline dry run: exit 0" "0" "$st"
  assert_eq "statusline dry run: nothing is created" "no" "$(exists "$p/claude")"
  assert_contains "statusline dry run: says it would install the script" "would install" "$out"
  assert_contains "statusline dry run: says it would create settings.json" "would create" "$out"
  assert_eq "statusline dry run: does not claim the status line has appeared" "0" "$(printf '%s' "$out" | grep -c 'NEW Claude Code session (see')"
  mkdir -p "$p/claude"
  printf '{"statusLine":{"type":"command","command":"bash a.sh"}}\n' > "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --statusline --force --dry-run >/dev/null 2>&1
  assert_contains "statusline dry run with --force: the existing line is not replaced" "bash a.sh" "$(sl_cmd "$p/claude/settings.json")"
  assert_eq "statusline dry run with --force: no backup" "0" "$(count_backups "$p/claude")"
  rm -rf "$p"
  return 0
}

test_statusline_check_mode() {
  local p out st; need_node "statusline check" || return 0
  p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --check 2>&1); st=$?
  assert_eq "statusline check before installing it: exit 1" "1" "$st"
  assert_contains "statusline check: reports the script missing" "missing  statusline.mjs" "$out"
  assert_contains "statusline check: reports the setting missing" "missing  settings.json statusLine" "$out"
  assert_eq "statusline check: writes nothing" "no" "$(exists "$p/claude/settings.json")"
  bash "$INSTALLER" --prefix "$p/claude" --statusline >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --check 2>&1); st=$?
  assert_eq "statusline check after installing it: exit 0" "0" "$st"
  assert_contains "statusline check after installing it: both are current" "current  settings.json statusLine" "$out"
  printf '{"model":"widget-1"}\n' > "$p/claude/settings.json"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --check 2>&1); st=$?
  assert_eq "statusline check with the script current but no statusLine set: exit 1" "1" "$st"
  assert_contains "statusline check with the script current but no statusLine set: reports the setting missing" "missing  settings.json statusLine" "$out"
  assert_contains "statusline check with the script current but no statusLine set: the script itself is current" "current  statusline.mjs" "$out"
  assert_eq "statusline check with the script current but no statusLine set: not reported as a helper failure" "0" "$(printf '%s' "$out" | grep -c 'exited')"
  printf '// stale\n' >> "$p/claude/statusline.mjs"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --statusline --check 2>&1); st=$?
  assert_eq "statusline check with a modified script: exit 1" "1" "$st"
  assert_contains "statusline check with a modified script: says it differs" "differs  statusline.mjs" "$out"
  out=$(bash "$INSTALLER" --prefix "$p/claude" --check 2>&1)
  assert_eq "check without --statusline says nothing about it" "0" "$(printf '%s' "$out" | grep -c -i 'statusline')"
  rm -rf "$p"
  return 0
}

test_statusline_check_does_not_fail_for_a_different_status_line() {
  local p st; need_node "statusline check, different line" || return 0
  p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/claude" --statusline >/dev/null 2>&1
  printf '{"statusLine":{"type":"command","command":"bash a.sh"}}\n' > "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --statusline --check >/dev/null 2>&1; st=$?
  assert_eq "statusline check with a different line configured: exit 0 (re-running would not change it)" "0" "$st"
  rm -rf "$p"
  return 0
}

test_statusline_relative_prefix_gives_an_absolute_command() {
  local p cmd; need_node "statusline relative prefix" || return 0
  p=$(mktemp -d)
  ( cd "$p" && bash "$INSTALLER" --prefix rel-claude --statusline >/dev/null 2>&1 )
  cmd=$(sl_cmd "$p/rel-claude/settings.json")
  assert_eq "relative --prefix: the command still starts with an absolute path" "1" "$(printf '%s' "$cmd" | grep -c -E '^node "?(/|[A-Za-z]:/)')"
  assert_contains "relative --prefix: and names the installed script" "/rel-claude/statusline.mjs" "$cmd"
  rm -rf "$p"
  return 0
}

test_statusline_path_with_a_space_is_quoted() {
  local p cmd; need_node "statusline path with a space" || return 0
  p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/with space/claude" --statusline >/dev/null 2>&1
  cmd=$(sl_cmd "$p/with space/claude/settings.json")
  assert_eq "path with a space: the script path is single-quoted" "1" "$(printf '%s' "$cmd" | grep -c -E "^node '.* .*/statusline[.]mjs'\$")"
  rm -rf "$p"
  return 0
}

# Claude Code hands the command to a shell, so nothing in the install path may be expanded.
test_statusline_command_never_lets_a_shell_expand_the_install_path() {
  local p prefix cmd marker; need_node "statusline command injection" || return 0
  p=$(mktemp -d); marker="$p/PWNED"
  prefix="$p/x\$(touch $marker)y \`touch $marker\` \$HOME/claude"
  bash "$INSTALLER" --prefix "$prefix" --statusline >/dev/null 2>&1
  cmd=$(sl_cmd "$prefix/settings.json")
  assert_contains "shell metacharacters in the install path: the command is single-quoted" "node '" "$cmd"
  # run the command text the way a shell would, with node swapped for echo
  bash -c "${cmd/#node/echo}" >/dev/null 2>&1
  assert_eq "shell metacharacters in the install path: nothing is executed or expanded" "no" "$(exists "$marker")"
  assert_contains "shell metacharacters in the install path: the characters are kept literally" '$HOME/claude/statusline.mjs' "$cmd"
  rm -rf "$p"
  return 0
}

test_statusline_refuses_a_path_that_cannot_be_quoted_safely() {
  local p out st; need_node "statusline unquotable path" || return 0
  p=$(mktemp -d)
  mkdir -p "$p/it's" 2>/dev/null || { echo "SKIP: statusline path with a single quote (this filesystem cannot create one)"; rm -rf "$p"; return 0; }
  out=$(bash "$INSTALLER" --prefix "$p/it's/claude" --statusline 2>&1); st=$?
  assert_eq "path with a single quote: settings.json is not written" "no" "$(exists "$p/it's/claude/settings.json")"
  assert_contains "path with a single quote: says why" "cannot be quoted safely" "$out"
  assert_eq "path with a single quote: exit 1 so it is noticed" "1" "$st"
  assert_eq "path with a single quote: the script itself is still copied" "yes" "$(exists "$p/it's/claude/statusline.mjs")"
  rm -rf "$p"
  return 0
}

test_statusline_reinstall_recognises_its_own_quoted_command() {
  local p out; need_node "statusline quoted idempotence" || return 0
  p=$(mktemp -d)
  bash "$INSTALLER" --prefix "$p/Jane (work)/claude" --statusline >/dev/null 2>&1
  out=$(bash "$INSTALLER" --prefix "$p/Jane (work)/claude" --statusline --force 2>&1)
  assert_contains "a quoted path with parentheses: the second run recognises the command as its own" "$UNCHANGED" "$out"
  assert_eq "a quoted path with parentheses: no backup on the second run" "0" "$(count_backups "$p/Jane (work)/claude")"
  rm -rf "$p"
  return 0
}

test_statusline_settings_file_modes_are_kept() {
  local p; need_node "statusline file modes" || return 0
  if command -v cygpath >/dev/null 2>&1; then echo "SKIP: statusline file modes (Windows does not have Unix permission bits)"; return 0; fi
  p=$(mktemp -d); mkdir -p "$p/claude"
  printf '{"env":{"A":"1"}}\n' > "$p/claude/settings.json"; chmod 600 "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --statusline >/dev/null 2>&1
  assert_eq "an existing 0600 settings.json is still 0600 after the edit" "-rw-------" "$(ls -l "$p/claude/settings.json" | cut -c1-10)"
  bash "$INSTALLER" --prefix "$p/fresh" --statusline >/dev/null 2>&1
  assert_eq "a settings.json the installer creates is private to its owner" "-rw-------" "$(ls -l "$p/fresh/settings.json" | cut -c1-10)"
  rm -rf "$p"
  return 0
}

test_statusline_without_node_copies_the_script_and_warns() {
  local p out tools t; need_node "statusline without node" || return 0
  if command -v cygpath >/dev/null 2>&1; then echo "SKIP: statusline without node (cannot build a node-free PATH under Git Bash)"; return 0; fi
  p=$(mktemp -d); tools="$p/tools"; mkdir -p "$tools"
  for t in dirname mkdir cp cmp chmod grep head sed tr mktemp rm basename cat ls; do
    ln -s "$(command -v "$t")" "$tools/$t" 2>/dev/null || cp "$(command -v "$t")" "$tools/$t"
  done
  out=$(PATH="$tools" "$(command -v bash)" "$INSTALLER" --prefix "$p/claude" --statusline 2>&1); local st=$?
  assert_eq "no node: the script is still copied" "yes" "$(exists "$p/claude/statusline.mjs")"
  assert_eq "no node: settings.json is not created" "no" "$(exists "$p/claude/settings.json")"
  assert_contains "no node: warns that node is missing" "node is not on PATH" "$out"
  assert_contains "no node: prints the snippet to add by hand" '"statusLine"' "$out"
  assert_eq "no node: not a failure (exit 0)" "0" "$st"
  rm -rf "$p"
  return 0
}

test_help_documents_the_statusline_flag() {
  local out; out=$(bash "$INSTALLER" --help 2>&1)
  assert_contains "help lists --statusline" "--statusline" "$out"
  assert_contains "help says --force also covers a different statusLine" "different statusLine" "$out"
  return 0
}

test_force_without_statusline_never_edits_settings() {
  local p orig; need_node "force without statusline" || return 0
  p=$(mktemp -d); mkdir -p "$p/claude"
  orig='{"statusLine":{"type":"command","command":"bash a.sh"}}'
  printf '%s\n' "$orig" > "$p/claude/settings.json"
  bash "$INSTALLER" --prefix "$p/claude" --force >/dev/null 2>&1
  assert_eq "--force alone never edits settings.json" "$orig" "$(cat "$p/claude/settings.json")"
  rm -rf "$p"
  return 0
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

test_statusline_is_opt_in
test_statusline_install_copies_the_script_and_sets_settings
test_statusline_second_run_changes_nothing
test_statusline_keeps_other_settings_and_backs_up
test_statusline_keeps_a_different_status_line_unless_forced
test_statusline_hand_installed_tilde_form_is_left_alone
test_statusline_invalid_json_is_never_touched
test_statusline_dry_run_writes_nothing
test_statusline_check_mode
test_statusline_check_does_not_fail_for_a_different_status_line
test_statusline_relative_prefix_gives_an_absolute_command
test_statusline_path_with_a_space_is_quoted
test_statusline_command_never_lets_a_shell_expand_the_install_path
test_statusline_refuses_a_path_that_cannot_be_quoted_safely
test_statusline_reinstall_recognises_its_own_quoted_command
test_statusline_settings_file_modes_are_kept
test_statusline_without_node_copies_the_script_and_warns
test_help_documents_the_statusline_flag
test_force_without_statusline_never_edits_settings

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
