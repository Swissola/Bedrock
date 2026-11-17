#!/usr/bin/env bash
# Test harness for tools/migrate-vault-format, the one-shot converter to vault format 2.
# Run: bash tools/testing/test-migrate-vault-format.sh
#
# Every fixture is a throwaway vault under mktemp, built here. Nothing reads a real vault.
# The script writes a backup beside the vault, so each vault lives in its own parent folder
# and is removed with it.

set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
SCRIPT="${SCRIPT_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/migrate-vault-format}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0
CLEANUP_DIRS=()
NOTES_DIR=daily-notes
CONFIG_FILE=vault-config.md
OPEN_FILE_WIDGET=open-items-widget.md

cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d" 2>/dev/null; done
  return 0
}
trap cleanup EXIT

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
assert_file_missing() {
  local desc="$1" path="$2"
  if [[ -e "$path" ]]; then echo "FAIL: $desc ($path exists)"; FAIL=$((FAIL + 1))
  else echo "PASS: $desc"; PASS=$((PASS + 1)); fi
  return $?
}

# A new empty vault; prints its path. The parent is what gets cleaned up.
new_vault() {
  local parent
  parent="$(mktemp -d)"
  CLEANUP_DIRS+=("$parent")
  mkdir -p "$parent/vault"
  echo "$parent/vault"
  return 0
}

# note_file <path> <repo frontmatter or empty>: a daily note whose open-item lines come from stdin.
note_file() {
  local path="$1" repo="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo '---'
    if [[ -n "$repo" ]]; then echo "repo: $repo"; fi
    echo 'tags: [daily-note]'
    echo '---'
    echo
    echo '## What Was Done'
    echo '1. something'
    echo
    echo '## Open Questions / Next Steps'
    cat
  } > "$path"
  return 0
}

write_config() {  # args: vault, then one "key: value" per argument
  local v="$1"; shift
  { echo '---'; local l; for l in "$@"; do echo "$l"; done; echo '---'; echo; echo 'settings'; } > "$v/$CONFIG_FILE"
  return 0
}

# A checksum listing of every file under a folder, for before and after comparisons.
snapshot() {
  local f
  find "$1" -type f | sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done
  return 0
}

# run_migrate <vault> [args]: sets OUT and ST.
OUT=""
ST=0
run_migrate() {
  local v="$1"; shift
  OUT="$(bash "$SCRIPT" --vault "$v" "$@" 2>&1)"; ST=$?
  return 0
}

open_count() { grep -c '^- \[ \]' "$1" 2>/dev/null || true; return 0; }
marker_of() { [[ -f "$1/$CONFIG_FILE" ]] || return 0; tr -d '\r' < "$1/$CONFIG_FILE" | grep '^vaultFormat:' | head -n 1; return 0; }

test_a_solo_flat_vault_converts() {
  local v; v="$(new_vault)"
  write_config "$v" "dailyNotesPath: $NOTES_DIR" "reposPath: Projects/{repo}/index.md"
  mkdir -p "$v/Projects/widget"; echo doc > "$v/Projects/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n- [ ] two (opened 2026-11-02)\n- [ ] three\n' | note_file "$v/$NOTES_DIR/2026-11-03-widget-first.md" ""
  run_migrate "$v"
  assert_eq "solo flat: exit 0" "0" "$ST"
  assert_eq "solo flat: three open items written" "3" "$(open_count "$v/$NOTES_DIR/$OPEN_FILE_WIDGET")"
  assert_eq "solo flat: marker set" "vaultFormat: 2" "$(marker_of "$v")"
  assert_contains "solo flat: file names the repo" "repo: widget" "$(cat "$v/$NOTES_DIR/$OPEN_FILE_WIDGET")"
  assert_contains "solo flat: has Open and Closed sections" "## Closed" "$(cat "$v/$NOTES_DIR/$OPEN_FILE_WIDGET")"
  return 0
}

