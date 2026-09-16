# Connecting Claude Code to this vault

> **Scope:** a one-time, per-machine setup that lets Claude Code read and write this vault directly, via an MCP server named `obsidian` backed by the Obsidian **Local REST API** community plugin. Not specific to this team or this vault's content — the same steps work for any Obsidian vault.
>
> **Hosting:** this pattern assumes each person has their own local clone, kept in sync via this repo's own git history. A centrally-hosted, multi-user server is a different (harder, more InfoSec-sensitive) setup and isn't covered here.

## Step 0 — Clone first, then install and open Obsidian

**Clone this repo before installing or opening Obsidian at all.** Doing it in this order means there's nothing else for Obsidian's first-launch prompt to tempt you into by mistake:

```bash
git clone <your-repo-url>
```

Don't have Obsidian installed yet? Download the installer for your OS from [obsidian.md](https://obsidian.md) — no admin rights needed on any platform, it installs per-user like most desktop apps.

Open Obsidian. If it offers a choice, pick **"Open folder as vault"** and select the folder you just cloned — **not "Create new vault"**, which starts an empty, unrelated vault instead of this one. The cloned repo *is* the vault; there's nothing separate to create. (This is also why cloning first matters: if Obsidian's first launch happens before the clone exists, "Create new vault" becomes the tempting wrong answer — see [Known Gotchas](#known-gotchas).)

## Prerequisites

> ⚠️ **Before running any command below:** replace every placeholder — `<your-vault-path>`, `<latest-tag>`, `<api-key>`, `<your-repo-url>` — with your own real value first. A placeholder left in place typically fails silently (creates empty folders, downloads nothing) rather than erroring loudly. If you're not sure what a placeholder should be, ask before running it.

- Node.js + npm installed
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
- Obsidian installed, this repo cloned and opened as your vault (Step 0 above)

## Step 1 — Confirm the `claude` command works

```bash
claude --version
```

> ⚠️ **Stale PATH shim gotcha (Windows, common with nvm-for-windows):** if an old Node-version-manager shim sits first on `PATH` but its `claude.exe` was renamed or removed by an updater, bare `claude` fails while the real install lives elsewhere (typically `%APPDATA%\npm`). Remove the dead shim and reopen the terminal.

## Step 2 — Install the Local REST API plugin

**Try this first, it's almost always available:** in Obsidian, go to **Settings → Community plugins → Browse**, search "Local REST API", then **Install → Enable**.

> ⚠️ **Only use the fallback below if Browse is genuinely unavailable** (restricted/locked-down install) — it needs a real vault path and a real release tag substituted in, or it fails silently rather than erroring clearly.

If Browse really is unavailable, drop the plugin files in directly (ask your AI assistant to do this, so it can look up the actual current release tag instead of you guessing):

```bash
vault="<your-vault-path>"   # ← e.g. "/Users/you/Projects/your-vault-repo"
pdir="$vault/.obsidian/plugins/obsidian-local-rest-api"
mkdir -p "$pdir"

base="https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/<latest-tag>"   # ← check the releases page for the current tag: https://github.com/coddingtonbear/obsidian-local-rest-api/releases
for f in main.js manifest.json styles.css; do
    curl -L "$base/$f" -o "$pdir/$f"
done

echo '["obsidian-local-rest-api"]' > "$vault/.obsidian/community-plugins.json"
```

(Windows/PowerShell equivalent: same idea with `New-Item`/`Invoke-WebRequest` in place of `mkdir`/`curl`.)

Then fully close and reopen Obsidian on the vault, accepting "Turn on community plugins / Trust author" if prompted. On first load the plugin generates its API key and self-signed certificate into `.obsidian/plugins/obsidian-local-rest-api/data.json`.

## Quick path: run the setup script for everything remaining

Steps 1 and 2 above are the only parts that genuinely can't be scripted — clicking through Obsidian's own UI has to happen by hand, once. Everything from here — Steps 3 through 5 — can be done for you in one go:

- **Windows:** open an **Administrator** `pwsh` (PowerShell 7+) prompt — not a non-elevated one, and not legacy `powershell.exe` — then:

  ```powershell
  cd <path-to-your-clone>
  .\tools\setup-mcp.ps1
  ```

- **macOS/Linux:**

  ```bash
  cd <path-to-your-clone>
  chmod +x tools/setup-mcp.sh
  ./tools/setup-mcp.sh
  ```

It re-checks Steps 1 and 2 itself first, and stops with a clear, specific error if either isn't actually done yet rather than failing confusingly later on. Once past that, it auto-detects your vault path from its own location, reads the API key straight out of the plugin's config (nothing to copy-paste), and is safe to re-run at any point — including to fix a bad prior MCP registration.

The manual version of Steps 3–5 below is still here for understanding what the script does and for troubleshooting if it errors. The automation in [`docs/automation.md`](automation.md) (the reminder hooks, and the local commands/skills) is a separate, additional one-time install of its own — this script doesn't touch it.

## Step 3 — Enable the HTTP server

By default the plugin only enables HTTPS on port `27124`, which uses a self-signed certificate — that causes certificate-validation pain for MCP clients. Turn on plain HTTP instead:

```bash
vault="<your-vault-path>"   # ← same one as Step 2; this doesn't carry over between terminal sessions
f="$vault/.obsidian/plugins/obsidian-local-rest-api/data.json"
sed -i.bak 's/"enableInsecureServer": false/"enableInsecureServer": true/' "$f"
```

Restart Obsidian so the plugin binds port `27123`. Grab the `apiKey` value from `data.json` for the next step.

## Step 4 — Register the MCP server

```bash
claude mcp add --transport http obsidian "http://localhost:27123/mcp/" --header "Authorization: Bearer <api-key>" --scope user
```

- `--scope user` → available across all Claude Code sessions/projects on this machine, not just one
- Obsidian must be open — the MCP server runs inside the app
- Restart your Claude Code session after adding, for the connection to pick up

> If your organization runs Claude Code under an enterprise policy that restricts which MCP server URLs can be registered, `localhost` may not satisfy an allowlist pattern that expects a hostname. See [Enterprise MCP allowlists](#enterprise-mcp-allowlists-optional) below.

## Step 5 — Verify

```bash
curl -s -H "Authorization: Bearer <api-key>" http://localhost:27123/vault/

claude mcp list
```

Ask your AI assistant to read a known file (e.g. `index.md`) to confirm it works end-to-end.

## Enterprise MCP allowlists (optional)

Some enterprise Claude Code deployments restrict `claude mcp add` to an explicit allowlist of URL patterns, and reject anything else — including `localhost` — with an error like `not allowed by enterprise policy`. If that's your situation, one working pattern:

1. Ask whoever administers your Claude Code policy to allowlist a pattern like `http://obsidian.mcp.internal:27123/*` (any hostname works — it just needs to not be a raw IP or `localhost` if those are specifically excluded).
2. Map that hostname to your own machine in your hosts file, so it actually resolves:
   - **Windows** (`C:\Windows\System32\drivers\etc\hosts`, edit as Administrator): `127.0.0.1 obsidian.mcp.internal`
   - **macOS/Linux** (`/etc/hosts`, edit with `sudo`): `127.0.0.1 obsidian.mcp.internal`
3. Register against that hostname instead of `localhost` in Step 4 above.

This only affects your own machine's local name resolution — it isn't a real DNS entry and doesn't need to be. If you're rolling this out as documented guidance for others to follow (rather than just your own setup), loop in whoever owns that policy first — an allowlist entry approved for one person's use isn't automatically approved as a repeatable process for a whole team.

## Known Gotchas

| Issue | Fix |
|---|---|
| Obsidian prompted "Create new vault?" on first open | Choose **"Open folder as vault"** instead and select your clone of this repo — "Create new vault" starts an empty, unrelated vault elsewhere. See Step 0 |
| Ran a command with a placeholder (`<your-vault-path>`, `<api-key>`, etc.) left in literally | Fails silently rather than erroring — creates empty junk folders at the literal path, downloads nothing, or registers a connection that will fail later. Always substitute real values first |
| Ran a later step in a new terminal, an earlier step's shell variable no longer set | Shell variables don't persist between terminal sessions — re-declare `$vault` (or `$vault`/`$f` in PowerShell) in each new session rather than assuming it's still set |
| Registered the MCP server with `<api-key>` left in literally | `claude mcp add` succeeds either way (it doesn't validate the header at registration time) but the connection then fails with HTTP 401 — `claude mcp list` shows `obsidian: ... Failed to connect`. Fix: `claude mcp remove obsidian --scope user`, then re-add with the real key from `data.json` |
| Setup script says `claude` not found, but it works in your normal terminal | On Windows, run it in `pwsh` (PowerShell 7+), not a spawned legacy `powershell.exe` — the two can resolve `PATH` differently |
| Community plugins Browse missing/locked | Install plugin files manually (Step 2 fallback) |
| Certificate errors on port 27124 | Use plain HTTP on 27123 instead (`"enableInsecureServer": true`) — Step 3 |
| `claude mcp add` fails with "not allowed by enterprise policy" | Your org's allowlist likely does a literal string match, port included — see [Enterprise MCP allowlists](#enterprise-mcp-allowlists-optional) |
| Obsidian must be open | The MCP server runs inside the app — no Obsidian running means no MCP connection, regardless of what `claude mcp list` says |
| API key exposed in a shell history or chat | Regenerate it in the plugin settings, then re-run the registration step with the new key |
| `.obsidian/plugins/*/data.json` committed to git | Contains the live API key and certificate — confirm it's in `.gitignore` **before** your first commit, not after |
| Wrote a file into a dot-prefixed folder (e.g. `.claude/`) inside the vault via the MCP write tool | Reports success, but the file is then invisible to every other vault tool afterward (not listed, not readable, not deletable) — Obsidian's plugin API treats dot-folders as hidden/plugin-config space, not indexed vault content. Use a plain folder name instead |
| A folder in `tools/` looks empty in Obsidian's file explorer, even though the files exist on disk | Obsidian's **Settings → Files and Links → "Detect all file extensions"** is off by default, which hides files with an unrecognised or missing extension (e.g. this repo's extensionless hook templates) from the explorer entirely. Turn that setting on to see everything the repo actually contains |

## Related

- [`docs/mcp-tools-reference.md`](mcp-tools-reference.md) — everything the vault connection can actually do
- [`docs/automation.md`](automation.md) — optional git hooks and Claude Code commands/skills built on top of this connection
- [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) — what to actually do with the vault once this is working
- Central hosting (a shared, network-reachable server rather than per-person local clones) is a real option for larger teams but reopens network/security questions that are out of scope for this guide.
