---
description: Catch up on the vault — read the hub note and recent daily notes
argument-hint: [optional topic or person to focus on]
---
<!-- bedrock-template: vault-context, version 5 -->

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
| `hubNote` | `index.md` | The vault's hub note. `none` means there isn't one, so do not read it in step 3 |
| `dailyNotesPath` | `daily-notes/{author}` | Where daily notes live. `{author}` stands for each contributor's subfolder, so scan every subfolder; a path with no `{author}` is a single flat folder |
| `reposPath` | `repos/{repo}/index.md` | Where a repo's own reference doc lives |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. |
| `contextReadsRepoDoc` | `false` | If `true`, also read the current repo's doc at `reposPath` when it exists |
| `staleOpenItemDays` | `30` | An open item older than this many days is flagged stale |

## Steps

1. **Who and where.** The repo name is the name of the main checkout's folder (`git rev-parse --path-format=absolute --git-common-dir` ends in the main checkout's `.git`; take the folder above it, so a linked worktree gets its main repo's name), lowercased unless `repoNameCase` is `keep`. Your author name is `git config user.name`, lowercased with spaces turned to hyphens; with no `user.name`, no note counts as yours.
2. **Do not reload what is already here.** If this conversation already holds the `session-start-vault-context` hook's output for this repo (a block starting `--- Vault context for <repo> (auto-loaded) ---`; a block starting `--- Vault context pointer for` only names files and does not count, so load as below), say so, use its notes and open-item list as they are, and load only what it lacks, such as a topic search or a note it left out for size.
3. If `hubNote` isn't `none`, read it. If `contextReadsRepoDoc` is `true` and the repo doc exists, read that too.
4. **With an argument** ("$ARGUMENTS", a topic or person): search the whole vault, the one case where crossing repos is wanted. Return at most 5 notes, most recent first, each trimmed to its `Context for Future Sessions` section, and say how many more matched. Then go to step 9.
5. **Otherwise find this repo's notes by listing folders, without reading any note.** A note belongs to the repo if its filename, after the date, starts with the repo name and a hyphen, taking the longest match among the repos documented under `reposPath` (so `widget` does not claim `widget-ui`'s notes). Take your own latest note for this repo, always, plus the latest note for this repo from each of up to three other contributors, most recent first (newest filename date, then modification time if the backend reports it). A solo vault therefore loads one note.
6. **Read those notes and show them trimmed.** Yours: `Context for Future Sessions`, the prose of `Open Questions / Next Steps` and the latest `## Update` section. Others': `Context for Future Sessions` only. Leave out every checkbox line (`- [ ]`, `[x]`, `[-]`, `[>]`) from what you show: open items go in step 7. Show each note's tags.
7. **Open items.** From each contributor's latest note for this repo, loaded or not (search for `- [ ]` rather than reading whole notes; if you must read one that step 5 did not select, take only its open items and show nothing else from it), list the open items once each with owner and age. Age counts from `opened YYYY-MM-DD` on the line if there is one, else from the note's date. Flag as stale any older than `staleOpenItemDays`, and list stale ones first. Show at most 10, then "and N more".
8. **No notes for this repo?** Use the newest note with no repo in its filename (an older note), reading the frontmatter of at most the newest 5 and skipping any whose `repo:` names a different repo, and stop at the first usable one. Label it "older note, repo unknown" and say there are at least N such notes. Never use a note that belongs to another repo. If there is none, say there are no notes yet.
9. Summarise for me: what was done, what is open (the list from step 7), and anything I should know before continuing. Keep it tight: a few sentences per note, not a re-print.