test_a_team_vault_converts_per_author() {
  local v; v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] alice item (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-03-widget-a.md" ""
  printf -- '- [ ] bob item (opened 2026-11-02)\n' | note_file "$v/$NOTES_DIR/bob/2026-11-04-widget-b.md" ""
  run_migrate "$v"
  assert_eq "team: exit 0" "0" "$ST"
  assert_eq "team: alice has one item" "1" "$(open_count "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET")"
  assert_contains "team: alice's file has her item" "alice item" "$(cat "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET")"
  assert_contains "team: bob's file has his item" "bob item" "$(cat "$v/$NOTES_DIR/bob/$OPEN_FILE_WIDGET")"
  assert_eq "team: nothing of bob's in alice's file" "0" "$(grep -c 'bob item' "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET")"
  return 0
}

test_a_second_run_changes_nothing() {
  local v before after
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-03-widget-a.md" ""
  run_migrate "$v"
  before="$(snapshot "$v")"
  run_migrate "$v"
  after="$(snapshot "$v")"
  assert_eq "second run: exit 0" "0" "$ST"
  assert_eq "second run: no file changed" "$before" "$after"
  assert_contains "second run: says it is already converted" "already" "$OUT"
  assert_eq "second run: no second backup" "1" "$(find "$(dirname "$v")" -maxdepth 1 -name 'vault-backup-*' | wc -l | tr -d ' ')"
  return 0
}

test_a_dry_run_writes_nothing() {
  local v before after
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-03-widget-a.md" ""
  before="$(snapshot "$(dirname "$v")")"
  run_migrate "$v" --dry-run
  after="$(snapshot "$(dirname "$v")")"
  assert_eq "dry run: exit 0" "0" "$ST"
  assert_eq "dry run: nothing written, no backup" "$before" "$after"
  assert_contains "dry run: says so" "dry-run" "$OUT"
  assert_contains "dry run: reports the counts" "repo=widget author=alice read=1 written=1 merged=0" "$OUT"
  return 0
}

test_notes_on_the_latest_date_are_merged_and_older_ones_ignored() {
  local v f
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] older only (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-10-widget-old.md" ""
  printf -- '- [ ] item A (opened 2026-11-02)\n- [ ] item B (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-15-widget-one.md" ""
  printf -- '- [ ] item B (opened 2026-11-05)\n- [ ] item C (opened 2026-11-06)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-15-widget-two.md" ""
  run_migrate "$v"
  f="$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "same-date notes: union of three items" "3" "$(open_count "$f")"
  assert_contains "same-date notes: counts reported" "read=4 written=3 merged=1" "$OUT"
  assert_contains "same-date notes: earliest opened date kept for the duplicate" "item B (opened 2026-11-01)" "$(cat "$f")"
  assert_eq "same-date notes: the older note's item is not carried" "0" "$(grep -c 'older only' "$f")"
  return 0
}

test_a_from_suffix_is_stripped_and_deduplicated() {
  local v f
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] Fix thing (from [[2026-11-01-widget-x]], opened 2026-10-20)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-15-widget-one.md" ""
  printf -- '- [ ] Fix thing (opened 2026-10-20)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-15-widget-two.md" ""
  run_migrate "$v"
  f="$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "from-suffix: one item" "1" "$(open_count "$f")"
  assert_contains "from-suffix: clean line" "- [ ] Fix thing (opened 2026-10-20)" "$(cat "$f")"
  assert_eq "from-suffix: no wikilink left" "0" "$(grep -c '\[\[' "$f")"
  return 0
}

test_an_item_with_no_opened_date_takes_the_note_date() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] bare item\n' | note_file "$v/$NOTES_DIR/alice/2026-11-03-widget-a.md" ""
  run_migrate "$v"
  assert_contains "no opened: note date used" "- [ ] bare item (opened 2026-11-03)" "$(cat "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET")"
  return 0
}

test_a_repo_with_no_open_items_gets_an_empty_open_section() {
  local v f
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [x] done already (done 2026-11-02)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-03-widget-a.md" ""
  run_migrate "$v"
  f="$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "no open items: exit 0" "0" "$ST"
  assert_eq "no open items: zero items listed" "0" "$(open_count "$f")"
  assert_contains "no open items: still has the Open heading" "## Open" "$(cat "$f")"
  assert_contains "no open items: reported" "read=0 written=0" "$OUT"
  return 0
}

