---
name: obsidian-vault-conventions
description: Use whenever reading from or writing to this team's Obsidian vault via the `obsidian` MCP server (any `mcp__obsidian__*` tool call), or when asked about its folder structure, daily-note naming, or content conventions.
---

# Obsidian vault conventions

Quick-reference pointer, not the source of truth — the canonical version lives in `runbooks/using-the-vault.md` in this vault repo.

## Folder structure

| Folder | Contains |
|---|---|
| `index.md` | Hand-maintained hub: tables of repos/systems, plus a full document index |
| `daily-notes/<author>/` | One file per work session, one subfolder per contributor — a log of what happened, not a polished doc |
| `repos/<name>/` | Durable reference docs about a specific system/repo — how it works, not what happened on a given day |
| `runbooks/` | Step-by-step procedures for recurring tasks |

**daily-notes are a session log; `repos/` and `runbooks/` are the current-state reference.** Anything worth knowing next time without reading old sessions belongs in `repos/` or `runbooks/`, cross-linked from the daily note that produced it — not left buried in the daily note itself.

## Daily-note naming

`daily-notes/<author-full-name-hyphenated>/YYYY-MM-DD-<short-topic>.md` — always the full name (`jane-doe`), never just a forename, since a forename-only folder can silently merge two people's notes together. The author slug comes from `git config user.name`, lowercased, spaces turned to hyphens.

If picking a session back up later the same day, append a `## Update (later same session) — ...` section to the existing file rather than starting a new one.

## Cross-linking

Use `[[repos/x/y]]`-style wikilinks liberally. Durable docs (`repos/`, `runbooks/`) link to each other both ways when related; daily-notes link *out* to durable docs they touched, but durable docs don't usually link back to individual daily-notes.

## Known gotchas (vault-specific, not MCP setup)

- **Confirm before relying on `vault_patch`** — surgical section/heading edits have been unreliable on at least one widely-used version of this plugin. Until you've confirmed it's trustworthy on your own vault, read the full current content first, then write the full updated content back, even for a small edit.
- **Dot-prefixed folders are invisible to vault tools** — writing into e.g. `.claude/` inside the vault reports success via `vault_write`, but the file is then unlisted, unreadable, and undeletable by every other `mcp__obsidian__*` tool afterward. Use a plain folder name instead.
- **Redact real credentials, tenant IDs, and personal data** — describe config *shape*, not real values, even though this is an internal knowledge base.

For the full daily-note template, the `repos/` bootstrap workflow, and everything else — read `runbooks/using-the-vault.md` and `docs/mcp-setup.md` in this vault repo directly.
