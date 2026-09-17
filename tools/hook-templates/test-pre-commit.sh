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
HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-commit"
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

# Runs the hook inside $1 (repo dir), with $2 (if given) a stub bindir
# prepended to PATH for a fake betterleaks. Doesn't otherwise sanitize PATH:
# the "no scanner" tests rely on the dev/CI machine not having a real
# betterleaks installed, not on hiding one.
run_hook() {
  local repo="$1" bindir="${2:-}"
  ( cd "$repo" && PATH="${bindir:+$bindir:}$PATH" "$HOOK_SCRIPT" )
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

test_no_staged_changes_exits_zero_silently
test_no_scanner_installed_warns_every_time_but_never_blocks
test_betterleaks_clean_exits_zero_no_banner
test_betterleaks_dirty_warns_but_does_not_block_by_default
test_betterleaks_dirty_strict_mode_blocks

echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
