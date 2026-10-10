---
description: Write this session as a daily note in the vault
argument-hint: [optional short topic, otherwise inferred from the conversation]
---
<!-- bedrock-template: vault-log, version 3 -->

See `runbooks/using-the-vault.md` in the vault, section 2, for full details of the folder/filename convention and template this follows — this command just automates it. Per-vault differences (a different folder layout, extra frontmatter, a change-log byproduct) are optional and live in a `vault-config.md` note at the vault root; see `docs/vault-config.md`. With no `vault-config.md`, every setting below takes its default and this behaves exactly as it always has.

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Two different `obsidian` MCP servers are in use, with different tool names. Detect which one you actually have from the tools available to you (not from any config file, which you can't read until you know the tool names), then use that column of this table for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| write a note, replacing it | `vault_write` (whole file, frontmatter included in the text) | `write_note` (`mode: overwrite`, frontmatter passed separately) |
| append to an existing note | read it, then `vault_write` the full updated content. Do not use `vault_append` (its newline handling isn't documented) or `vault_patch` (unreliable on some plugin versions, see the Known Gotchas table in `docs/mcp-setup.md`) | `write_note` with `mode: append` |

If you have neither set of tools, stop and say so.

**Settings.** Do this first, on its own: read `vault-config.md` at the vault root and wait for the result before making any other vault call (do not batch it with other reads or listings — the settings decide which paths to touch). If it doesn't exist, or a key is missing from it, use the default. If it exists but part of it is malformed, use what you can read reliably, the default for everything else, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key, if present, overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `dailyNotesPath` | `daily-notes/{author}` | Folder for daily notes. `{author}` and `{repo}` are filled in from steps 1 and 3 |
| `filenamePattern` | `{date}-{topic}` | Note filename without `.md` |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. The `session-start-vault-context` hook reads the same setting, so they always agree on the name |
| `appendRule` | `same-day-any-topic` | `same-day-any-topic`: if any note from today exists in the folder, append to it. `exact-path`: only append if the exact path exists, otherwise create a new note |
| `tags` | *(you pick relevant tags)* | A fixed list, e.g. `[daily-note, {repo}]` |
| `frontmatterExtras` | *(none)* | Extra frontmatter fields to write. Supported: `machine`, `location` |
| `locationHomePrefix` | *(unset)* | IPv4 prefix of the "home" network, e.g. `192.168.1.`. If set and `location` is requested: `home-lan` when the default gateway starts with it, otherwise `off-lan`. If unset, or you can't determine the gateway, omit `location` and say so |
| `titleHeading` | `true` | Whether the body starts with a `# YYYY-MM-DD — Short title` heading |
| `bodySections` | *(the template in step 6)* | An ordered list of `##` section names to use instead |
| `changeLog` | `off` | `compact`: also add a change-log entry, see step 8 |
| `vaultSync` | `git` | How the vault reaches other machines, used only for the closing reminder: `git` or anything else (e.g. `syncthing`) |

## Steps

1. **Author** (only if `{author}` appears in `dailyNotesPath` or `filenamePattern`): run `git config user.name`, lowercase it, replace spaces with hyphens (e.g. "Jane Doe" → `jane-doe`). This is a git identity lookup, not tied to the vault repo — it works the same regardless of which repo this session is running in.
2. **Date:** today as `YYYY-MM-DD`.
3. **Repo** (only if `{repo}` is used, or `changeLog` is `compact`): the basename of `git rev-parse --show-toplevel`, lowercased unless `repoNameCase` is `keep`; the working directory's name if this isn't a git repo.
4. **Machine and location** (only if listed in `frontmatterExtras`): `machine` is the lowercased output of `hostname`. `location` per `locationHomePrefix` above.
5. **Topic:** use "$ARGUMENTS" if given, otherwise infer 2-4 hyphenated words from what this session actually did.
6. **Find or create the note.** List the resolved `dailyNotesPath` folder, then apply `appendRule`:
   - If a note qualifies for appending: read it, then append a new `## Update (later same session) — <short description>` section to the end rather than creating a new file or overwriting what's there (using the append operation from the table).
   - Otherwise create a new note at `<dailyNotesPath>/<filenamePattern>.md`, following this template exactly (adapt the content of each section to what actually happened, keep the structure and headings; use `bodySections` instead if set, and omit the `#` heading line if `titleHeading` is `false`):

```markdown
---
title: Short descriptive title
tags: [relevant, tags]
date: YYYY-MM-DD
---

# YYYY-MM-DD — Short title

## What Was Done
(numbered list of concrete actions)

## Decisions Made
(what was decided and — importantly — why, including who steered it if not your own call)

## Problems Solved
(root cause + fix, for anything non-obvious)

## Commands Used
(anything worth copy-pasting next time)

## Context for Future Sessions
(state as of now — what's live, what's stale, what to check first)

## Open Questions / Next Steps
- [ ] checklist of what's unresolved
```

   Add any `frontmatterExtras` to the frontmatter, and use the fixed `tags` if one is set.
7. **Never write secrets** — passwords, tokens, API keys, passphrases, private keys, connection strings with embedded credentials — into the note, even if one appeared in the conversation. Say where the secret lives instead. This is not configurable.
8. **Change-log byproduct** (only if `changeLog` is `compact`, and a `change-log.md` exists at the repo root from step 3). Add one entry directly under the file's intro, newest first, in exactly this shape:

```markdown
## YYYY-MM-DD - Short title

**What changed:** ...

**Why:** ...

**Result:** ...

**Notes:** ... Full narrative: `<vault-relative note path>`.
```

   One to three sentences per field. Don't commit it.
9. Tell me the exact vault path written, and whether `change-log.md` was edited. If `vaultSync` is `git`, remind me this is a **local file write only** — nobody else sees it until it's committed and pushed from the vault repo (`git status`, `git add`, `git commit`, `git push`). Otherwise say the note reaches my other machines through that sync (`vaultSync`), with nothing for me to commit.
