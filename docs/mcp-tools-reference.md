# Obsidian MCP tool capability reference

> **Scope:** what the `obsidian` MCP server can actually do, once it's registered (see [`mcp-setup.md`](mcp-setup.md) if it isn't yet). This is a reference to consult as needed, not something to read top-to-bottom — you don't need to know the underlying tool names day to day; describe the outcome and your AI assistant will pick the right one. This exists so you know what's *possible* to ask for.

The `obsidian` MCP server (backed by the Local REST API community plugin) exposes 16 tools in total, covering more than the handful of examples in the [Vault Usage Guide](../runbooks/using-the-vault.md)'s "Basic operations" section:

## Reading & finding things

- Read a whole file, or just one heading, block, or frontmatter field out of it — cheaper than reading the whole thing, and how your assistant makes a targeted edit without re-reading everything first — *"read just the Known Gotchas section of the setup guide"*
- List what's in a folder — *"what's in `daily-notes/`?"*
- Full-text search across the vault, ranked by relevance — *"search for anything mentioning the deploy pipeline"*
- Structured search by tag, frontmatter field, or modified date — not just free text — *"find every daily note tagged `onboarding`"*
- List every tag used across the vault, with usage counts — *"what tags exist in this vault?"*
- Ask what file is currently open in Obsidian itself

## Writing & editing

- Overwrite a file completely, or create a new one — *"write today's session as a daily note"*
- Append to the end of a file without touching the rest — *"add an update to the bottom of today's daily note"*
- Make a surgical edit to one heading, block, or frontmatter field — insert before/after it, replace it, or delete it — without regenerating the whole document. This is what keeps "update this doc with X" from silently rewriting unrelated sections — *"add a row to the Known Gotchas table, don't touch anything else"*

> In practice, the surgical-edit tool is unreliable in at least one widely-used version of this plugin (it can silently wipe a document down to just its heading). See the Known Gotchas table in [`mcp-setup.md`](mcp-setup.md) and the convention note in [`obsidian-vault-conventions`](../tools/skill-templates/obsidian-vault-conventions/SKILL.md): read the full file, edit the content yourself, then write the full file back — even for small edits — until you've confirmed the surgical tool is trustworthy on your own vault and plugin version.

## Organizing

- Move or rename a file — Obsidian updates any internal links pointing at it automatically
- Copy a file to a new location
- Delete a file — goes to trash (system or in-app, per your Obsidian preference) by default, not gone for good — *"delete that draft, I don't need it"*

## Driving Obsidian itself

- Open a file in the Obsidian window, creating it first if it doesn't exist
- List and run any registered Obsidian command by ID — e.g. toggling formatting, or triggering another installed plugin's command

## Related

- [`mcp-setup.md`](mcp-setup.md) — MCP setup and day-to-day usage conventions
- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md)
