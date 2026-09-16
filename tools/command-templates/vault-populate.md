---
description: Summarise the current repo and write a repos/<name>/ reference doc into the vault
argument-hint: [optional repo name override, otherwise inferred from this folder]
---

See `runbooks/using-the-vault.md` in the vault, section 3, for the full manual version of this workflow and its rationale — this command just automates it.

Using the `obsidian` MCP server (must be registered at user scope, and Obsidian must be open — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

1. Confirm the current working directory is a real git repo and is **not** the vault itself (check whether `index.md` and a `daily-notes/` folder exist right here, in this same working directory, as the tell). If it is the vault, stop and say this command is for documenting *other* repos from inside their own folder, not the vault itself.
2. Determine the repo name: "$ARGUMENTS" if given, otherwise the repo's folder name (or its `git remote` name if that's clearer).
3. Read `repos/<name>/index.md` in the vault first, if it already exists. This run should refresh or extend an existing doc, not blindly overwrite tribal knowledge someone already recorded there. Prefer a full read-then-full-write over `vault_patch` unless you've confirmed the patch tool is reliable on this vault and plugin version — always read the full current content first, then write the full updated content back.
4. Summarise this repo for a new-starter reference doc: what it does, how it's structured, how it's run/deployed, and anything that would trip up someone new to it. Base this on the actual code in front of you, not assumptions — and if an existing doc already covers tribal knowledge a code-only read can't reconstruct, preserve it rather than dropping it. If another `repos/<other-name>/index.md` already exists in the vault, follow its structure as a model for consistency; otherwise use your own best judgement for a clear reference doc.
5. Write (or update) `repos/<name>/index.md` in the vault.
6. Read `index.md` (the vault hub) and add a row for this repo to its Systems/Repos table if one doesn't already exist, linking to `[[repos/<name>/index]]` — an undiscoverable doc barely beats no doc at all.
7. Tell me plainly: **this is a first-pass, machine-generated draft**. I should read it myself and correct anything wrong or missing before trusting it, especially anything that needed real tribal knowledge to get right (per `runbooks/using-the-vault.md`, step 5 of the repos-bootstrap workflow).
