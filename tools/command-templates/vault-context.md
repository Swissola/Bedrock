---
description: Catch up on the vault — the repo summary, the latest handoffs and the open items
argument-hint: [optional topic or person to focus on]
allowed-tools: Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --context-behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --context-behind)
---
<!-- bedrock-template: vault-context, version 7 -->

See `runbooks/using-the-vault.md` in the vault, section 1, for the manual version of this workflow; this command automates it. Optional per-vault settings live in `vault-config.md` at the vault root (`docs/vault-config.md`); with none, every setting takes its default.

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Detect which `obsidian` MCP server you have from the tools actually available to you (their tool names differ), and use that column for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| search notes | the plugin's search tool | `search_notes` |

If you have neither set of tools, stop and say so.

**Settings.** First, on its own: read `vault-config.md` at the vault root and wait for the result before any other vault call (never batch it with other reads or listings, as the settings decide which paths to touch). A missing file or key takes the default. If part of it is malformed, use what you can read reliably, the default for the rest, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `vaultFormat` | *(none)* | `2` is the layout this command reads. Anything else is the old layout |
| `dailyNotesPath` | `daily-notes/{author}` | Where daily notes live. `{author}` stands for each contributor's subfolder, so scan every subfolder; a path with no `{author}` is a single flat folder |
| `reposPath` | `repos/{repo}/index.md` | Where a repo's own reference doc lives. Its summary, `context.md`, is the same path with the file name replaced |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. |
| `contextReadsRepoDoc` | `false` | If `true`, also read the current repo's full doc at `reposPath` when it exists |
| `staleOpenItemDays` | `30` | An open item older than this many days is flagged stale |

## Steps

1. **Who and where.** The repo name is the name of the main checkout's folder (`git rev-parse --path-format=absolute --git-common-dir` ends in the main checkout's `.git`; take the folder above it, so a linked worktree gets its main repo's name), lowercased unless `repoNameCase` is `keep`. Your author name is `git config user.name`, lowercased with spaces turned to hyphens; with no `user.name`, no note counts as yours.
2. **Check the layout.** If `vaultFormat` is not `2`, say the vault is in the old layout, offer to run `migrate-vault-format` (the command templates must be updated first), and stop.
3. **Do not reload what is already here.** If this conversation already holds the `session-start-vault-context` hook's output for this repo (a block starting `--- Vault context for <repo> (auto-loaded) ---`; a block starting `--- Vault context pointer for` only names files and does not count as loaded, but it does name the notes to read, see step 6), say so, use it as it is, and load only what it lacks, such as a topic search.
4. **With an argument** ("$ARGUMENTS", a topic or person): search the whole vault, the one case where crossing repos is wanted, and read the repo doc at `reposPath` if it exists. Return at most 5 notes, most recent first, each trimmed to its `Handoff` section (`Context for Future Sessions` in a note that has none), and say how many more matched. Then go to step 9.
5. **Otherwise read the repo summary**, `context.md` beside the repo doc. If it is missing, say so and offer `/vault-populate`. Read the full repo doc only if `contextReadsRepoDoc` is `true`.
6. **Find this repo's notes.** If a pointer block is in the conversation, its `Your latest note`, `Latest note from` and `Most recent daily note` lines name them: use those paths, and do not list any folder. Otherwise list folders, without reading any note. A note belongs to the repo if its filename, after the date, starts with the repo name and a hyphen, taking the longest match among the repos documented under `reposPath` (so `widget` does not claim `widget-ui`'s notes). Ignore `open-items-*` files. Take your own latest note for this repo, always, plus the latest from each of up to three other contributors, most recent first (newest filename date, then modification time if the backend reports it). Read them and show only each `Handoff` section, with the latest `## Update` section too for yours.
7. **Open items.** Each contributor keeps `open-items-<repo>.md` in their notes folder. Read each one's `## Open` section and nothing else (`## Closed` is history). List every item once with owner and age, counted from `opened YYYY-MM-DD`. Flag as stale any older than `staleOpenItemDays`, stale first. Show at most 10, then "and N more". If a folder holds a `.sync-conflict-` copy of an open-items file, say that person's list is unreliable.
   **Freshness.** Before that list, run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind`, then run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --context-behind`. The first prints `Behind the repo: N commits after <when>. Open items may be out of date.` when the repo has commits newer than the newest note. The second prints `Repo summary: N commits behind the code since <hash>. Run /vault-populate.` when the summary has fallen behind. Run both even if the session-start block is already here. Print any line they give exactly as printed, first in the summary, and say nothing about freshness if they print nothing. Never count commits yourself.
8. **No notes for this repo?** Use the newest note with no repo in its filename (an older note), reading the frontmatter of at most the newest 5 and skipping any whose `repo:` names a different repo. Label it "older note, repo unknown". Never use a note that belongs to another repo. If there is none, say there are no notes yet.
9. Summarise for me: the freshness lines first, then what the summary and the handoffs say, what is open (the list from step 7), and anything I should know before continuing. Keep it tight. End with one line saying `/vault-context <topic>` searches the full notes.
