#!/usr/bin/env bash
# Test harness for tools/hook-templates/pre-commit.
# Run: bash tools/hook-templates/test-pre-commit.sh
#
# Modelled on this directory's own test-post-merge.sh: pre-commit has real
# branching logic (strict vs warn, no-scanner-found handling) rather than
# pre-push's near-zero-logic warning, so comments and manual testing alone
# aren't enough here either.
#
# Every fixture is a throwaway git repo under mktemp. No real betterleaks
# needs to be installed to run this suite, since it's stubbed.

set -u
HOOK_SCRIPT="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-commit}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0

make_test_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config core.autocrlf false
  echo "seed" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "seed"
  echo "$dir"
}

# Stub `betterleaks` on PATH. $1 = bindir, $2 = "clean" (exit 0, no output)
# or "dirty" (exit 1, prints a fixed finding line). Stands in for the real
# `betterleaks protect --staged --redact -v`.
make_stub_betterleaks() {
  local bindir="$1" mode="$2"
  mkdir -p "$bindir"
  if [ "$mode" = "dirty" ]; then
    cat > "$bindir/betterleaks" <<'EOF'
#!/bin/bash
echo "stub finding: fake-secret-detected"
exit 1
EOF
  else
    cat > "$bindir/betterleaks" <<'EOF'
#!/bin/bash
exit 0
EOF
  fi
  chmod +x "$bindir/betterleaks"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (expected [$expected], got [$actual])"
    FAIL=$((FAIL + 1))
  fi
}

# PATH with every directory that holds a real betterleaks removed, so the "no scanner"
# tests behave the same on a machine that has it installed.
path_without_betterleaks() {
  local out="" dir
  local IFS=:
  for dir in $PATH; do
    [[ -x "$dir/betterleaks" || -x "$dir/betterleaks.exe" ]] && continue
    out="${out:+$out:}$dir"
  done
  printf '%s' "$out"
  return 0
}

# Runs the hook inside $1 (repo dir). With $2 a stub bindir is prepended to PATH
# for a fake betterleaks; without it, any real betterleaks is hidden from PATH.
run_hook() {
  local repo="$1" bindir="${2:-}" path
  if [[ -n "$bindir" ]]; then path="$bindir:$PATH"; else path=$(path_without_betterleaks); fi
  ( cd "$repo" && PATH="$path" "$HOOK_SCRIPT" )
}

test_no_staged_changes_exits_zero_silently() {
  local repo output status
  repo=$(make_test_repo)
  output=$(run_hook "$repo" 2>&1)
  status=$?
  assert_eq "no staged changes: exit 0" "0" "$status"
  assert_eq "no staged changes: no output" "" "$output"
  rm -rf "$repo"
}

test_no_scanner_installed_warns_every_time_but_never_blocks() {
  local repo output1 output2 status1 status2
  repo=$(make_test_repo)
  printf 'anything\n' > "$repo/a.md"
  git -C "$repo" add a.md
  output1=$(run_hook "$repo" 2>&1)
  status1=$?
  printf 'anything else\n' > "$repo/a.md"
  git -C "$repo" add a.md
  output2=$(run_hook "$repo" 2>&1)
  status2=$?
  assert_eq "no scanner, run 1: exit 0" "0" "$status1"
  assert_eq "no scanner, run 1: notice shown" "1" "$(printf '%s' "$output1" | grep -c "betterleaks isn't installed")"
  assert_eq "no scanner, run 2: exit 0" "0" "$status2"
  assert_eq "no scanner, run 2: notice shown again (not throttled)" "1" "$(printf '%s' "$output2" | grep -c "betterleaks isn't installed")"
  rm -rf "$repo"
}

test_betterleaks_clean_exits_zero_no_banner() {
  local repo bindir output status
  repo=$(make_test_repo)
  bindir=$(mktemp -d)
  make_stub_betterleaks "$bindir" "clean"
  printf 'anything\n' > "$repo/a.md"
  git -C "$repo" add a.md
  output=$(run_hook "$repo" "$bindir" 2>&1)
  status=$?
  assert_eq "betterleaks present, clean: exit 0" "0" "$status"
  assert_eq "betterleaks present, clean: no finding banner" "0" "$(printf '%s' "$output" | grep -c 'possible secret')"
  assert_eq "betterleaks present, clean: no 'not installed' notice" "0" "$(printf '%s' "$output" | grep -c "isn't installed")"
  rm -rf "$repo" "$bindir"
}

