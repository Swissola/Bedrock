#!/usr/bin/env bash
# Test harness for tools/hook-templates/session-start-vault-check.
# Run: bash tools/hook-templates/test-session-start-vault-check.sh
#
# The hook reminds you, at session start and (throttled) after tool calls, that the
# vault has commits not on origin yet. Its promises, each pinned down here: it
# exits 0 on every path, it prints the reminder on stdout (which Claude Code feeds
# to the session), it stays silent unless something is really unpushed, SessionStart
# is never throttled while PostToolUse is, it fails open on missing or malformed
# input, and it never puts commit subjects in the message.
#
# Fixtures are throwaway repos under mktemp: a "vault" pushed once to a local bare
# "origin", then given local-only commits. The hook's state directory is
# $HOME/.claude/hook-logs with no override of its own, so every run replaces HOME
# with a temp directory; nothing here touches the real one.
#
# Among other things it checks: exit status on every path, the
# throttle boundaries, marker behaviour on every path, both ways round for the
# jq-less fallback, hash listing, and behind-only and diverged origins.

set -u
HOOK_SCRIPT="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-start-vault-check}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0
UNPUSHED_TEXT="unpushed commit(s)"; ONE_PENDING="has 1 unpushed commit(s)"
CLEANUP_DIRS=()
LAST_CHECK_REL=".claude/hook-logs/.vault-nudge-last-check"
SECRET_SUBJECT="SUBJECT_MARKER_DO_NOT_ECHO"
START='{"hook_event_name":"SessionStart"}'
POST='{"hook_event_name":"PostToolUse"}'

# Removes every fixture even when the script is interrupted or a check fails.
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d" 2>/dev/null; done
  return 0
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" = "$actual" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (expected [$expected], got [$actual])"
    FAIL=$((FAIL + 1))
  fi
  return $?
}

# assert_has <desc> <file> <literal>: the file contains the text.
assert_has() {
  local desc="$1" file="$2" needle="$3"
  assert_eq "$desc" "yes" "$(grep -qF -- "$needle" "$file" 2>/dev/null && echo yes || echo no)"
  return $?
}

# assert_lacks <desc> <file> <literal>: the file does not contain the text.
assert_lacks() {
  local desc="$1" file="$2" needle="$3"
  assert_eq "$desc" "no" "$(grep -qF -- "$needle" "$file" 2>/dev/null && echo yes || echo no)"
  return $?
}

# assert_silent <desc> <file>: the file exists and is empty.
assert_silent() {
  local desc="$1" file="$2"
  assert_eq "$desc" "empty" "$([[ -f "$file" ]] && [[ ! -s "$file" ]] && echo empty || echo "not-empty")"
  return $?
}

now() { date +%s; return $?; }

# mtime_of <file>: seconds since the epoch, GNU or BSD stat.
mtime_of() { local file="$1"; stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null; return $?; }

# age_file <file> <seconds>: set the file's mtime that many seconds in the past.
# GNU `touch -d @N` does not exist on macOS, so build a touch -t stamp instead.
age_file() {
  local f="$1" secs="$2" epoch stamp
  epoch=$(( $(now) - secs ))
  stamp=$(date -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$epoch" +%Y%m%d%H%M.%S)
  touch -t "$stamp" "$f"
  return $?
}

marker_exists() { [[ -f "$FAKE_HOME/$LAST_CHECK_REL" ]] && echo yes || echo no; return $?; }

# make_marker <age-seconds>: a throttle marker last touched that long ago.
make_marker() {
  local age="$1"
  mkdir -p "$FAKE_HOME/.claude/hook-logs"
  : > "$FAKE_HOME/$LAST_CHECK_REL"
  age_file "$FAKE_HOME/$LAST_CHECK_REL" "$age"
  return $?
}

new_workdir() {
  WORK=$(mktemp -d)
  CLEANUP_DIRS+=("$WORK")
  VAULT="$WORK/vault"
  FAKE_HOME="$WORK/home"
  OUT="$WORK/stdout.log"
  ERR="$WORK/stderr.log"
  mkdir -p "$FAKE_HOME"
  return $?
}

drop_workdir() { rm -rf "$WORK"; return $?; }

init_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config core.autocrlf false
  printf 'a\n' > "$dir/f.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init"
  git -C "$dir" branch -M "$branch"
  return $?
}

