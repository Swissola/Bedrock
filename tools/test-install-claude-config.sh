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

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