test_betterleaks_dirty_warns_but_does_not_block_by_default() {
  local repo bindir output status
  repo=$(make_test_repo)
  bindir=$(mktemp -d)
  make_stub_betterleaks "$bindir" "dirty"
  printf 'anything\n' > "$repo/a.md"
  git -C "$repo" add a.md
  output=$(run_hook "$repo" "$bindir" 2>&1)
  status=$?
  assert_eq "betterleaks present, dirty, non-strict: exit 0" "0" "$status"
  assert_eq "betterleaks present, dirty: finding banner shown" "1" "$(printf '%s' "$output" | grep -c 'possible secret')"
  assert_eq "betterleaks present, dirty: stub's own finding text passed through" "1" "$(printf '%s' "$output" | grep -c 'fake-secret-detected')"
  rm -rf "$repo" "$bindir"
}

test_betterleaks_dirty_strict_mode_blocks() {
  local repo bindir output status
  repo=$(make_test_repo)
  bindir=$(mktemp -d)
  make_stub_betterleaks "$bindir" "dirty"
  printf 'anything\n' > "$repo/a.md"
  git -C "$repo" add a.md
  output=$(cd "$repo" && PATH="$bindir:$PATH" PRECOMMIT_SECRET_SCAN_STRICT=1 "$HOOK_SCRIPT" 2>&1)
  status=$?
  assert_eq "betterleaks present, dirty, strict: exit 1" "1" "$status"
  rm -rf "$repo" "$bindir"
}


# --- extended coverage -----------------------------------------------------------
#
# Added on top of the original five scenarios. The helpers register every temp dir so
# a trap removes them even when a check fails (the original tests clean up inline).

CLEANUP_DIRS=()
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done
  return 0
}
trap cleanup EXIT

assert_has() {
  assert_eq "$1" "yes" "$(printf '%s' "$2" | grep -qF -- "$3" && echo yes || echo no)"
}

# expect_defect <desc> <desired> <actual>: an expected failure for a CONFIRMED defect in
# the code under test. While the defect exists it is reported as KNOWN DEFECT and does not
# fail the run (it is listed again in the summary, so it cannot be forgotten). The moment
# the behaviour is fixed it FAILS, telling you to turn this into a plain assert_eq.
KNOWN_DEFECTS=0
expect_defect() {
  local desc="$1" desired="$2" actual="$3"
  if [ "$desired" = "$actual" ]; then
    echo "FAIL: $desc is now fixed: change expect_defect to assert_eq"
    FAIL=$((FAIL + 1))
  else
    echo "KNOWN DEFECT: $desc (wanted [$desired], got [$actual])"
    KNOWN_DEFECTS=$((KNOWN_DEFECTS + 1))
  fi
}

assert_lacks() {
  assert_eq "$1" "no" "$(printf '%s' "$2" | grep -qF -- "$3" && echo yes || echo no)"
}

# A fresh repo plus a stub bindir, both registered for cleanup.
new_case() {
  CASE_REPO=$(make_test_repo)
  CASE_BIN=$(mktemp -d)
  CLEANUP_DIRS+=("$CASE_REPO" "$CASE_BIN")
  CASE_ARGS="$CASE_BIN/args.log"
  CASE_RAN="$CASE_BIN/ran"
}

# Stub `betterleaks` that records how it was called, then prints $3 on stdout and
# $4 on stderr and exits $2. $1 = bindir.
make_recording_stub() {
  local bindir="$1" code="$2" out="${3:-}" err="${4:-}"
  mkdir -p "$bindir"
  cat > "$bindir/betterleaks" <<EOF
#!/bin/bash
echo "\$*" > "$bindir/args.log"
touch "$bindir/ran"
[ -n "$out" ] && echo "$out"
[ -n "$err" ] && echo "$err" >&2
exit $code
EOF
  chmod +x "$bindir/betterleaks"
}

stage_file() {
  printf '%s\n' "${3:-content}" > "$1/$2"
  git -C "$1" add -- "$2"
}

# run_extended <strict-value-or-unset> [bindir]: sets $OUT (stdout+stderr) and $STATUS.
run_extended() {
  local strict="$1" bindir="${2:-}" path
  if [[ -n "$bindir" ]]; then path="$bindir:$PATH"; else path=$(path_without_betterleaks); fi
  if [[ "$strict" = "<unset>" ]]; then
    OUT=$(cd "$CASE_REPO" && env -u PRECOMMIT_SECRET_SCAN_STRICT PATH="$path" "$HOOK_SCRIPT" 2>&1)
  else
    OUT=$(cd "$CASE_REPO" && env PRECOMMIT_SECRET_SCAN_STRICT="$strict" PATH="$path" "$HOOK_SCRIPT" 2>&1)
  fi
  STATUS=$?
}

