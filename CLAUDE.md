# Vault conventions

Claude Code loads this file when it runs in the vault. It is a short pointer. The full version is `runbooks/using-the-vault.md`.

## Layout

| Path | Contains |
|---|---|
| `index.md` | Hub note: a table of repos and systems, and a document index |
| `daily-notes/<author>/` | A log of work sessions, one subfolder per contributor |
| `repos/<name>/` | Reference docs for one system: how it works now, not what happened on a given day |
| `runbooks/` | Step-by-step procedures for recurring tasks |

Daily notes are history. `repos/` and `runbooks/` are the current state. If it will be needed next time without reading old sessions, it belongs in the latter, linked from the daily note that produced it.

## Daily notes

- Path: `daily-notes/<author>/YYYY-MM-DD-<repo>-<topic>.md`, one note per repo worked in, with `repo: <repo>` in the frontmatter and the repo as a tag.
- `<author>` is `git config user.name`, lowercased, spaces turned into hyphens. Always the full name, never a forename alone, or two people's notes can merge.
- Coming back to the same repo the same day: append a `## Update (later same session)` section to your existing note. Do not start a new one.
- Open items are `- [ ]` lines under `## Open Questions / Next Steps`, with `opened YYYY-MM-DD`. Done is `[x]`, dropped is `[-]`, carried forward is `[>]`.
- Link with `[[repos/x/y]]`. Daily notes link out to durable docs. Durable docs do not link back to daily notes.

## Rules

- Never write a real credential, tenant ID or personal detail into a note. Describe the shape of the config instead.
- Never edit under `## Hand-written notes` in a repo doc. It belongs to people.
- Do not write into dot-folders such as `.claude/` through the vault tools. The write reports success, but the file is then invisible to every other vault tool.
- With the Local REST API tools, read the whole note and write the whole note back. `vault_patch` has been unreliable.

Settings that change any of this are in `vault-config.md` if the vault has one. See `docs/vault-config.md`.
