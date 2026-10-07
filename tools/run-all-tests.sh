#!/usr/bin/env bash
# Runs every test suite in this repo and prints one line per suite.
#
#   bash tools/run-all-tests.sh                 run everything, one after another
#   bash tools/run-all-tests.sh --parallel      run the suites at the same time (much faster,
#                                               especially on Windows; every suite uses its own
#                                               temp folders, so they do not interfere)
#   bash tools/run-all-tests.sh --only hook     run only suites whose file name contains "hook"
#   bash tools/run-all-tests.sh --list          list the suites and exit
#   bash tools/run-all-tests.sh --verbose       show each suite's full output, not just failures
#
# Exit status is 0 only if every suite that ran passed. A suite that cannot run here
# (node or PowerShell not installed) is reported as skipped, never as a pass.
#
# The model-driven command harness (tools/command-templates/test/run-command-tests.mjs)
# is deliberately NOT here: it makes real model calls, costs money and is probabilistic. See
# docs/testing.md.

set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PARALLEL=0
ONLY=""
LIST=0
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel) PARALLEL=1; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --list) LIST=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# "kind|path (relative to tools/)": kind picks the interpreter.
SUITES=(
  "bash|hook-templates/test-pre-commit.sh"
  "bash|hook-templates/test-pre-push.sh"
  "bash|hook-templates/test-post-merge.sh"
  "bash|hook-templates/test-session-start-vault-check.sh"
  "bash|hook-templates/test-session-start-vault-context.sh"
  "bash|test-install-claude-config.sh"
  "bash|test-setup-mcp.sh"
  "bash|test-structure.sh"
  "node|command-templates/test/test-stub-rest-api-mcp.mjs"
  "pwsh|test-powershell-scripts.ps1"
)

selected=()
for s in "${SUITES[@]}"; do
  [[ -z "$ONLY" || "$s" == *"$ONLY"* ]] && selected+=("$s")
done

if [[ "$LIST" = "1" ]]; then
  for s in "${selected[@]}"; do echo "${s%%|*}  ${s#*|}"; done
  exit 0
fi
if [[ "${#selected[@]}" -eq 0 ]]; then echo "No suite matches '$ONLY'" >&2; exit 2; fi

OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT

# Writes <n>.out and <n>.status ("pass", "fail" or "skip: reason") for suite number $1.
run_suite() {
  local n="$1" kind="${2%%|*}" path="$TOOLS_DIR/${2#*|}" ps
  case "$kind" in
    bash) bash "$path" > "$OUT_DIR/$n.out" 2>&1; [[ $? -eq 0 ]] && echo pass > "$OUT_DIR/$n.status" || echo fail > "$OUT_DIR/$n.status" ;;
    node)
      if ! command -v node >/dev/null 2>&1; then echo "skip: node is not installed" > "$OUT_DIR/$n.status"; return 0; fi
      node "$path" > "$OUT_DIR/$n.out" 2>&1; [[ $? -eq 0 ]] && echo pass > "$OUT_DIR/$n.status" || echo fail > "$OUT_DIR/$n.status" ;;
    pwsh)
      ps=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)
      if [[ -z "$ps" ]]; then echo "skip: PowerShell is not installed" > "$OUT_DIR/$n.status"; return 0; fi
      "$ps" -NoProfile -File "$path" > "$OUT_DIR/$n.out" 2>&1; [[ $? -eq 0 ]] && echo pass > "$OUT_DIR/$n.status" || echo fail > "$OUT_DIR/$n.status" ;;
  esac
  return 0
}

began=$SECONDS
i=0
for s in "${selected[@]}"; do
  if [[ "$PARALLEL" = "1" ]]; then run_suite "$i" "$s" & else run_suite "$i" "$s"; fi
  i=$((i + 1))
done
[[ "$PARALLEL" = "1" ]] && wait

failed=0; skipped=0; passed=0
i=0
for s in "${selected[@]}"; do
  status=$(cat "$OUT_DIR/$i.status" 2>/dev/null || echo "fail")
  summary=$(grep -E '^--- .* ---$|^[0-9]+ passed, [0-9]+ failed' "$OUT_DIR/$i.out" 2>/dev/null | tail -n1)
  case "$status" in
    pass) passed=$((passed + 1)); printf 'PASS  %-62s %s\n' "${s#*|}" "$summary" ;;
    skip*) skipped=$((skipped + 1)); printf 'SKIP  %-62s %s\n' "${s#*|}" "${status#skip: }" ;;
    *) failed=$((failed + 1)); printf 'FAIL  %-62s %s\n' "${s#*|}" "$summary" ;;
  esac
  if [[ "$status" = "fail" ]]; then grep -E '^FAIL|KNOWN DEFECT' "$OUT_DIR/$i.out" | head -n 40 | sed 's/^/        /'; fi
  if [[ "$status" = "pass" ]]; then grep -E '^KNOWN DEFECT|^SKIP' "$OUT_DIR/$i.out" | sed 's/^/        /'; fi
  [[ "$VERBOSE" = "1" ]] && sed 's/^/        | /' "$OUT_DIR/$i.out"
  i=$((i + 1))
done

echo
echo "$passed passed, $failed failed, $skipped skipped, in $((SECONDS - began))s"
[[ "$failed" -eq 0 ]]
