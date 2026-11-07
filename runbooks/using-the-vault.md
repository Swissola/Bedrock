---
title: Using the vault - conventions, session start, daily notes, and populating repos/ docs
tags: [runbook, onboarding, workflow]
---

# Using the vault

> **Scope:** for anyone using the vault day to day, once it is connected (see [`docs/mcp-setup.md`](../docs/mcp-setup.md)). It covers what the vault is for, its folder conventions, and the three recurring actions: catching up at session start, logging a session, and bootstrapping a repo doc for a system that isn't documented yet. They are written as plain-English prompts anyone can use today, with no automation required.
>
> If you've installed the optional commands from [`docs/automation.md`](../docs/automation.md), the three actions are also available as `/vault-context`, `/vault-log` and `/vault-populate`. They're condensed pointers back to this page, not a separate implementation, so the prompts below work identically either way.

## Prerequisites (all three workflows)

- **Obsidian must be open**, with this vault loaded. The MCP connection runs inside the app, so with Obsidian closed your assistant can't reach the vault at all. (This applies to the default Local REST API backend. See [Backends](../docs/vault-config.md#backends) for the alternative.)
- **The `obsidian` MCP server must already be registered on your machine.** It is a one-time step, described in [`docs/mcp-setup.md`](../docs/mcp-setup.md). You can check with `claude mcp list`.
- Registration is `--scope user`, so once done it's available in **any** session, whichever folder you're working in. You don't need to be inside this vault's own folder to use any of the three workflows.

## What the vault is for

A git-backed knowledge base that your AI assistant can read and write directly while you work. Context you'd otherwise re-explain every session (how a system works, what you decided and why, what's still open) persists and compounds instead of evaporating at the end of the chat.

## Folder structure

| Folder | Contains | Written by |
|---|---|---|
| `index.md` | The hub note: tables of repos and systems, plus a full document index | You, occasionally. Keep it current when you add a repo doc |
| `daily-notes/<name>/` | Daily notes: one file per repo per work session, a log of what happened, not a polished doc. One subfolder per contributor (see below) | Mostly your AI assistant, at your prompting, during or after a session |
| `repos/<name>/` | Repo docs: durable reference about a specific system or repo, how it works, not what happened on a given day | Your assistant, built up and revised over many sessions |
| `runbooks/` | Step-by-step procedures for recurring tasks (this file is one) | You or your assistant, once a procedure is proven and worth repeating |

The distinction that matters: **daily notes are a session log. `repos/` and `runbooks/` are the current-state reference.** If something's worth knowing next time without reading through old sessions, it belongs in `repos/` or `runbooks/`, cross-linked from the daily note that produced it, not left buried in the daily note itself.

## Basic operations

Once the `obsidian` MCP server is registered, just ask your assistant in plain language. It has vault read, write and search tools available directly:

- *"Read `repos/widget-service/index.md`"* reads a note.
- *"Search the vault for anything about the deploy pipeline"* searches across notes.
- *"Write today's session as a daily note"* creates or updates a note.
- *"Update `repos/widget-service/index.md` with what we just did"* edits an existing doc rather than overwriting it.

