#!/usr/bin/env bash
# Test harness for tools/hook-templates/session-start-vault-context.
# Run: bash tools/hook-templates/test-session-start-vault-context.sh
#
# Modelled on this directory's test-pre-commit.sh and test-post-merge.sh. The
# hook only reads files (never writes), so every fixture is a throwaway vault
# folder plus a throwaway git repo under mktemp, nothing touches a real vault.
#
# Covers two things: the default behaviour (no vault-config.md, must stay exactly
# as documented in docs/automation.md) and the optional vault-config.md keys
# `reposPath` and `dailyNotesPath` (see docs/vault-config.md).

set -u
HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-start-vault-context"
PASS=0
FAIL=0
EXIT_ZERO="EXIT=0"
# literals the tests repeat many times
DOC_MARKER="REPODOC-MARKER"
STARTUP_EVENT='{"source":"startup"}'

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
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then echo "FAIL: $desc (output unexpectedly contains [$needle])"; FAIL=$((FAIL + 1))
  else echo "PASS: $desc"; PASS=$((PASS + 1)); fi
  return $?
}

# A code repo whose origin names it, so the hook derives REPO_NAME from the remote.
make_code_repo() {
  local name="$1" dir
  dir=$(mktemp -d)
  git -C "$dir" init -q -b main
  git -C "$dir" remote add origin "https://example.com/org/${name}.git"
  echo "$dir"
  return $?
}

# A daily note with both forward-looking sections plus a history section.
write_note() {  # args: path, marker
  local path="$1" marker="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
title: $marker
---
## What Was Done
HISTORY-$marker

## Context for Future Sessions
CONTEXT-$marker

## Open Questions / Next Steps
- [ ] NEXT-$marker
EOF
  return $?
}

run_hook() {  # args: code repo, vault root (may be empty), stdin
  local repo="$1" vault="${2:-}" stdin="${3:-}"
  ( cd "$repo" && printf '%s' "$stdin" | VAULT_ROOT="$vault" bash "$HOOK_SCRIPT" 2>&1 )
  return $?
}

# ---------------------------------------------------------------- default layout

test_no_vault_root_is_silent() {
  local repo out; repo=$(make_code_repo widget)
  out=$(run_hook "$repo" "" "$STARTUP_EVENT")
  assert_eq "no VAULT_ROOT: silent no-op" "" "$out"
  rm -rf "$repo"
  return $?
}

test_missing_repo_doc_is_silent() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_eq "default layout, no repos/<name>/index.md: silent no-op" "" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_default_layout_loads_doc_and_forward_looking_sections() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  mkdir -p "$vault/repos/widget"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "default layout: repo doc loaded" "$DOC_MARKER" "$out"
  assert_contains "default layout: header names repos/widget/index.md" "## repos/widget/index.md" "$out"
  assert_contains "default layout: context section loaded" "CONTEXT-A" "$out"
  assert_contains "default layout: next-steps section loaded" "NEXT-A" "$out"
  assert_not_contains "default layout: history section NOT loaded" "HISTORY-A" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_most_recent_note_by_mtime_across_contributors() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  mkdir -p "$vault/repos/widget"; echo "doc" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-zzz.md" OLD
  write_note "$vault/daily-notes/bob/2026-10-05-aaa.md" NEW
  touch -t 202610050800 "$vault/daily-notes/alice/2026-10-05-zzz.md"
  touch -t 202610051200 "$vault/daily-notes/bob/2026-10-05-aaa.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "newest by mtime wins across contributors" "CONTEXT-NEW" "$out"
  assert_not_contains "older note (alphabetically later) not loaded" "CONTEXT-OLD" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_compact_skips_and_malformed_stdin_fails_open() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  mkdir -p "$vault/repos/widget"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" '{"source":"compact"}')
  assert_eq "source=compact: skipped entirely" "" "$out"
  out=$(run_hook "$repo" "$vault" 'not json at all')
  assert_contains "malformed stdin: still injects (fails open)" "$DOC_MARKER" "$out"
  out=$(run_hook "$repo" "$vault" '')
  assert_contains "empty stdin: still injects (fails open)" "$DOC_MARKER" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_note_without_forward_sections_loads_in_full() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  mkdir -p "$vault/repos/widget" "$vault/daily-notes/alice"
  echo "doc" > "$vault/repos/widget/index.md"
  printf '## What Was Done\nONLY-HISTORY\n' > "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "note with no forward-looking sections: loaded in full" "ONLY-HISTORY" "$out"
  assert_contains "…and says so" "loading in full" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_no_daily_notes_says_so() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  mkdir -p "$vault/repos/widget"; echo "doc" > "$vault/repos/widget/index.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "no daily notes: says so" "(No daily notes in the vault yet.)" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

