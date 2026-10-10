# Claude Code status line (optional)

> **Scope:** a small, dependency-free status line for Claude Code that works the same on Windows, macOS and Linux. It is a single Node script, [`tools/statusline/statusline.mjs`](../tools/statusline/statusline.mjs), that reads the JSON Claude Code sends it and prints two lines. Nothing in the vault depends on it; install it only if you want it.

## What it shows

```
[Widget 1 ·high 🧠] | 📦 jane-doe/widget-service 🌿 feature/status-line
▓▓▓░░░░░░░ 33% | 5h ▓░░░░░░░░░ 12% (3h 5m) | 7d ▓▓▓▓▓░░░░░ 55% (2d 4h)
```

The first line is the model, effort level and a brain marker when extended thinking is on, then the repository (`owner/name`) and the branch. A folder marker (`📁 folder`) is added only when the folder name differs from the repository name, so it appears when it tells you something. In a repository with a detached HEAD the branch is replaced by the first seven characters of the commit.

The second line starts with a context bar (green below 70%, yellow from 70%, red from 90%), then one usage block that depends on the kind of account:

| Account | What Claude Code sends | What is shown |
|---|---|---|
| Pro or Max subscription | `rate_limits.five_hour` and `rate_limits.seven_day` | 5 hour and 7 day bars with reset times. The 7 day reset is shown only at 50% or more |
| Claude apps gateway with a spend limit | `rate_limits.spend_limit` | A spend bar, plus `$used/$limit` and the reset time when they are supplied |
| API or pay-as-you-go | no `rate_limits` | The estimated session cost, at list price, so it may differ from the bill |

Usage bars are green below 60%, yellow from 60% and red from 80%, because running out of allowance mid-session is more disruptive than a compaction. A worktree tag (`🌳 name (branch)`) and an agent tag (`👤 name`) are added at the end of line 2 when they are in use.

## Requirements

- Node.js 18 or later. Claude Code itself is a native binary, so Node is not guaranteed to be on the machine.
- `git` is not needed in normal use. The branch is read straight from `.git/HEAD`, which keeps each refresh to one short-lived process. The one exception is a repository created with `git init --ref-format=reftable`, where `HEAD` holds a placeholder; the script then runs a single `git branch --show-current`.
- A terminal font with the emoji used (📁 📦 🌿 🧠 🌳 👤).
- The spend bar needs Claude Code 2.1.251 or later, and the `$used/$limit` amounts need 2.1.284 or later. On older versions the fields are simply absent and the script falls back to what is there.

## Installing by hand

Copy the script somewhere stable, for example `~/.claude/statusline.mjs`, and add this to `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "node ~/.claude/statusline.mjs" }
}
```

Start a new Claude Code session to pick it up.

**On Windows, check how the command is launched.** Claude Code runs status line commands through Git Bash when Git for Windows is installed, and through PowerShell otherwise. Bash expands `~`; PowerShell does not expand it for native programs, so `node ~/.claude/statusline.mjs` may receive a literal `~`. If the status line is blank on a machine without Git for Windows, use an absolute path with forward slashes instead, for example `node C:/Users/jane-doe/.claude/statusline.mjs`.

## Limits worth knowing

- **Managed machines.** If your organisation's managed settings set `allowManagedHooksOnly`, a custom status line is removed without any warning. Nothing here can detect that.
- **Cost on a subscription, briefly.** `rate_limits` is absent before the first response of a session, and a window is dropped once its reset time passes. In either gap a subscriber sees the cost display for a moment instead of the bars. It is cosmetic and corrects itself.
- **Field names can change.** The script is checked against the status line documentation (code.claude.com/docs/en/statusline) as it stood in October 2026. The tests here prove the script is right for that JSON; they cannot prove Claude Code keeps sending it. Re-check the page when Claude Code updates.
- **Not a Claude Code run.** The CI runners do not have Claude Code, so how the command is launched on macOS and Windows is only as good as the documentation says.
- **Branch edge cases.** Only `refs/heads/` references are parsed, and bare repositories and `GIT_DIR` are ignored. A linked worktree's `.git` file holds an absolute path, which may not resolve when a Windows checkout is viewed from WSL or a container; the branch is then left out rather than guessed.

## Tests

`node tools/statusline/test-statusline.mjs` runs the suite: robustness against empty and invalid input, every usage mode (including a reading of 0%), the colour thresholds, repositories, linked worktrees, detached HEAD, reftable, input arriving in slow chunks, and the exact `node ~/.claude/statusline.mjs` command under bash. It builds throwaway repositories in temp folders and never touches your real `~/.claude`. See [`testing.md`](testing.md).