You don't need to know the underlying tool names, so describe the outcome. See [`docs/mcp-tools-reference.md`](../docs/mcp-tools-reference.md) for the full list of what's possible (surgical section edits, move, copy and delete, structured tag and frontmatter search, driving Obsidian's own commands, and more).

## 1. Session start: catching up

Run `git pull` in the vault repo first. Otherwise you're reading a stale copy without knowing it.

Then ask your assistant, in plain English:

> *"Read `index.md` and the most recent daily note before we start."*

Resuming something specific? Name it:

> *"Read the last daily note about the deploy pipeline."*

This picks up where a previous session (yours or a teammate's) left off, without anyone re-explaining it.

If the code repo has commits newer than the latest note, the session-start hook and `/vault-context` say so first, with a count, for example `Behind the repo: 15 commits after 2026-11-06 15:02. Open items may be out of date.` Treat the open items as unchecked until you have compared them with what has landed. See [`docs/automation.md`](../docs/automation.md#session-start-vault-context-point-a-session-at-its-repos-vault-context) for how it is counted and what it cannot see.

## 2. End of session: writing a daily note

Before closing down, ask your assistant:

> *"Write today's session as a daily note."*

### The folder and filename convention

This is a shared vault, so daily notes are split one subfolder per contributor: `daily-notes/<your-full-name>/YYYY-MM-DD-<repo>-<short-topic>.md`. **One note per repo you worked in**, so a session that touched three repos writes three notes, each holding only its own repo's work.

- **The subfolder, not the filename, carries the author.** Use `daily-notes/jane-doe/`, not `daily-notes/2026-09-14-jane-doe-topic.md`. Once there are more than a couple of contributors, a flat folder with everyone's notes mixed together gets hard to scan.
- **The repo is in the filename and in the frontmatter** (`repo: widget-service`, plus the same name as a tag). The repo name is the folder the repo lives in, lowercased. This is what lets the session-start hook load the notes for the repo you are in without reading every note in the vault.
- **Always your full name, forename-surname** (`jane-doe`, from `git config user.name`, lowercased with spaces turned to hyphens), **never just a forename** (`jane`). A team of any size can end up with two people sharing a first name, and a forename-only folder would silently merge their notes.

### The template

There's no enforced template, but converging on one is worth it. Reuse this rather than reinventing it each time:

```markdown
---
title: Short descriptive title
repo: widget-service
tags: [daily-note, widget-service, theme-tags]
date: YYYY-MM-DD
---

# YYYY-MM-DD — Short title

## What Was Done
(numbered list of concrete actions)

## Decisions Made
(what was decided and, importantly, *why*, including who steered it if not your own call)

## Problems Solved
(root cause + fix, for anything non-obvious)

## Commands Used
(anything worth copy-pasting next time)

## Context for Future Sessions
(state as of now: what's live, what's stale, what to check first)

## Open Questions / Next Steps
- [ ] checklist of what's unresolved
```

### Open items

An **open item** is a `- [ ]` line under `## Open Questions / Next Steps`. It is tracked across notes until it is closed. The markers are:

| Marker | Meaning | Written as |
|---|---|---|
| `- [ ]` | Open | `- [ ] text (opened YYYY-MM-DD)` |
| `- [x]` | Done | `- [x] text (done YYYY-MM-DD, see [[note]])` |
| `- [-]` | Dropped | `- [-] text (dropped YYYY-MM-DD: reason)` |
| `- [>]` | Carried to a newer note | `- [>] text (carried to [[new note]] YYYY-MM-DD)` |

A carried item in the new note reads `- [ ] text (from [[old note]], opened YYYY-MM-DD)`. The opened date stays the original one, so an item's age is never reset by carrying it.

`/vault-log` reconciles open items at the end of a session:

- It says first when the repo has commits newer than your newest note that this session did not make, meaning an earlier session was never logged. It gives the count only, and leaves those commits out of the note unless you ask for them to be covered.
- It ticks what the session finished, and closes an item that other work has overtaken as dropped, with `(dropped YYYY-MM-DD: superseded by [[note]])`.
- Before it carries an untouched item forward, it checks whether a later commit mentions the terms in backticks in the item, and puts any hit to you as possibly done, with the commit hashes. It never ticks from a match, and an item with no backticked term is not searched.
- It carries untouched items forward silently.
- It asks you about partly touched ones, and about anything open longer than `staleOpenItemDays` (30 by default). Such an item is called **stale**.
- It closes another person's item only with evidence, and then changes only that line's marker.

### Coming back to the same repo the same day

Append an `## Update (later same session) — ...` section to your existing note for that repo, rather than starting a new one. It keeps the full story in one place. Another repo's note from the same day is never appended to.

> **Different conventions in your own vault?** The folder, filename, template and same-day-same-repo rule above are the defaults. A vault that wants something else (a different folder layout, extra frontmatter, several notes per day) can say so in an optional `vault-config.md`. See [`docs/vault-config.md`](../docs/vault-config.md). With no such file, everything on this page applies as written.

If anything durable came out of the session (a system now understood, a procedure worth repeating), ask for it to be pulled into `repos/` or `runbooks/` and cross-linked. Don't leave it stranded in the daily note, where the next person won't think to look.

## 3. Bootstrapping a repo doc (`repos/<name>/`)

A blank vault stays blank unless someone deliberately fills it. Waiting for repo docs to emerge from daily work is slow, and biased towards whatever people happen to be touching that week. Systems nobody has had a reason to touch recently never get written up, even if they're important. Use this whenever a new system needs its first doc, or an existing one has drifted far enough from reality to be worth regenerating, not just once at vault setup.

1. **Build a candidate list.** Don't aim to be exhaustive on day one. Start with the systems your team reaches for most often, or the ones with the worst "only one person understands this" risk. A short list done well beats a long list done thinly.

2. **For each repo, open your assistant in that repo's own working directory**, not the vault. Because the `obsidian` MCP server is registered globally, the same session can read the local repo's actual code *and* write into the vault, so there's nothing to copy between sessions.

3. **Ask for a first-pass summary**, for example:
   > "Summarise this repo for a new-starter reference doc: what it does, how it's structured, how it's run/deployed, and anything that would trip up someone new to it. Write it to `repos/<name>/index.md` in the vault, following an existing `repos/<other-name>/index.md` as a structural example if one exists."

   Or run `/vault-populate` if you've installed the commands. You know it worked when `repos/<name>/index.md` exists in the vault.

4. **Link it from `index.md`'s Systems/Repos table** in the vault. A doc nobody can find from the hub is barely better than no doc at all.

5. **Review the draft once, don't just regenerate it.** A first pass from reading code alone will miss tribal knowledge: why something was actually decided, what's genuinely load-bearing versus legacy, what's about to change. The person who knows the system best should correct the draft in place, not have the assistant re-derive it from scratch.

6. **Revisit it when the system materially changes** (a major migration, an architecture change), not on a fixed schedule. A repo doc that has silently gone stale is worse than one that's honestly thin. If you set `repoDocBehindCommits` in `vault-config.md` ([`docs/vault-config.md`](../docs/vault-config.md)), `/vault-log` says when the code has moved that many commits past the commit the doc was built from, and offers `/vault-populate`. It never runs it for you, since the result is a draft to read.

## Cross-linking

Use `[[repos/x/y]]`-style wikilinks liberally. Durable docs in `repos/` and `runbooks/` link to each other both ways when they're related. Daily notes link *out* to the durable docs they touched, but durable docs don't usually link back to individual daily notes: there'd be too many, and they're not the current-state reference.

## Growing this as a team vault

Since this vault is meant for your whole team rather than one person, a few things are worth agreeing early rather than letting drift:

- **One `repos/<name>/` per system you all touch regularly.** Split it into multiple files (an index, then topic-specific docs) once a system's documentation outgrows a single page.
- **Don't duplicate, cross-link.** If two people are documenting the same system from different angles, that's two docs cross-linked, not one person's version winning.
- **Redact real credentials, tenant IDs, and personal data.** Describe config *shape*, not real values, even though it's an internal knowledge base. This matters more here than in most internal wikis: the point of this pattern is git history and easy forking and sharing, so anything sensitive committed here is harder to walk back than in a system with access controls. If something does slip through, [`git-recovery.md`](git-recovery.md#1-a-secret-or-personal-data-got-committed) says what to do.

## Push policy: direct to `main`, no required PR

This vault is deliberately looser than a code repo, for two reasons:

- It is context, not executable production code, so the cost of something imperfect landing is low and cheaply reverted (`git revert`).
- The automation in [`docs/automation.md`](../docs/automation.md) depends on it. The `post-merge` hook auto-commits and a human pushes directly, both straight onto `main`. A required-PR branch policy on `main` will reject that push outright and break the workflow as designed, if you turn one on without adjusting for it.

**Check, don't assume.** If you adopt any of this, look at your git host's branch protection settings for this repo and confirm they don't already require a PR to merge into `main`. A brand-new repo usually has nothing configured by default, but a repo that inherited settings from an org-wide default might. If a PR is required, either relax the policy for this repo specifically, or redesign the hook workflow around it (a service-account PR auto-merge, say).

**What review happens instead of a PR gate**, proportionate to the risk:

- A human looks at `git status` and `git log origin/main..main` before every push (Example 3 in [`daily-workflow.md`](daily-workflow.md)). This is the real review point, not a formality, since a hook's own output check only verifies *which file* was written, not whether the content is correct.
- A human reviews a repo's *first* generated doc once, in full, before trusting it (step 5 of the bootstrap workflow above).
- Weekly housekeeping ([`daily-workflow.md`](daily-workflow.md)) is the batch-review backstop. It includes a skim of the week's automated commits, not just tidying `index.md` links.
- A merge conflict (Example 4 in `daily-workflow.md`) forces a human look by construction, because git won't let you push past one silently.

**Reducing merge conflicts.** They're rare by design, not by luck:

- Pull at the start of every session (the first rule in [`daily-workflow.md`](daily-workflow.md)). Most conflicts come from two people working off stale copies for a while, not from working on the same doc at the same moment.
- Daily notes live in per-person subfolders, so they structurally can't conflict with anyone else's.
- The `post-merge` hook is meant to write exactly one file, and it checks afterwards. A write anywhere else is flagged in its log and left for you to look at, so it can't quietly sprawl across shared docs and multiply the collision surface.
- Split a shared doc into topic-specific sub-files once it outgrows a single page, so two people's concurrent edits land in different files.
- Ask your assistant for a **targeted addition** ("add a bullet about X to `repos/<name>/index.md`") rather than "regenerate this doc". A small, additive edit to one section is far less likely to collide with someone else's concurrent edit than a full rewrite of the same file.

## Related

- [`../docs/mcp-setup.md`](../docs/mcp-setup.md): MCP setup
- [`../docs/automation.md`](../docs/automation.md): optional commands and hooks that build on top of these manual workflows
- [`daily-workflow.md`](daily-workflow.md): where these actions fit into an actual session (start, during, end), plus worked examples
- [`git-recovery.md`](git-recovery.md): undoing mistakes in the vault repo
- [`../index.md`](../index.md): the hub note
