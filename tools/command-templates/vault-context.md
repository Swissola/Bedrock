---
description: Catch up on the vault — read the hub note and recent daily notes
argument-hint: [optional topic or person to focus on]
---

See `runbooks/using-the-vault.md` in the vault, section 1, for the manual version of this workflow and its rationale — this command just automates it.

Using the `obsidian` MCP server (must be registered at user scope, and Obsidian must be open — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

1. Read `index.md` for the current state of the vault hub.
2. Find the most recent daily note(s):
   - If an argument was given ("$ARGUMENTS"), search the vault for daily notes mentioning that topic or person and prioritise those, most recent first.
   - Otherwise, list `daily-notes/<author>/` across every contributor subfolder and pick the single most recent file by its `YYYY-MM-DD` filename prefix, regardless of who wrote it.
3. Read the note(s) found.
4. Summarise for me: what was done, what's still open (the `Open Questions / Next Steps` checklist), and anything I should know before continuing. Keep it tight — a few sentences per note, not a full re-print of the file.