test_scanner_is_called_to_scan_the_staged_changes_with_redaction() {
  new_case
  make_recording_stub "$CASE_BIN" 0
  stage_file "$CASE_REPO" a.md
  run_extended "<unset>" "$CASE_BIN"
  assert_eq "scanner is asked to scan staged changes, redacted, verbose" "protect --staged --redact -v" "$(cat "$CASE_ARGS" 2>/dev/null)"
}

test_deleted_files_alone_are_not_scanned() {
  new_case
  make_recording_stub "$CASE_BIN" 1 "should-not-run"
  git -C "$CASE_REPO" rm -q README.md
  run_extended 1 "$CASE_BIN"
  assert_eq "only a deletion staged: exit 0 even in strict mode" "0" "$STATUS"
  assert_eq "only a deletion staged: scanner not invoked" "no" "$([ -f "$CASE_RAN" ] && echo yes || echo no)"
}

test_modified_files_are_scanned() {
  new_case
  make_recording_stub "$CASE_BIN" 0
  printf 'changed\n' > "$CASE_REPO/README.md"
  git -C "$CASE_REPO" add README.md
  run_extended "<unset>" "$CASE_BIN"
  assert_eq "a modified file counts as scannable" "yes" "$([ -f "$CASE_RAN" ] && echo yes || echo no)"
}

# Regression test. The hook once listed staged files with `--diff-filter=ACM`, which leaves
# out R (renamed). A file renamed AND edited in the same commit is reported by git as R0xx,
# so if it was the only thing staged the hook saw an empty list and exited 0 without
# scanning, even in strict mode (confirmed by hand against the real betterleaks: a rename
# plus an added AWS key, the scanner finds it, the hook exited 0). Fixed by ACMR.
test_renamed_and_edited_file_is_scanned() {
  local i
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  for i in $(seq 1 40); do echo "ordinary line number $i of the notes"; done > "$CASE_REPO/notes.md"
  git -C "$CASE_REPO" add notes.md
  git -C "$CASE_REPO" commit -q -m "add notes"
  git -C "$CASE_REPO" mv notes.md renamed.md
  echo "one more line added during the rename" >> "$CASE_REPO/renamed.md"
  git -C "$CASE_REPO" add renamed.md
  assert_eq "fixture: git reports the staged change as a rename" "R" "$(git -C "$CASE_REPO" diff --cached --name-status | cut -c1)"
  run_extended 1 "$CASE_BIN"
  assert_eq "a renamed-and-edited file is scanned (strict, scanner finds something: blocks)" "1" "$STATUS"
}

test_first_commit_in_an_empty_repo_is_scanned() {
  local repo
  new_case
  repo=$(mktemp -d)
  CLEANUP_DIRS+=("$repo")
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config core.autocrlf false
  make_recording_stub "$CASE_BIN" 1 "" "finding in first commit"
  stage_file "$repo" first.md
  OUT=$(cd "$repo" && env PRECOMMIT_SECRET_SCAN_STRICT=1 PATH="$CASE_BIN:$PATH" "$HOOK_SCRIPT" 2>&1)
  STATUS=$?
  assert_eq "no HEAD yet, strict, dirty: blocked" "1" "$STATUS"
  assert_has "no HEAD yet: finding text shown" "$OUT" "finding in first commit"
}

test_strict_accepts_1_and_true_only() {
  local v
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  stage_file "$CASE_REPO" a.md
  for v in 1 true; do
    run_extended "$v" "$CASE_BIN"
    assert_eq "strict value '$v' blocks" "1" "$STATUS"
  done
  for v in 0 false "" yes TRUE on; do
    run_extended "$v" "$CASE_BIN"
    assert_eq "strict value '$v' does not block" "0" "$STATUS"
  done
}

test_strict_with_a_clean_scan_still_passes() {
  new_case
  make_recording_stub "$CASE_BIN" 0
  stage_file "$CASE_REPO" a.md
  run_extended 1 "$CASE_BIN"
  assert_eq "strict, clean scan: exit 0" "0" "$STATUS"
  assert_eq "strict, clean scan: silent" "" "$OUT"
}

test_strict_without_a_scanner_warns_but_cannot_block() {
  new_case
  stage_file "$CASE_REPO" a.md
  run_extended 1
  assert_eq "strict, no scanner: exit 0 (nothing to enforce with)" "0" "$STATUS"
  assert_has "strict, no scanner: still tells the user to install it" "$OUT" "betterleaks isn't installed"
  assert_has "strict, no scanner: install pointer given" "$OUT" "https://betterleaks.com/"
}

