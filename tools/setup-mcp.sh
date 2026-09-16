#!/usr/bin/env bash
# Automates the scriptable parts of docs/mcp-setup.md for this vault, on macOS/Linux.
#
# Safe to re-run at any point - it checks current state before changing anything, and
# never needs a placeholder value typed in by hand (vault path is auto-detected from this
# script's own location; the API key is read directly out of the plugin's data.json).
#
# What it can't do for you: installing the "Local REST API" Obsidian plugin itself
# (Settings -> Community plugins -> Browse -> "Local REST API" -> Install + Enable) -
# that's a one-time GUI/trust-prompt step. Run this script after that's done.
#
# Registers the MCP server against http://localhost:27123/. If your organization's
# Claude Code policy requires a specific allowlisted hostname instead of localhost,
# see "Enterprise MCP allowlists" in docs/mcp-setup.md and register manually with
# that hostname instead of running this script.
#
# Usage: ./setup-mcp.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "Vault path: $VAULT_PATH"

# --- Step 1: Claude Code present ---
if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: Claude Code not found on PATH. Install it first: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
fi
claude_version="$(claude --version 2>/dev/null)"
echo "[Step 1] OK - Claude Code $claude_version"

# --- Step 2: plugin installed? (can't be automated past this check - see header comment) ---
plugin_dir="$VAULT_PATH/.obsidian/plugins/obsidian-local-rest-api"
data_file="$plugin_dir/data.json"

if [ ! -f "$data_file" ]; then
    echo "ERROR: Local REST API plugin not found at $data_file. Install it via Obsidian first: Settings -> Community plugins -> Browse -> 'Local REST API' -> Install + Enable. Then re-run this script." >&2
    exit 1
fi
echo "[Step 2] OK - plugin installed"

# --- Step 3: enable the plain-HTTP server ---
if grep -q '"enableInsecureServer": false' "$data_file"; then
    sed -i.bak 's/"enableInsecureServer": false/"enableInsecureServer": true/' "$data_file"
    echo "[Step 3] Enabled HTTP server. Restart Obsidian now, then re-run this script to continue."
    exit 0
elif grep -q '"enableInsecureServer": true' "$data_file"; then
    echo "[Step 3] OK - HTTP server already enabled"
else
    echo "ERROR: Could not find 'enableInsecureServer' in $data_file - plugin config format may have changed. Check it by hand." >&2
    exit 1
fi

api_key="$(grep -o '"apiKey": *"[^"]*"' "$data_file" | sed -E 's/.*"apiKey": *"([^"]*)".*/\1/')"
if [ -z "$api_key" ]; then
    echo "ERROR: Could not find 'apiKey' in $data_file. Open Obsidian with the plugin enabled at least once first." >&2
    exit 1
fi

port="$(grep -o '"insecurePort": *[0-9]*' "$data_file" | grep -o '[0-9]*$')"
port="${port:-27123}"

# --- Step 4: register the MCP server (remove-then-add, so re-running fixes a bad prior registration) ---
claude mcp remove obsidian --scope user >/dev/null 2>&1 || true
claude mcp add --transport http obsidian "http://localhost:${port}/mcp/" --header "Authorization: Bearer ${api_key}" --scope user
echo "[Step 4] OK - registered. Restart your Claude Code session to pick this up."

# --- Step 5: verify the HTTP endpoint answers ---
http_status="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${api_key}" "http://localhost:${port}/vault/")"
if [ "$http_status" != "200" ]; then
    echo "ERROR: [Step 5] Vault endpoint responded HTTP $http_status, expected 200." >&2
    exit 1
fi
echo "[Step 5] OK - vault endpoint responded HTTP $http_status"

echo ""
echo "Done. Restart your Claude Code session, then ask it to read 'index.md' to confirm end-to-end."