# ------------------------------------------------------------- vault-config.md

personal_vault() {  # builds a vault using the personal layout plus decoys in the default places
  local vault; vault=$(mktemp -d)
  printf -- '---\ndailyNotesPath: Inbox/daily-notes\nreposPath: "Projects/{repo}/index.md"\n---\nhuman text\n' > "$vault/vault-config.md"
  mkdir -p "$vault/Projects/widget"; echo "PROJECT-DOC-MARKER" > "$vault/Projects/widget/index.md"
  write_note "$vault/Inbox/daily-notes/2026-10-05-widget-x.md" PERSONAL
  # decoys in the DEFAULT locations, newer, which a config-ignoring hook would pick
  mkdir -p "$vault/repos/widget"; echo "DECOY-REPODOC" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-decoy.md" DECOY
  touch -t 202610050800 "$vault/Inbox/daily-notes/2026-10-05-widget-x.md"
  touch -t 202610051200 "$vault/daily-notes/alice/2026-10-05-decoy.md"
  echo "$vault"
  return $?
}

test_config_repos_path_and_daily_notes_path() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(personal_vault)
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "config: repo doc read from reposPath" "PROJECT-DOC-MARKER" "$out"
  assert_contains "config: header shows the configured relative path" "## Projects/widget/index.md" "$out"
  assert_not_contains "config: default-location repo doc ignored" "DECOY-REPODOC" "$out"
  assert_contains "config: note read from dailyNotesPath" "CONTEXT-PERSONAL" "$out"
  assert_not_contains "config: newer note in the default folder ignored" "CONTEXT-DECOY" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_config_crlf_and_quotes() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(personal_vault)
  printf -- '---\r\ndailyNotesPath: "Inbox/daily-notes"\r\nreposPath: '"'"'Projects/{repo}/index.md'"'"'\r\n---\r\n' > "$vault/vault-config.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "config with CRLF and single/double quotes parses" "PROJECT-DOC-MARKER" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_config_without_keys_uses_defaults() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  printf -- '---\nchangeLog: compact\n---\n' > "$vault/vault-config.md"
  mkdir -p "$vault/repos/widget"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "config present but no relevant keys: defaults" "$DOC_MARKER" "$out"
  assert_contains "…daily notes from the default folder" "CONTEXT-A" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_unclosed_frontmatter_is_ignored() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  printf -- '---\nreposPath: Projects/{repo}/index.md\nno closing delimiter here\n' > "$vault/vault-config.md"
  mkdir -p "$vault/repos/widget"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "unclosed frontmatter: config ignored, defaults used" "$DOC_MARKER" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_unsafe_config_paths_are_ignored() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  printf -- '---\nreposPath: ../outside/{repo}.md\ndailyNotesPath: /etc\n---\n' > "$vault/vault-config.md"
  mkdir -p "$vault/repos/widget"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "reposPath containing '..' ignored, default used" "$DOC_MARKER" "$out"
  assert_not_contains "absolute dailyNotesPath ignored (no /etc content)" "root:" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_author_placeholder_resolves_to_base_folder() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(mktemp -d)
  printf -- '---\ndailyNotesPath: team-notes/{author}\n---\n' > "$vault/vault-config.md"
  mkdir -p "$vault/repos/widget"; echo "doc" > "$vault/repos/widget/index.md"
  write_note "$vault/team-notes/carol/2026-10-05-c.md" CAROL
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "{author} in dailyNotesPath: scans every subfolder of the base" "CONTEXT-CAROL" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

# ----------------------------------------------- appended "## Update" sections
# /vault-log appends a `## Update (later same session) - ...` section when a
# note for the same session already exists. The two forward-looking sections
# can't be rewritten by an append, so without this the latest state never
# reached the next session. The hook loads the MOST RECENT update section too.

make_vault_with_doc() {
  local v; v=$(mktemp -d)
  mkdir -p "$v/repos/widget"; echo "$DOC_MARKER" > "$v/repos/widget/index.md"
  echo "$v"
  return $?
}

