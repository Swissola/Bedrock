#!/usr/bin/env bash
# Test harness for tools/hook-templates/pre-push.
# Run: bash tools/hook-templates/test-pre-push.sh
#
# The hook warns (never blocks) when the vault has commits that are not on
# origin yet, at the moment you push some other repo. Its promises, each pinned
# down here: it exits 0 on every path, it speaks only on stderr, it stays quiet
# unless there really is something unpushed, it throttles repeat warnings, and
# it never puts commit subjects in the message.
#
# Fixtures are throwaway repos under mktemp: a "vault" pushed once to a local bare
# "origin" (so further local commits make a real origin/main..main gap with no
# network), and a separate "other repo" to push from. The hook's state directory is
# $HOME/.claude/hook-logs with no override of its own, so every run replaces HOME
# with a temp directory; nothing here touches the real one.
#
# Among other things it checks: exit status on every path, the
# throttle boundaries, behind-only and diverged origins, and a real `git push`.

set -u
HOOK_SCRIPT="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-push}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0
UNPUSHED_TEXT="unpushed commit(s)"
CLEANUP_DIRS=()
LAST_WARN_REL=".claude/hook-logs/.vault-prepush-last-warn"
SECRET_SUBJECT="SUBJECT_MARKER_DO_NOT_ECHO"

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

