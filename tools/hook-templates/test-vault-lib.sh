#!/usr/bin/env bash
# Test harness for tools/hook-templates/vault-lib, the helpers pre-push and
# session-start-vault-check share.
# Run: bash tools/hook-templates/test-vault-lib.sh
#
# Fixtures are throwaway repos under mktemp: a "vault" cloned from a local bare "origin", so
# commits made afterwards make a real origin/<branch>..<branch> gap with no network.

set -u
LIB="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vault-lib}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0
CLEANUP_DIRS=()

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

# shellcheck source=vault-lib
. "$LIB"

# make_vault <branch>: a clone of a fresh bare origin whose default branch is <branch>,
# with one commit pushed. Prints the clone's path.
make_vault() {
  local branch="$1" d
  d=$(mktemp -d); CLEANUP_DIRS+=("$d")
  git init -q --bare -b "$branch" "$d/origin.git"
  git clone -q "$d/origin.git" "$d/vault" 2>/dev/null
  git -C "$d/vault" config user.email t@example.invalid
  git -C "$d/vault" config user.name t
  git -C "$d/vault" checkout -q -B "$branch"
  echo one > "$d/vault/a.md"
  git -C "$d/vault" add a.md
  git -C "$d/vault" commit -q -m one
  git -C "$d/vault" push -q -u origin "$branch" 2>/dev/null
  git -C "$d/vault" remote set-head origin "$branch" >/dev/null 2>&1
  echo "$d/vault"
  return 0
}

add_commit() {  # <vault> <file>
  echo "$2" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "SUBJECT_MARKER $2"
  return $?
}

test_the_default_branch_comes_from_origin_head() {
  local v
  v=$(make_vault trunk)
  assert_eq "origin/HEAD says trunk" "trunk" "$(vault_branch "$v")"
  v=$(make_vault main)
  assert_eq "origin/HEAD says main" "main" "$(vault_branch "$v")"
  return 0
}

test_without_origin_head_it_falls_back_to_main() {
  local v
  v=$(make_vault trunk)
  git -C "$v" remote set-head origin -d >/dev/null 2>&1
  assert_eq "no origin/HEAD: main" "main" "$(vault_branch "$v")"
  assert_eq "not a repo at all: main" "main" "$(vault_branch "$(mktemp -d)")"
  return 0
}

test_unpushed_commits_are_listed_as_short_hashes_only() {
  local v out
  v=$(make_vault trunk)
  assert_eq "nothing unpushed: nothing printed" "" "$(vault_unpushed_hashes "$v" trunk)"
  add_commit "$v" b.md; add_commit "$v" c.md
  out=$(vault_unpushed_hashes "$v" trunk)
  assert_eq "two unpushed commits: two lines" "2" "$(printf '%s\n' "$out" | grep -c .)"
  assert_eq "the lines are hashes" "0" "$(printf '%s\n' "$out" | grep -vcE '^[0-9a-f]{4,}$')"
  assert_eq "no commit subject is printed" "0" "$(printf '%s\n' "$out" | grep -c SUBJECT_MARKER)"
  return 0
}

test_a_missing_branch_or_origin_copy_is_not_an_error_to_print() {
  local v st
  v=$(make_vault trunk)
  vault_unpushed_hashes "$v" nosuch >/dev/null 2>&1; st=$?
  assert_eq "no such local branch: returns 1" "1" "$st"
  git -C "$v" checkout -q -b local-only
  add_commit "$v" d.md
  vault_unpushed_hashes "$v" local-only >/dev/null 2>&1; st=$?
  assert_eq "branch with no origin copy: returns 1" "1" "$st"
  assert_eq "...and prints nothing" "" "$(vault_unpushed_hashes "$v" local-only 2>/dev/null)"
  vault_unpushed_hashes "$(mktemp -d)" trunk >/dev/null 2>&1; st=$?
  assert_eq "not a repo: returns 1" "1" "$st"
  return 0
}

test_the_default_branch_comes_from_origin_head
test_without_origin_head_it_falls_back_to_main
test_unpushed_commits_are_listed_as_short_hashes_only
test_a_missing_branch_or_origin_copy_is_not_an_error_to_print

echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