test_latest_update_section_is_loaded() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  printf '\n## Update (later same session) - later work\nUPDATE-ONE-MARKER\n' >> "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "update section: its content is loaded" "UPDATE-ONE-MARKER" "$out"
  assert_contains "update section: loaded under a label saying what it is" "most recent update" "$out"
  assert_contains "update section: forward-looking sections still loaded" "CONTEXT-A" "$out"
  assert_not_contains "update section: history section still NOT loaded" "HISTORY-A" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_only_the_most_recent_update_is_loaded() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  printf '\n## Update (later same session) - first\nUPDATE-OLD-MARKER\n' >> "$vault/daily-notes/alice/2026-10-05-a.md"
  printf '\n## Update (later same session) - second\nUPDATE-NEW-MARKER\n' >> "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "several updates: the newest is loaded" "UPDATE-NEW-MARKER" "$out"
  assert_not_contains "several updates: an older one is NOT loaded" "UPDATE-OLD-MARKER" "$out"
  assert_contains "several updates: says how many earlier ones were skipped" "1 earlier update" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_long_update_is_truncated_with_a_marker() {
  local repo vault out i; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  { printf '\n## Update (later same session) - long\n'; for i in $(seq 1 100); do echo "UPD-LINE-$i"; done; } >> "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "long update: the start is loaded" "UPD-LINE-1" "$out"
  assert_not_contains "long update: the tail is cut" "UPD-LINE-100" "$out"
  assert_contains "long update: says it was truncated" "truncated" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_update_section_before_the_forward_sections() {
  # position in the note must not matter
  local repo vault out; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  mkdir -p "$vault/daily-notes/alice"
  printf '## What Was Done\nHISTORY-B\n\n## Update (later same session) - early\nUPDATE-EARLY-MARKER\n\n## Context for Future Sessions\nCONTEXT-B\n' > "$vault/daily-notes/alice/2026-10-05-b.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "update before the forward sections: still loaded" "UPDATE-EARLY-MARKER" "$out"
  assert_contains "…and the forward section after it is still loaded" "CONTEXT-B" "$out"
  assert_not_contains "…without pulling in the history section" "HISTORY-B" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_note_without_updates_is_unchanged() {
  local repo vault out; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_not_contains "no update section: no update label in the output" "most recent update" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_update_only_note_still_loads_in_full() {
  # no forward-looking sections: the existing fallback (load the whole note) stands
  local repo vault out; repo=$(make_code_repo widget); vault=$(make_vault_with_doc)
  mkdir -p "$vault/daily-notes/alice"
  printf '## What Was Done\nONLY-HISTORY-C\n\n## Update (later same session) - u\nUPDATE-C-MARKER\n' > "$vault/daily-notes/alice/2026-10-05-c.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "no forward sections: loads in full (history)" "ONLY-HISTORY-C" "$out"
  assert_contains "no forward sections: loads in full (update)" "UPDATE-C-MARKER" "$out"
  assert_contains "no forward sections: says it loaded in full" "loading in full" "$out"
  rm -rf "$repo" "$vault"
  return $?
}

test_no_vault_root_is_silent
test_missing_repo_doc_is_silent
test_default_layout_loads_doc_and_forward_looking_sections
test_most_recent_note_by_mtime_across_contributors
test_compact_skips_and_malformed_stdin_fails_open
test_note_without_forward_sections_loads_in_full
test_no_daily_notes_says_so
test_config_repos_path_and_daily_notes_path
test_config_crlf_and_quotes
test_config_without_keys_uses_defaults
test_unclosed_frontmatter_is_ignored
test_unsafe_config_paths_are_ignored
test_author_placeholder_resolves_to_base_folder
test_latest_update_section_is_loaded
test_only_the_most_recent_update_is_loaded
test_long_update_is_truncated_with_a_marker
test_update_section_before_the_forward_sections
test_note_without_updates_is_unchanged
test_update_only_note_still_loads_in_full

# ------------------------------------------------------------ extended coverage
# Added on top of the scenarios above, which must keep passing unchanged. Fixtures
# here are registered for cleanup by a trap, so a failed check cannot leak them.

CLEANUP_DIRS=()
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d" 2>/dev/null; done
  return 0
}
trap cleanup EXIT

fx_dir() { local d; d=$(mktemp -d); CLEANUP_DIRS+=("$d"); echo "$d"; return 0; }

# A vault holding repos/widget/index.md, registered for cleanup.
fx_vault() {
  local v; v=$(fx_dir)
  mkdir -p "$v/repos/widget"; echo "$DOC_MARKER" > "$v/repos/widget/index.md"
  echo "$v"
  return 0
}

# A code repo named $1 (via its origin), registered for cleanup.
fx_repo() {
  local r; r=$(make_code_repo "$1"); CLEANUP_DIRS+=("$r"); echo "$r"
  return 0
}

# Like run_hook but also reports the exit status as the last line "EXIT=<n>".
run_hook_status() {
  local repo="$1" vault="${2:-}" stdin="${3:-}" out
  out=$( cd "$repo" && printf '%s' "$stdin" | VAULT_ROOT="$vault" bash "$HOOK_SCRIPT" 2>&1; echo "EXIT=$?" )
  printf '%s' "$out"
  return 0
}

test_the_hook_always_exits_zero() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  out=$(run_hook_status "$repo" "" "$STARTUP_EVENT");        assert_contains "exit 0 with no VAULT_ROOT" "$EXIT_ZERO" "$out"
  out=$(run_hook_status "$repo" "$vault" '{"source":"compact"}'); assert_contains "exit 0 on compact" "$EXIT_ZERO" "$out"
  out=$(run_hook_status "$repo" "$vault" "$STARTUP_EVENT");  assert_contains "exit 0 on a normal load" "$EXIT_ZERO" "$out"
  out=$(run_hook_status "$repo" "$(fx_dir)" "$STARTUP_EVENT"); assert_contains "exit 0 when the repo has no doc" "$EXIT_ZERO" "$out"
  out=$(run_hook_status "$repo" "/no/such/vault" "$STARTUP_EVENT"); assert_contains "exit 0 when the vault does not exist" "$EXIT_ZERO" "$out"
  return 0
}

test_every_source_except_compact_injects_context() {
  local repo vault s out
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  for s in startup resume clear fork somethingnew; do
    out=$(run_hook "$repo" "$vault" "{\"source\":\"$s\"}")
    assert_contains "source=$s: injects the repo doc" "$DOC_MARKER" "$out"
  done
  return 0
}

test_compact_is_recognised_whatever_the_json_layout() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  out=$(run_hook "$repo" "$vault" '{"source" : "compact"}');                          assert_eq "spaces around the colon" "" "$out"
  out=$(run_hook "$repo" "$vault" '{"session_id":"x","source":"compact","cwd":"/a"}'); assert_eq "other fields around it" "" "$out"
  out=$(run_hook "$repo" "$vault" "{
  \"source\": \"compact\"
}");                                                                                    assert_eq "pretty-printed over several lines" "" "$out"
  out=$(run_hook "$repo" "$vault" '{"source":"startup","note":"compact"}');           assert_contains "the word compact in another field does not skip" "$DOC_MARKER" "$out"
  return 0
}

