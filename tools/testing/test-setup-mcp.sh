#!/usr/bin/env bash
# Test harness for tools/setup-mcp.sh.
# Run: bash tools/testing/test-setup-mcp.sh
#
# setup-mcp.sh registers the Obsidian "Local REST API" plugin as a Claude Code MCP
# server in five steps: Claude Code is present, the plugin is installed, its HTTP
# server is switched on, the server is registered with the plugin's API key, and the
# endpoint is probed. This suite walks every step and every error branch.
#
# Nothing real is touched: `claude` and `curl` are stubs on PATH that record their
# arguments, so no MCP registration is made and no network call goes out. The script
# finds the vault from its own location (one level above its folder), so each test
# copies it into a throwaway vault; `.obsidian/plugins/obsidian-local-rest-api/data.json`
# is the fixture the script reads and edits.

set -u
SRC_SCRIPT="${SCRIPT_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup-mcp.sh}"  # override: point at a mutated copy to prove the suite fails
PASS=0
FAIL=0
CLEANUP_DIRS=()
API_KEY="k3y-FAKE-0123456789abcdef"

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

# A throwaway vault holding a copy of the script, plus stub binaries and logs.
new_vault() {
  WORK=$(mktemp -d)
  CLEANUP_DIRS+=("$WORK")
  VAULT="$WORK/vault"
  BIN="$WORK/bin"
  OUT="$WORK/stdout.log"
  ERR="$WORK/stderr.log"
  CLAUDE_LOG="$WORK/claude-calls.log"
  CURL_LOG="$WORK/curl-calls.log"
  DATA="$VAULT/.obsidian/plugins/obsidian-local-rest-api/data.json"
  mkdir -p "$VAULT/tools" "$BIN" "$(dirname "$DATA")"
  cp "$SRC_SCRIPT" "$VAULT/tools/setup-mcp.sh"
  : > "$CLAUDE_LOG"; : > "$CURL_LOG"
  return $?
}

drop_vault() { rm -rf "$WORK"; return $?; }

# write_data <insecure-flag> [port-line] [key-line]: a plugin data.json shaped like
# the one Obsidian writes (pretty-printed, one key per line).
write_data() {
  local flag="$1" port_line="${2-  \"insecurePort\": 27123,}" key_line="${3-  \"apiKey\": \"$API_KEY\",}"
  {
    echo "{"
    echo "  \"port\": 27124,"
    [[ -n "$port_line" ]] && echo "$port_line"
    echo "  \"enableInsecureServer\": $flag,"
    [[ -n "$key_line" ]] && echo "$key_line"
    echo "  \"bindingHost\": \"127.0.0.1\""
    echo "}"
  } > "$DATA"
  return $?
}

# Stub `claude`: logs "<args>" per call, answers --version, and exits $CLAUDE_REMOVE_EXIT
# for `mcp remove` (a remove with nothing registered fails in the real tool).
make_stub_claude() {
  cat > "$BIN/claude" <<EOF
#!/bin/bash
echo "\$*" >> "$CLAUDE_LOG"
if [ "\$1" = "--version" ]; then echo "9.9.9 (stub)"; exit 0; fi
if [ "\$1" = "mcp" ] && [ "\$2" = "remove" ]; then exit \${CLAUDE_REMOVE_EXIT:-0}; fi
exit 0
EOF
  chmod +x "$BIN/claude"
  return $?
}

# Stub `curl`: logs its arguments and prints $STUB_HTTP_STATUS, as `-w %{http_code}` would.
make_stub_curl() {
  cat > "$BIN/curl" <<EOF
#!/bin/bash
echo "\$*" >> "$CURL_LOG"
printf '%s' "\${STUB_HTTP_STATUS:-200}"
exit 0
EOF
  chmod +x "$BIN/curl"
  return $?
}

# PATH with every directory that holds a real `claude` removed.
path_without_claude() {
  local out="" dir
  local IFS=:
  for dir in $PATH; do
    [[ -x "$dir/claude" || -x "$dir/claude.exe" || -x "$dir/claude.cmd" ]] && continue
    out="${out:+$out:}$dir"
  done
  printf '%s' "$out"
  return 0
}

# run_script [env assignments...]: stub dir first on PATH. Sets $STATUS.
run_script() {
  : > "$OUT"; : > "$ERR"
  ( cd "$WORK" && env PATH="$BIN:$PATH" "$@" bash "$VAULT/tools/setup-mcp.sh" ) > "$OUT" 2> "$ERR"
  STATUS=$?
  return $?
}

# --- step 1: Claude Code present ------------------------------------------------

