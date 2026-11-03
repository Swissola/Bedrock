# Obsidian MCP tool capability reference

> **Scope:** for anyone who wants to know what is possible to ask for once the `obsidian` MCP server is registered (if it isn't yet, see [`mcp-setup.md`](mcp-setup.md)). It is a reference to consult as needed, not something to read top to bottom. You don't need to know the underlying tool names. Describe the outcome and your AI assistant picks the right tool.

The `obsidian` MCP server is the connection that lets Claude Code read and write the vault. Backed by the Local REST API community plugin, it has a built-in MCP server (at `/mcp/` on the plugin's port) that lists 20 tools in its README, 17 of them by default and the three signed-URL ones only when that setting is on. Extensions can add more. They cover more than the handful of examples in the "Basic operations" section of [`using-the-vault.md`](../runbooks/using-the-vault.md#basic-operations). The vault can instead be served by MCPVault, which has different tool names (see [Backends](vault-config.md#backends)).

## Reading & finding things

- Read a whole file (or a binary one such as an image), or just one heading, block, or frontmatter field out of it. This is cheaper than reading the whole thing, and is how your assistant makes a targeted edit without re-reading everything first - *"read just the Known Gotchas section of the setup guide"*
- List what's in a folder - *"what's in `daily-notes/`?"*
- Full-text search across the vault, ranked by relevance - *"search for anything mentioning the deploy pipeline"*
- Structured search by tag, frontmatter field, or modified date, not just free text - *"find every daily note tagged `onboarding`"*
- List every tag used across the vault, with usage counts - *"what tags exist in this vault?"*
- Ask what file is currently open in Obsidian itself

## Writing & editing

- Overwrite a file completely, or create a new one - *"write today's session as a daily note"*
- Append to the end of a file without touching the rest - *"add an update to the bottom of today's daily note"*
- Make a surgical edit to one heading, block, or frontmatter field - insert before/after it, replace it, or delete it - without regenerating the whole document. This is what keeps "update this doc with X" from silently rewriting unrelated sections - *"add a row to the Known Gotchas table, don't touch anything else"*

> **Caution:** the surgical-edit tool is unreliable in at least one widely used version of this plugin. It can silently wipe a document down to just its heading. The rule in the vault's [`CLAUDE.md`](../CLAUDE.md) is to read the full note and write the full note back, even for small edits, until you have confirmed the surgical tool is trustworthy on your own vault and plugin version.

## Organizing

- Move or rename a file - Obsidian updates any internal links pointing at it automatically
- Copy a file to a new location
- Delete a file. It goes to the trash (system or in-app, per your Obsidian preference) by default, so it is not gone for good - *"delete that draft, I don't need it"*

## Driving Obsidian itself

- Open a file in the Obsidian window, creating it first if it doesn't exist
- List and run any registered Obsidian command by ID - e.g. toggling formatting, or triggering another installed plugin's command

## Related

- [`mcp-setup.md`](mcp-setup.md) - connecting Claude Code to the vault
- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md)
