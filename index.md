# <Your Team> Vault

Shared Obsidian vault for <your team>, git-backed via this repo. This is the hub note: the front page that points to every system and document in the vault. New here? Start with [[docs/mcp-setup]] to connect your AI assistant to the vault, then [[runbooks/using-the-vault]] for what to do with it.

> Replace the title above and everything in this file with your own team's content. This is the one file every vault needs to have from day one. See [[runbooks/adopting-for-a-new-team]] for the full reset checklist.

## Systems / Repos

| Repo | What it is | Docs |
|---|---|---|
| `widget-service` | *(example)* a placeholder entry - replace with your team's actual systems | [[repos/widget-service/index]] |

Add a row (and a repo doc at `[[repos/<name>/index]]`, the reference page for that codebase) here for each system you start documenting in this vault. An undiscoverable doc barely beats no doc at all, and this table is how people find it.

## Guides

Setting up:

- [[docs/mcp-setup]]: connect your AI assistant to the vault, once per machine
- [[runbooks/adopting-for-a-new-team]]: checklist for turning this template into your own team's vault

Using it:

- [[runbooks/using-the-vault]]: session-start catch-up, writing daily notes, and bootstrapping repo docs
- [[runbooks/daily-workflow]]: a return-to checklist for day-to-day vault use
- [[runbooks/git-recovery]]: undoing mistakes: bad commits, committed secrets, deleted notes, lost work
- [[docs/mcp-tools-reference]]: full reference of what the vault connection can do

Optional extras and reference:

- [[docs/automation]]: slash commands and git and session hooks
- [[docs/vault-config]]: per-vault settings, for a vault laid out differently from the defaults
- [[docs/statusline]]: a Claude Code status line
- [[docs/testing]]: how the tools are tested
- [[docs/publishing-to-a-wiki]]: mirroring selected docs to another wiki

## Daily Notes

Daily notes are session logs. They live in `daily-notes/<author>/`, one subfolder per team member. Start here for the most recent context:

- *(link the most recent daily note here once you have one)*

## Full Document Index

Keep this section current as you add docs. It's the one place a new team member (or a future session) can see everything that exists without guessing folder names.

- `docs/mcp-setup.md`
- `docs/mcp-tools-reference.md`
- `docs/automation.md`
- `docs/vault-config.md`
- `docs/statusline.md`
- `docs/testing.md`
- `docs/publishing-to-a-wiki.md`
- `runbooks/using-the-vault.md`
- `runbooks/daily-workflow.md`
- `runbooks/git-recovery.md`
- `runbooks/adopting-for-a-new-team.md`
