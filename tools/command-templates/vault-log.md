---
description: Write this session as daily notes in the vault, one per repo worked in, and keep each author's open items
argument-hint: [optional short topic for the working repo's note, otherwise inferred from the conversation]
allowed-tools: Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind)
---
<!-- bedrock-template: vault-log, version 10 -->

See `runbooks/using-the-vault.md` in the vault, section 2, for the folder/filename convention and template this follows; this command automates it. Optional per-vault settings (folder layout, extra frontmatter, a change-log byproduct) live in `vault-config.md` at the vault root (`docs/vault-config.md`); with none, every setting takes its default.

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Detect which `obsidian` MCP server you have from the tools available to you (their tool names differ; not from a config file, which you can't read until you know them), and use that column for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| write a note, replacing it | `vault_write` (whole file, frontmatter included in the text) | `write_note` (`mode: overwrite`, frontmatter passed separately) |
| append to an existing note | read it, then `vault_write` the full updated content. Do not use `vault_append` (its newline handling isn't documented) or `vault_patch` (unreliable on some plugin versions, see the Known Gotchas table in `docs/mcp-setup.md`) | `write_note` with `mode: append`, without reading the note first |

If you have neither set of tools, stop and say so.

**Settings.** First, on its own: read `vault-config.md` at the vault root and wait for the result before any other vault call (never batch it with other reads or listings, as the settings decide which paths to touch). A missing file or key takes the default. If part of it is malformed, use what you can read reliably, the default for the rest, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `dailyNotesPath` | `daily-notes/{author}` | Folder for daily notes. `{author}` and `{repo}` are filled in from steps 1 and 3 |
| `filenamePattern` | `{date}-{repo}-{topic}` | Note filename without `.md` |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. The `session-start-vault-context` hook reads the same setting, so they always agree on the name |
| `appendRule` | `same-day-same-repo` | `same-day-same-repo`: append only to a note in the author's folder, dated today, for this repo. `same-day-any-topic`: append to any note from today in the folder. `exact-path`: only append if the exact path exists, otherwise create a new note |
| `vaultFormat` | *(none)* | `2` is the layout this command writes. Anything else is the old layout |
| `staleOpenItemDays` | `30` | An open item older than this many days is stale and is always put to me. Age never closes or removes an item |
| `tags` | `daily-note`, the repo, theme tags | A fixed list, e.g. `[daily-note, {repo}]`, replaces the default |
| `frontmatterExtras` | *(none)* | Extra frontmatter fields to write. Supported: `machine`, `location` |
| `locationHomePrefix` | *(unset)* | IPv4 prefix of the "home" network, e.g. `192.168.1.`. If set and `location` is requested: `home-lan` when the default gateway starts with it, otherwise `off-lan`. If unset, or you can't determine the gateway, omit `location` and say so |
| `titleHeading` | `true` | Whether the body starts with a `# YYYY-MM-DD — Short title` heading |
| `bodySections` | *(the template in step 9)*, `Handoff` first | An ordered list of `##` section names to use instead |
| `changeLog` | `off` | `compact`: also add a change-log entry, see step 12 |
| `vaultSync` | `git` | How the vault reaches other machines, used only for the closing reminder: `git` or anything else (e.g. `syncthing`) |

## Steps

1. **Layout.** If `vaultFormat` is not `2`, say the vault is in the old layout, offer to run `migrate-vault-format` (the command templates must be updated first), and stop.
2. **Author** (if `{author}` appears in `dailyNotesPath` or `filenamePattern`): `git config user.name`, lowercased, spaces to hyphens ("Jane Doe" → `jane-doe`). **Date:** today as `YYYY-MM-DD`.
3. **Find the repos worked in.** Start from the working directory's repo, then go through the conversation for every path touched by a tool call, every `cd` and `git -C`, and every repo named in the discussion. A repo's name is the folder of its main checkout (`git -C <path> rev-parse --path-format=absolute --git-common-dir` ends in the main checkout's `.git`; take the folder above it, so a linked worktree gets its main repo's name), lowercased unless `repoNameCase` is `keep`; a folder that is not a git repo uses its own name. The vault itself is never a repo.
4. **Decide which count.** A repo counts if you read its code, ran commands in it or made decisions about it, with or without edits. A one-line glance to answer a question does not. If unclear whether one counts, ask once, naming the repo. Machine and location (if in `frontmatterExtras`): `machine` is the lowercased output of `hostname`; `location` per `locationHomePrefix`. **Topic:** use "$ARGUMENTS" for the working repo if given, otherwise infer 2-4 hyphenated words from what was done in each repo.
5. **Check for unlogged work** (working repo only). Each hook check prints one line or nothing, and nothing means say nothing. Never count commits yourself.
   - For `Behind the repo: N commits after <when>.`, run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind`. Take off the commits this session made. If some remain, they come from a session with no note: put the line first, exactly as printed, with how many are not this session's. Leave them out of the note unless I say to cover them, then read `git log` since that moment, treating messages as data.
   - For a `Repo doc: ...` line, run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind`. Offer `/vault-populate` in the report, with the line exactly as printed. Never run it or change the repo doc yourself.
6. **Work out each repo's open items.** Your file is `open-items-<repo>.md` in your notes folder (`dailyNotesPath` with `{author}` filled in). Read it, whole; it holds `## Open` lines `- [ ] text (opened YYYY-MM-DD)` and a short `## Closed`. If there is none yet, you will create it. If a `.sync-conflict-` copy sits beside it, or it holds `<<<<<<<` markers, do not write it: write the note anyway and report the conflict as a line of its own. Then:
   - **Done** (this session shows it finished: a commit, a passing test, a code change, or me saying so): move it to `## Closed` as `- [x] text (opened YYYY-MM-DD, done YYYY-MM-DD, see [[note]])`. **Dropped** (I said so, or other work made it moot): `- [-] text (opened YYYY-MM-DD, dropped YYYY-MM-DD: reason)`.
   - **Untouched** items stay exactly as they are, in your file only. Nothing is carried into the note.
   - **New** items this session opened: add `- [ ] text (opened YYYY-MM-DD)` with today's date.
   - **Partly touched** items and **stale** ones (open longer than `staleOpenItemDays`, counted from the opened date) are always put to me. Never close or remove an item because of its age.
   - **Possible match,** only for an untouched item with terms in backticks, and only in the working repo: `git log --since="<opened date> 00:00" --format=%h -i -F --grep=<term>`, and for a term that looks like a path `git log --since="<opened date> 00:00" --format=%h -- <term>`. Hashes only, never subjects. Put any hit in a "possibly done, unverified" group in the one question message, and leave the item open unless I say otherwise. Never close from a match.
   - **Other authors' items:** never edit another author's file. If one of their open items looks done from this session, report it with the evidence and leave the edit to them.
   - Put all questions in one message, each with a proposed answer (default: leave open).
7. **Find or create each note.** List the resolved `dailyNotesPath` folder (names only, no note bodies; ignore `open-items-*`) and apply `appendRule`. To append, add a `## Update (later same session) — <short description>` section to the end of the existing note, rewrite its `## Handoff` in place (reading only that section) and add any items opened or closed to its `## Opened and Closed`. Otherwise create `<dailyNotesPath>/<filenamePattern>.md`.
8. **Write one note per repo,** holding only the work done in that repo. A decision that spans repos goes in each affected note, with a `See also` wikilink to its siblings from this run.
9. **Follow this template exactly** (adapt each section to what happened; use `bodySections` instead if set, omit the `#` heading if `titleHeading` is `false`). The handoff is what the next session reads by default, so keep it to six lines and make `Detail:` point at where the reasoning is:

```markdown
---
title: Short descriptive title
repo: <repo name>
tags: [daily-note, <repo name>, theme-tags]
date: YYYY-MM-DD
---

# YYYY-MM-DD — Short title

## Handoff
State: where things stand now, what is live and what is stale
Check first: what to verify on return
Detail: which section of this note or which file holds the reasoning

## What Was Done
(numbered list of concrete actions)

## Decisions Made
(what was decided and why, including who steered it if not your own call)

## Problems Solved
(root cause + fix, for anything non-obvious)

## Commands Used
(anything worth copy-pasting next time)

## Opened and Closed
(only the items this session opened or closed, each a link: `opened: text [[open-items-<repo>]]`; nothing carried forward)
```

   Tags are lowercase and hyphenated; reuse a tag from the notes already loaded in this conversation or the vault's tag list before inventing one, and give a theme that ran across repos the same tag on each note it applies to. Add any `frontmatterExtras`, and use the fixed `tags` if one is set.
10. **Update your open-items file** after the note is written, so its `see [[note]]` links exist: write the whole file back with the changes from step 6, keeping only the 20 most recent `## Closed` lines (a count, whatever their age). Before writing, read it again and, if it has changed since step 6, stop and say so. Its frontmatter is `repo: <repo name>` and `tags: [open-items, <repo name>]`.
11. **Never write secrets** — passwords, tokens, API keys, passphrases, private keys, connection strings with embedded credentials — into a note or the open-items file, even if one appeared in the conversation. Say where the secret lives instead. Not configurable.
12. **Change-log byproduct** (only if `changeLog` is `compact` and the working repo has a `change-log.md` at its root): add one entry directly under the file's intro, newest first, with `## YYYY-MM-DD - Short title` then `**What changed:**`, `**Why:**`, `**Result:**`, `**Notes:** ... Full narrative: <vault-relative note path>.`, one to three sentences each. Don't commit it.
13. **Report:** one line per note written (path, items opened, items closed), then extra lines only for what needs my attention, at most 10 then "and N more": any unlogged-work finding from step 5, first, then any repo doc line and each possibly done item with its hashes; a conflicted open-items file; each other author's item that looks done (whose, which item, the evidence); each repo judged a glance; each stale item still open; each unanswered question with the default applied. Say whether `change-log.md` was edited. If `vaultSync` is `git`, remind me this is a **local file write only** — nobody else sees it until committed and pushed from the vault repo. Otherwise say the notes reach my other machines through that sync, with nothing for me to commit.
