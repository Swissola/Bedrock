---
title: Using the vault — conventions, session start, daily notes, and populating repos/ docs
tags: [runbook, onboarding, workflow]
---

# Using the vault

> **Scope:** what the vault is for, its folder conventions, and the three recurring actions — catching up at session start, logging a session, and bootstrapping a `repos/<name>/` doc for a system that isn't documented yet — written as plain-English prompts anyone can use today, with no automation required.
>
> If you've installed the optional commands/skills from [`docs/automation.md`](../docs/automation.md), these three actions are also available as `/vault-context`, `/vault-log`, and `/vault-populate`. They're condensed pointers back to this page, not a separate implementation — the prompts below work identically either way.

## Prerequisites (all three workflows)

- **Obsidian must be open**, with this vault loaded — the MCP connection runs inside the app; closed Obsidian means your assistant can't reach the vault at all.
- **The `obsidian` MCP server must already be registered on your machine** — a one-time setup step, see [`docs/mcp-setup.md`](../docs/mcp-setup.md).
- Registration is `--scope user`, so once done it's available in **any** session regardless of which folder you're working in — you don't need to be inside this vault's own folder to use any of the three workflows below.

## What the vault is for

A git-backed knowledge base your AI assistant can read and write directly while you work — so context you'd otherwise re-explain every session (how a system works, what you decided and why, what's still open) persists and compounds instead of evaporating at the end of the chat.

## Folder structure

| Folder | Contains | Written by |
|---|---|---|
| `index.md` | Hand-maintained hub: tables of repos/systems, plus a full document index | You, occasionally — keep it current when you add a new `repos/` doc |
| `daily-notes/<name>/` | One file per work session — a log of what happened, not a polished doc. One subfolder per contributor (see below) | Mostly your AI assistant, at your prompting, during/after a session |
| `repos/<name>/` | Durable reference docs about a specific system/repo — how it works, not what happened on a given day | Your assistant, built up and revised over many sessions |
| `runbooks/` | Step-by-step procedures for recurring tasks (this file is one) | You or your assistant, once a procedure is proven and worth repeating |

The distinction that matters: **daily-notes are a session log, `repos/`/`runbooks/` are the current-state reference.** If something's worth knowing next time without reading through old sessions, it belongs in `repos/` or `runbooks/`, cross-linked from the daily note that produced it — not left buried in the daily note itself.

## Basic operations

Once the `obsidian` MCP server is registered, just ask your assistant in plain language — it has vault read/write/search tools available directly:

- *"Read `repos/widget-service/index.md`"* — reads a note
- *"Search the vault for anything about the deploy pipeline"* — searches across notes
- *"Write today's session as a daily note"* — creates/updates a note
- *"Update `repos/widget-service/index.md` with what we just did"* — edits an existing doc rather than overwriting it