test_repo_name_falls_back_to_the_folder_name_without_an_origin() {
  local repo vault out
  repo=$(fx_dir); mkdir -p "$repo/gadget-svc"; git -C "$repo/gadget-svc" init -q -b main
  vault=$(fx_dir); mkdir -p "$vault/repos/gadget-svc"; echo "GADGET-DOC" > "$vault/repos/gadget-svc/index.md"
  out=$(run_hook "$repo/gadget-svc" "$vault" "$STARTUP_EVENT")
  assert_contains "no origin: the folder name is the repo name" "GADGET-DOC" "$out"
  assert_contains "no origin: header names it" "Vault context for gadget-svc" "$out"
  return 0
}

test_repo_name_comes_from_the_origin_in_every_common_form() {
  local url name repo vault out
  vault=$(fx_dir)
  for url in "git@bitbucket.org:sharpgaming/ssh-style.git:ssh-style" "https://github.com/org/no-suffix:no-suffix" "https://github.com/org/with-suffix.git:with-suffix"; do
    name="${url##*:}"; url="${url%:*}"
    mkdir -p "$vault/repos/$name"; echo "DOC-OF-$name" > "$vault/repos/$name/index.md"
    repo=$(fx_dir); git -C "$repo" init -q -b main; git -C "$repo" remote add origin "$url"
    out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
    assert_contains "origin $url: loads repos/$name" "DOC-OF-$name" "$out"
  done
  return 0
}

test_output_starts_with_the_context_header() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_eq "first line is the auto-loaded header" "--- Vault context for widget (auto-loaded, see runbooks/using-the-vault.md in the vault) ---" "$(printf '%s\n' "$out" | head -n1)"
  return 0
}

