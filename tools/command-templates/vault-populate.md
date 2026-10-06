---
description: Summarise the current repo and write a reference doc for it into the vault
argument-hint: [optional repo name override, otherwise inferred from this folder]
---
<!-- bedrock-template: vault-populate, version 2 -->

See `runbooks/using-the-vault.md` in the vault, section 3, for the full manual version of this workflow and its rationale — this command just automates it. Per-vault differences are optional and live in a `vault-config.md` note at the vault root; see `docs/vault-config.md`. With no `vault-config.md`, every setting below takes its default and this behaves exactly as it always has (writing `repos/<name>/index.md`).

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Two different `obsidian` MCP servers are in use, with different tool names. Detect which one you have from the tools actually available to you, and use that column for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| write a note, replacing it | `vault_write` (whole file) | `write_note` (`mode: overwrite`) |

Always read the full current content, then write the full updated content back, for either backend (the surgical `vault_patch` tool is unreliable on some plugin versions, see the Known Gotchas table in `docs/mcp-setup.md`). If you have neither set of tools, stop and say so.

**Settings.** Do this first, on its own: read `vault-config.md` at the vault root and wait for the result before making any other vault call (do not batch it with other reads or listings — the settings decide which paths to touch). If it doesn't exist, or a key is missing, use the default. If it exists but part of it is malformed, use what you can read reliably, the default for everything else, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key, if present, overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `reposPath` | `repos/{repo}/index.md` | Where this repo's doc is written. `{repo}` is the name from step 2 |
| `hubNote` | `index.md` | The vault's hub note. `none` means there isn't one, skip step 6 |

## Steps

1. Confirm the current working directory is a real git repo and is **not** the vault itself (check whether `vault-config.md`, or the `hubNote` together with the daily notes folder from `dailyNotesPath`, exist right here in this same working directory — with the defaults that is `index.md` and a `daily-notes/` folder — as the tell). If it is the vault, stop and say this command is for documenting *other* repos from inside their own folder, not the vault itself.
2. Determine the repo name: "$ARGUMENTS" if given, otherwise the repo's folder name (or its `git remote` name if that's clearer).
3. Read the doc at `reposPath` in the vault first, if it already exists. This run should refresh or extend an existing doc, not blindly overwrite tribal knowledge someone already recorded there.
4. Summarise this repo for a new-starter reference doc: what it does, how it's structured, how it's run/deployed, and anything that would trip up someone new to it. Base this on the actual code in front of you, not assumptions — and if an existing doc already covers tribal knowledge a code-only read can't reconstruct, preserve it rather than dropping it. If another repo's doc already exists at a sibling `reposPath` in the vault, follow its structure as a model for consistency; otherwise use your own best judgement for a clear reference doc.
5. Write (or update) the doc at `reposPath` in the vault. Never write secrets — passwords, tokens, API keys, passphrases, private keys, connection strings with embedded credentials — into it, even if one is present in the repo; say where the secret lives instead.
6. If `hubNote` isn't `none`: read it and add a row for this repo to its Systems/Repos table if one doesn't already exist, linking to the doc written in step 5 — an undiscoverable doc barely beats no doc at all.
7. Tell me plainly: **this is a first-pass, machine-generated draft**. I should read it myself and correct anything wrong or missing before trusting it, especially anything that needed real tribal knowledge to get right (per `runbooks/using-the-vault.md`, step 5 of the repos-bootstrap workflow).
