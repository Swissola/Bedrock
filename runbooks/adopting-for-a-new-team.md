---
title: Adopting this template for your own team
tags: [runbook, onboarding, multi-team]
---

# Adopting this template for your own team

> **Scope:** you've used this repo as a template (or forked/cloned it) to set up this same Obsidian + MCP pattern for your own team. This checklist is what to change before treating it as ready for anyone else to use — not a one-time-only concern, since it's also exactly what someone spinning up a *second*, separate team vault from this same template needs to do.

## Why this is worth a checklist at all

Most of the value here isn't specific to whichever team originally wrote it up: the MCP setup steps, `tools/setup-mcp.ps1`/`tools/setup-mcp.sh`, the vault folder conventions, the reminder hooks (`tools/hook-templates/`), and the local commands/skills (`tools/command-templates/`, `tools/skill-templates/`) all apply to any team doing this, and none of them hardcode a team name — they derive it from the repo they're actually installed in. Using this as a template saves re-deriving all of that, and re-hitting the gotchas the [Known Gotchas](../docs/mcp-setup.md#known-gotchas) table already paid for.

**Deliberately kept small**: the checklist below is genuinely only the *content* and *identity* items that can't be auto-derived — the repo's own name/remote and its example content. Everything else — the setup scripts, the hooks, the local commands/skills — needs no editing at all after the rename.

## The catch — don't skip this

A naive copy carries the previous team's specifics over silently rather than erroring, which is exactly the failure shape this whole setup is otherwise hardened against. **Do this checklist before treating a new vault as ready for anyone else to use.**

## Checklist

- [ ] **Rename the repo** (e.g. `bedrock-<your-team>`) and re-point the git remote — don't just leave it as a clone of this template.
- [ ] **Reset `index.md`** — replace the placeholder title and Systems/Repos table with your own team's name and your own systems.
- [ ] **Clear out `daily-notes/`** — the example folder here (`daily-notes/example-person/`) is a placeholder, not template content to keep. Delete it once you have your own.
- [ ] **Clear out `repos/`** — remove any example `repos/<name>/index.md` docs that came with the template; your team builds up its own from scratch (see [`runbooks/using-the-vault.md`](using-the-vault.md)).
- [ ] **If you set up the optional [wiki-publishing appendix](../docs/publishing-to-a-wiki.md)**, update its config with your own space/site identifiers — don't leave a previous team's target in place, or a publish could overwrite the wrong page.
- [ ] **If you use a CI pipeline for anything repo-specific** (e.g. the optional wiki publish job), check any branch-name assumptions in it match this repo's actual default branch.
- [ ] **No change needed:** `tools/setup-mcp.ps1` / `tools/setup-mcp.sh` (auto-detect the vault path from their own location), the MCP setup steps and Known Gotchas table in `docs/mcp-setup.md`, `.gitignore` and `.gitattributes`, `tools/hook-templates/post-merge` (derives its repo name and doc target from its own git remote — correct automatically for any fork), `tools/hook-templates/session-start-vault-check`, `tools/hook-templates/session-start-vault-context`, and `tools/hook-templates/pre-push` (all already derive `VAULT_ROOT` from wherever they're installed, or take it as an explicit override), `tools/hook-templates/test-post-merge.sh` (builds its own throwaway git fixtures, doesn't touch this repo's real content), `tools/command-templates/` and `tools/skill-templates/` (none of these name any particular team).
- [ ] If you keep a local scratch file for in-progress setup notes (e.g. `TASK-HANDOVER.md`), it's already gitignored in this template — but if you're literally copying a working directory rather than doing a fresh `git clone`, delete it by hand too; it won't carry over via a proper clone/fork either way.

## A note on multiple teams sharing one vault vs. separate vaults per team

This template assumes **one vault per team** (or per closely-related group of teams), each its own repo. If you're tempted to add a second team's docs into *this same* vault instead of forking a new one, think it through first: cross-linking works cleanly within one repo, but two teams with different push policies, different reviewers, and different content-sensitivity needs sharing one git history and one `index.md` tends to get contentious fast. Forking per team keeps each team's governance independent, at the cost of not being able to cross-link between vaults with a plain `[[wikilink]]` (a plain URL link between the two repos' hosted views works fine instead, if both are hosted somewhere browsable).

## Related

- [`using-the-vault.md`](using-the-vault.md) — this template's own conventions, once you've adopted it
- [`../docs/mcp-setup.md`](../docs/mcp-setup.md)