new_workdir() {
  WORK=$(mktemp -d)
  CLEANUP_DIRS+=("$WORK")
  VAULT="$WORK/vault"
  OTHER="$WORK/other-repo"
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

other_repo() { init_repo "$OTHER" main; return $?; }

# run_hook <cwd> <vault-root-or-empty> [stdin]: runs the hook as git would, from
# <cwd>, with HOME redirected. Sets $STATUS; stdout and stderr land in $OUT and $ERR.
run_hook() {
  local dir="$1" vroot="$2" input="${3:-refs/heads/main aaa refs/heads/main bbb}"
  : > "$OUT"; : > "$ERR"
  if [[ -n "$vroot" ]]; then
    ( cd "$dir" && printf '%s\n' "$input" | env HOME="$FAKE_HOME" VAULT_ROOT="$vroot" bash "$HOOK_SCRIPT" ) > "$OUT" 2> "$ERR"
  else
    ( cd "$dir" && printf '%s\n' "$input" | env -u VAULT_ROOT HOME="$FAKE_HOME" bash "$HOOK_SCRIPT" ) > "$OUT" 2> "$ERR"
  fi
  STATUS=$?
  return $?
}

# --- nothing to warn about ---------------------------------------------------

test_silent_and_exit_0_when_vault_root_cannot_be_derived() {
  new_workdir
  mkdir -p "$WORK/plain"
  run_hook "$WORK/plain" ""
  assert_eq "no vault root: exit 0" "0" "$STATUS"
  assert_silent "no vault root: nothing on stderr" "$ERR"
  assert_silent "no vault root: nothing on stdout" "$OUT"
  drop_workdir
  return $?
}

test_silent_when_the_repo_being_pushed_is_the_vault_itself() {
  new_workdir
  vault_ahead 2
  run_hook "$VAULT" ""
  assert_eq "pushing the vault: exit 0" "0" "$STATUS"
  assert_silent "pushing the vault: no warning, its commits are what this push sends" "$ERR"
  assert_eq "pushing the vault: no throttle marker written" "no" "$([[ -e "$FAKE_HOME/$LAST_WARN_REL" ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_silent_when_vault_has_no_main_branch() {
  new_workdir
  other_repo
  init_repo "$VAULT" trunk
  run_hook "$OTHER" "$VAULT"
  assert_eq "no main branch: exit 0" "0" "$STATUS"
  assert_silent "no main branch: no warning" "$ERR"
  drop_workdir
  return $?
}

# A vault that is just a folder (for example one kept in sync by Syncthing) has no commits
# to be unpushed, so a push from some other repo gets no warning and must not fail.
test_silent_and_exit_0_when_the_vault_is_not_a_git_repo() {
  new_workdir
  other_repo
  mkdir -p "$VAULT"; echo "a note" > "$VAULT/note.md"; rm -rf "$VAULT/.git"
  run_hook "$OTHER" "$VAULT"
  assert_eq "plain-folder vault: exit 0" "0" "$STATUS"
  assert_silent "plain-folder vault: no warning" "$ERR"
  drop_workdir
  return $?
}

test_silent_when_vault_has_no_origin() {
  new_workdir
  other_repo
  init_repo "$VAULT" main
  run_hook "$OTHER" "$VAULT"
  assert_eq "no origin remote: exit 0" "0" "$STATUS"
  assert_silent "no origin remote: no warning" "$ERR"
  drop_workdir
  return $?
}

test_silent_when_vault_is_in_sync_with_origin() {
  new_workdir
  other_repo
  vault_ahead 0
  run_hook "$OTHER" "$VAULT"
  assert_eq "in sync: exit 0" "0" "$STATUS"
  assert_silent "in sync: no warning" "$ERR"
  assert_eq "in sync: no throttle marker written" "no" "$([[ -e "$FAKE_HOME/$LAST_WARN_REL" ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_silent_when_vault_is_only_behind_origin() {
  new_workdir
  other_repo
  vault_ahead 0
  # a second clone pushes a commit, so origin/main is ahead of the vault's main
  git clone -q -b main "$WORK/origin.git" "$WORK/clone"
  git -C "$WORK/clone" config core.autocrlf false
  git -C "$WORK/clone" config user.email "test@example.com"
  git -C "$WORK/clone" config user.name "Test"
  printf 'remote\n' >> "$WORK/clone/f.md"
  git -C "$WORK/clone" commit -qam "someone else's commit"
  git -C "$WORK/clone" push -q origin HEAD:main
  git -C "$VAULT" fetch -q origin
  assert_eq "behind only: fixture really has origin ahead of main" "1" "$(git -C "$VAULT" rev-list --count main..origin/main)"
  run_hook "$OTHER" "$VAULT"
  assert_eq "behind only: exit 0" "0" "$STATUS"
  assert_silent "behind only: nothing unpushed, so no warning" "$ERR"
  drop_workdir
  return $?
}

# --- the warning ---------------------------------------------------------------

test_warns_with_count_path_and_push_command() {
  new_workdir
  other_repo
  vault_ahead 3
  run_hook "$OTHER" "$VAULT"
  assert_eq "3 pending: exit 0, the push is never blocked" "0" "$STATUS"
  assert_has "3 pending: count in the warning" "$ERR" "has 3 unpushed commit(s)"
  assert_has "3 pending: vault path named" "$ERR" "$VAULT"
  assert_has "3 pending: push command suggested" "$ERR" "git -C \"$VAULT\" push"
  assert_silent "3 pending: stdout stays empty, the warning is on stderr" "$OUT"
  assert_eq "3 pending: throttle marker written" "yes" "$([[ -f "$FAKE_HOME/$LAST_WARN_REL" ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_warns_for_a_single_pending_commit() {
  new_workdir
  other_repo
  vault_ahead 1
  run_hook "$OTHER" "$VAULT"
  assert_has "1 pending: count in the warning" "$ERR" "has 1 unpushed commit(s)"
  drop_workdir
  return $?
}

test_counts_only_local_commits_when_origin_has_diverged() {
  new_workdir
  other_repo
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
  run_hook "$OTHER" "$VAULT"
  assert_has "diverged: only the 2 local-only commits are counted" "$ERR" "has 2 unpushed commit(s)"
  drop_workdir
  return $?
}

test_commit_subjects_are_never_echoed() {
  new_workdir
  other_repo
  vault_ahead 2 "$SECRET_SUBJECT"
  run_hook "$OTHER" "$VAULT"
  assert_has "subjects: the warning is still shown" "$ERR" "$UNPUSHED_TEXT"
  assert_lacks "subjects: commit message text is not echoed to stderr" "$ERR" "$SECRET_SUBJECT"
  assert_lacks "subjects: commit message text is not echoed to stdout" "$OUT" "$SECRET_SUBJECT"
  drop_workdir
  return $?
}

test_creates_its_state_directory_when_missing() {
  new_workdir
  other_repo
  vault_ahead 1
  rm -rf "$FAKE_HOME/.claude"
  run_hook "$OTHER" "$VAULT"
  assert_eq "no state dir yet: exit 0" "0" "$STATUS"
  assert_eq "no state dir yet: created along with the marker" "yes" "$([[ -f "$FAKE_HOME/$LAST_WARN_REL" ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_vault_path_with_a_space_is_handled() {
  new_workdir
  other_repo
  VAULT="$WORK/my vault"
  vault_ahead 1
  run_hook "$OTHER" "$VAULT"
  assert_eq "space in vault path: exit 0" "0" "$STATUS"
  assert_has "space in vault path: warning names the full path" "$ERR" "git -C \"$VAULT\" push"
  drop_workdir
  return $?
}

# --- throttling -------------------------------------------------------------

test_second_warning_within_cooldown_is_suppressed() {
  new_workdir
  other_repo
  vault_ahead 2
  run_hook "$OTHER" "$VAULT"
  assert_has "first push: warned" "$ERR" "$UNPUSHED_TEXT"
  run_hook "$OTHER" "$VAULT"
  assert_eq "second push straight after: exit 0" "0" "$STATUS"
  assert_silent "second push straight after: throttled, no warning" "$ERR"
  drop_workdir
  return $?
}

test_throttled_run_does_not_move_the_marker() {
  new_workdir
  other_repo
  vault_ahead 2
  mkdir -p "$FAKE_HOME/.claude/hook-logs"
  : > "$FAKE_HOME/$LAST_WARN_REL"
  age_file "$FAKE_HOME/$LAST_WARN_REL" 100
  local before after
  before=$(mtime_of "$FAKE_HOME/$LAST_WARN_REL")
  run_hook "$OTHER" "$VAULT"
  after=$(mtime_of "$FAKE_HOME/$LAST_WARN_REL")
  assert_silent "throttled: no warning" "$ERR"
  assert_eq "throttled: marker mtime unchanged, so the window is not extended by being ignored" "$before" "$after"
  drop_workdir
  return $?
}

test_warns_again_once_cooldown_has_passed() {
  new_workdir
  other_repo
  vault_ahead 2
  mkdir -p "$FAKE_HOME/.claude/hook-logs"
  : > "$FAKE_HOME/$LAST_WARN_REL"
  age_file "$FAKE_HOME/$LAST_WARN_REL" 700
  run_hook "$OTHER" "$VAULT"
  assert_eq "past cooldown: exit 0" "0" "$STATUS"
  assert_has "past cooldown (700s of 600s): warns again" "$ERR" "$UNPUSHED_TEXT"
  assert_eq "past cooldown: marker refreshed to now" "yes" "$([[ $(( $(now) - $(mtime_of "$FAKE_HOME/$LAST_WARN_REL") )) -lt 60 ]] && echo yes || echo no)"
  drop_workdir
  return $?
}

test_cooldown_boundary_just_inside_is_throttled() {
  new_workdir
  other_repo
  vault_ahead 1
  mkdir -p "$FAKE_HOME/.claude/hook-logs"
  : > "$FAKE_HOME/$LAST_WARN_REL"
  age_file "$FAKE_HOME/$LAST_WARN_REL" 570
  run_hook "$OTHER" "$VAULT"
  assert_silent "570s old (cooldown 600s): still throttled" "$ERR"
  drop_workdir
  return $?
}

test_cooldown_boundary_just_outside_warns() {
  new_workdir
  other_repo
  vault_ahead 1
  mkdir -p "$FAKE_HOME/.claude/hook-logs"
  : > "$FAKE_HOME/$LAST_WARN_REL"
  age_file "$FAKE_HOME/$LAST_WARN_REL" 630
  run_hook "$OTHER" "$VAULT"
  assert_has "630s old (cooldown 600s): warns" "$ERR" "$UNPUSHED_TEXT"
  drop_workdir
  return $?
}

# --- stdin handling --------------------------------------------------------

test_multi_ref_stdin_is_consumed_without_hanging() {
  new_workdir
  other_repo
  vault_ahead 1
  run_hook "$OTHER" "$VAULT" "refs/heads/main a1 refs/heads/main b2
refs/heads/other c3 refs/heads/other d4"
  assert_eq "multi-ref stdin: exit 0" "0" "$STATUS"
  assert_has "multi-ref stdin: still reports the pending commit" "$ERR" "has 1 unpushed commit(s)"
  drop_workdir
  return $?
}

test_empty_stdin_still_works() {
  new_workdir
  other_repo
  vault_ahead 1
  : > "$OUT"; : > "$ERR"
  ( cd "$OTHER" && env HOME="$FAKE_HOME" VAULT_ROOT="$VAULT" bash "$HOOK_SCRIPT" < /dev/null ) > "$OUT" 2> "$ERR"
  STATUS=$?
  assert_eq "empty stdin: exit 0" "0" "$STATUS"
  assert_has "empty stdin: still reports the pending commit" "$ERR" "has 1 unpushed commit(s)"
  drop_workdir
  return $?
}

# --- through a real `git push` --------------------------------------------------

test_installed_as_a_real_hook_warns_but_the_push_succeeds() {
  new_workdir
  other_repo
  vault_ahead 2
  git init -q --bare "$WORK/other-origin.git"
  git -C "$OTHER" remote add origin "$WORK/other-origin.git"
  cp "$HOOK_SCRIPT" "$OTHER/.git/hooks/pre-push"
  chmod +x "$OTHER/.git/hooks/pre-push"
  printf 'change\n' >> "$OTHER/g.md"
  git -C "$OTHER" add -A
  git -C "$OTHER" commit -qm "work in the other repo"
  ( cd "$OTHER" && env HOME="$FAKE_HOME" VAULT_ROOT="$VAULT" git push -q origin main ) > "$OUT" 2> "$ERR"
  STATUS=$?
  assert_eq "real git push: succeeds, the hook never blocks it" "0" "$STATUS"
  assert_has "real git push: the vault warning reached the terminal" "$ERR" "has 2 unpushed commit(s)"
  assert_eq "real git push: both of the other repo's commits arrived on its origin" "2" "$(git -C "$WORK/other-origin.git" rev-list --count main)"
  drop_workdir
  return $?
}

test_silent_and_exit_0_when_vault_root_cannot_be_derived
test_silent_when_the_repo_being_pushed_is_the_vault_itself
test_silent_when_vault_has_no_main_branch
test_silent_and_exit_0_when_the_vault_is_not_a_git_repo
test_silent_when_vault_has_no_origin
test_silent_when_vault_is_in_sync_with_origin
test_silent_when_vault_is_only_behind_origin
test_warns_with_count_path_and_push_command
test_warns_for_a_single_pending_commit
test_counts_only_local_commits_when_origin_has_diverged
test_commit_subjects_are_never_echoed
test_creates_its_state_directory_when_missing
test_vault_path_with_a_space_is_handled
test_second_warning_within_cooldown_is_suppressed
test_throttled_run_does_not_move_the_marker
test_warns_again_once_cooldown_has_passed
test_cooldown_boundary_just_inside_is_throttled
test_cooldown_boundary_just_outside_warns
test_multi_ref_stdin_is_consumed_without_hanging
test_empty_stdin_still_works
test_installed_as_a_real_hook_warns_but_the_push_succeeds

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