# vault_ahead <n> [subject-prefix]: vault on main, pushed once to a bare origin,
# then n local-only commits.
vault_ahead() {
  local n="$1" subject="${2:-pending commit}" i
  init_repo "$VAULT" main
  git init -q --bare "$WORK/origin.git"
  git -C "$VAULT" remote add origin "$WORK/origin.git"
  git -C "$VAULT" push -q origin main
  i=1
  while [[ "$i" -le "$n" ]]; do
    printf 'line-%s\n' "$i" >> "$VAULT/f.md"
    git -C "$VAULT" commit -qam "$subject $i"
    i=$((i + 1))
  done
  return $?
}

# PATH with every directory that holds jq removed, so the "no jq" tests behave the
# same on a machine that has it installed.
path_without_jq() {
  local jq_path jq_dir out="" dir shim c p
  jq_path=$(command -v jq) || { printf '%s' "$PATH"; return 0; }   # no jq at all: nothing to hide
  jq_dir=$(dirname "$jq_path")
  if [[ "$(dirname "$(command -v bash)")" = "$jq_dir" || "$(dirname "$(command -v git)")" = "$jq_dir" ]]; then
    # jq lives next to bash and git (Linux: /usr/bin), so dropping its directory would drop
    # them too and the hook could not start. Build a PATH of links to just what the hook
    # needs, without jq.
    shim="$WORK/nojq-bin"; mkdir -p "$shim"
    for c in bash git cat grep sed awk date stat touch mkdir tr wc head cut sort dirname basename rm env sleep; do
      p=$(command -v "$c" 2>/dev/null) && [[ -x "$p" ]] && ln -sf "$p" "$shim/$c"
    done
    printf '%s' "$shim"
    return 0
  fi
  local IFS=:
  for dir in $PATH; do
    [[ -x "$dir/jq" || -x "$dir/jq.exe" ]] && continue
    out="${out:+$out:}$dir"
  done
  printf '%s' "$out"
  return 0
}

# run_hook <vault-root-or-empty> <stdin> [path-override]: runs the hook from the
# work dir (not the vault), with HOME redirected. Sets $STATUS; stdout and stderr
# land in $OUT and $ERR.
run_hook() {
  local vroot="$1" input="$2" path="${3:-$PATH}"
  : > "$OUT"; : > "$ERR"
  mkdir -p "$WORK/elsewhere"
  if [[ -n "$vroot" ]]; then
    ( cd "$WORK/elsewhere" && printf '%s' "$input" | env PATH="$path" HOME="$FAKE_HOME" VAULT_ROOT="$vroot" bash "$HOOK_SCRIPT" ) > "$OUT" 2> "$ERR"
  else
    ( cd "$WORK/elsewhere" && printf '%s' "$input" | env -u VAULT_ROOT PATH="$path" HOME="$FAKE_HOME" bash "$HOOK_SCRIPT" ) > "$OUT" 2> "$ERR"
  fi
  STATUS=$?
  return $?
}

# --- nothing to report --------------------------------------------------------

test_silent_and_exit_0_when_vault_root_cannot_be_derived() {
  new_workdir
  run_hook "" "$START"
  assert_eq "no vault root: exit 0" "0" "$STATUS"
  assert_silent "no vault root: nothing on stdout" "$OUT"
  assert_eq "no vault root: no marker (no check happened)" "no" "$(marker_exists)"
  drop_workdir
  return $?
}

# A vault that is just a folder (for example one kept in sync by Syncthing) has no commits
# to be unpushed, so the hook has nothing to say, at either event, and must not fail.
test_silent_and_exit_0_when_the_vault_is_not_a_git_repo() {
  new_workdir
  mkdir -p "$VAULT"; echo "a note" > "$VAULT/note.md"; rm -rf "$VAULT/.git"
  run_hook "$VAULT" "$START"
  assert_eq "plain-folder vault, SessionStart: exit 0" "0" "$STATUS"
  assert_silent "plain-folder vault, SessionStart: nothing on stdout" "$OUT"
  run_hook "$VAULT" "$POST"
  assert_eq "plain-folder vault, PostToolUse: exit 0" "0" "$STATUS"
  assert_silent "plain-folder vault, PostToolUse: nothing on stdout" "$OUT"
  drop_workdir
  return $?
}