test_a_shorter_repo_name_does_not_claim_a_longer_ones_notes() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget" "$v/repos/widget-ui"; echo doc > "$v/repos/widget/index.md"; echo doc > "$v/repos/widget-ui/index.md"
  printf -- '- [ ] ui item (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-ui-theme.md" ""
  printf -- '- [ ] core item (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-04-widget-core.md" ""
  run_migrate "$v"
  assert_eq "prefix: widget has one item" "1" "$(open_count "$v/$NOTES_DIR/alice/open-items-widget.md")"
  assert_contains "prefix: widget has the core item" "core item" "$(cat "$v/$NOTES_DIR/alice/open-items-widget.md")"
  assert_contains "prefix: widget-ui has the ui item" "ui item" "$(cat "$v/$NOTES_DIR/alice/open-items-widget-ui.md")"
  return 0
}

test_the_repo_in_a_notes_frontmatter_wins_over_its_filename() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] named by frontmatter (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-misc-thing.md" widget
  run_migrate "$v"
  assert_contains "frontmatter: item lands in widget's file" "named by frontmatter" "$(cat "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET")"
  return 0
}

test_crlf_notes_convert_without_carriage_returns() {
  local v f
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n- [ ] two (opened 2026-11-02)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  sed 's/$/\r/' "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" > "$v/crlf.tmp" && mv "$v/crlf.tmp" "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md"
  run_migrate "$v"
  f="$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "CRLF: both items converted" "2" "$(open_count "$f")"
  assert_eq "CRLF: no carriage return in the output" "0" "$(grep -c "$(printf '\r')" "$f")"
  return 0
}

test_repo_name_case_keep_names_the_file_with_the_repos_case() {
  local v
  v="$(new_vault)"
  write_config "$v" "repoNameCase: keep"
  mkdir -p "$v/repos/Widget"; echo doc > "$v/repos/Widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-Widget-a.md" ""
  run_migrate "$v"
  assert_eq "case keep: mixed-case file name" "1" "$(open_count "$v/$NOTES_DIR/alice/open-items-Widget.md")"
  assert_eq "case keep: marker added and the setting kept" "repoNameCase: keep" "$(grep '^repoNameCase' "$v/$CONFIG_FILE")"
  return 0
}