test_fails_when_claude_is_not_installed() {
  new_vault
  write_data true
  make_stub_curl
  : > "$OUT"; : > "$ERR"
  ( cd "$WORK" && env PATH="$BIN:$(path_without_claude)" bash "$VAULT/tools/setup-mcp.sh" ) > "$OUT" 2> "$ERR"
  STATUS=$?
  assert_eq "no claude: exit 1" "1" "$STATUS"
  assert_has "no claude: says Claude Code is missing and how to install it" "$ERR" "Claude Code not found on PATH"
  assert_has "no claude: gives the install command" "$ERR" "npm install -g @anthropic-ai/claude-code"
  assert_eq "no claude: data.json untouched" "no" "$([[ -e "$DATA.bak" ]] && echo yes || echo no)"
  drop_vault
  return $?
}

test_reports_the_vault_path_and_claude_version() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script
  assert_has "vault path is the folder above tools/" "$OUT" "Vault path: $VAULT"
  assert_has "step 1 shows the Claude Code version" "$OUT" "[Step 1] OK - Claude Code 9.9.9 (stub)"
  drop_vault
  return $?
}

# --- step 2: plugin installed -----------------------------------------------------

test_fails_when_the_plugin_is_not_installed() {
  new_vault
  rm -rf "$VAULT/.obsidian"
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "no plugin: exit 1" "1" "$STATUS"
  assert_has "no plugin: names the missing data.json" "$ERR" "Local REST API plugin not found at $DATA"
  assert_has "no plugin: tells the user how to install it" "$ERR" "Settings -> Community plugins"
  assert_eq "no plugin: nothing registered" "0" "$(grep -c 'mcp' "$CLAUDE_LOG")"
  drop_vault
  return $?
}

# --- step 3: enable the HTTP server -----------------------------------------------

test_switches_the_http_server_on_and_stops_for_a_restart() {
  new_vault
  write_data false
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "server was off: exit 0 (a clean stop, not a failure)" "0" "$STATUS"
  assert_has "server was off: tells the user to restart Obsidian" "$OUT" "Restart Obsidian now"
  assert_eq "server was off: data.json flipped to true" "1" "$(grep -c '"enableInsecureServer": true' "$DATA")"
  assert_eq "server was off: no 'false' left behind" "0" "$(grep -c '"enableInsecureServer": false' "$DATA")"
  assert_eq "server was off: a .bak copy of the original was kept" "1" "$(grep -c '"enableInsecureServer": false' "$DATA.bak")"
  assert_eq "server was off: it stops before registering anything" "0" "$(grep -c 'mcp' "$CLAUDE_LOG")"
  assert_eq "server was off: it stops before probing the endpoint" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
  drop_vault
  return $?
}

test_changes_nothing_else_in_data_json_when_enabling() {
  new_vault
  write_data false
  local before
  before=$(grep -v enableInsecureServer "$DATA")
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "other settings in data.json are preserved" "$before" "$(grep -v enableInsecureServer "$DATA")"
  drop_vault
  return $?
}

test_continues_when_the_http_server_is_already_on() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "server on: exit 0" "0" "$STATUS"
  assert_has "server on: step 3 reports it" "$OUT" "[Step 3] OK - HTTP server already enabled"
  assert_eq "server on: data.json not rewritten (no .bak)" "no" "$([[ -e "$DATA.bak" ]] && echo yes || echo no)"
  drop_vault
  return $?
}

test_fails_when_the_plugin_config_has_no_enable_setting() {
  new_vault
  printf '{\n  "apiKey": "%s"\n}\n' "$API_KEY" > "$DATA"
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "no enableInsecureServer: exit 1" "1" "$STATUS"
  assert_has "no enableInsecureServer: says the format may have changed" "$ERR" "Could not find 'enableInsecureServer'"
  assert_eq "no enableInsecureServer: nothing registered" "0" "$(grep -c 'mcp' "$CLAUDE_LOG")"
  drop_vault
  return $?
}

# --- the API key and port ---------------------------------------------------------

test_fails_when_there_is_no_api_key() {
  new_vault
  write_data true "  \"insecurePort\": 27123," ""
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "no apiKey: exit 1" "1" "$STATUS"
  assert_has "no apiKey: says to open Obsidian with the plugin once" "$ERR" "Could not find 'apiKey'"
  assert_eq "no apiKey: nothing registered" "0" "$(grep -c 'mcp' "$CLAUDE_LOG")"
  drop_vault
  return $?
}

test_fails_when_the_api_key_is_empty() {
  new_vault
  write_data true "  \"insecurePort\": 27123," "  \"apiKey\": \"\","
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "empty apiKey: exit 1" "1" "$STATUS"
  assert_has "empty apiKey: same message as a missing one" "$ERR" "Could not find 'apiKey'"
  drop_vault
  return $?
}

test_the_api_key_is_never_printed() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script
  assert_lacks "api key not echoed on stdout" "$OUT" "$API_KEY"
  assert_lacks "api key not echoed on stderr" "$ERR" "$API_KEY"
  drop_vault
  return $?
}

test_default_port_is_used_when_the_config_has_none() {
  new_vault
  write_data true ""
  make_stub_claude; make_stub_curl
  run_script
  assert_has "no insecurePort: registers on 27123" "$CLAUDE_LOG" "http://localhost:27123/mcp/"
  assert_has "no insecurePort: probes 27123" "$CURL_LOG" "http://localhost:27123/vault/"
  drop_vault
  return $?
}