test_a_note_with_only_one_forward_section_loads_just_that_one() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  mkdir -p "$vault/daily-notes/alice"
  printf '## What Was Done\nHIST-ONE\n\n## Context for Future Sessions\nCTX-ONLY\n' > "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "context only: the context section is loaded" "CTX-ONLY" "$out"
  assert_contains "context only: says forward-looking sections only" "forward-looking sections only" "$out"
  assert_not_contains "context only: history is not loaded" "HIST-ONE" "$out"
  rm -f "$vault/daily-notes/alice/2026-10-05-a.md"
  printf '## What Was Done\nHIST-TWO\n\n## Open Questions / Next Steps\n- [ ] NEXT-ONLY\n' > "$vault/daily-notes/alice/2026-10-05-b.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "next steps only: that section is loaded" "NEXT-ONLY" "$out"
  assert_not_contains "next steps only: history is not loaded" "HIST-TWO" "$out"
  return 0
}

test_sections_end_at_the_next_heading_and_keep_their_subheadings() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault); mkdir -p "$vault/daily-notes/alice"
  cat > "$vault/daily-notes/alice/2026-10-05-a.md" <<'EOF'
## What Was Done
HIST

## Context for Future Sessions
CTX-LINE-1
### A sub-heading inside the context
CTX-SUB-LINE

## Problems Solved
PROBLEMS-AFTER-CONTEXT

## Open Questions / Next Steps
- [ ] NEXT-LINE

## Commands Used
COMMANDS-AFTER-NEXT
EOF
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "context: first line kept" "CTX-LINE-1" "$out"
  assert_contains "context: a ### sub-heading and its text are part of the section" "CTX-SUB-LINE" "$out"
  assert_not_contains "context ends at the next ## heading" "PROBLEMS-AFTER-CONTEXT" "$out"
  assert_contains "next steps loaded" "NEXT-LINE" "$out"
  assert_not_contains "next steps end at the next ## heading" "COMMANDS-AFTER-NEXT" "$out"
  return 0
}

test_non_markdown_files_are_never_picked_as_the_latest_note() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" REALNOTE
  echo "NOT-A-NOTE" > "$vault/daily-notes/alice/scratch.txt"
  touch -t 202610051200 "$vault/daily-notes/alice/2026-10-05-a.md"
  touch -t 202610052300 "$vault/daily-notes/alice/scratch.txt"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "a newer .txt file is ignored, the .md note wins" "CONTEXT-REALNOTE" "$out"
  assert_not_contains "the .txt content never appears" "NOT-A-NOTE" "$out"
  return 0
}

test_notes_in_nested_folders_and_with_spaces_in_the_name_are_found() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/archive 2026/2026-10-05 my note.md" SPACED
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "nested folder with spaces, file name with spaces: found" "CONTEXT-SPACED" "$out"
  assert_contains "the header shows the vault-relative path" "daily-notes/alice/archive 2026/2026-10-05 my note.md" "$out"
  return 0
}

test_an_empty_daily_notes_folder_says_there_are_no_notes() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault); mkdir -p "$vault/daily-notes/alice"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "daily-notes exists but holds no notes: says so" "(No daily notes in the vault yet.)" "$out"
  assert_contains "…and still loads the repo doc" "$DOC_MARKER" "$out"
  return 0
}

test_a_note_with_windows_line_endings_is_still_loaded() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault); mkdir -p "$vault/daily-notes/alice"
  printf '## What Was Done\r\nHIST-CRLF\r\n\r\n## Context for Future Sessions\r\nCTX-CRLF\r\n\r\n## Open Questions / Next Steps\r\n- [ ] NEXT-CRLF\r\n' > "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "CRLF note: the context text reaches the session (section match or full fallback)" "CTX-CRLF" "$out"
  assert_contains "CRLF note: the next-steps text reaches the session" "NEXT-CRLF" "$out"
  return 0
}

test_the_hook_never_writes_to_the_vault() {
  local repo vault before after
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  printf -- '---\nreposPath: repos/{repo}/index.md\n---\n' > "$vault/vault-config.md"
  before=$(cd "$vault" && find . -type f -exec cksum {} + | sort; cd "$vault" && find . | sort)
  run_hook "$repo" "$vault" "$STARTUP_EVENT" >/dev/null
  after=$(cd "$vault" && find . -type f -exec cksum {} + | sort; cd "$vault" && find . | sort)
  assert_eq "every vault file keeps its content, and none was added or removed" "$before" "$after"
  return 0
}