test_any_nonzero_scanner_exit_is_treated_as_a_finding() {
  local code
  new_case
  stage_file "$CASE_REPO" a.md
  for code in 1 2 126 127; do
    make_recording_stub "$CASE_BIN" "$code" "" "scanner said code $code"
    run_extended 1 "$CASE_BIN"
    assert_eq "scanner exit $code, strict: blocks (a crashed scanner fails closed)" "1" "$STATUS"
    run_extended "<unset>" "$CASE_BIN"
    assert_eq "scanner exit $code, default: warns, does not block" "0" "$STATUS"
    assert_has "scanner exit $code: scanner's own message is shown" "$OUT" "scanner said code $code"
  done
}

test_scanner_output_on_both_streams_reaches_the_banner() {
  new_case
  make_recording_stub "$CASE_BIN" 1 "from-stdout" "from-stderr"
  stage_file "$CASE_REPO" a.md
  run_extended "<unset>" "$CASE_BIN"
  assert_has "stdout of the scanner is shown" "$OUT" "from-stdout"
  assert_has "stderr of the scanner is shown" "$OUT" "from-stderr"
}

test_banner_tells_the_user_what_to_do() {
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  stage_file "$CASE_REPO" a.md
  run_extended "<unset>" "$CASE_BIN"
  assert_has "banner: how to unstage a real secret" "$OUT" "git restore --staged <file>"
  assert_has "banner: the bypass for a false positive" "$OUT" "--no-verify"
  assert_has "banner: the allowlist file format" "$OUT" ".gitleaksignore"
}

test_clean_scan_prints_nothing() {
  new_case
  make_recording_stub "$CASE_BIN" 0 "scanner chatter" "more chatter"
  stage_file "$CASE_REPO" a.md
  run_extended "<unset>" "$CASE_BIN"
  assert_eq "clean scan: exit 0" "0" "$STATUS"
  assert_eq "clean scan: the scanner's output is swallowed, nothing shown" "" "$OUT"
}

test_hook_works_from_a_subdirectory_and_with_spaces_in_filenames() {
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  mkdir -p "$CASE_REPO/docs/sub dir"
  stage_file "$CASE_REPO" "docs/sub dir/my note.md"
  OUT=$(cd "$CASE_REPO/docs/sub dir" && env PRECOMMIT_SECRET_SCAN_STRICT=1 PATH="$CASE_BIN:$PATH" "$HOOK_SCRIPT" 2>&1)
  STATUS=$?
  assert_eq "run from a subdirectory, awkward filename, strict: blocks" "1" "$STATUS"
}

# Installs the hook as a real .git/hooks/pre-commit and commits through git itself.
install_hook() {
  cp "$HOOK_SCRIPT" "$CASE_REPO/.git/hooks/pre-commit"
  chmod +x "$CASE_REPO/.git/hooks/pre-commit"
}

head_of() { git -C "$1" rev-parse HEAD; }

test_real_commit_is_blocked_in_strict_mode_and_nothing_is_committed() {
  local before
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  install_hook
  stage_file "$CASE_REPO" a.md
  before=$(head_of "$CASE_REPO")
  ( cd "$CASE_REPO" && env PRECOMMIT_SECRET_SCAN_STRICT=1 PATH="$CASE_BIN:$PATH" git commit -q -m "should be blocked" ) >/dev/null 2>&1
  STATUS=$?
  assert_eq "git commit in strict mode with a finding: fails" "1" "$STATUS"
  assert_eq "git commit in strict mode with a finding: HEAD did not move" "$before" "$(head_of "$CASE_REPO")"
  assert_eq "git commit in strict mode with a finding: the file is still staged" "a.md" "$(git -C "$CASE_REPO" diff --cached --name-only)"
}

test_real_commit_goes_through_with_a_warning_by_default() {
  local before
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  install_hook
  stage_file "$CASE_REPO" a.md
  before=$(head_of "$CASE_REPO")
  OUT=$(cd "$CASE_REPO" && env -u PRECOMMIT_SECRET_SCAN_STRICT PATH="$CASE_BIN:$PATH" git commit -q -m "warned but allowed" 2>&1)
  STATUS=$?
  assert_eq "git commit in default mode with a finding: succeeds" "0" "$STATUS"
  assert_eq "git commit in default mode with a finding: HEAD moved" "yes" "$([ "$before" != "$(head_of "$CASE_REPO")" ] && echo yes || echo no)"
  assert_has "git commit in default mode with a finding: warning was shown" "$OUT" "possible secret"
}

