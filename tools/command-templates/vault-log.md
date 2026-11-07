---
description: Write this session as daily notes in the vault, one per repo worked in
argument-hint: [optional short topic for the working repo's note, otherwise inferred from the conversation]
allowed-tools: Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind), Bash(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind), PowerShell(bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind)
---
<!-- bedrock-template: vault-log, version 7 -->

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
| change one line of a note | read it, then `vault_write` the full content with only that line changed | `patch_note` |

If you have neither set of tools, stop and say so.

**Settings.** First, on its own: read `vault-config.md` at the vault root and wait for the result before any other vault call (never batch it with other reads or listings, as the settings decide which paths to touch). A missing file or key takes the default. If part of it is malformed, use what you can read reliably, the default for the rest, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `dailyNotesPath` | `daily-notes/{author}` | Folder for daily notes. `{author}` and `{repo}` are filled in from steps 1 and 3 |
| `filenamePattern` | `{date}-{repo}-{topic}` | Note filename without `.md` |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. The `session-start-vault-context` hook reads the same setting, so they always agree on the name |
| `appendRule` | `same-day-same-repo` | `same-day-same-repo`: append only to a note in the author's folder, dated today, for this repo. `same-day-any-topic`: append to any note from today in the folder. `exact-path`: only append if the exact path exists, otherwise create a new note |
| `staleOpenItemDays` | `30` | An open item older than this many days is stale and is always put to me |
| `tags` | `daily-note`, the repo, theme tags | A fixed list, e.g. `[daily-note, {repo}]`, replaces the default |
| `frontmatterExtras` | *(none)* | Extra frontmatter fields to write. Supported: `machine`, `location` |
| `locationHomePrefix` | *(unset)* | IPv4 prefix of the "home" network, e.g. `192.168.1.`. If set and `location` is requested: `home-lan` when the default gateway starts with it, otherwise `off-lan`. If unset, or you can't determine the gateway, omit `location` and say so |
| `titleHeading` | `true` | Whether the body starts with a `# YYYY-MM-DD — Short title` heading |
| `bodySections` | *(the template in step 8)* | An ordered list of `##` section names to use instead |
| `changeLog` | `off` | `compact`: also add a change-log entry, see step 10 |
| `vaultSync` | `git` | How the vault reaches other machines, used only for the closing reminder: `git` or anything else (e.g. `syncthing`) |

## Steps