test_the_backup_is_outside_the_vault_and_holds_the_originals() {
  local v b
  v="$(new_vault)"
  write_config "$v" "dailyNotesPath: $NOTES_DIR/{author}"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  run_migrate "$v"
  b="$(printf '%s\n' "$OUT" | sed -n 's/^backup=//p' | head -n 1)"
  assert_eq "backup: a folder was reported and exists" "yes" "$([[ -n "$b" && -d "$b" ]] && echo yes || echo no)"
  case "$b/" in "$v"/*) echo "FAIL: backup is inside the vault"; FAIL=$((FAIL + 1)) ;; *) echo "PASS: backup is outside the vault"; PASS=$((PASS + 1)) ;; esac
  assert_eq "backup: has the original note" "yes" "$([[ -f "$b/$NOTES_DIR/alice/2026-11-05-widget-a.md" ]] && echo yes || echo no)"
  assert_eq "backup: has the original config, without the marker" "" "$(marker_of "$b")"
  return 0
}

test_a_conflict_copy_of_an_open_items_file_stops_the_run() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  echo stale > "$v/$NOTES_DIR/alice/open-items-widget.sync-conflict-20261101-120000-ABCDEFG.md"
  run_migrate "$v"
  assert_eq "conflict: exit 2" "2" "$ST"
  assert_contains "conflict: names the problem" "conflict" "$OUT"
  assert_file_missing "conflict: no open-items file written" "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "conflict: no marker" "" "$(marker_of "$v")"
  return 0
}

test_a_failed_verification_sets_no_marker_and_writes_nothing() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n- [ ] two (opened 2026-11-02)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  OUT="$(MIGRATE_FAIL_AFTER_WRITE=1 bash "$SCRIPT" --vault "$v" 2>&1)"; ST=$?
  assert_eq "mismatch: exit 1" "1" "$ST"
  assert_file_missing "mismatch: no open-items file moved into place" "$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  assert_eq "mismatch: no marker" "" "$(marker_of "$v")"
  return 0
}

test_old_notes_are_left_untouched() {
  local v before after
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  printf -- '- [ ] two (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-02-widget-b.md" ""
  before="$(snapshot "$v/$NOTES_DIR/alice" | grep -v open-items)"
  run_migrate "$v"
  after="$(snapshot "$v/$NOTES_DIR/alice" | grep -v open-items)"
  assert_eq "old notes: byte-identical after the run" "$before" "$after"
  return 0
}

test_an_existing_open_items_file_is_kept() {
  local v f
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  f="$v/$NOTES_DIR/alice/$OPEN_FILE_WIDGET"
  printf -- '---\nrepo: widget\n---\n\n## Open\n- [ ] hand edited (opened 2026-11-09)\n\n## Closed\n' > "$f"
  run_migrate "$v"
  assert_contains "existing file: content kept" "hand edited" "$(cat "$f")"
  assert_eq "existing file: the old item was not added to it" "0" "$(grep -c 'one (opened' "$f")"
  assert_eq "existing file: marker still set" "vaultFormat: 2" "$(marker_of "$v")"
  return 0
}

test_an_unreadable_config_stops_before_anything_is_written() {
  local v before after
  v="$(new_vault)"
  printf -- '---\ndailyNotesPath: daily-notes\nno closing line\n' > "$v/$CONFIG_FILE"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  before="$(snapshot "$(dirname "$v")")"
  run_migrate "$v"
  after="$(snapshot "$(dirname "$v")")"
  assert_eq "bad config: exit 1" "1" "$ST"
  assert_eq "bad config: nothing written" "$before" "$after"
  return 0
}

test_a_missing_config_is_created_with_the_marker() {
  local v
  v="$(new_vault)"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  run_migrate "$v"
  assert_eq "no config: created with the marker" "vaultFormat: 2" "$(marker_of "$v")"
  return 0
}

test_an_existing_marker_value_is_replaced_not_duplicated() {
  local v
  v="$(new_vault)"
  write_config "$v" "vaultFormat: 1" "staleOpenItemDays: 14"
  mkdir -p "$v/repos/widget"; echo doc > "$v/repos/widget/index.md"
  printf -- '- [ ] one (opened 2026-11-01)\n' | note_file "$v/$NOTES_DIR/alice/2026-11-05-widget-a.md" ""
  run_migrate "$v"
  assert_eq "old marker: one vaultFormat line" "1" "$(grep -c '^vaultFormat:' "$v/$CONFIG_FILE")"
  assert_eq "old marker: now 2" "vaultFormat: 2" "$(marker_of "$v")"
  assert_eq "old marker: other settings kept" "staleOpenItemDays: 14" "$(grep '^staleOpenItemDays' "$v/$CONFIG_FILE")"
  return 0
}

test_bad_usage_exits_2() {
  OUT="$(bash "$SCRIPT" --nonsense 2>&1)"; ST=$?
  assert_eq "usage: unknown option exits 2" "2" "$ST"
  OUT="$(bash "$SCRIPT" --vault "$(mktemp -d)/nope" 2>&1)"; ST=$?
  assert_eq "usage: missing vault folder exits 2" "2" "$ST"
  return 0
}

test_a_solo_flat_vault_converts
test_a_team_vault_converts_per_author
test_a_second_run_changes_nothing
test_a_dry_run_writes_nothing
test_notes_on_the_latest_date_are_merged_and_older_ones_ignored
test_a_from_suffix_is_stripped_and_deduplicated
test_an_item_with_no_opened_date_takes_the_note_date
test_a_repo_with_no_open_items_gets_an_empty_open_section
test_a_shorter_repo_name_does_not_claim_a_longer_ones_notes
test_the_repo_in_a_notes_frontmatter_wins_over_its_filename
test_crlf_notes_convert_without_carriage_returns
test_repo_name_case_keep_names_the_file_with_the_repos_case
test_the_backup_is_outside_the_vault_and_holds_the_originals
test_a_conflict_copy_of_an_open_items_file_stops_the_run
test_a_failed_verification_sets_no_marker_and_writes_nothing
test_old_notes_are_left_untouched
test_an_existing_open_items_file_is_kept
test_an_unreadable_config_stops_before_anything_is_written
test_a_missing_config_is_created_with_the_marker
test_an_existing_marker_value_is_replaced_not_duplicated
test_bad_usage_exits_2

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