test_silent_when_vault_has_no_main_branch() {
  new_workdir
  init_repo "$VAULT" trunk
  run_hook "$VAULT" "$START"
  assert_eq "no main branch: exit 0" "0" "$STATUS"
  assert_silent "no main branch: nothing on stdout" "$OUT"
  assert_eq "no main branch: no marker (no check happened)" "no" "$(marker_exists)"
  drop_workdir
  return $?
}

test_silent_when_vault_has_no_origin() {
  new_workdir
  init_repo "$VAULT" main
  run_hook "$VAULT" "$START"
  assert_eq "no origin remote: exit 0" "0" "$STATUS"
  assert_silent "no origin remote: nothing on stdout" "$OUT"
  assert_eq "no origin remote: no marker (no check happened)" "no" "$(marker_exists)"
  drop_workdir
  return $?
}

test_in_sync_is_silent_but_records_that_a_check_ran() {
  new_workdir
  vault_ahead 0
  run_hook "$VAULT" "$START"
  assert_eq "in sync: exit 0" "0" "$STATUS"
  assert_silent "in sync: nothing on stdout" "$OUT"
  assert_eq "in sync: marker written, the check genuinely ran" "yes" "$(marker_exists)"
  drop_workdir
  return $?
}

test_silent_when_vault_is_only_behind_origin() {
  new_workdir
  vault_ahead 0
  git clone -q -b main "$WORK/origin.git" "$WORK/clone"
  git -C "$WORK/clone" config core.autocrlf false
  git -C "$WORK/clone" config user.email "test@example.com"
  git -C "$WORK/clone" config user.name "Test"
  printf 'remote\n' >> "$WORK/clone/f.md"
  git -C "$WORK/clone" commit -qam "someone else's commit"
  git -C "$WORK/clone" push -q origin HEAD:main
  git -C "$VAULT" fetch -q origin
  assert_eq "behind only: fixture really has origin ahead of main" "1" "$(git -C "$VAULT" rev-list --count main..origin/main)"
  run_hook "$VAULT" "$START"
  assert_eq "behind only: exit 0" "0" "$STATUS"
  assert_silent "behind only: nothing unpushed, so nothing on stdout" "$OUT"
  drop_workdir
  return $?
}

test_compact_source_skips_even_with_pending_commits() {
  new_workdir
  vault_ahead 2
  run_hook "$VAULT" '{"source":"compact","hook_event_name":"SessionStart"}'
  assert_eq "compact: exit 0" "0" "$STATUS"
  assert_silent "compact: no reminder when the session is only recompacting" "$OUT"
  assert_eq "compact: no marker, the check was skipped entirely" "no" "$(marker_exists)"
  drop_workdir
  return $?
}

# --- the reminder -----------------------------------------------------------------

test_session_start_reports_count_hashes_and_commands() {
  new_workdir
  vault_ahead 2
  run_hook "$VAULT" "$START"
  assert_eq "session start: exit 0, the session is never blocked" "0" "$STATUS"
  assert_has "session start: count" "$OUT" "has 2 unpushed commit(s) on main"
  assert_has "session start: vault path" "$OUT" "$VAULT"
  assert_has "session start: review command" "$OUT" "git -C \"$VAULT\" log origin/main..main"
  assert_has "session start: push command" "$OUT" "git -C \"$VAULT\" push"
  assert_silent "session start: stderr stays empty" "$ERR"
  assert_eq "session start: marker written" "yes" "$(marker_exists)"
  drop_workdir
  return $?
}