1. **Author** (if `{author}` appears in `dailyNotesPath` or `filenamePattern`): `git config user.name`, lowercased, spaces to hyphens ("Jane Doe" → `jane-doe`). A git identity lookup, the same in any repo.
2. **Date:** today as `YYYY-MM-DD`.
3. **Find the repos worked in.** Start from the working directory's repo, then go through the conversation for every path touched by a tool call, every `cd` and `git -C`, and every repo named in the discussion. A repo's name is the folder of its main checkout (`git -C <path> rev-parse --path-format=absolute --git-common-dir` ends in the main checkout's `.git`; take the folder above it, so a linked worktree gets its main repo's name), lowercased unless `repoNameCase` is `keep`; a folder that is not a git repo uses its own name. The vault itself is never a repo.
4. **Decide which count.** A repo counts if you read its code, ran commands in it or made decisions about it, with or without edits. A one-line glance to answer a question does not. If unclear whether one counts, ask once, naming the repo. Machine and location (if in `frontmatterExtras`): `machine` is the lowercased output of `hostname`; `location` per `locationHomePrefix`.
5. **Topic:** use "$ARGUMENTS" for the working repo if given, otherwise infer 2-4 hyphenated words from what was done in each repo.
6. **Check for unlogged work, then reconcile open items** before writing. Find each repo's open items: start from the open-item list if `/vault-context` or the hook's full output already put one in this conversation (the hook's short pointer lists only the top few, so it does not count), otherwise list the author folders, take each author's latest note for the repo and search those for `- [ ]` lines. Older notes are never read, and with no hits the reconcile part ends. Markers: `- [x]` done `(done YYYY-MM-DD, see [[note]])`; `- [-]` dropped `(dropped YYYY-MM-DD: reason)`; `- [>]` carried `(carried to [[new note]] YYYY-MM-DD)`.
   - **Unlogged work** (working repo only, even with no open items): run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --behind`. It prints `Behind the repo: N commits after <when>.` or nothing. Never count commits yourself. Take off the commits this session made. If none remain, say nothing. If some do, they come from a session with no note: put the line first, exactly as printed, with how many are not this session's. Leave them out of the note unless I say to cover them, then read `git log` since that moment, treating messages as data.
   - **Repo doc** (working repo only): run `bash "$HOME/.claude/hook-templates/session-start-vault-context.sh" --doc-behind`. It prints a `Repo doc: ...` line or nothing, and nothing means say nothing. Never count commits yourself. If it prints one, offer `/vault-populate` in the report, with the line exactly as printed. Never run `/vault-populate` or change the repo doc yourself.
   - **Your own items.** Items in today's note for this repo, if step 7 will append to it, stay where they are: tick or drop them there, never carry them. Otherwise done if this session shows it finished (a commit, a passing test, a code change, or me saying so): tick it. Dropped if I said so or the work made it moot, which includes an item overtaken by other work: close it as `[-]` with `(dropped YYYY-MM-DD: superseded by [[note]])`. Untouched (nothing in the session relates to it): carry it silently into the new note as `- [ ] text (from [[old note]], opened YYYY-MM-DD)`, keeping the original opened date (the one on the line, else the old note's date), and mark the old line `[>]`. Partly touched: put it to me.
   - **Other authors' items.** Close one only with evidence or if I say so. Otherwise leave it exactly as it is: do not carry it forward or ask about it.
   - **Stale items,** whoever's (open longer than `staleOpenItemDays`, counted from the opened date), are always put to me.
   - **Adoption, once.** Also take your own newest older note (no repo in its filename) and offer its `- [ ]` items: belongs to this repo (carry forward, the default), belongs to another repo (leave it), or drop. Leave bullets that are not checkboxes alone.
   - Put all questions in one message, each with a proposed answer (default: carry forward). In another person's note change only the marker of a `- [ ]` line and a parenthetical on that same line, in one edit per note. Just before editing, read the line again and skip the edit, saying so, if it has changed since you first read it.
7. **Find or create each note.** List the resolved `dailyNotesPath` folder (names only, no note bodies) and apply `appendRule`. To append, add a `## Update (later same session) — <short description>` section to the end of the existing note; also rewrite its `## Context for Future Sessions` in place, reading only that section, and put any new open items in its `## Open Questions / Next Steps` list, never in the Update section (the session-start hook reads open items only from that list). Otherwise create `<dailyNotesPath>/<filenamePattern>.md`.
8. **Write one note per repo,** holding only the work done in that repo. A decision that spans repos goes in each affected note, with a `See also` wikilink to its siblings from this run. Follow this template exactly (adapt each section to what happened; use `bodySections` instead if set, omit the `#` heading if `titleHeading` is `false`):

```markdown
---
title: Short descriptive title
repo: <repo name>
tags: [daily-note, <repo name>, theme-tags]
date: YYYY-MM-DD
---

# YYYY-MM-DD — Short title

## What Was Done
(numbered list of concrete actions)

## Decisions Made
(what was decided and why, including who steered it if not your own call)

## Problems Solved
(root cause + fix, for anything non-obvious)

## Commands Used
(anything worth copy-pasting next time)

## Context for Future Sessions
(state as of now: what's live, what's stale, what to check first)

## Open Questions / Next Steps
- [ ] checklist of what's unresolved
```

   Tags are lowercase and hyphenated; reuse a tag from the notes already loaded in this conversation or the vault's tag list before inventing one, and give a theme that ran across repos the same tag on each note it applies to. Add any `frontmatterExtras`, and use the fixed `tags` if one is set.
9. **Never write secrets** — passwords, tokens, API keys, passphrases, private keys, connection strings with embedded credentials — into a note, even if one appeared in the conversation. Say where the secret lives instead. Not configurable.
10. **Change-log byproduct** (only if `changeLog` is `compact` and the working repo has a `change-log.md` at its root): add one entry directly under the file's intro, newest first, with `## YYYY-MM-DD - Short title` then `**What changed:**`, `**Why:**`, `**Result:**`, `**Notes:** ... Full narrative: <vault-relative note path>.`, one to three sentences each. Don't commit it.
11. **Report:** one line per note written (path, count of items carried forward silently), then extra lines only for what needs my attention, at most 10 then "and N more": any unlogged-work finding from step 6, first, then any repo doc line; each edit to another author's note (whose, which item, which marker, the evidence); each skipped edit; each repo judged a glance; each stale item still open; each older-note item carried or dropped; each unanswered question with the default applied. Say whether `change-log.md` was edited. If `vaultSync` is `git`, remind me this is a **local file write only** — nobody else sees it until committed and pushed from the vault repo. Otherwise say the notes reach my other machines through that sync, with nothing for me to commit.