You don't need to know the underlying tool names — describe the outcome. See [`docs/mcp-tools-reference.md`](../docs/mcp-tools-reference.md) for the full list of what's actually possible (surgical section edits, move/copy/delete, structured tag/frontmatter search, driving Obsidian's own commands, and more).

## 1. Session start — catching up

Before diving into work, ask your assistant, in plain English:

> *"Read `index.md` and the most recent daily note before we start."*

Resuming something specific? Name it:

> *"Read the last daily note about the deploy pipeline."*

This picks up where a previous session (yours or a teammate's) left off, without anyone re-explaining it. Do this **after** `git pull` in the vault repo — otherwise you're reading a stale copy without knowing it.

## 2. End of session — writing a daily note

Before closing down, ask your assistant:

> *"Write today's session as a daily note."*

### The folder and filename convention

This is a shared vault, so notes are split one subfolder per contributor: `daily-notes/<your-full-name>/YYYY-MM-DD-<short-topic>.md`.

- **Subfolder, not filename, carries the author** — `daily-notes/jane-doe/`, not `daily-notes/2026-09-14-jane-doe-topic.md`. Once there are more than a couple of contributors, a flat folder with everyone's notes mixed together gets hard to scan; a subfolder per person keeps it navigable.
- **Always your full name, forename-surname** (`jane-doe`, from `git config user.name`, lowercased with spaces turned to hyphens) — **never just a forename** (`jane`). A team of any size can easily end up with two people sharing a first name, and a forename-only folder would silently merge their notes together.

### The template

There's no enforced template, but converging on one consistently is worth it — reuse this rather than reinventing it each time:

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
(what was decided and — importantly — *why*, including who steered it if not your own call)

## Problems Solved
(root cause + fix, for anything non-obvious)

## Commands Used
(anything worth copy-pasting next time)

## Context for Future Sessions
(state as of now — what's live, what's stale, what to check first)

## Open Questions / Next Steps
- [ ] checklist of what's unresolved
```

If you pick a session back up later the same day, **append an `## Update (later same session) — ...` section to the existing file** rather than starting a new one — keeps the full story in one place.

If anything durable came out of the session (a system now understood, a procedure worth repeating), ask for it to be pulled into `repos/` or `runbooks/` and cross-linked — don't leave it stranded in the daily note where the next person won't think to look.

## 3. Bootstrapping a `repos/<name>/` doc

> A blank vault stays blank unless someone deliberately fills it. Waiting for `repos/` docs to emerge naturally from daily work is slow and biased towards whatever people happen to be touching that week — systems nobody's had a reason to touch recently never get written up, even if they're important. Use this whenever a new system needs its first doc, or an existing one has drifted far enough from reality to be worth regenerating — not just once, at vault setup.

1. **Build a candidate list.** Don't aim for exhaustive on day one — start with the systems your team reaches for most often, or the ones with the worst "only one person understands this" risk. A short list done well beats a long list done thinly.

2. **For each repo, open your assistant in that repo's own working directory** (not the vault). Because the `obsidian` MCP server is registered globally, the same session can read the local repo's actual code *and* write into the vault — no need to copy anything between sessions.

3. **Ask for a first-pass summary**, e.g.:
   > "Summarise this repo for a new-starter reference doc: what it does, how it's structured, how it's run/deployed, and anything that would trip up someone new to it. Write it to `repos/<name>/index.md` in the vault, following an existing `repos/<other-name>/index.md` as a structural example if one exists."

4. **Link it from `index.md`'s Systems/Repos table** in the vault — a doc nobody can find from the hub is barely better than no doc.

5. **Human-review the draft once, don't just regenerate it.** A first pass from reading code alone will miss tribal knowledge — why something was actually decided, what's genuinely load-bearing versus legacy, what's about to change. The person who knows the system best should correct the draft in place, not have the assistant re-derive it from scratch.

6. **Revisit per-repo when it materially changes** (a major migration, an architecture change), not on a fixed schedule — a `repos/` doc that's silently gone stale is worse than one that's honestly thin.

## Cross-linking

Use `[[repos/x/y]]`-style wikilinks liberally. The convention: durable docs in `repos/` and `runbooks/` link to each other both ways when they're related; daily-notes link *out* to the durable docs they touched, but durable docs don't usually link back to individual daily-notes (there'd be too many, and they're not the current-state reference).

## Growing this as a team vault

Since this vault is meant for your whole team rather than one person, a couple of things worth agreeing early rather than letting drift:

- **One `repos/<name>/` per system you all touch regularly** — split into multiple files (an index, then topic-specific docs) once a system's documentation outgrows a single page.
- **Don't duplicate — cross-link.** If two people are documenting the same system from different angles, that's two docs cross-linked, not one person's version winning.
- **Redact real credentials, tenant IDs, and personal data.** No real secrets or personal data in vault docs, even though it's an internal knowledge base — describe config *shape*, not real values. This matters even more here than in most internal wikis, since the entire point of this pattern is git history and easy forking/sharing — anything sensitive committed here is genuinely harder to walk back than in a system with access controls.

## Push policy: direct to `main`, no required PR

Deliberately looser than a code repo, for two reasons: this vault is context, not executable production code, so the cost of something imperfect landing is low and cheaply reverted (`git revert`); and the automation in [`docs/automation.md`](../docs/automation.md) depends on it — the `post-merge` hook auto-commits and a human pushes directly, both straight onto `main`. A required-PR branch policy on `main` will reject that push outright and break the workflow as designed, if you turn one on without adjusting for it.

**Worth confirming, not assumed**, if you adopt any of this: check your git host's branch protection settings for this repo don't already require a PR to merge into `main`. A brand-new repo usually has nothing configured by default, so this is often a non-issue in practice, but it's worth an actual look rather than an assumption, especially if the repo inherited settings from an org-wide default. If a PR is required, either relax the policy for this repo specifically, or redesign the hook workflow around it (a service-account PR auto-merge, say).

**What review happens, instead of a PR gate**, proportionate to the actual risk:

- A human glances at `git status`/`git log origin/main..main` before every push (Example 3 in [`daily-workflow.md`](daily-workflow.md)) — this is the real review point, not a formality, since a hook's own output-validation check only verifies *which file* was written, not whether the content is correct.
- Step 5 of the repos-bootstrap workflow above — a human reviews a repo's *first* generated doc once, in full, before trusting it.
- Weekly housekeeping ([`daily-workflow.md`](daily-workflow.md)) is the batch-review backstop: worth explicitly including a skim of the week's automated commits, not just tidying `index.md` links.
- A merge conflict (Example 4 in `daily-workflow.md`) forces a human look by construction — git won't let you push past one silently.

**Reducing merge conflicts, concretely** (they're rare by design, not by luck):

- Pull at the start of every session (already the first rule in [`daily-workflow.md`](daily-workflow.md)) — most conflicts come from two people working off stale copies for a while, not from working on the same doc at the same moment.
- Daily notes are per-person subfolders — structurally can't conflict with anyone else's.
- If you install the `post-merge` hook, its output-validation check confines each run to exactly one file — it can't sprawl into touching multiple shared docs and multiply the collision surface.
- Split a shared doc into topic-specific sub-files once it outgrows a single page — two people's concurrent edits then land in different files instead of the same one.
- Ask your assistant for a **targeted addition** ("add a bullet about X to `repos/<name>/index.md`") rather than "regenerate this doc" — a small, additive edit to one section is far less likely to collide with someone else's concurrent edit than a full rewrite of the same file.

## Related

- [`../docs/mcp-setup.md`](../docs/mcp-setup.md) — MCP setup
- [`../docs/automation.md`](../docs/automation.md) — optional commands, skills, and hooks that build on top of these manual workflows
- [`daily-workflow.md`](daily-workflow.md) — where these actions fit into an actual session (start/during/end), plus worked examples
- [`../index.md`](../index.md)
