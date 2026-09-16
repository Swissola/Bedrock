# Bedrock

**A shared, git-backed context brain for your team, built on Obsidian and Claude Code.**

A pattern — not a product — for turning a plain [Obsidian](https://obsidian.md) vault into a shared, git-backed knowledge base that an AI coding assistant (this guide is written for [Claude Code](https://claude.com/claude-code), but the idea generalises) can read and write directly while your team works, so context that would normally evaporate at the end of a chat — how a system works, what was decided and why, what's still open — persists and compounds instead.

This repo *is* the vault. Fork it, rename it, push it to whichever git host you already use (GitHub, GitLab, Bitbucket, self-hosted — nothing here is host-specific), and you have a working Bedrock vault for your team on day one.

**Nothing in this repo is specific to any particular company, team, or codebase.** Every example uses a placeholder team name, a placeholder repo (`widget-service`), and a placeholder person (`jane-doe`). Swap those for your own as you go — see [Adopting this for your team](runbooks/adopting-for-a-new-team.md).

## Why this, and not just "a wiki"

A normal wiki is something people *remember to update*. This is different in two ways:

1. **Your AI assistant writes to it as a side effect of the work you're already doing**, not as a separate documentation chore. "Write today's session as a daily note" or "update this doc with what we just decided" costs you one sentence, at the moment the context is freshest.
2. **It's git, not a database.** Every change is a commit, by a named author, with a diff you can review, revert, or blame. There's no separate access-control system to administer and no vendor lock-in — anyone with a git client and a text editor can read every word of it even without Obsidian installed.

The trade-off is honesty about what this *isn't*: it's not real-time multi-user editing (two people editing the same file at the same moment is a merge, not a live cursor), and it's not a replacement for your actual documentation platform if you have one with tighter governance needs. It's a fast, low-ceremony layer that's very good at capturing the kind of context that normally only lives in one person's head or one long Slack thread.

## What's in this repo

| Path | What it is | Written by |
|---|---|---|
| `index.md` | Hand-maintained hub note: a table of the systems/repos you're documenting, plus a full document index | You, occasionally |
| `daily-notes/<person>/` | One file per work session — a log of what happened, not a polished doc. One subfolder per contributor | Your AI assistant, at your prompting |
| `repos/<name>/` | Durable reference docs about a specific system or codebase — how it works, not what happened on a given day | Your AI assistant, built up and revised over many sessions |
| `runbooks/` | Step-by-step procedures for recurring tasks (this file's own siblings are examples) | You or your AI assistant, once a procedure is proven |
| `docs/` | Setup and reference material — how to connect the assistant to the vault, and what it can do once connected | You |
| `tools/` | Copy-paste setup scripts, optional git hooks, and optional Claude Code commands/skills that make the workflow below effortless | You, once, per machine |

The distinction that matters throughout: **`daily-notes/` is a session log; `repos/` and `runbooks/` are the current-state reference.** Anything worth knowing next time without reading through old sessions belongs in the latter, cross-linked from the daily note that produced it.

## Quick start

1. **Use this repo as a template** (or fork/clone it) into a new repo on your git host of choice, named for your team or project — e.g. `bedrock-<your-team>`.
2. **Clone it locally, then install Obsidian and open the clone as your vault** — in that order. See [Step 0 of the setup guide](docs/mcp-setup.md#step-0--clone-first-then-install-and-open-obsidian) for why the order matters.
3. **Connect your AI assistant to the vault** — either run [`tools/setup-mcp.ps1`](tools/setup-mcp.ps1) (Windows) / [`tools/setup-mcp.sh`](tools/setup-mcp.sh) (macOS/Linux), or follow the manual steps in [`docs/mcp-setup.md`](docs/mcp-setup.md).
4. **Reset the placeholders** for your own team — see the checklist in [`runbooks/adopting-for-a-new-team.md`](runbooks/adopting-for-a-new-team.md).
5. **Start using it** — [`runbooks/using-the-vault.md`](runbooks/using-the-vault.md) covers the three things you'll do constantly (catch up at session start, log a session, bootstrap a doc for a new codebase); [`runbooks/daily-workflow.md`](runbooks/daily-workflow.md) is the return-to checklist once that's part of your routine.
6. **Optional automation** — once the manual workflow feels natural, [`tools/`](tools) has git hooks and Claude Code commands/skills that remove most of the remembering. Entirely optional; the vault works fine without them.

## Guides

- [`docs/mcp-setup.md`](docs/mcp-setup.md) — connect Claude Code to the vault (one-time, per machine)
- [`docs/mcp-tools-reference.md`](docs/mcp-tools-reference.md) — everything the vault connection can actually do
- [`runbooks/using-the-vault.md`](runbooks/using-the-vault.md) — the three recurring workflows, as plain-English prompts
- [`runbooks/daily-workflow.md`](runbooks/daily-workflow.md) — a return-to checklist, plus worked examples including how merge conflicts happen and get resolved
- [`runbooks/adopting-for-a-new-team.md`](runbooks/adopting-for-a-new-team.md) — the checklist for turning this template into *your* team's vault
- [`docs/publishing-to-a-wiki.md`](docs/publishing-to-a-wiki.md) — optional: mirror selected docs out to Confluence/Notion/SharePoint/whatever your org already uses

## Push policy: direct to `main`, no required PR

This is a deliberate, opinionated choice this pattern depends on — worth reading even if you end up disagreeing with it for your team. See the "Push policy" section of [`runbooks/using-the-vault.md`](runbooks/using-the-vault.md#push-policy-direct-to-main-no-required-pr) for the full reasoning: why the cost of an imperfect doc landing is low, what review happens *instead* of a PR gate, and why a required-PR branch rule on `main` will actively break the automation in `tools/hook-templates/` if you turn one on without adjusting for it.

## Credits

This pattern isn't original — it grew directly out of a lunch-and-learn given by [Jonathan Vaughan](https://github.com/JonathanVaughan), whose own reference vault was the first working demonstration that a git-backed Obsidian vault plus an AI coding assistant could actually hold a team's context like this. Everything in this repo — the folder conventions, the daily-note discipline, the hooks, the whole shape of the thing — builds on that original idea. Full credit to him for the foundation; any rough edges in the generalised version here are our own.

## License

Add whichever license you'd like this template distributed under (e.g. MIT) — there's nothing in here that isn't meant to be copied, adapted, and given away.