test_reminder_lists_exactly_the_pending_short_hashes() {
  new_workdir
  vault_ahead 2
  local h1 h2
  h1=$(git -C "$VAULT" log -1 --format=%h)
  h2=$(git -C "$VAULT" log -2 --format=%h | tail -n1)
  run_hook "$VAULT" "$START"
  assert_has "hashes: newest pending commit listed" "$OUT" "$h1"
  assert_has "hashes: older pending commit listed" "$OUT" "$h2"
  assert_has "hashes: comma separated, newest first" "$OUT" "($h1, $h2)"
  drop_workdir
  return $?
}

test_single_pending_commit_is_reported() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" "$START"
  assert_has "1 pending: count" "$OUT" "$ONE_PENDING"
  drop_workdir
  return $?
}

test_counts_only_local_commits_when_origin_has_diverged() {
  new_workdir
  vault_ahead 2
  git clone -q -b main "$WORK/origin.git" "$WORK/clone"
  git -C "$WORK/clone" config core.autocrlf false
  git -C "$WORK/clone" config user.email "test@example.com"
  git -C "$WORK/clone" config user.name "Test"
  printf 'remote\n' > "$WORK/clone/other.md"
  git -C "$WORK/clone" add other.md
  git -C "$WORK/clone" commit -qm "remote-only commit"
  git -C "$WORK/clone" push -q origin HEAD:main
  git -C "$VAULT" fetch -q origin
  assert_eq "diverged: fixture really has 1 commit on origin that main lacks" "1" "$(git -C "$VAULT" rev-list --count main..origin/main)"
  run_hook "$VAULT" "$START"
  assert_has "diverged: only the 2 local-only commits are counted" "$OUT" "has 2 unpushed commit(s)"
  drop_workdir
  return $?
}

test_commit_subjects_are_never_echoed() {
  new_workdir
  vault_ahead 2 "$SECRET_SUBJECT"
  run_hook "$VAULT" "$START"
  assert_has "subjects: the reminder is still shown" "$OUT" "$UNPUSHED_TEXT"
  assert_lacks "subjects: commit message text is not echoed to stdout" "$OUT" "$SECRET_SUBJECT"
  assert_lacks "subjects: commit message text is not echoed to stderr" "$ERR" "$SECRET_SUBJECT"
  drop_workdir
  return $?
}

test_vault_path_with_a_space_is_handled() {
  new_workdir
  VAULT="$WORK/my vault"
  vault_ahead 1
  run_hook "$VAULT" "$START"
  assert_eq "space in vault path: exit 0" "0" "$STATUS"
  assert_has "space in vault path: push command names the full path" "$OUT" "git -C \"$VAULT\" push"
  drop_workdir
  return $?
}

# --- throttling: PostToolUse only --------------------------------------------------

test_session_start_is_never_throttled() {
  new_workdir
  vault_ahead 1
  make_marker 5
  run_hook "$VAULT" "$START"
  assert_has "session start with a 5s-old marker: still reminds" "$OUT" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

test_post_tool_use_first_check_is_not_throttled() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" "$POST"
  assert_has "post-tool-use, no marker yet: reminds" "$OUT" "$ONE_PENDING"
  assert_eq "post-tool-use, no marker yet: marker written" "yes" "$(marker_exists)"
  drop_workdir
  return $?
}

test_post_tool_use_within_cooldown_is_silent_and_leaves_marker() {
  new_workdir
  vault_ahead 2
  make_marker 100
  local before after
  before=$(mtime_of "$FAKE_HOME/$LAST_CHECK_REL")
  run_hook "$VAULT" "$POST"
  after=$(mtime_of "$FAKE_HOME/$LAST_CHECK_REL")
  assert_eq "post-tool-use within cooldown: exit 0" "0" "$STATUS"
  assert_silent "post-tool-use within cooldown: throttled, silent" "$OUT"
  assert_eq "post-tool-use within cooldown: marker mtime unchanged" "$before" "$after"
  drop_workdir
  return $?
}

