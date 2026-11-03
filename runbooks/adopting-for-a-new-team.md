---
title: Adopting this template for your own team
tags: [runbook, onboarding, multi-team]
---

# Adopting this template for your own team

> **Scope:** for whoever turns this template into a team's own vault, whether that is the first team to use it or someone setting up a *second*, separate vault from the same template. You've used this repo as a template (or forked or cloned it) to set up the Obsidian and MCP pattern for your own team. This checklist is what to change before anyone else relies on it. Do it before treating the new vault as ready.

## Why there is a checklist

Most of the value here isn't specific to whichever team first wrote it up. The MCP setup steps, `tools/setup-mcp.ps1` and `tools/setup-mcp.sh`, the vault folder conventions, the hooks (`tools/hook-templates/`) and the slash commands (`tools/command-templates/`) all apply to any team, and none of them hardcode a team name: they derive it from the repo they're installed in. Using this as a template saves re-deriving all that, and re-hitting the gotchas the [Known Gotchas](../docs/mcp-setup.md#known-gotchas) table already paid for.

The checklist below is deliberately small. It covers only the *content* and *identity* items that can't be derived automatically: the repo's own name and remote, and its example content. Everything else needs no editing after the rename.

**Don't skip it.** A naive copy carries the previous team's specifics over silently rather than erroring, which is the failure shape the rest of this setup is hardened against.

## Checklist

- [ ] **Rename the repo** (e.g. `bedrock-<your-team>`) and re-point the git remote - don't just leave it as a clone of this template.
- [ ] **Reset `index.md`** - replace the placeholder title and Systems/Repos table with your own team's name and your own systems.
- [ ] **Clear out `daily-notes/`** - the example folder here (`daily-notes/example-person/`) is a placeholder, not template content to keep. Delete it once you have your own.
- [ ] **Decide on the note naming.** The default is one daily note per repo, `daily-notes/<author>/YYYY-MM-DD-<repo>-<topic>.md`, with `repo:` frontmatter and open-item tracking (`staleOpenItemDays`, 30 by default). To change that, set `filenamePattern`, `appendRule` or `staleOpenItemDays` in [`vault-config.md`](../docs/vault-config.md). If your team has older notes in the previous naming, do nothing: the session-start hook shows the newest one until a repo has notes of its own, and `/vault-log` offers its open items for adoption once.
- [ ] **Read `CLAUDE.md` at the repo root.** It is the short set of conventions Claude Code loads when it runs in the vault (layout, daily-note rules, open-item markers, what never to write). Change anything that does not match how your team will work, and keep it short, because it is loaded into every session.
- [ ] **Clear out `repos/`** - remove any example repo docs (`repos/<name>/index.md`) that came with the template. Your team builds up its own from scratch (see [`using-the-vault.md`](using-the-vault.md#3-bootstrapping-a-repo-doc-reposname)).
- [ ] **If you set up the optional [wiki-publishing appendix](../docs/publishing-to-a-wiki.md)**, update its config with your own space/site identifiers - don't leave a previous team's target in place, or a publish could overwrite the wrong page.
- [ ] **If you use a CI pipeline for anything repo-specific** (e.g. the optional wiki publish job), check any branch-name assumptions in it match this repo's actual default branch.
- [ ] **If you keep a local scratch file** for in-progress setup notes (for example `TASK-HANDOVER.md`), it is already gitignored in this template and does not carry over through a clone or fork. If you copied a working directory instead of doing a fresh `git clone`, delete it by hand.

### What needs no change

Leave these alone. None names a particular team, or each derives what it needs from where it is installed:

- `tools/setup-mcp.ps1` and `tools/setup-mcp.sh`: they detect the vault path from their own location.
- The MCP setup steps and Known Gotchas table in `docs/mcp-setup.md`.
- `.gitignore` and `.gitattributes`.
- `tools/hook-templates/post-merge`: it derives its repo name and doc target from the folder it is installed in, so it is correct for any fork.
- `tools/hook-templates/session-start-vault-check`, `session-start-vault-context` and `pre-push`: none of them names a team. `session-start-vault-check` and `session-start-vault-context` need `VAULT_ROOT` passed in (the installer's wrapper reads it from `~/.claude/hook-configs/vault-root`), and `pre-push` falls back to the repo being pushed, so set `VAULT_ROOT` when you install it in a repo other than the vault.
- `tools/hook-templates/pre-commit`: a generic secret scan.
- `tools/hook-templates/test-post-merge.sh` and `test-pre-commit.sh`: they build their own throwaway git fixtures and never touch this repo's content.
- `tools/command-templates/`.

## One vault per team, or one shared vault

This template assumes **one vault per team** (or per closely related group of teams), each its own repo. If you're tempted to add a second team's docs to *this same* vault instead of forking a new one, think it through first. Cross-linking works cleanly within one repo, but two teams with different push policies, reviewers and content-sensitivity needs, sharing one git history and one `index.md`, tends to get contentious fast.

Forking per team keeps each team's governance independent. The cost is that you can't cross-link between vaults with a plain `[[wikilink]]`. A plain URL link between the two repos' hosted views works instead, if both are hosted somewhere browsable.

## Related

- [`using-the-vault.md`](using-the-vault.md): this template's own conventions, once you've adopted it
- [`../docs/mcp-setup.md`](../docs/mcp-setup.md): connecting Claude Code to the vault
