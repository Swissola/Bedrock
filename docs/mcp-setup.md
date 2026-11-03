# Connecting Claude Code to this vault

> **Scope:** for anyone setting up a machine to use the vault. It is a one-time, per-machine setup that lets Claude Code read and write the vault directly, through an **MCP server** named `obsidian`. (MCP, the Model Context Protocol, is how Claude Code talks to outside tools.) The server is backed by the Obsidian **Local REST API** community plugin. Nothing here is specific to this team or this vault's content: the same steps work for any Obsidian vault.
>
> **Hosting:** this pattern assumes each person has their own local clone, kept in sync through this repo's git history. A centrally hosted, multi-user server is a different (harder, more InfoSec-sensitive) setup and isn't covered here.
>
> **Another backend:** MCPVault is an alternative that needs no Obsidian plugin. See [Backends](vault-config.md#backends). This page covers the Local REST API route.

## The steps at a glance

| Step | What | Scriptable? |
|---|---|---|
| 0 | Clone the repo, install Obsidian, open the clone as a vault | No |
| 1 | Confirm `claude` works | Checked by the script |
| 2 | Install and enable the Local REST API plugin | No (it is clicking through Obsidian), checked by the script |
| 3 | Switch on the plugin's plain-HTTP server | Yes |
| 4 | Register the `obsidian` MCP server with Claude Code | Yes |
| 5 | Verify | Yes |

Do steps 0 to 2 by hand, then either run the [setup script](#quick-path-run-the-setup-script-for-steps-3-to-5) or follow steps 3 to 5 manually.

## Prerequisites

- Node.js and npm installed.
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`).
- Obsidian installed, and this repo cloned and opened as your vault (Step 0).

> **Warning, before running any command below:** replace every placeholder (`<your-vault-path>`, `<latest-tag>`, `<api-key>`, `<your-repo-url>`) with your own real value first. A placeholder left in place typically fails silently (creates empty folders, downloads nothing) rather than erroring loudly. If you're not sure what a placeholder should be, ask before running it.

## Step 0: Clone first, then install and open Obsidian

**Clone this repo before installing or opening Obsidian at all.** Doing it in this order means there's nothing else for Obsidian's first-launch prompt to tempt you into by mistake.

```bash
git clone <your-repo-url>
```

Don't have Obsidian yet? Download the installer for your OS from [obsidian.md](https://obsidian.md). No admin rights are needed on any platform, it installs per-user like most desktop apps.

Open Obsidian. If it offers a choice, pick **"Open folder as vault"** and select the folder you just cloned, **not "Create new vault"**, which starts an empty, unrelated vault instead of this one. The cloned repo *is* the vault, so there's nothing separate to create. This is also why cloning first matters: if Obsidian's first launch happens before the clone exists, "Create new vault" becomes the tempting wrong answer (see [Known Gotchas](#known-gotchas)).

You are done when the vault's folders (`runbooks/`, `docs/` and so on) show in Obsidian's file list.

## Step 1: Confirm the `claude` command works

```bash
claude --version
```

You are done when it prints a version number.

> **Stale PATH shim (Windows, common with nvm-for-windows):** if an old Node-version-manager shim sits first on `PATH` but its `claude.exe` was renamed or removed by an updater, bare `claude` fails while the real install lives elsewhere (typically `%APPDATA%\npm`). Remove the dead shim and reopen the terminal.

## Step 2: Install the Local REST API plugin

**Try this first, it's almost always available.** In Obsidian, go to **Settings → Community plugins → Browse**, search "Local REST API", then **Install → Enable**.

**Only use the fallback below if Browse is genuinely unavailable** (a restricted or locked-down install). It needs a real vault path and a real release tag substituted in, or it fails silently rather than erroring clearly. Ask your AI assistant to do it, so it can look up the actual current release tag instead of you guessing.

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

(Windows PowerShell equivalent: the same idea with `New-Item` and `Invoke-WebRequest` in place of `mkdir` and `curl`.)

Then fully close and reopen Obsidian on the vault, accepting "Turn on community plugins / Trust author" if prompted.

You are done when `.obsidian/plugins/obsidian-local-rest-api/data.json` exists. On first load the plugin writes its API key and self-signed certificate into that file.

## Quick path: run the setup script for steps 3 to 5

Steps 1 and 2 are the only parts that can't be scripted, because clicking through Obsidian's own UI has to happen by hand, once. The script re-checks both itself, stops with a specific error if either isn't done yet, and then does steps 3 to 5. It detects your vault path from its own location and reads the API key straight out of the plugin's config, so there is nothing to copy and paste. It is safe to re-run at any point, including to fix a bad earlier MCP registration.

**Windows.** Open `pwsh` (PowerShell 7 or later, not the legacy `powershell.exe`), then:

```powershell
cd <path-to-your-clone>
.\tools\setup-mcp.ps1
```

**macOS and Linux:**

```bash
cd <path-to-your-clone>
chmod +x tools/setup-mcp.sh
./tools/setup-mcp.sh
```

What to expect:

1. **The first run usually stops part-way.** If the plugin's plain-HTTP server is off, the script switches it on and prints `[Step 3] Enabled HTTP server. Restart Obsidian now, then re-run this script to continue.` Restart Obsidian and run the script again.
2. **The second run finishes.** It prints `[Step 4] OK - registered`, then `[Step 5] OK - vault endpoint responded HTTP 200`, then `Done.`
3. **Restart your Claude Code session**, then ask it to read `index.md`. That confirms the whole chain.

If it errors, the message names the step that failed, and the manual steps below show what each step does. If `claude` is not found but works in your normal terminal, see [Known Gotchas](#known-gotchas).

This script doesn't touch the automation in [`automation.md`](automation.md) (the slash commands and hooks), which is a separate, optional install.

## Step 3: Enable the HTTP server

By default the plugin only enables HTTPS on port `27124`, with a self-signed certificate, which causes certificate-validation trouble for MCP clients. Turn on plain HTTP instead:

```bash
vault="<your-vault-path>"   # ← same one as Step 2; this doesn't carry over between terminal sessions
f="$vault/.obsidian/plugins/obsidian-local-rest-api/data.json"
sed -i.bak 's/"enableInsecureServer": false/"enableInsecureServer": true/' "$f"
```

Restart Obsidian so the plugin binds port `27123`. Then copy the `apiKey` value from `data.json` for the next step.

## Step 4: Register the MCP server

```bash
claude mcp add --transport http obsidian "http://localhost:27123/mcp/" --header "Authorization: Bearer <api-key>" --scope user
```

- `--scope user` makes it available in every Claude Code session on this machine, not just one project.
- Obsidian must be open, because the MCP server runs inside the app.
- Restart your Claude Code session after adding, so the connection is picked up.

If your organisation runs Claude Code under an enterprise policy that restricts which MCP server URLs can be registered, `localhost` may not satisfy an allowlist pattern that expects a hostname. See [Enterprise MCP allowlists](#enterprise-mcp-allowlists-optional).

## Step 5: Verify

```bash
curl -s -H "Authorization: Bearer <api-key>" http://localhost:27123/vault/

claude mcp list
```

You are done when `curl` returns a JSON list of the vault's files and `claude mcp list` shows `obsidian` as connected rather than `Failed to connect`. Then ask your AI assistant to read a known file (for example `index.md`) to confirm it works end to end.

## Using more than one vault on one machine (optional)

If you work in two vaults, the Local REST API plugin gets in the way in three ways. Each vault's plugin generates its **own API key**; both default to the **same ports** (HTTP 27123, HTTPS 27124); and only one Obsidian vault window can serve those ports at a time. Registered as one `obsidian` server with one key, the MCP tools return HTTP 401 whenever the other vault is the open one, even though the server is up.

The setup Bedrock supports is **one key and one port per machine, and you open the vault you want to work in**:

1. Pick one vault's `apiKey` (in `.obsidian/plugins/obsidian-local-rest-api/data.json`) and copy the same value into the other vault's `data.json`. Close that vault in Obsidian first, so the plugin does not overwrite the edit, then reopen it.
2. Leave both on the same ports.
3. Register `obsidian` once (Step 4, or `setup-mcp`). It now works for whichever vault is open.
4. Before a session that reads or writes a vault, open that vault in Obsidian.

What follows from that:

- **Claude's MCP tools and the `post-merge` hook act on the open vault, whichever vault the repo belongs to.** A hook for the vault that is not open has its write land in the wrong vault or nowhere, and then fails its check. See [Working across more than one vault](automation.md#working-across-more-than-one-vault).
- **Do not run `setup-mcp` from the second vault** unless the keys match. It reads that vault's own key and replaces the single `obsidian` registration, which silently switches the key.
- **HTTP 401 with Obsidian running** means the open vault's key differs from the registered one. Make them match, or re-register with the open vault's key.
- The same key is now in two `data.json` files. Both stay gitignored, and the key is the one credential for whichever vault is open, so regenerate it in both places if it leaks.

If you would rather keep separate keys, the alternative is one registration per vault under different names (for example `obsidian-<vault>`), on different ports, with one Obsidian window each. That works, but the commands and hooks assume a server called `obsidian`, so it is not covered here.

## Enterprise MCP allowlists (optional)

Some enterprise Claude Code deployments restrict `claude mcp add` to an explicit allowlist of URL patterns, and reject anything else, including `localhost`, with an error like `not allowed by enterprise policy`. If that's your situation, one working pattern:

1. Ask whoever administers your Claude Code policy to allowlist a pattern like `http://obsidian.mcp.internal:27123/*`. Any hostname works, as long as it isn't a raw IP or `localhost` if those are specifically excluded.
2. Map that hostname to your own machine in your hosts file, so it actually resolves:
   - **Windows** (`C:\Windows\System32\drivers\etc\hosts`, edit as Administrator): `127.0.0.1 obsidian.mcp.internal`
   - **macOS and Linux** (`/etc/hosts`, edit with `sudo`): `127.0.0.1 obsidian.mcp.internal`
3. Register against that hostname instead of `localhost` in Step 4.

This only affects your own machine's name resolution. It isn't a real DNS entry and doesn't need to be. If you're rolling this out as guidance for others, loop in whoever owns that policy first: an allowlist entry approved for one person isn't automatically approved as a repeatable process for a whole team.

## Known Gotchas

| Issue | Fix |
|---|---|
| Obsidian prompted "Create new vault?" on first open | Choose **"Open folder as vault"** instead and select your clone of this repo. "Create new vault" starts an empty, unrelated vault elsewhere. See Step 0 |
| Ran a command with a placeholder (`<your-vault-path>`, `<api-key>`, etc.) left in literally | Fails silently rather than erroring: it creates empty junk folders at the literal path, downloads nothing, or registers a connection that fails later. Always substitute real values first |
| Ran a later step in a new terminal and an earlier step's shell variable is no longer set | Shell variables don't persist between terminal sessions. Re-declare `$vault` (or `$vault` and `$f` in PowerShell) in each new session |
| Registered the MCP server with `<api-key>` left in literally | `claude mcp add` succeeds either way (it doesn't validate the header at registration time), but the connection then fails with HTTP 401 and `claude mcp list` shows `obsidian: ... Failed to connect`. Fix: `claude mcp remove obsidian --scope user`, then re-add with the real key from `data.json` |
| Setup script says `claude` not found, but it works in your normal terminal | On Windows, run it in `pwsh` (PowerShell 7+), not a spawned legacy `powershell.exe`. The two can resolve `PATH` differently |
| Community plugins Browse missing or locked | Install the plugin files manually (the Step 2 fallback) |
| Certificate errors on port 27124 | Use plain HTTP on 27123 instead (`"enableInsecureServer": true`), Step 3 |
| `claude mcp add` fails with "not allowed by enterprise policy" | Your org's allowlist likely does a literal string match, port included. See [Enterprise MCP allowlists](#enterprise-mcp-allowlists-optional) |
| Obsidian must be open | The MCP server runs inside the app. With no Obsidian running there is no MCP connection, whatever `claude mcp list` says |
| After switching the open vault, the HTTP server does not start | Flip the plugin's "Non-encrypted (HTTP) Server" toggle off and on by hand, even when `enableInsecureServer` is already `true` in `data.json`. Seen more than once after switching vaults |
| API key exposed in a shell history or chat | Regenerate it in the plugin settings, then re-run the registration step with the new key |
| `.obsidian/plugins/*/data.json` committed to git | It contains the live API key and certificate. Confirm it's in `.gitignore` **before** your first commit, not after |
| A note was cut down to its heading after an edit made with the surgical edit tool (`vault_patch`) | That tool is unreliable on some versions of the plugin. Read the whole note and write the whole note back instead, as the vault's `CLAUDE.md` says, until you have confirmed the tool is safe on your version |
| Wrote a file into a dot-prefixed folder (for example `.claude/`) inside the vault through the MCP write tool | It reports success, but the file is then invisible to every other vault tool (not listed, not readable, not deletable), because Obsidian's plugin API treats dot-folders as hidden or plugin-config space, not indexed vault content. Use a plain folder name instead |
| A folder in `tools/` looks empty in Obsidian's file explorer, even though the files exist on disk | Obsidian's **Settings → Files and Links → "Detect all file extensions"** is off by default, which hides files with an unrecognised or missing extension (for example this repo's extensionless hook templates). Turn it on to see everything the repo contains |

## Related

- [`mcp-tools-reference.md`](mcp-tools-reference.md): everything the vault connection can actually do
- [`automation.md`](automation.md): optional git hooks and Claude Code commands built on top of this connection
- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md): what to do with the vault once this is working
- Central hosting (a shared, network-reachable server rather than per-person local clones) is a real option for larger teams, but it reopens network and security questions that are out of scope here.