test_update_cap_can_be_changed_with_update_max_lines() {
  local repo vault out i
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  { printf '\n## Update (later same session) - long\n'; for i in $(seq 1 30); do echo "CAP-LINE-$i"; done; } >> "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$( cd "$repo" && printf '%s' "$STARTUP_EVENT" | VAULT_ROOT="$vault" UPDATE_MAX_LINES=5 bash "$HOOK_SCRIPT" 2>&1 )
  assert_contains "cap of 5: the first lines are loaded" "CAP-LINE-3" "$out"
  assert_not_contains "cap of 5: later lines are cut" "CAP-LINE-10" "$out"
  assert_contains "cap of 5: the marker says how many lines were left" "update truncated" "$out"
  out=$( cd "$repo" && printf '%s' "$STARTUP_EVENT" | VAULT_ROOT="$vault" UPDATE_MAX_LINES=500 bash "$HOOK_SCRIPT" 2>&1 )
  assert_contains "cap of 500: the whole update is loaded" "CAP-LINE-30" "$out"
  assert_not_contains "cap of 500: no truncation marker" "update truncated" "$out"
  return 0
}

test_update_stops_at_the_next_heading_and_counts_earlier_updates() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  write_note "$vault/daily-notes/alice/2026-10-05-a.md" A
  printf '\n## Update - one\nU1\n\n## Update - two\nU2\n\n## Update - three\nU3-IN\n\n## Appendix\nAPPENDIX-AFTER-UPDATE\n' >> "$vault/daily-notes/alice/2026-10-05-a.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "three updates: the last is loaded" "U3-IN" "$out"
  assert_not_contains "three updates: content after it under another heading is not" "APPENDIX-AFTER-UPDATE" "$out"
  assert_contains "three updates: says 2 earlier ones were left out" "2 earlier update(s) in the note not loaded" "$out"
  return 0
}

test_a_repos_path_without_a_placeholder_names_one_fixed_doc() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_dir); mkdir -p "$vault/docs"
  printf -- '---\nreposPath: docs/overview.md\n---\n' > "$vault/vault-config.md"
  echo "FIXED-OVERVIEW" > "$vault/docs/overview.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "reposPath with no {repo}: that file is loaded" "FIXED-OVERVIEW" "$out"
  assert_contains "…and the header shows it" "## docs/overview.md" "$out"
  return 0
}

test_config_values_with_trailing_comments_and_empty_values() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_dir)
  mkdir -p "$vault/Projects/widget" "$vault/repos/widget"
  echo "COMMENTED-DOC" > "$vault/Projects/widget/index.md"; echo "$DOC_MARKER" > "$vault/repos/widget/index.md"
  printf -- '---\nreposPath: Projects/{repo}/index.md   # where repo docs live\n---\n' > "$vault/vault-config.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "a trailing '# comment' is stripped from the value" "COMMENTED-DOC" "$out"
  printf -- '---\nreposPath:\ndailyNotesPath: ""\n---\n' > "$vault/vault-config.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "empty values fall back to the defaults" "$DOC_MARKER" "$out"
  return 0
}

test_a_longer_config_key_is_not_mistaken_for_a_shorter_one() {
  local repo vault out
  repo=$(fx_repo widget); vault=$(fx_vault)
  printf -- '---\nreposPathExtra: elsewhere/{repo}.md\n---\n' > "$vault/vault-config.md"
  out=$(run_hook "$repo" "$vault" "$STARTUP_EVENT")
  assert_contains "reposPathExtra is not read as reposPath: default doc still loads" "$DOC_MARKER" "$out"
  return 0
}

test_the_hook_always_exits_zero
test_every_source_except_compact_injects_context
test_compact_is_recognised_whatever_the_json_layout
test_repo_name_falls_back_to_the_folder_name_without_an_origin
test_repo_name_comes_from_the_origin_in_every_common_form
test_output_starts_with_the_context_header
test_a_note_with_only_one_forward_section_loads_just_that_one
test_sections_end_at_the_next_heading_and_keep_their_subheadings
test_non_markdown_files_are_never_picked_as_the_latest_note
test_notes_in_nested_folders_and_with_spaces_in_the_name_are_found
test_an_empty_daily_notes_folder_says_there_are_no_notes
test_a_note_with_windows_line_endings_is_still_loaded
test_the_hook_never_writes_to_the_vault
test_update_cap_can_be_changed_with_update_max_lines
test_update_stops_at_the_next_heading_and_counts_earlier_updates
test_a_repos_path_without_a_placeholder_names_one_fixed_doc
test_config_values_with_trailing_comments_and_empty_values
test_a_longer_config_key_is_not_mistaken_for_a_shorter_one

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