test_a_custom_port_is_used_for_registration_and_the_probe() {
  new_vault
  write_data true "  \"insecurePort\": 31337,"
  make_stub_claude; make_stub_curl
  run_script
  assert_has "custom port: registered against it" "$CLAUDE_LOG" "http://localhost:31337/mcp/"
  assert_has "custom port: probed on it" "$CURL_LOG" "http://localhost:31337/vault/"
  assert_lacks "custom port: the default port is not used" "$CLAUDE_LOG" "27123"
  drop_vault
  return $?
}

test_api_key_is_read_from_compact_json_formatting() {
  new_vault
  write_data true "  \"insecurePort\": 27123," "  \"apiKey\":\"$API_KEY\","
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "apiKey with no space after the colon: exit 0" "0" "$STATUS"
  assert_has "apiKey with no space after the colon: key still picked up" "$CLAUDE_LOG" "Authorization: Bearer $API_KEY"
  drop_vault
  return $?
}

# --- step 4: registration ---------------------------------------------------------

test_removes_then_adds_the_registration_with_the_key_and_user_scope() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script
  assert_eq "registration: exit 0" "0" "$STATUS"
  assert_eq "registration: the remove call comes first" "mcp remove obsidian --scope user" "$(sed -n 2p "$CLAUDE_LOG")"
  assert_eq "registration: then the add call with transport, URL, header and scope" \
    "mcp add --transport http obsidian http://localhost:27123/mcp/ --header Authorization: Bearer $API_KEY --scope user" \
    "$(sed -n 3p "$CLAUDE_LOG")"
  assert_has "registration: tells the user to restart Claude Code" "$OUT" "[Step 4] OK - registered. Restart your Claude Code session"
  drop_vault
  return $?
}

test_a_failing_remove_does_not_stop_registration() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script CLAUDE_REMOVE_EXIT=1
  assert_eq "nothing to remove (remove exits 1): still exit 0" "0" "$STATUS"
  assert_eq "nothing to remove: the add still happens" "1" "$(grep -c '^mcp add ' "$CLAUDE_LOG")"
  drop_vault
  return $?
}

test_running_twice_re_registers_each_time() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script
  run_script
  assert_eq "re-run: exit 0" "0" "$STATUS"
  assert_eq "re-run: remove called on both runs" "2" "$(grep -c '^mcp remove ' "$CLAUDE_LOG")"
  assert_eq "re-run: add called on both runs" "2" "$(grep -c '^mcp add ' "$CLAUDE_LOG")"
  drop_vault
  return $?
}

# --- step 5: probe the endpoint ---------------------------------------------------

test_succeeds_when_the_endpoint_answers_200() {
  new_vault
  write_data true
  make_stub_claude; make_stub_curl
  run_script STUB_HTTP_STATUS=200
  assert_eq "endpoint 200: exit 0" "0" "$STATUS"
  assert_has "endpoint 200: step 5 reports it" "$OUT" "[Step 5] OK - vault endpoint responded HTTP 200"
  assert_has "endpoint 200: ends with the next-step hint" "$OUT" "ask it to read 'index.md'"
  assert_has "probe sends the bearer key" "$CURL_LOG" "Authorization: Bearer $API_KEY"
  drop_vault
  return $?
}

test_fails_when_the_endpoint_answers_anything_but_200() {
  local code
  for code in 401 404 500 000; do
    new_vault
    write_data true
    make_stub_claude; make_stub_curl
    run_script STUB_HTTP_STATUS=$code
    assert_eq "endpoint $code: exit 1" "1" "$STATUS"
    assert_has "endpoint $code: says which status came back" "$ERR" "responded HTTP $code, expected 200"
    assert_lacks "endpoint $code: no success line" "$OUT" "Done."
    drop_vault
  done
  return $?
}

test_fails_when_claude_is_not_installed
test_reports_the_vault_path_and_claude_version
test_fails_when_the_plugin_is_not_installed
test_switches_the_http_server_on_and_stops_for_a_restart
test_changes_nothing_else_in_data_json_when_enabling
test_continues_when_the_http_server_is_already_on
test_fails_when_the_plugin_config_has_no_enable_setting
test_fails_when_there_is_no_api_key
test_fails_when_the_api_key_is_empty
test_the_api_key_is_never_printed
test_default_port_is_used_when_the_config_has_none
test_a_custom_port_is_used_for_registration_and_the_probe
test_api_key_is_read_from_compact_json_formatting
test_removes_then_adds_the_registration_with_the_key_and_user_scope
test_a_failing_remove_does_not_stop_registration
test_running_twice_re_registers_each_time
test_succeeds_when_the_endpoint_answers_200
test_fails_when_the_endpoint_answers_anything_but_200

echo "--- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
