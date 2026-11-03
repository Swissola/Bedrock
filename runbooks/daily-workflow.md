---
title: Suggested daily workflow for using the vault
tags: [runbook, workflow]
---

# Suggested daily workflow

> **Scope:** for anyone using the vault regularly. It is a checklist to return to, to make the vault part of how you actually work, once the MCP connection is set up (see [`docs/mcp-setup.md`](../docs/mcp-setup.md)) and you know the basic conventions (see [`using-the-vault.md`](using-the-vault.md)). It is not a one-time read, so revisit it, especially early on. It also has four worked examples, including a merge conflict, and a short glossary of git terms.

The vault only pays off if it's part of how you work, not a separate chore. A rough shape that's held up well in practice follows. The **vault** is this repo. A **daily note** is a session log, and the **repo doc** (`repos/<name>/index.md`) is the reference page for one codebase. An **open item** is a `- [ ]` line in a daily note. See [Terms](../README.md#terms).

## Starting a session

1. **`git pull` first, in the vault repo, before anything else.** This is a shared vault, so skipping this means reading stale `index.md` and `repos/` content, and risking a conflict later if you edit something someone else already changed.
2. **Ask your assistant to catch you up**: *"read `index.md` and the most recent daily note"*. It picks up where you left off without you re-explaining. For the repo you are in, ask for your latest note about it, and the open items anyone left. Resuming something specific? Name it: *"read the last daily note about the deploy pipeline."*

Two optional shortcuts, both described in [`docs/automation.md`](../docs/automation.md):

- The `/vault-context` command does step 2 in one go.
- The `session-start-vault-context` hook (opt-in per repo) does it with no asking. A session in that repo starts with a short **pointer**: the path of the repo doc, the path and date of your latest note for that repo (and of up to three other contributors'), and the open items with their owners and ages, stale ones first. It does not load the notes themselves. The assistant reads them when the task needs them, or you run `/vault-context` to load them in full. It stays quiet on `resume`.

## During the session

- **Capture decisions when they happen**, not from memory afterwards. Ask your assistant to update the relevant `repos/<name>/index.md` the moment something durable is settled, while the reasoning is still in the conversation. Don't wait until the end of the session to decide what was worth keeping.
- **Check the vault before re-investigating.** Asking your assistant what's already documented about a system, before you work it out from scratch, is a normal use.

## Ending a session

1. **Ask your assistant to *"write today's session as a daily note"*** before you close down. It writes one note per repo you worked in, following the template in [`using-the-vault.md`](using-the-vault.md). First it reconciles open items: it ticks what the session finished, carries untouched ones forward with their original `opened` date, and asks about the rest. The optional `/vault-log` command automates this step, including finding the folder and filename convention and appending to a same-day note for the same repo.
2. **Pull anything durable into `repos/` or `runbooks/`.** If a system is now understood or a procedure is worth repeating, ask for it to be written there and cross-linked. Don't leave it stranded in the daily note, where the next person won't think to look.
3. **Check `git status`, commit, and push before you close down**, in the vault repo. The `post-merge` hook, if you've installed it, auto-commits its own doc updates locally as they happen, so they won't be lost, but it never pushes. If you don't push, nobody else gets the update. Pushing is the only way anyone else sees what changed, because there is no other notification, so an unpushed session might as well not have happened, for everyone else.

## If you install the `post-merge` self-documenting hook (optional)

The repo doc it maintains for a repo (`repos/<that-repo-name>/index.md`) updates itself after each pull that changes the repo, so you don't need to ask your assistant to keep it current the way you would for every other repo doc. See [`docs/automation.md`](../docs/automation.md#post-merge-a-self-documenting-repo).

## A few terms, if git is still new to you

Skip this if you're already comfortable with git. If not, every example below uses these words:

- **Repo (repository)**: a folder whose history git is tracking. This vault is one repo; each codebase you work on (e.g. `widget-service`) is its own, separate repo with its own separate history. They don't know about each other.
- **Commit**: a saved snapshot of some changes, with a message describing what and why. Commits are local to your machine until you push them.
- **Push**: upload your commits to your git host, so everyone else can get them. Nobody else sees a commit until it's pushed.
- **Pull**: download commits other people have already pushed, into your own local copy. If you don't pull, you're working from a stale copy without knowing it.
- **`git status`**: "what's changed on my machine that isn't committed yet?" Run this whenever you're not sure what state things are in - it's always safe, it never changes anything.
- **Uncommitted change**: a file that's been edited but not yet turned into a commit. It only exists on your machine, and can be lost more easily than a commit can (e.g. by a careless `git pull` or `git checkout`).
- **Unpushed commit**: a commit that exists on your machine but hasn't been uploaded yet. Safer than an uncommitted change (it's a real, named snapshot), but still invisible to everyone else until pushed.
- **Merge conflict**: git's way of saying "two people changed the same lines of the same file, and I can't guess which version you want" - it stops and asks you to decide by hand. Covered in Example 4 below.

When something goes wrong beyond a merge conflict (a bad commit, a secret committed, a deleted note, a pull that refuses to run), see [`git-recovery.md`](git-recovery.md).

## Worked examples

Before any of these, the [prerequisites in `using-the-vault.md`](using-the-vault.md#prerequisites-all-three-workflows) must be true: Obsidian open with this vault loaded, and the `obsidian` MCP server registered on your machine.

### Example 1: Documenting a brand-new repo for the first time

You want to add a repo that isn't in the vault yet, say, `widget-service`, and also do some real work in it.

1. **Open Obsidian**, with this vault loaded. Leave it open in the background for the rest of the session.
2. **Open your assistant inside `widget-service`'s own folder** - not inside the vault. This feels counterintuitive the first time, but it's correct: the MCP connection to the vault is registered for your whole machine (`--scope user`), not tied to one folder, so a session sitting in `widget-service` can read that repo's actual code *and* write into the vault at the same time.
3. **Ask your assistant, in plain English**, something like:
   > *"Summarise this repo for a new-starter reference doc: what it does, how it's structured, how it's run/deployed, and anything that would trip up someone new to it. Write it to `repos/widget-service/index.md` in the vault, following an existing `repos/<name>/index.md` as a structural example if one exists."*
4. Your assistant reads the real code in front of it, then writes the new doc straight into the vault over that MCP connection - even though your terminal never leaves the `widget-service` folder.
5. **Read the draft yourself and correct it.** A first pass from reading code alone will miss the tribal knowledge - why something was actually decided, what's genuinely load-bearing versus legacy. This step matters; don't skip it.
6. Ask your assistant to **link the new doc from `index.md`'s Systems/Repos table** - an undiscoverable doc barely beats no doc at all.
7. Do your actual work in `widget-service`.
8. **The moment something durable comes up** (a decision, a gotcha), ask your assistant to update `repos/widget-service/index.md` there and then - don't wait until the end to decide what was worth keeping.
9. **End of session**: ask your assistant to *"write today's session as a daily note"*.
10. **Hook considerations**: if `widget-service` doesn't have the optional `post-merge` hook installed, nothing happens automatically here - every vault write in this example was you explicitly asking for it. That's expected and fine; hooks are an optional layer on top of this, not a replacement for it.
11. **This is the step it's easiest to forget**: everything your assistant just wrote landed as real files on disk *inside the vault repo's own folder*, but writing a file isn't the same as sharing it. Open a terminal in the **vault repo** (a different folder from `widget-service`) and run `git status`, you'll see the new `repos/widget-service/index.md` and today's daily note listed as changes. `git add`, `git commit`, then `git push` them from there, or nobody else will ever see today's work, no matter how good it is.

### Example 2: A teammate picks up the same repo the next day

Someone else continues the `widget-service` work from Example 1, the next day.

1. Open Obsidian.
2. **In the vault repo**, run `git pull` first. This downloads yesterday's new doc and daily note onto this person's machine - without it, they'd be reading a stale, empty-looking vault and wouldn't know it.
3. Ask your assistant to *"read `index.md` and the most recent daily note about widget-service"* - picks up yesterday's context without anyone re-explaining it.
4. **Separately, in `widget-service` itself**, run `git pull` there too. This is a genuinely different, unrelated repo with its own history - pulling one never pulls the other.
5. Do the actual work.
6. Same as Example 1: update `repos/widget-service/index.md` the moment something durable happens, and write a daily note at the end.
7. **Before closing down**: `git status` in the vault repo, commit, push. Same discipline, every session, regardless of who you are.
8. **Hook considerations**: still nothing automatic, for the same reason as Example 1 - `widget-service` isn't hooked up. If it *were* (a separate, deliberate decision, not done by default), then step 4's `git pull` on `widget-service` would also, quietly, auto-write and auto-commit (but never auto-push) an update to the vault in the background. Step 7's `git status` check would then show that alongside your own manual changes, all ready to review and push together.

### Example 3: You've gone a few days without pushing: what's actually sitting there, and what do you do?

This is the case the optional reminder hooks exist for - there are two of them (see [`docs/automation.md`](../docs/automation.md)), catching this from different angles.

1. If you've installed the `session-start-vault-check` hook and you open a session in some **completely unrelated** repo days later, it prints something like: *"Note: the vault at `...` has 3 unpushed commit(s) on main not yet on origin ... Push when ready."* - even though you're nowhere near the vault right now. It's not just a session-start thing either: the same reminder also nags periodically during a long session that never restarts.
2. Even if a session runs for hours without catching it that way, there's a second catch, if you've also installed `pre-push`: the moment you `git push` *anything*, in any repo, a warning (never a block) reminds you the vault also has something pending - on the theory that you're already in a "pushing" frame of mind right then. It stays silent if the repo you're pushing already *is* the vault, since in that case the push you're doing covers it.
3. Without either hook, or as a manual double-check even with them, open a terminal in the vault repo and run **two different checks**, because they answer two different questions:
   - `git status` - anything edited but not yet turned into a commit at all (e.g. you tweaked a note directly in the Obsidian app, not through your assistant).
   - `git log origin/main..main` - commits that already exist on your machine but haven't been uploaded yet (this is exactly what the reminder hooks are checking).
4. **If `git status` shows uncommitted changes**: `git add` and `git commit` them with a message describing what they are.
5. **Look at what's about to be pushed before you push it**, `git log origin/main..main` (or `--stat` for more detail). This might be a mix of your own commits and several small automated commits a hook made on its own. That's normal and expected if you've installed the `post-merge` hook. But a quick look here *is* the actual safety check this whole design depends on, a hook's output-validation only verifies it wrote to the right file, not that what it wrote is actually correct, so a glance before pushing is the last line of defence, not a formality.
   If something there shouldn't go out, [`git-recovery.md`](git-recovery.md) covers undoing it, including unwanted hook commits.
6. `git push`. Everything above is now visible to the rest of the team.

### Example 4: Two people changed the same doc: a merge conflict

Worth knowing before it happens to you for the first time, since it looks alarming otherwise.

1. You and a teammate both had `repos/widget-service/index.md` open in separate sessions and both asked your assistant to update it, without either of you pulling first.
2. Whoever pushes **first** has no problem - their `git push` just works.
3. Whoever pushes **second** gets rejected: git says the remote has changes they don't have locally. Run `git pull` to fetch those changes - if the edits touched *different* parts of the file, git merges them automatically and you're done. If they touched the *same* lines, git marks the file as conflicted and stops, leaving both versions visible in the file with `<<<<<<<`/`=======`/`>>>>>>>` markers around the disputed section.
4. **This is normal, not a crisis.** Open the file, read both versions, decide what the combined result should actually say (ask your assistant to help reconcile them if it's not obvious), delete the `<<<<<<<`/`=======`/`>>>>>>>` markers once you're happy, then `git add` the file and `git commit` to finish the merge.
5. **Why Example 1's "pull first" habit matters**: pulling at the start of a session is what makes this rare in practice. Conflicts happen when two people work from stale copies for a while without syncing - the more often everyone pulls, the smaller and rarer the conflicts that do happen.

This repo pushes straight to `main`, no PR required - see [`using-the-vault.md`](using-the-vault.md#push-policy-direct-to-main-no-required-pr)'s "Push policy" section for why that's the right call here (and isn't, for most code repos), what review happens instead, and the other concrete ways this vault's design already keeps conflicts rare.

## Weekly-ish housekeeping

- Skim `index.md` and add links for any `repos/` docs that piled up during the week without being wired in.
- Check the open items (`- [ ]`) in recent daily notes - anything older than `staleOpenItemDays` (30) is flagged stale. Tick off what's resolved, drop what no longer matters, or fold it into the durable doc it affects.
- **If you've installed the `post-merge` hook, skim the week's automated commits** (`git log --oneline --grep "via post-merge hook"`) - this repo doesn't require PR review before anything reaches `main` (see [`using-the-vault.md`](using-the-vault.md)'s push-policy section for why), so this weekly skim is the batch-review backstop, on top of the per-push glance in Example 3 above.

## Related

- [`../docs/mcp-setup.md`](../docs/mcp-setup.md) - MCP setup
- [`using-the-vault.md`](using-the-vault.md) - folder conventions, daily-note template, cross-linking
- [`git-recovery.md`](git-recovery.md) - undoing mistakes: bad commits, committed secrets, deleted notes, lost work
- [`../index.md`](../index.md)
