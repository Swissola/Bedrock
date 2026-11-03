---
title: Git recovery — undoing mistakes in the vault repo
tags: [runbook, git, recovery]
---

# Git recovery

> **Scope:** what to do when something has gone wrong in the vault repo: a secret committed, a bad commit, an unwanted hook commit, a pull that refuses to run, a deleted note, or work that seems to have vanished. The everyday loop (pull, write, commit, push) and merge conflicts are covered in [`daily-workflow.md`](daily-workflow.md). This page covers the unhappy paths.
>
> If git terms are new to you, read the "A few terms" section of [`daily-workflow.md`](daily-workflow.md) first. Every section below assumes you have a terminal open **in the vault repo's folder**, not in some other repo.

## Before you do anything

1. **Stop and look.** Run `git status` (what's changed but not committed) and `git log --oneline origin/main..main` (what's committed but not pushed yet). Both commands only look; they never change anything.
2. **Work out whether the problem has been pushed.** It's the one question that decides which fix is safe. If the commit shows up in `git log origin/main..main`, it's still only on your machine. If it doesn't, everyone else may already have it.
3. **Never `git push --force` to `main`.** This vault is shared and pushes straight to `main` (see [`using-the-vault.md`](using-the-vault.md#push-policy-direct-to-main-no-required-pr)), so a force-push silently deletes other people's work. None of the fixes below need one, except the history rewrite in section 1, which is a deliberate, coordinated exception.
4. **If it was ever committed, it's almost certainly recoverable.** Section 7 explains how.

## 1. A secret or personal data got committed

The `pre-commit` hook scans for secret-shaped content, but no scan is perfect. If a password, token, key, tenant ID or someone's personal data made it into a commit:

**First, whatever else is true: treat the secret as compromised, and revoke or rotate it now.** Do this before tidying git. Rotation is what actually protects you. Everything below is cleanup.

**If it hasn't been pushed yet:**

```bash
# remove the secret from the file, then:
git add <file>
git commit --amend --no-edit     # if it's in your most recent commit
# or, if it's further back in your unpushed commits:
git reset --soft origin/main     # un-commit everything unpushed, keeping the changes staged
# remove the secret, then commit again
git log -p origin/main..main     # check: the secret must not appear anywhere in the output
```

**If it has been pushed:** removing it in a new commit stops it appearing in the current version of the note, but it stays in the git history, in every teammate's clone, and in every fork of this vault. From there:

- **If the secret has been rotated and is now useless,** a normal commit removing it from the file is usually enough. Record what happened in your daily note.
- **If the content itself is the problem** (personal data, or something that can't be rotated), the history has to be rewritten with a tool such as `git filter-repo`, followed by a coordinated force-push and everyone re-cloning. That's a job for whoever owns the repo. Talk to them before doing anything, and don't attempt it alone.

## 2. A bad commit that hasn't been pushed

Wrong file, wrong content, or a message you'd rather fix, and it's still only on your machine.

| You want to… | Run | What happens to your changes |
|---|---|---|
| Fix the most recent commit | edit, `git add`, then `git commit --amend` | Folded into that commit |
| Undo the last commit, keep the work ready to recommit | `git reset --soft HEAD~1` | Still staged |
| Undo the last commit, keep the work as ordinary edits | `git reset HEAD~1` | In the files, unstaged |
| Throw the last commit away completely | `git reset --hard HEAD~1` | **Gone** (only recoverable via section 7) |

`HEAD~1` means "one commit back". `HEAD~3` would undo the last three.

## 3. A bad commit that has already been pushed

Don't reset. Other people may already have pulled it. Add a commit that cancels it out instead:

```bash
git log --oneline            # find the bad commit's hash, e.g. a1b2c3d
git revert a1b2c3d           # creates a new commit that undoes it
git push
```

The history then shows both the mistake and its reversal, which is what you want in a shared repo, and nobody needs to do anything special on their next `git pull`.

## 4. A hook made an automated commit you don't want

If you've installed the `post-merge` hook, it commits its own doc updates locally (never pushing them). Example 3 in [`daily-workflow.md`](daily-workflow.md) says to look before pushing. If what you find there is wrong:

```bash
git log --oneline --grep "via post-merge hook" origin/main..main   # list unpushed hook commits
git revert <hash>                                                  # undo one cleanly
```

Using `revert` here, even though the commit isn't pushed yet, is deliberate. Hook commits are often mixed in with your own, and `git reset` would remove everything after the point you reset to, your commits included. Alternatively, if the hook's update was mostly right, just correct the doc and commit the fix. That's often the better outcome.

## 5. `git pull` refuses to run

Git says something like *"Your local changes to the following files would be overwritten by merge"*. This usually happens after editing a note directly in the Obsidian app and forgetting to commit it.

**If you want to keep your edits** (usual case):

```bash
git add <file>
git commit -m "Describe the edit"
git pull                       # if this reports a conflict, see Example 4 in daily-workflow.md
```

**If you want to keep them but not commit yet:**

```bash
git stash                      # park your edits
git pull
git stash pop                  # bring them back on top of the fresh copy
```

**If you don't want the edits at all:** `git restore <file>` discards them. ⚠️ This can't be undone, because uncommitted edits aren't in git's history.

## 6. A note was deleted by mistake

**Deleted but the deletion isn't committed yet:**

```bash
git restore <path/to/note.md>
```

**The deletion has been committed (pushed or not):**

```bash
git log --oneline --diff-filter=D -- <path/to/note.md>   # find the commit that deleted it, e.g. d4e5f6a
git restore --source=d4e5f6a~1 <path/to/note.md>         # bring back the version just before that commit
git add <path/to/note.md>
git commit -m "Restore <note> deleted by mistake"
```

## 7. Work seems to have vanished

After a `reset --hard` you regret, or a confusing sequence of commands, check the **reflog**. It's git's local record of every commit your repo has pointed at recently.

```bash
git reflog                       # newest first; find the line from just before things went wrong
git branch rescue <hash>         # safest: put that state on a side branch to inspect
```

Once you've confirmed `rescue` has what you need, bring it back onto `main` (`git switch main`, then `git merge rescue`) and delete the side branch with `git branch -d rescue`. If you're unsure, ask someone before merging.

The reflog only covers things that were **committed** at some point, and only on **your** machine. Uncommitted edits discarded with `git restore` or `git reset --hard` aren't in it.

## 8. Push rejected

Someone else pushed first. This is covered in Example 4 of [`daily-workflow.md`](daily-workflow.md): `git pull`, resolve any conflict, then `git push`. Don't "fix" a rejected push with `--force` (see "Before you do anything").

## Related

- [`daily-workflow.md`](daily-workflow.md): the everyday loop, git terms, and merge conflicts
- [`using-the-vault.md`](using-the-vault.md): push policy and why the vault doesn't use PRs
- [`../index.md`](../index.md)
