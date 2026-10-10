#!/usr/bin/env bash
# Mutation checks: proves the test suites can actually fail.
#
#   bash tools/testing/run-mutation-tests.sh                     every hook and script (slow)
#   bash tools/testing/run-mutation-tests.sh --hook pre-push     one group; repeat or comma-separate for several
#   bash tools/testing/run-mutation-tests.sh --list              the groups and how many mutants each has
#   bash tools/testing/run-mutation-tests.sh --check-applies     check every mutant still applies; runs no suite (fast)
#   bash tools/testing/run-mutation-tests.sh --jobs 4            run four mutants at once (default 1)
#
# How it works: for each mutant in tools/testing/mutation/mutants.txt (a deliberate one-line break, such
# as a flipped condition or a dropped line) this copies tools/ to a temp folder, applies the
# change to the COPY, and runs that hook's own test suite from there. The suite is meant to
# FAIL. A mutant it does not notice is a SURVIVOR: a behaviour nothing checks.
#
# Before a group's mutants, its suite is run once on the unmodified copy. If that fails the
# group is reported as a broken baseline and its mutants are not run, because "the suite
# failed" would then prove nothing.
#
# This is slow on purpose (a full suite run per mutant, minutes each), which is why it is not
# part of the normal build: see .github/workflows/mutation-tests.yml, which is manual only.
# The repo itself is never modified, and each run uses a throwaway HOME.
#
# Exit status: 0 only if every mutant applied, was a valid script, and was killed.

set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
MUTANTS="${MUTANTS_FILE:-$TOOLS_DIR/testing/mutation/mutants.txt}"   # MUTANTS_FILE: a different list (used to test this runner)

HOOKS=""
JOBS=1
LIST=0
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook) HOOKS="$HOOKS,${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-1}"; shift 2 ;;
    --list) LIST=1; shift ;;
    --check-applies) CHECK=1; shift ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$JOBS" in ''|*[!0-9]*) echo "--jobs needs a number" >&2; exit 2 ;; *) ;; esac
[[ "$JOBS" -ge 1 ]] || JOBS=1

# Mutant lines as "hook@@name@@target@@expr@@why", comments and blanks dropped.
mutant_lines() { grep -v '^[[:space:]]*\(#.*\)\?$' "$MUTANTS"; return 0; }
field() { local line="$1" n="$2"; printf '%s' "$line" | awk -F'@@' -v n="$n" '{ print $n }'; return 0; }

suite_for() {
  local group="$1"
  if [[ -f "$ROOT/tools/hook-templates/test-$group.sh" ]]; then echo "tools/hook-templates/test-$group.sh"
  elif [[ -f "$ROOT/tools/$group/test-$group.mjs" ]]; then echo "tools/$group/test-$group.mjs"
  else echo "tools/testing/test-$group.sh"; fi
  return 0
}

all_groups() { mutant_lines | awk -F'@@' '{ print $1 }' | awk '!seen[$0]++'; return 0; }

if [[ "$LIST" = "1" ]]; then
  for g in $(all_groups); do
    printf '%-30s %2s mutants  %s\n' "$g" "$(mutant_lines | awk -F'@@' -v g="$g" '$1 == g' | wc -l | tr -d ' ')" "$(suite_for "$g")"
  done
  exit 0
fi

# The groups to run: the ones named, or all of them.
wanted=$(printf '%s' "$HOOKS" | tr ',' '\n' | awk 'NF')
groups=$(all_groups)
if [[ -n "$wanted" ]]; then
  for w in $wanted; do
    case " $(echo $groups) " in *" $w "*) ;; *) echo "No mutants for '$w'. Groups: $(echo $groups)" >&2; exit 2 ;; esac
  done
  groups="$wanted"
fi

# --- apply check: every mutant changes its target and leaves valid bash ----------------------
check_one() {
  local line="$1" target expr f
  target=$(field "$line" 3); expr=$(field "$line" 4)
  f="$ROOT/$target"
  [[ -f "$f" ]] || { echo "BROKEN   $(field "$line" 2): target $target does not exist"; return 1; }
  local out; out=$(mktemp)
  sed "$expr" "$f" > "$out" 2>/dev/null
  if cmp -s "$f" "$out"; then rm -f "$out"; echo "BROKEN   $(field "$line" 2): the expression changes nothing in $target"; return 1; fi
  case "$target" in
    *.mjs)
      mv "$out" "$out.mjs"; out="$out.mjs"
      if ! node --check "$out" 2>/dev/null; then rm -f "$out"; echo "BROKEN   $(field "$line" 2): the mutated $target is not valid JavaScript"; return 1; fi ;;
    *)
      if ! bash -n "$out" 2>/dev/null; then rm -f "$out"; echo "BROKEN   $(field "$line" 2): the mutated $target is not valid bash"; return 1; fi ;;
  esac
  rm -f "$out"
  return 0
}