test_post_tool_use_after_cooldown_reminds_and_refreshes_marker() {
  new_workdir
  vault_ahead 2
  make_marker 3700
  run_hook "$VAULT" "$POST"
  assert_has "post-tool-use at 3700s of 3600s: reminds" "$OUT" "$UNPUSHED_TEXT"
  assert_eq "post-tool-use at 3700s: marker refreshed to now" "yes" "$([[ $(( $(now) - $(mtime_of "$FAKE_HOME/$LAST_CHECK_REL") )) -lt 60 ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_cooldown_boundary_just_inside_is_throttled() {
  new_workdir
  vault_ahead 1
  make_marker 3570
  run_hook "$VAULT" "$POST"
  assert_silent "3570s old (cooldown 3600s): still throttled" "$OUT"
  drop_workdir
  return $?
}

test_cooldown_boundary_just_outside_reminds() {
  new_workdir
  vault_ahead 1
  make_marker 3630
  run_hook "$VAULT" "$POST"
  assert_has "3630s old (cooldown 3600s): reminds" "$OUT" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

test_throttled_post_tool_use_still_reminds_at_next_session_start() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" "$POST"
  assert_has "first post-tool-use: reminds" "$OUT" "$UNPUSHED_TEXT"
  run_hook "$VAULT" "$POST"
  assert_silent "second post-tool-use straight after: throttled" "$OUT"
  run_hook "$VAULT" "$START"
  assert_has "session start straight after: not throttled" "$OUT" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

# --- fail open ------------------------------------------------------------------

test_without_jq_it_still_checks_and_never_throttles() {
  new_workdir
  vault_ahead 1
  make_marker 5
  run_hook "$VAULT" "$POST" "$(path_without_jq)"
  assert_eq "no jq: exit 0" "0" "$STATUS"
  assert_has "no jq: event unknown, treated as session start, so it reminds even inside the cooldown" "$OUT" "$ONE_PENDING"
  drop_workdir
  return $?
}

test_without_jq_compact_cannot_be_detected_so_it_still_checks() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" '{"source":"compact"}' "$(path_without_jq)"
  assert_has "no jq + compact: the skip needs jq, so the safe direction is to check" "$OUT" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

test_malformed_stdin_still_checks() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" "this is not json"
  assert_eq "malformed stdin: exit 0" "0" "$STATUS"
  assert_has "malformed stdin: still reminds" "$OUT" "$ONE_PENDING"
  drop_workdir
  return $?
}

test_empty_stdin_still_checks() {
  new_workdir
  vault_ahead 1
  run_hook "$VAULT" ""
  assert_eq "empty stdin: exit 0" "0" "$STATUS"
  assert_has "empty stdin: still reminds" "$OUT" "$ONE_PENDING"
  drop_workdir
  return $?
}

test_json_without_an_event_name_is_treated_as_unthrottled() {
  new_workdir
  vault_ahead 1
  make_marker 5
  run_hook "$VAULT" '{"session_id":"abc"}'
  assert_has "json with no hook_event_name: not throttled" "$OUT" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

test_silent_and_exit_0_when_vault_root_cannot_be_derived
test_silent_and_exit_0_when_the_vault_is_not_a_git_repo
test_silent_when_vault_has_no_main_branch
test_silent_when_vault_has_no_origin
test_in_sync_is_silent_but_records_that_a_check_ran
test_silent_when_vault_is_only_behind_origin
test_compact_source_skips_even_with_pending_commits
test_session_start_reports_count_hashes_and_commands
test_reminder_lists_exactly_the_pending_short_hashes
test_single_pending_commit_is_reported
test_counts_only_local_commits_when_origin_has_diverged
test_commit_subjects_are_never_echoed
test_vault_path_with_a_space_is_handled
test_session_start_is_never_throttled
test_post_tool_use_first_check_is_not_throttled
test_post_tool_use_within_cooldown_is_silent_and_leaves_marker
test_post_tool_use_after_cooldown_reminds_and_refreshes_marker
test_cooldown_boundary_just_inside_is_throttled
test_cooldown_boundary_just_outside_reminds
test_throttled_post_tool_use_still_reminds_at_next_session_start
test_without_jq_it_still_checks_and_never_throttles
test_without_jq_compact_cannot_be_detected_so_it_still_checks
test_malformed_stdin_still_checks
test_empty_stdin_still_checks
test_json_without_an_event_name_is_treated_as_unthrottled

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
