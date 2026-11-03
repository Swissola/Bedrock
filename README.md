# Bedrock

**A shared, git-backed context brain for your team, built on Obsidian and Claude Code.**

Bedrock is a pattern, not a product: a plain [Obsidian](https://obsidian.md) vault, kept in git, that an AI coding assistant can read and write directly while your team works. This guide is written for [Claude Code](https://claude.com/claude-code), but the idea generalises. Context that would normally evaporate at the end of a chat (how a system works, what was decided and why, what is still open) persists and builds up instead.

This repo *is* the vault. Fork it, rename it, push it to whichever git host you already use (GitHub, GitLab, Bitbucket, self-hosted; nothing here is host-specific), and you have a working Bedrock vault for your team on day one. Nothing in it is specific to any company, team or codebase. Every example uses a placeholder team name, a placeholder repo (`widget-service`) and a placeholder person (`jane-doe`). Swap those for your own as you go; see [Adopting this for your team](runbooks/adopting-for-a-new-team.md).

**Who this is for:** an engineer or tester who wants an AI assistant to keep a team's working knowledge in git, without a separate documentation chore. You need a git host, Node.js, Claude Code and Obsidian. You do not need to write any code.

## Terms

These words are used in the same sense on every page.

| Term | Meaning |
|---|---|
| **Vault** | This repo: a folder of Markdown notes that Obsidian opens and git tracks. Each person has their own clone. |
| **Hub note** | `index.md`, the vault's front page: a table of the systems you document, and an index of documents. |
| **Daily note** | A log of one work session in one repo, written by the assistant when you ask. It lives in `daily-notes/<author>/` and is history, not reference. |
| **Repo doc** | The vault's reference page for one codebase, `repos/<name>/index.md`: how that system works now. Not a log. |
| **Runbook** | A step-by-step procedure for a recurring task, in `runbooks/`. |
| **Open item** | A `- [ ]` line under `## Open Questions / Next Steps` in a daily note, with the date it was opened. `/vault-log` closes, drops or carries each one forward. |
| **Stale** | An open item older than `staleOpenItemDays` (30 by default). It is always put to you and always listed first. |
| **MCP server** | The connection that lets Claude Code read and write the vault. Here it is named `obsidian`. |
| **MCP backend** | What provides that `obsidian` server: the Obsidian Local REST API plugin (needs Obsidian open) or MCPVault (reads the files directly). See [Backends](docs/vault-config.md#backends). |
| **Slash command** | A named prompt in Claude Code: `/vault-context`, `/vault-log`, `/vault-populate`. |
| **Git hook** | A script git runs on a git event (`pre-commit`, `post-merge`, `pre-push`). |
| **Session hook** | A script Claude Code runs when a session starts (`session-start-vault-check`, `session-start-vault-context`). |
| **Pointer mode** | The default for `session-start-vault-context`: it tells a new session where the notes are, instead of loading them. `CONTEXT_MODE=full` loads the contents. |

## Why this, and not just a wiki

A normal wiki is something people remember to update. This is different in two ways:

1. **Your assistant writes to it as a side effect of the work you are already doing**, not as a separate documentation chore. "Write today's session as a daily note" or "update this doc with what we just decided" costs one sentence, at the moment the context is freshest.
2. **It is git, not a database.** Every change is a commit by a named author, with a diff you can review, revert or blame. There is no separate access-control system to run and no vendor lock-in, and anyone with a git client and a text editor can read every word without Obsidian installed.

It is worth being plain about what it is not. It is not real-time multi-user editing (two people changing the same file at the same moment is a merge, not a shared cursor), and it does not replace your documentation platform if you have one with tighter governance needs. It is a quick, low-ceremony layer that is good at capturing the context that normally lives in one person's head or one long chat thread.

## What's in this repo

| Path | What it is | Written by |
|---|---|---|
| `index.md` | The hub note, hand-maintained | You, occasionally |
| `daily-notes/<person>/` | Daily notes, one per repo worked in, one subfolder per contributor | Your assistant, when you ask |
| `repos/<name>/` | Repo docs: how one system works now, not what happened on a given day | Your assistant, revised over many sessions |
| `runbooks/` | Step-by-step procedures for recurring tasks | You or your assistant, once a procedure is proven |
| `docs/` | Setup and reference material: connecting the assistant, what it can do, the automation, the tests | You |
| `tools/` | Setup scripts, optional git and session hooks, optional slash commands | You, once per machine |
| `CLAUDE.md` | The vault's conventions in a page, which Claude Code loads when it runs here | You |

**`daily-notes/` is a session log. `repos/` and `runbooks/` are the current-state reference.** Anything worth knowing next time without reading old sessions belongs in the latter, linked from the daily note that produced it.

Open work is tracked in the daily notes themselves. When you log a session, the assistant closes, drops or carries forward each open item, and puts any stale one to you.

## Quick start

Each step says what it gives you. Do them in order; steps 1 to 5 are the minimum.

1. **Create your vault repo.** Use this repo as a template (or fork or clone it) on your git host, named for your team or project, for example `bedrock-<your-team>`.
2. **Clone it, then install Obsidian and open the clone as a vault**, in that order, choosing "Open folder as vault". [Step 0 of the setup guide](docs/mcp-setup.md#step-0-clone-first-then-install-and-open-obsidian) explains why the order matters. You are done when the vault's notes show in Obsidian's file list.
3. **Connect Claude Code to the vault.** Install the Local REST API plugin in Obsidian, then run `tools/setup-mcp.sh` (macOS and Linux) or `tools/setup-mcp.ps1` (Windows) from the clone, or follow the manual steps in [`docs/mcp-setup.md`](docs/mcp-setup.md). You are done when a new Claude Code session can read `index.md` when you ask it to.
4. **Reset the placeholders** for your own team, using the checklist in [`runbooks/adopting-for-a-new-team.md`](runbooks/adopting-for-a-new-team.md).
5. **Start using it.** [`runbooks/using-the-vault.md`](runbooks/using-the-vault.md) covers the three things you will do constantly: catch up at session start, log a session, and bootstrap a repo doc for a new codebase. [`runbooks/daily-workflow.md`](runbooks/daily-workflow.md) is the checklist to come back to once that is routine.
6. **Optional: automation.** Once the manual workflow feels natural, [`docs/automation.md`](docs/automation.md) covers the slash commands and the git and session hooks that remove most of the remembering. None of it is required.

## The automation, and how it is tested

The optional automation has two layers: three slash commands, and six hook files. [`docs/automation.md`](docs/automation.md) has a table of what runs when.

Two of the hooks touch security-relevant ground:

- `post-merge` runs an AI assistant unattended against your vault. It runs with a restricted tool set, treats every filename as untrusted data, and flags any write outside its one doc instead of acting on it.
- `pre-commit` scans staged changes for secrets and decides whether to warn or block.

Every hook, the installer and the setup scripts have their own isolated test suite, and `bash tools/testing/run-all-tests.sh` runs the lot. The same suites run in GitHub Actions on every pull request (Linux, macOS and Windows, though the Windows job skips the two slowest, `post-merge` and `session-start-vault-context`), and a separate manual workflow runs mutation checks that prove the suites can fail. [`docs/testing.md`](docs/testing.md) says what each one checks.

## Guides

Setting up:

- [`docs/mcp-setup.md`](docs/mcp-setup.md): connect Claude Code to the vault (once per machine)
- [`runbooks/adopting-for-a-new-team.md`](runbooks/adopting-for-a-new-team.md): the checklist for turning this template into your team's vault

Using it:

- [`runbooks/using-the-vault.md`](runbooks/using-the-vault.md): the three recurring workflows, as plain-English prompts
- [`runbooks/daily-workflow.md`](runbooks/daily-workflow.md): a checklist to come back to, with worked examples including how merge conflicts happen and get resolved
- [`runbooks/git-recovery.md`](runbooks/git-recovery.md): undoing mistakes, from a committed secret to lost work
- [`docs/mcp-tools-reference.md`](docs/mcp-tools-reference.md): everything the vault connection can do

Optional extras and reference:

- [`docs/automation.md`](docs/automation.md): the slash commands and the git and session hooks
- [`docs/vault-config.md`](docs/vault-config.md): per-vault settings, for a vault laid out differently from the defaults
- [`docs/statusline.md`](docs/statusline.md): a cross-platform Claude Code status line (model, branch, context and usage bars)
- [`docs/testing.md`](docs/testing.md): how to run the test suites, what each checks, the manual mutation checks, and what is deliberately not covered
- [`docs/publishing-to-a-wiki.md`](docs/publishing-to-a-wiki.md): mirror selected docs out to Confluence, Notion, SharePoint or whatever your organisation already uses

## Push policy: direct to `main`, no required PR

This is a deliberate choice that the pattern depends on, so it is worth reading even if you end up disagreeing with it. The ["Push policy" section of `runbooks/using-the-vault.md`](runbooks/using-the-vault.md#push-policy-direct-to-main-no-required-pr) gives the full reasoning: why an imperfect doc landing costs little, what review happens instead of a PR gate, and why a required-PR rule on `main` will break the automation in `tools/hook-templates/` if you turn one on without adjusting for it.

## Credits

This pattern is not original. It grew out of a lunch-and-learn given by [Jonathan Vaughan](https://github.com/JonathanVaughan), whose own reference vault was the first working demonstration that a git-backed Obsidian vault and an AI coding assistant could hold a team's context like this. The folder conventions, the daily-note discipline, the hooks and the whole shape of it build on that idea. Full credit to him for the foundation; any rough edges in the generalised version here are ours.

## Licence

Add whichever licence you would like this template distributed under (for example MIT). Nothing in here is meant to be anything other than copied, adapted and given away.
