---
description: Summarise the current repo and write a reference doc for it into the vault
argument-hint: [optional repo name override, otherwise inferred from this folder]
---
<!-- bedrock-template: vault-populate, version 4 -->

See `runbooks/using-the-vault.md` in the vault, section 3, for the manual version of this workflow; this command automates it. Optional per-vault settings live in `vault-config.md` at the vault root (`docs/vault-config.md`); with none, every setting takes its default (writing `repos/<name>/index.md`).

Using the `obsidian` MCP server (must be registered at user scope — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

## Step 0 — Backend and settings

**Backend.** Detect which `obsidian` MCP server you have from the tools actually available to you (their tool names differ), and use that column for every step below:

| Operation | `rest-api` (Local REST API plugin) | `mcpvault` |
|---|---|---|
| list a folder | `vault_list` | `list_directory` |
| read a note | `vault_read` | `read_note` |
| write a note, replacing it | `vault_write` (whole file) | `write_note` (`mode: overwrite`) |

Always read the full current content, then write the full updated content back, for either backend (the surgical `vault_patch` tool is unreliable on some plugin versions, see the Known Gotchas table in `docs/mcp-setup.md`). If you have neither set of tools, stop and say so.

**Settings.** First, on its own: read `vault-config.md` at the vault root and wait for the result before any other vault call (never batch it with other reads or listings, as the settings decide which paths to touch). A missing file or key takes the default. If part of it is malformed, use what you can read reliably, the default for the rest, and tell me plainly which part was unreadable. Unknown keys are ignored. A `backend` key overrides the detection above.

| Setting | Default | Meaning |
|---|---|---|
| `reposPath` | `repos/{repo}/index.md` | Where this repo's doc is written. `{repo}` is the name from step 2 |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named. |
| `hubNote` | `index.md` | The vault's hub note. `none` means there isn't one, skip step 6 |

## Steps

1. Confirm the current working directory is a real git repo and is **not** the vault itself (check whether `vault-config.md`, or the `hubNote` together with the daily notes folder from `dailyNotesPath`, exist right here in this same working directory: with the defaults that is `index.md` and a `daily-notes/` folder). If it is the vault, stop and say this command is for documenting *other* repos from inside their own folder.
2. Determine the repo name: "$ARGUMENTS" if given, otherwise the name of the main checkout's folder: `git rev-parse --path-format=absolute --git-common-dir` ends in the main checkout's `.git`, so take the folder above it (a linked worktree therefore gets its main repo's name, the same name the `session-start-vault-context` hook uses; never the `git remote` name), lowercased unless `repoNameCase` is `keep`.
3. Read the doc at `reposPath` in the vault, if it exists, and keep what you read. Note its frontmatter `source-commit` and its `## Hand-written notes` section.
4. Decide how much of the repo to read. Get the current commit with `git rev-parse HEAD`. If the doc has a `source-commit`: when it is the same commit (compare by prefix), say the doc is **up to date** and stop, with no survey and no write; when `git cat-file -e <source-commit>^{commit}` succeeds, read only the files listed by `git diff --name-only <source-commit>..HEAD` and update only the parts of the doc they affect; when it is not in this repo's history, survey the whole repo. With no `source-commit` (a first run or an older doc), or if I ask for a full survey, survey the whole repo.
5. Write the doc (the full file) at `reposPath`: what the repo does, how it is structured, how it is run or deployed, and anything that would trip up someone new. Base it on the code in front of you, not assumptions. If a sibling repo doc exists at `reposPath`, follow its structure. The frontmatter holds `repo` (the name from step 2), `last-populated` (today, `YYYY-MM-DD`), `source-commit` (the short SHA of `HEAD`) and `tags: [repo-doc, <repo name>]` (keep any other tags already there). End the doc with a `## Hand-written notes` section. A refresh never changes that section: keep it exactly as you read it. If the existing doc has no such section (a doc from before this rule), move whatever in it the code cannot show, such as decisions, history and tribal knowledge, into a new one rather than dropping it; create the empty heading only if there is nothing to keep. Everything else may be regenerated, though keep what is still true.
6. Just before writing, read the doc again. If it differs from what you read in step 3, stop, write nothing, and tell me it changed since you started so we do not overwrite someone else's edit; I can run the command again. Never write secrets (passwords, tokens, API keys, passphrases, private keys, connection strings with credentials) into the doc, even if one is in the repo; say where it lives instead.
7. If `hubNote` isn't `none`: read it and add a row for this repo to its Systems/Repos table if one doesn't already exist, linking to the doc.
8. Tell me what you did. A first run is a **first-pass, machine-generated draft**: I should read it and correct anything wrong or missing before trusting it, especially anything that needed real tribal knowledge (see `runbooks/using-the-vault.md`). On a refresh, say which files you re-read and what changed.