if [[ "$CHECK" = "1" ]]; then
  bad=0; n=0
  while IFS= read -r line; do
    g=$(field "$line" 1)
    case " $(echo $groups) " in *" $g "*) ;; *) continue ;; esac
    n=$((n + 1))
    if check_one "$line"; then echo "ok       $(field "$line" 2) ($g)"; else bad=$((bad + 1)); fi
    if [[ ! -f "$ROOT/$(suite_for "$g")" ]]; then echo "BROKEN   $g: suite $(suite_for "$g") does not exist"; bad=$((bad + 1)); fi
  done < <(mutant_lines)
  echo "$n mutants checked, $bad broken"
  [[ "$bad" -eq 0 ]]
  exit $?
fi

# --- the runs ---------------------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A copy of tools/ with a clean HOME; prints its path.
fresh_copy() {
  local d; d=$(mktemp -d "$WORK/copy.XXXXXX")
  cp -R "$ROOT/tools" "$d/tools"
  mkdir -p "$d/home"
  echo "$d"
  return 0
}

# run_suite <copy> <suite>: 0 if the suite passed.
run_suite() {
  local copy="$1" suite="$2"
  local runner=bash
  case "$suite" in *.mjs) runner=node ;; *) ;; esac
  ( cd "$copy" && env HOME="$copy/home" "$runner" "$copy/$suite" ) > "$copy/suite.out" 2>&1
  return $?
}

# run_mutant <index> <line>: writes "<index>.result" as KILLED / SURVIVED / BROKEN plus detail.
run_mutant() {
  local idx="$1" line="$2" target expr g suite d f
  g=$(field "$line" 1); target=$(field "$line" 3); expr=$(field "$line" 4)
  suite=$(suite_for "$g")
  if ! check_one "$line" > "$WORK/$idx.why"; then echo "BROKEN" > "$WORK/$idx.status"; return 0; fi
  if [[ "$(field "$line" 6)" = "not-observable-on-windows" ]] && [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then echo "SKIPPED" > "$WORK/$idx.status"; return 0; fi
  d=$(fresh_copy); f="$d/$target"
  sed "$expr" "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"   # cat keeps the file's mode
  if run_suite "$d" "$suite"; then
    echo "SURVIVED" > "$WORK/$idx.status"
  else
    echo "KILLED" > "$WORK/$idx.status"
    grep -c '^FAIL' "$d/suite.out" > "$WORK/$idx.why" 2>/dev/null
  fi
  rm -rf "$d"
  return 0
}

began=$SECONDS
total_killed=0; total_survived=0; total_broken=0; total_baseline_broken=0; total_skipped=0

for g in $groups; do
  suite=$(suite_for "$g")
  echo "== $g  ($suite)"
  d=$(fresh_copy)
  if ! run_suite "$d" "$suite"; then
    echo "   BASELINE FAILS: the unmodified suite does not pass, so mutants for '$g' were not run"
    grep -E '^FAIL' "$d/suite.out" | head -n 5 | sed 's/^/     /'
    total_baseline_broken=$((total_baseline_broken + 1)); rm -rf "$d"; continue
  fi
  rm -rf "$d"

  : > "$WORK/index.$g"
  idx=0
  while IFS= read -r line; do
    [[ "$(field "$line" 1)" = "$g" ]] || continue
    idx=$((idx + 1)); key="$g.$idx"
    echo "$key $line" >> "$WORK/index.$g"
    while [[ $(jobs -rp | wc -l | tr -d ' ') -ge "$JOBS" ]]; do sleep 2; done
    run_mutant "$key" "$line" &
  done < <(mutant_lines)
  wait

  while IFS= read -r entry; do
    key="${entry%% *}"; line="${entry#* }"
    status=$(cat "$WORK/$key.status" 2>/dev/null || echo "BROKEN")
    case "$status" in
      KILLED)   total_killed=$((total_killed + 1)); printf '   killed    %-6s %s (%s failing checks)\n' "$(field "$line" 2)" "$(field "$line" 5)" "$(cat "$WORK/$key.why" 2>/dev/null)" ;;
      SURVIVED) total_survived=$((total_survived + 1)); printf '   SURVIVED  %-6s %s   <-- the suite did not notice\n' "$(field "$line" 2)" "$(field "$line" 5)" ;;
      SKIPPED)  total_skipped=$((total_skipped + 1)); printf '   skipped   %-6s %s   (not observable on Windows: file modes are emulated; runs on Linux and macOS)
' "$(field "$line" 2)" "$(field "$line" 5)" ;;
      *)        total_broken=$((total_broken + 1)); printf '   BROKEN    %-6s %s\n' "$(field "$line" 2)" "$(cat "$WORK/$key.why" 2>/dev/null)" ;;
    esac
  done < "$WORK/index.$g"
done

echo
echo "killed $total_killed, survived $total_survived, skipped $total_skipped, broken $total_broken, baselines failing $total_baseline_broken, in $((SECONDS - began))s"
[[ "$total_survived" -eq 0 && "$total_broken" -eq 0 && "$total_baseline_broken" -eq 0 ]]
