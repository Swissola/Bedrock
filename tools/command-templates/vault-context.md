---
description: Catch up on the vault — read the hub note and recent daily notes
argument-hint: [optional topic or person to focus on]
---
<!-- bedrock-template: vault-context, version 3 -->

See `runbooks/using-the-vault.md` in the vault, section 1, for the manual version of this workflow and its rationale — this command just automates it. Per-vault differences are optional and live in a `vault-config.md` note at the vault root; see `docs/vault-config.md`. With no `vault-config.md`, every setting below takes its default and this behaves exactly as it always has.

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Two different `obsidian` MCP servers are in use, with different tool names. Detect which one you have from the tools actually available to you, and use that column for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| search notes | the plugin's search tool | `search_notes` |

If you have neither set of tools, stop and say so.

**Settings.** Do this first, on its own: read `vault-config.md` at the vault root and wait for the result before making any other vault call (do not batch it with other reads or listings — the settings decide which paths to touch). If it doesn't exist, or a key is missing, use the default. If it exists but part of it is malformed, use what you can read reliably, the default for everything else, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key, if present, overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `hubNote` | `index.md` | The vault's hub note. `none` means there isn't one, skip step 1 |
| `dailyNotesPath` | `daily-notes/{author}` | Where daily notes live. `{author}` stands for each contributor's subfolder, so scan every subfolder; a path with no `{author}` is a single flat folder |
| `reposPath` | `repos/{repo}/index.md` | Where a repo's own reference doc lives |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. |
| `contextReadsRepoDoc` | `false` | If `true`, also read the current repo's doc at `reposPath` (`{repo}` is the basename of `git rev-parse --show-toplevel`, lowercased unless `repoNameCase` is `keep`) when it exists |

## Steps

1. If `hubNote` isn't `none`, read it for the current state of the vault hub.
2. Find the most recent daily note(s):
   - If an argument was given ("$ARGUMENTS"), search the vault for daily notes mentioning that topic or person and prioritise those, most recent first.
   - Otherwise, list the daily notes folder(s) per `dailyNotesPath` and pick the single most recent file by its `YYYY-MM-DD` filename prefix, regardless of who wrote it. If several share the newest date and your backend can report modification times, take the most recently modified of them; otherwise take all of them.
3. Read the note(s) found. If `contextReadsRepoDoc` is `true` and the repo doc exists, read that too.
4. Summarise for me: what was done, what's still open (the `Open Questions / Next Steps` checklist), and anything I should know before continuing. Keep it tight — a few sentences per note, not a full re-print of the file.
