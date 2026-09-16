---
description: Write this session as a daily note in the vault
argument-hint: [optional short topic, otherwise inferred from the conversation]
---

See `runbooks/using-the-vault.md` in the vault, section 2, for full details of the folder/filename convention and template this follows — this command just automates it.

Using the `obsidian` MCP server (must be registered at user scope, and Obsidian must be open — if any `mcp__obsidian__*` call fails, say so plainly and point at `docs/mcp-setup.md` rather than guessing):

1. Determine the author folder: run `git config user.name`, lowercase it, and replace spaces with hyphens (e.g. "Jane Doe" → `jane-doe`). This is a git identity lookup, not something tied to the vault repo specifically — it works the same regardless of which repo this session is actually running in.
2. Determine today's date as `YYYY-MM-DD`.
3. Determine a short topic slug: use "$ARGUMENTS" if given, otherwise infer 2-4 hyphenated words from what this session actually did.
4. List `daily-notes/<author>/` and check two things:
   - Does a note for **today**, any topic, already exist for this author?
   - Does a note at the exact `<date>-<topic>.md` path already exist?
   - If a note for today already exists in either sense: read it, then append a new `## Update (later same session) — <short description>` section to the end rather than creating a new file or overwriting what's there.
   - Otherwise: create a new note.
5. For a **new** note, follow this template exactly (adapt the content of each section to what actually happened, keep the structure and headings):

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

6. Write it with `vault_write`. Prefer a full read-then-full-write over `vault_patch` for the append case unless you've confirmed the patch tool is reliable on this vault and plugin version (see the Known Gotchas table in `docs/mcp-setup.md`): read the existing file's full content first, then write the full updated content back.
7. Tell me the exact vault path written, and remind me this is a **local file write only** — nobody else sees it until it's committed and pushed from the vault repo (`git status`, `git add`, `git commit`, `git push`).