test_no_verify_skips_the_hook_even_in_strict_mode() {
  new_case
  make_recording_stub "$CASE_BIN" 1 "finding"
  install_hook
  stage_file "$CASE_REPO" a.md
  ( cd "$CASE_REPO" && env PRECOMMIT_SECRET_SCAN_STRICT=1 PATH="$CASE_BIN:$PATH" git commit -q --no-verify -m "bypass" ) >/dev/null 2>&1
  STATUS=$?
  assert_eq "git commit --no-verify in strict mode: succeeds" "0" "$STATUS"
  assert_eq "git commit --no-verify: the scanner never ran" "no" "$([ -f "$CASE_RAN" ] && echo yes || echo no)"
}

# --- against the real betterleaks, when this machine has it ---------------------------
#
# The stubs above prove the hook's own logic; they cannot prove betterleaks still
# understands the arguments the hook passes. These run the installed scanner on
# throwaway repos. Without it they print a SKIP and do not count as a pass. The
# secret-shaped values are assembled from pieces so this file itself never contains a
# match for a scanner to flag.

have_real_betterleaks() { [[ -n "$(PATH="$ORIG_PATH" command -v betterleaks 2>/dev/null)" ]]; }
ORIG_PATH="$PATH"

stage_realistic_secret() {
  local aws_id="AKIA""J7Q2XK4MZP5N3WRB" aws_secret="h8Kq2Zx9Lm4Vn7Bc1Td6""Yf3Rw5Sg0Uj8Pa2Ne4Oi"
  printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$aws_id" "$aws_secret" > "$1/creds.env"
  git -C "$1" add creds.env
}

test_real_betterleaks_flags_a_staged_secret_in_strict_mode() {
  if ! have_real_betterleaks; then
    echo "SKIP: real betterleaks not installed, argument compatibility not checked (install: https://betterleaks.com/)"
    return 0
  fi
  new_case
  stage_realistic_secret "$CASE_REPO"
  OUT=$(cd "$CASE_REPO" && env PRECOMMIT_SECRET_SCAN_STRICT=1 "$HOOK_SCRIPT" 2>&1)
  STATUS=$?
  assert_eq "real betterleaks, secret staged, strict: blocks" "1" "$STATUS"
  assert_has "real betterleaks: banner shown" "$OUT" "possible secret"
  assert_lacks "real betterleaks: the secret value itself is redacted from the output" "$OUT" "Yf3Rw5Sg0Uj8Pa2Ne4Oi"
}

test_real_betterleaks_passes_a_clean_staged_file() {
  if ! have_real_betterleaks; then
    echo "SKIP: real betterleaks not installed, argument compatibility not checked (install: https://betterleaks.com/)"
    return 0
  fi
  new_case
  stage_file "$CASE_REPO" notes.md "just some ordinary prose"
  OUT=$(cd "$CASE_REPO" && env PRECOMMIT_SECRET_SCAN_STRICT=1 "$HOOK_SCRIPT" 2>&1)
  STATUS=$?
  assert_eq "real betterleaks, clean file, strict: passes" "0" "$STATUS"
  assert_eq "real betterleaks, clean file: silent" "" "$OUT"
}

test_no_staged_changes_exits_zero_silently
test_no_scanner_installed_warns_every_time_but_never_blocks
test_betterleaks_clean_exits_zero_no_banner
test_betterleaks_dirty_warns_but_does_not_block_by_default
test_betterleaks_dirty_strict_mode_blocks
test_scanner_is_called_to_scan_the_staged_changes_with_redaction
test_deleted_files_alone_are_not_scanned
test_modified_files_are_scanned
test_renamed_and_edited_file_is_scanned
test_first_commit_in_an_empty_repo_is_scanned
test_strict_accepts_1_and_true_only
test_strict_with_a_clean_scan_still_passes
test_strict_without_a_scanner_warns_but_cannot_block
test_any_nonzero_scanner_exit_is_treated_as_a_finding
test_scanner_output_on_both_streams_reaches_the_banner
test_banner_tells_the_user_what_to_do
test_clean_scan_prints_nothing
test_hook_works_from_a_subdirectory_and_with_spaces_in_filenames
test_real_commit_is_blocked_in_strict_mode_and_nothing_is_committed
test_real_commit_goes_through_with_a_warning_by_default
test_no_verify_skips_the_hook_even_in_strict_mode
test_real_betterleaks_flags_a_staged_secret_in_strict_mode
test_real_betterleaks_passes_a_clean_staged_file

echo "--- $PASS passed, $FAIL failed, $KNOWN_DEFECTS known defect(s) ---"
[ "$FAIL" -eq 0 ]
