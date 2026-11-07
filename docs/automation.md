# Automation: slash commands and hooks (optional)

> **Scope:** for anyone who has the manual workflow in [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) working and wants to stop having to remember it. Everything here is optional. The vault is fully useful without any of it.

Terms used on this page, in the same sense as everywhere else (see [Terms](../README.md#terms)):

- A **slash command** is a named prompt you type in Claude Code, such as `/vault-log`.
- A **git hook** is a script git runs on a git event (a commit, a pull, a push).
- A **session hook** is a script Claude Code runs when a session starts, or after a tool call.
- The **repo doc** is the vault's reference page for one codebase, `repos/<name>/index.md`.
- The **vault** is this repo, the one the notes live in. A **repo** below is any other codebase you work in.

## How the pieces fit together

There are two independent layers. Install either, both, or neither. Most repos only need the commands.

| Piece | Runs when | Where it is installed | What it does |
|---|---|---|---|
| `/vault-context`, `/vault-log`, `/vault-populate` | You type them, in Claude Code | `~/.claude/commands/`, once per machine | Catch up, log a session, bootstrap a repo doc |
| `pre-commit` | Git, before each commit | `.git/hooks/` of each repo that wants it | Scans staged changes for secrets |
| `post-merge` (also installed as `post-rewrite`) | Git, after a pull | `.git/hooks/` of each repo that wants it | Updates that repo's repo doc in the vault, unattended |
| `pre-push` | Git, before a push | `.git/hooks/` of each repo that wants it | Warns if the vault has unpushed commits |
| `session-start-vault-check` | Claude Code session start, and periodically during a session, in any repo | Your user-scope Claude Code settings | The same unpushed-commit warning |
| `session-start-vault-context` | Claude Code session start, in repos that opt in | That repo's `.claude/settings.json` | Points the session at that repo's vault context |
| `vault-lib` | Never run, only sourced | Beside the hooks | Shared helpers for `pre-push` and `session-start-vault-check` |

The hooks are the heavier layer. `post-merge` starts a headless AI run on every pull of a repo, so installing it is a real trade-off, and it only suits a repo you deliberately want to document itself in the vault.

The vault's conventions reach the assistant through a short [`CLAUDE.md`](../CLAUDE.md) at the vault root, which Claude Code loads itself when it runs there. There are no skills to install.

## Before you start

- A clone of this repo, and its absolute path (the **vault path**).
- The `obsidian` MCP server registered, if you have not done so already: see [`mcp-setup.md`](mcp-setup.md).
- `claude` on your `PATH`. `jq` and `timeout` (or `gtimeout`, or `perl`) are needed by `post-merge`. The installer warns about any of these it cannot find.

## Slash commands

### Install with the installer (recommended)

Run this from the root of a clone of this repo, once per machine:

```bash
bash tools/install-claude-config.sh --vault <absolute path to your vault>
```

On success it prints an `installed` line for each file and ends with `Done.` Re-run `bash tools/install-claude-config.sh --check` afterwards: it changes nothing and ends with `Everything is current.` when the installed copies match this repo. Open a **new** Claude Code session, because commands load at session start.

What it does:

- Copies the three commands to `~/.claude/commands/`.
- Copies the hook templates, `vault-lib` and a small wrapper, `session-start-vault-context.sh`, to `~/.claude/hook-templates/`. These are copies only. Nothing is enabled until you install a hook into a repo, as described below.
- Records the vault path in `~/.claude/hook-configs/vault-root`, so hooks installed in other repos can find the vault.
- Warns about anything missing (`claude`, `jq`, `timeout`).

Options:

| Option | Effect |
|---|---|
| `--check` | Reports what is current, outdated or missing, and changes nothing. Exit 1 if anything is not current. |
| `--dry-run` | Shows what it would do, and changes nothing. |
| `--backend mcpvault` | Also writes the MCP config the hooks use (`~/.claude/hook-configs/obsidian-mcp-config.json`). See [Backends](vault-config.md#backends). |
| `--statusline` | Also installs the optional [status line](statusline.md). `--force` replaces a different one, after a backup. |
| `--force` | Lets a new `--vault` path become the default (see below), and replaces a different status line. |
| `--no-skills` | Accepted and ignored, so old command lines keep working. Earlier versions installed two skills. The installer leaves them in place, says they are stale, and leaves the deleting to you. |
| `--prefix <dir>` | Installs into `<dir>` instead of `~/.claude`. Used by the tests. |

The installer is idempotent, so re-run it after pulling this repo.

**One vault path or several.** `~/.claude/hook-configs/vault-root` holds one absolute path per line, and the first line is the default. Running the installer with a second `--vault` adds a line. `--force` makes the new path the default instead. A trailing slash is ignored.

**On Windows**, `tools\install-claude-config.ps1` takes the same arguments and runs the script under Git for Windows' bash. Where script execution is restricted you may need `powershell -ExecutionPolicy Bypass -File ...`.

The installer is tested against a throwaway directory by `bash tools/testing/test-install-claude-config.sh`.

### Install by hand

Once per machine, from the root of a clone of this repo:

```bash
cp tools/command-templates/vault-context.md ~/.claude/commands/vault-context.md
cp tools/command-templates/vault-log.md ~/.claude/commands/vault-log.md
cp tools/command-templates/vault-populate.md ~/.claude/commands/vault-populate.md
```

(Windows PowerShell: `Copy-Item` in place of `cp`.)

### The three commands

| Command | What it does |
|---|---|
| `/vault-context` | Reads the hub note, your latest daily note for this repo, a short form of up to three other contributors' notes, and the open items across them, and says when the repo has moved on from them (see below) |
| `/vault-log` | Writes the session as one daily note per repo worked in, reconciles open items, and says when the working repo has commits from a session that was never logged (see below) |
| `/vault-populate` | Bootstraps a repo doc for a codebase. It keeps the doc's frontmatter and any `## Hand-written notes` section, and skips the rewrite when the repo has not changed since `source-commit` |

An **open item** is a `- [ ]` line in a daily note. One open for longer than `staleOpenItemDays` (30 by default) is **stale**. The full rules are in [`using-the-vault.md`](../runbooks/using-the-vault.md#2-end-of-session-writing-a-daily-note).

Things worth knowing about them:

- They are installed at **user scope** (`~/.claude/commands/`), not in this repo's `.claude/`, because `/vault-populate` has to work from inside whichever other repo you are documenting. Claude Code does not track that folder in git, so each machine needs the install once and a restart.
- They are condensed pointers back to the runbooks, not a second copy. If the two disagree, the runbooks win.
- `/vault-log` also reads an optional `vault-config.md` at the vault root, for vaults laid out differently from the runbook defaults. See [`vault-config.md`](vault-config.md).
- They work with either `obsidian` MCP backend: the Local REST API plugin, or MCPVault.
- Each template carries a `bedrock-template: <name>, version N` comment, so an installed copy can be compared with the one in this repo.

## Installing hooks into a repo

A **git hook** must be copied into `.git/hooks/` of each clone that wants it, because git never tracks that folder. Run the `cp` and `chmod` commands below from the root of the repo that should get the hook (not necessarily the vault). The source can be your clone of this repo, or `~/.claude/hook-templates/` once the installer has run.

### `pre-commit`: secret scan before a commit

Scans staged changes for likely secrets (API keys, tokens, private key blocks, connection strings with embedded passwords) before a commit lands, even locally. This is the cheapest point to catch one: an uncommitted change costs nothing to fix and a pushed one is much harder to walk back (see "Redact real credentials, tenant IDs, and personal data" in [`using-the-vault.md`](../runbooks/using-the-vault.md#growing-this-as-a-team-vault)).

```bash
cp tools/hook-templates/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

It needs [`betterleaks`](https://betterleaks.com/) on your `PATH`. It runs `betterleaks git --staged --redact`, the form the project documents for pre-commit hooks, with `-v` added on 1.x only. On 2.x `-v` means live validation of any credential found, so it is never passed there.

How it behaves:

- **A finding is not a failure.** Betterleaks exits 1 when it finds something. Any other non-zero code means the scan itself failed (bad config, unreadable repo, a crash). The hook reports a finding as "possible secret(s) in staged changes" and a failure as "the scanner failed, nothing was checked", so a broken scanner is never mistaken for a clean or a dirty result.
- **Non-blocking by default.** Both cases print a loud warning and let the commit through, because a hard block on a false positive trains people to bypass the hook. Set `PRECOMMIT_SECRET_SCAN_STRICT=1` (in your shell profile, or a repo-local `.envrc`) to block on either, which suits a team vault.
- **Getting past a false positive.** Use `git commit --no-verify`, or allowlist the finding with a `.gitleaksignore` entry or a repo `.gitleaks.toml` (betterleaks reads that file format).
- **No fallback scanner.** If betterleaks is not installed there is no scan at all, only a reminder on every commit (never throttled) to install it. A home-grown regex set would be weaker than the real tool and would give a false sense of coverage. This holds in strict mode too: with no scanner there is nothing to enforce with, so it warns and lets the commit through.
- **Secrets only, not general personal data.** Names, emails and phone numbers have no reliable shape in prose, and a scanner for them would flag ordinary sentences until people reached for `--no-verify`. Personal data stays a matter of human review.

To check it is working, stage a file and run `git commit`: with a clean scan it prints nothing, and with no scanner installed it prints the install reminder.

Test it with `bash tools/hook-templates/test-pre-commit.sh`, which stubs `betterleaks` so nothing needs installing. See [`testing.md`](testing.md).

### `post-merge`: a self-documenting repo

After a pull lands on the repo's default branch, this backgrounds a headless AI run that updates `repos/<this-repo-name>/index.md` (the repo doc) from the diff, so a repo documents its own changes with no one asking. It never creates the doc, so bootstrap it first.

**Prerequisites**

1. The repo doc exists in the vault. Create it once with `/vault-populate`, run from inside the repo. The hook refuses to run until `repos/<that-repo>/index.md` exists (or the doc at the configured `reposPath`).
2. A standalone `--mcp-config` file naming just the `obsidian` server (not your full Claude Code config) at `~/.claude/hook-configs/obsidian-mcp-config.json`. The installer writes it with `--backend mcpvault`. Otherwise ask your assistant to generate it from your existing MCP registration.
3. `pre-commit` installed alongside it, as described below.

**Install**

```bash
cp tools/hook-templates/post-merge .git/hooks/post-merge
cp tools/hook-templates/post-merge .git/hooks/post-rewrite
chmod +x .git/hooks/post-merge .git/hooks/post-rewrite
```

**Install the same file as `post-rewrite` too.** A plain `git pull`, and a fast-forward `git pull --rebase`, fire `post-merge`. A `pull --rebase` that has local commits to replay fires only `post-rewrite`, with the argument `rebase`. Without the second copy the hook never runs for anyone who pulls with rebase. The script acts on `rebase` and ignores `amend`. The range it documents starts at `ORIG_HEAD`, which git sets for both merges and rebases, so it covers the upstream changes only, never your own replayed commits.

**Install `pre-commit` alongside it.** The auto-commit is a plain `git commit`, so it triggers whatever `pre-commit` hook is installed. Without one, a secret written into the doc by an unattended run would reach local history unscanned.

```bash
cp tools/hook-templates/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**What success looks like.** After the next pull that changes something relevant, a log appears at `~/.claude/hook-logs/<repo>-post-merge.log`, and for a git vault a local commit titled `Auto-update repos/<repo>/index.md via post-merge hook (<sha>)` shows in `git -C <vault> log`. A run that failed also adds a line to `~/.claude/hook-logs/FAILURES.log`, which the hook shows once at the start of the next run. Nothing is pushed.

**What the run is allowed to do.** The run uses `--restricted`, which `claude --help` describes as removing the code-running tools, confining the file tools to the working directories, and ignoring user, project and local settings files. Combined with an explicit minimal `--mcp-config` and `--strict-mcp-config` pair, the run has only the vault tools it needs. Every changed filename is passed as untrusted data, in a fenced JSON block, rather than as an instruction. Names that look like secrets (`.env`, keys, `credentials.json`, `*.tfvars`, `.npmrc` and similar) are dropped before the model sees the list. If a future `claude` release rejected `--restricted`, the hook logs that fact with the CLI version in `FAILURES.log`.

**What it checks afterwards.** Independently of what the run says about itself, the hook compares the vault's `git status` before and after (file modification times, for a vault that is not a git repo).

- Anything new outside the doc is **flagged, never undone**. The paths go into the log and `FAILURES.log`, and the run is recorded with exit code 3.
- The hook cannot tell the model's write from a note you or another session wrote in the same minutes, so deleting or reverting by guesswork could destroy real work.
- Check with `git -C <vault> status`, then commit or discard what you find.

A successful update is **auto-committed locally**, only the doc itself, and never pushed. Pushing stays a manual, human-reviewed step (see [`daily-workflow.md`](../runbooks/daily-workflow.md)). A stray write elsewhere in the vault therefore stays uncommitted for you to look at.

**Installing it in a repo other than the vault.** The repo name and doc target derive from the folder the hook is installed in (lowercased unless `repoNameCase: keep` is set in [`vault-config.md`](vault-config.md); the git remote is never used), so copying the file unchanged into another repo already targets that repo. The vault location does not derive that way. `VAULT_ROOT` is resolved in this order:

1. the `VAULT_ROOT` environment variable;
2. the repo's own root, if its path is listed in `~/.claude/hook-configs/vault-root` (a repo that is itself one of your vaults documents itself);
3. the first line of `vault-root`;
4. the repo's own root.

Git runs hooks without `VAULT_ROOT` set, so the order matters: a vault that is listed documents into itself even when the first line names a different vault. The check is against the file, never against what the repo contains, so a pull cannot turn a repo into its own vault by adding a `vault-config.md`.

If `VAULT_ROOT` is wrong, the check for the repo doc catches it: the hook logs and exits rather than running against the wrong repo.

**One Obsidian server per hook config.** The hook's MCP config (`~/.claude/hook-configs/obsidian-mcp-config.json`) names one Obsidian server, and the Local REST API plugin serves only the vault that Obsidian window has open. A `post-merge` hook for a vault that is not the open one is therefore expected to fail its write check and leave the doc unchanged. That case has not been run against a real pull. Set `MCP_CONFIG` per repo, pointing at a server for that vault, if you need it.

**What it writes.** The doc's frontmatter carries `last-populated`, `source-commit` and the tags `repo-doc` and the repo name. The hook keeps those current and never changes the `## Hand-written notes` section.

**Per-vault settings.** `reposPath`, `repoNameCase` and `backend` in [`vault-config.md`](vault-config.md) apply here too. For a vault that is not a git repo, see [Hooks in `vault-config.md`](vault-config.md#hooks).

**Overrides.** `HOOK_LOG_DIR`, `MCP_CONFIG`, `TIMEOUT_SECS`, `RETRY_DELAY` and `KILL_SWITCH` can be set as environment variables, mainly for the tests.

**Stopping it.** Create `~/.claude/hook-templates/DISABLED` (any content) to stop the hook in every repo on the machine, or `~/.claude/hook-logs/.<repo>.disabled` to stop it in one.

Test it with `bash tools/hook-templates/test-post-merge.sh`. It builds its own temporary git fixtures and a stub `claude`, so it touches nothing real, and it takes several minutes on Windows. See [`testing.md`](testing.md).

### `pre-push`: a nudge while you are already pushing

A genuine git `pre-push` hook. It warns, never blocks, if the vault has unpushed commits at the moment you push something else, when you are already in a pushing frame of mind.

```bash
cp tools/hook-templates/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

- It stays silent if the repo being pushed is the vault, and throttles repeat warnings to one every ten minutes.
- It reads the vault's default branch from `origin/HEAD` (falling back to `main`).
- It sources `vault-lib` from next to itself or from `~/.claude/hook-templates/`, where the installer puts it. An installed copy under `.git/hooks` has no neighbour, so run the installer, or copy `vault-lib` into `~/.claude/hook-templates/` by hand. If it cannot find the helper it exits quietly, so a push is never held up.

Test it with `bash tools/hook-templates/test-pre-push.sh`. See [`testing.md`](testing.md).

## Installing session hooks

A **session hook** is registered in a Claude Code settings file instead of being copied into `.git/hooks/`, so there is no `chmod +x`. Settings changes take effect in a new session.

### `session-start-vault-check`: unpushed-commit reminder

A `post-merge` run in some other repo can auto-commit a doc update into the vault on a day you never open the vault. This hook is how you still find out. It only reminds. It never pushes.

It has to fire whatever repo you are in, so it is registered in your **user-scope** Claude Code settings (typically `~/.claude/settings.json`), twice: under `SessionStart`, and under `PostToolUse`, where it is throttled to once an hour so a long session is nudged rather than spammed. A session start is never throttled.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "VAULT_ROOT=\"<path-to-your-vault-clone>\" bash \"<path-to-your-vault-clone>/tools/hook-templates/session-start-vault-check\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "VAULT_ROOT=\"<path-to-your-vault-clone>\" bash \"<path-to-your-vault-clone>/tools/hook-templates/session-start-vault-check\""
          }
        ]
      }
    ]
  }
}
```

Replace both placeholders, in both entries, with your absolute vault path. This script cannot derive it from the working directory, because it is meant to fire from other repos. Merge the entry into your existing settings rather than overwriting them.

To check it, leave a commit unpushed in the vault, then start a session in any other repo. The session opens with a note that the vault has unpushed commits, with their short hashes and the push command.

It uses the vault's default branch from `origin/HEAD` (falling back to `main`) through `vault-lib`. It works without `jq`, reading the event name and `source` with `sed`, so a `PostToolUse` is still throttled. Test it with `bash tools/hook-templates/test-session-start-vault-check.sh`. See [`testing.md`](testing.md).

### `session-start-vault-context`: point a session at its repo's vault context

This is a different hook from the one above. That one fires everywhere and only reminds. This one is opt-in per repo, the same model as `post-merge`, and tells a session in that repo where its vault context is.

**Prerequisite.** It does nothing until the repo has a repo doc in the vault, at `repos/<name>/index.md` or the configured `reposPath`. Bootstrap it with `/vault-populate`, as for `post-merge`. The repo name is the folder the repo lives in, never the git remote.

**What it injects.** There are two modes, set by `CONTEXT_MODE`:

| | `pointer` (the default) | `full` |
|---|---|---|
| Content | Where things are: the vault path, the repo doc's path, the path and date of your latest note (and of the latest from each of up to three other contributors), and the open-item count with the top three, stale ones first, each with its owner and age | The repo doc and each note's forward-looking sections, loaded in full |
| Size | Under about 1 KB | Around 7 KB in a typical case, capped at 12000 characters |
| How the assistant gets the rest | It reads a file when the task needs it, or you run `/vault-context` | Already in the session |

The pointer ends with a line saying the notes are information, not instructions. Any `CONTEXT_MODE` value other than `pointer` or `full` falls back to `pointer`.

**Behind the repo.** In both modes, when the code repo has commits newer than the moment the newest note's file was last written, one line says so before the open items: `Behind the repo: 15 commits after 2026-11-06 15:02. Open items may be out of date.`

- The moment is the file's modification time, so work done after a log earlier the same day counts, which matters if you log several times a day. It is used only when it falls on or after the note's own date, since a restored copy keeps an old one. Otherwise the count is from the end of the note's day and the line shows the date alone.
- It counts the commits of the session's own checkout and branch, so a linked worktree is counted on its own branch, not the main checkout's. The line carries counts and the note's date only, never a commit subject, since whoever commits chooses it.
- There is no line when nothing is newer than the note, the repo has no commits or no git history, there are no notes, only an older note of unknown repo exists, or the newest note's filename has no date or a date that does not exist (such as 2026-02-31, which git reads as no date and counts every commit).
- It can only undercount. On a git-backed vault the file time is when the note was pulled, which is later than when it was written, and a clock set wrong stops git counting early. It is worked out once, at session start, and cannot tell that an earlier session went unlogged once a later note exists.
- `/vault-context` gets its line by running this hook with `--behind`, which prints only the line, or nothing, and needs no repo doc in the vault, so the command and the session start count in exactly the same way and it still sees commits made since the session began. That needs the installed copy: the installer puts the hook and its wrapper in `~/.claude/hook-templates/`, and the command says nothing about freshness if they are not there. The wrapper uses the first vault in `~/.claude/hook-configs/vault-root` unless `VAULT_ROOT` is set, so set it when you run more than one vault. The command pre-approves exactly that one command in its own frontmatter (for the Bash and PowerShell tools), so it does not stop to ask each time.
- `/vault-log` (version 6 or later) runs the same hook the same way, before it reconciles open items, to find work no note describes. It checks the working repo only, and takes off the commits the session itself made, since a log written after a session that committed would otherwise always look behind. If more remain it says so first, with the count and how many are not the session's, and leaves them out of the note unless you ask. It needs the same installed hook and has the same pre-approved command. With nothing newer than the newest note it says nothing.
- `/vault-log` (version 7) also runs the hook with `--doc-behind`, which prints `Repo doc: 41 commits and 18 files since its source-commit. Consider /vault-populate.` when the repo doc has fallen behind the code, or nothing. It is off unless `repoDocBehindCommits` is set in `vault-config.md`. It is silent when the doc is current, under the threshold, missing, or outside git, and says so once when the doc has no `source-commit` or names one that is not in the history. `/vault-log` puts the line in its report and offers `/vault-populate`. It never runs it or edits the doc, because the result is a draft to be read. Like `--behind`, it needs no repo doc to be found to stay quiet, counts only, and only checks the working repo.
- `/vault-log` (version 8) also checks, before it carries an untouched item forward, whether a later commit mentions it. It only looks for terms in backticks in the item's text (an identifier, a flag or a path), in the working repo, since the item's opened date, by commit message and by path. It uses hashes only and never repeats a commit message. A hit puts the item in a "possibly done, unverified" group in the one question message, and the item is still carried unless you say otherwise. A match never ticks anything, and an item with no backticked term is not searched.

| Variable | Mode | Default | Meaning |
|---|---|---|---|
| `CONTEXT_MODE` | both | `pointer` | `pointer` or `full` |
| `CONTEXT_POINTER_MAX_ITEMS` | pointer | 3 | How many open items the pointer lists |
| `CONTEXT_MAX_CONTRIBUTORS` | both | 3 | How many other contributors' latest notes are named (pointer) or loaded (full); your own does not count |
| `CONTEXT_MAX_OPEN_ITEMS` | full | 10 | Open items listed |
| `CONTEXT_MAX_CHARS` | full | 12000 | Output cap, dropping the furthest-back other note first |
| `UPDATE_MAX_LINES` | full | 40 | Lines kept from an appended `## Update ...` section |
| `REMIND_EVERY_MINUTES` | `--remind` | 120 | Minutes between reminders within one session |
| `REMIND_CHECK_MINUTES` | `--remind` | 60 | Minutes before a session looks again after finding nothing to say |

`staleOpenItemDays` (default 30) comes from `vault-config.md` in both modes.

**Install.** It is not a native git hook, so there is no `.git/hooks/` copy. The installer provides `~/.claude/hook-templates/session-start-vault-context.sh`, a wrapper that takes `VAULT_ROOT` from the first line of `vault-root` when it is not already set. Register the wrapper in *that other repo's* `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/hook-templates/session-start-vault-context.sh\""
          }
        ]
      }
    ]
  }
}
```

Claude Code project settings are version-controlled, so this can be committed and shared with a team, as long as every contributor has run the installer. Without the installer, point the command at the `session-start-vault-context` file in your vault clone and set `VAULT_ROOT` in the command, as for the reminder hook above.

**Reminding during the session (optional).** The same wrapper can run as a `Stop` hook with `--remind`. It is off until `unloggedReminderCommits` is a positive whole number in `vault-config.md`. After that, when the repo is at least that many commits past your newest note, it shows one message such as `Behind the repo: 5 commits after 2026-11-07 00:20. Run /vault-log before you finish.` A `Stop` hook runs after every turn, not once when the session ends, and Claude Code discards a `SessionEnd` hook's message, so it speaks at most once per session per `REMIND_EVERY_MINUTES`, keeping its window in a file per session under `~/.claude/hook-logs/`. It never blocks the turn and shows counts only. Listing the notes is the slow part, about a second and a half on a Windows machine, so it does that at most once every `REMIND_CHECK_MINUTES` (default 60) per session when it has nothing to say, and not at all while a reminder window is running. With the setting off it exits at once. Register it beside the `SessionStart` entry:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/hook-templates/session-start-vault-context.sh\" --remind"
          }
        ]
      }
    ]
  }
}
```

**What success looks like.** A new session in that repo starts with a block headed `--- Vault context pointer for <repo> (auto-loaded) ---` in the default pointer mode, or `--- Vault context for <repo> (auto-loaded) ---` in `full` mode. `/vault-context` treats only the second as already loaded, so it still loads the notes after a pointer. If nothing appears, the usual causes are a missing repo doc, a settings file that is not in that repo's `.claude/`, or a session that was resumed.

**Details that explain what you see.**

- It skips a `resume` and a mid-session `/compact`, whose own summary already carries what it injected earlier. It still injects when its input is malformed or missing, rather than go quiet on a genuine session start.
- It reads the vault directly off disk, the same deliberate exception to the MCP-only convention as the reminder hook, because it runs before the model's tool loop starts.
- A repo with no notes yet gets the newest older note that has no repo in its filename, labelled as such, so a vault in the old naming keeps working.

Test it with `bash tools/hook-templates/test-session-start-vault-context.sh`. See [`testing.md`](testing.md).

### `vault-lib`: shared helpers

Two functions, sourced by `pre-push` and `session-start-vault-check` so that there is one copy to fix: `vault_branch` (the vault's default branch from `origin/HEAD`, else `main`) and `vault_unpushed_hashes` (short hashes only, never commit subjects, which anyone who can commit chooses). Test it with `bash tools/hook-templates/test-vault-lib.sh`.

## Why there is no auto-push

Deliberately rejected. Having a hook push its own commit would remove the one human-review checkpoint the "no PR gate" model depends on (see [Push policy](../runbooks/using-the-vault.md#push-policy-direct-to-main-no-required-pr)), for AI-generated content going into a shared knowledge base. It would also risk unattended non-fast-forward races between people's machines.

The hooks shrink the window in which an update sits unpushed and unseen, and do not close it. Someone who goes quiet across every repo for a long stretch is still a blind spot, and that is an accepted limitation.

## Working across more than one vault

If you work in two team vaults, register the vault hooks once per vault, in user-scope `~/.claude/settings.json`, each entry with its own `VAULT_ROOT`:

- `session-start-vault-check` under both `SessionStart` and `PostToolUse`. It is about the vault, not the repo you are in, so it should fire everywhere and not be made conditional on the repo. One entry per vault gives one reminder for each vault that has unpushed commits.
- `session-start-vault-context` under `SessionStart`. It names the repo from the folder it runs in and says nothing when that vault holds no doc for the repo (`reposPath`), so one entry per vault does not clash: each vault speaks only for the repos it documents. If both vaults hold a doc for the same repo, both entries load context for it.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "VAULT_ROOT=\"<vault-a>\" bash \"<vault-a>/tools/hook-templates/session-start-vault-check\"" },
        { "type": "command", "command": "VAULT_ROOT=\"<vault-a>\" bash \"<vault-a>/tools/hook-templates/session-start-vault-context\"" },
        { "type": "command", "command": "VAULT_ROOT=\"<vault-b>\" bash \"<vault-b>/tools/hook-templates/session-start-vault-check\"" },
        { "type": "command", "command": "VAULT_ROOT=\"<vault-b>\" bash \"<vault-b>/tools/hook-templates/session-start-vault-context\"" }
      ] }
    ]
  }
}
```

Add the two `session-start-vault-check` entries under `PostToolUse` as well, as in the single-vault example above.

`~/.claude/hook-configs/vault-root` lists one vault path per line. Run `install-claude-config --vault <path>` once for each vault: it adds the path if it is not already listed, and the first line stays the default for hooks installed in other repos. `--force` makes the vault you name the default instead. The explicit `VAULT_ROOT=` in each registered `SessionStart` command still decides for those hooks. A listed vault's own `post-merge` hook documents into itself; run the installer for every vault that has one.

The hooks that talk to Obsidian (`post-merge`) and your interactive session reach whichever vault Obsidian has open, through one `obsidian` MCP server. Set up the shared key and port, and open the right vault before you work, as described in [Using more than one vault on one machine](mcp-setup.md#using-more-than-one-vault-on-one-machine-optional).

## Running the model-driven test harness from GitHub Actions (optional)

This section is for a repository admin who wants to run the command tests on GitHub. Skip it otherwise.

`tools/command-templates/test/run-command-tests.mjs` makes real `claude -p` calls, so it is not part of the automatic CI checks. `.github/workflows/model-harness.yml` runs it on demand, using a Claude subscription token. This repository is public, so the setup keeps that token away from anything but a deliberate, approved run on `main`.

One-time setup (repository admin):

1. In **Settings → Environments**, create `model-harness`. Add yourself as a **required reviewer**, and under **Deployment branches and tags** choose *Selected branches and tags* and allow only `main`.
2. Generate a token with `claude setup-token` and store it as an **environment** secret, not a repository secret:

   ```bash
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --env model-harness --repo <owner>/<repo>
   ```

   A repository-level secret with the same name would also be readable from any branch, which defeats the environment, so delete it if one exists (`gh secret delete CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>`).
3. Run it from **Actions → model harness (manual) → Run workflow** on `main`, pick a scenario (start with one), and approve the pending deployment.

What the workflow does and does not allow:

- It only starts from `workflow_dispatch`, and refuses to run off `main` or for another actor.
- Inputs are fixed choices, and permissions are read-only.
- Actions and the `claude` CLI version are pinned.
- It uses the stub REST API backend only, so nothing is fetched from a package registry at run time.
- It has a 30-minute limit and one run at a time.

The token is visible to the `claude` process during a run, so only run scenarios you have read. Revoke the token and delete the environment secret if you stop using this.

## Bot reviewer for pull requests (optional)

GitHub does not let you approve your own pull request, and a solo repository has no second reviewer. `.github/workflows/pr-review.yml` stands in for one: it has Claude read a pull request's diff and post what it finds as a comment headed "Bot review (advisory, not an approval)". It never approves, requests changes or merges, so you still decide.

It reuses the `model-harness` environment and `CLAUDE_CODE_OAUTH_TOKEN` secret from the section above, so there is nothing new to set up. Run it from **Actions → bot review (manual) → Run workflow** on `main`, give the pull request number, and approve the pending deployment.

Because this repository is public and a pull request is untrusted text, it is built to keep the token away from it:

- It starts only from `workflow_dispatch`, runs only on `main` for the owner, and fetches the diff as a file without checking out or running the branch.
- The step that holds the token has read-only permissions and only the `Read` tool, with the runner's credential and config folders denied by path.
- A second job, which never sees the token, has `pull-requests: write` and posts the comment.
- The diff is cut at 400 KB and the comment at 6000 characters. The model is told to read the diff in chunks to its last line and to say if it could not. A very large pull request can still go unreviewed in part, so keep them small or split them.

Treat the review like any other model output: it can miss things and it can be wrong. `tools/testing/test-structure.sh` checks that these properties still hold.

## Related

- [`statusline.md`](statusline.md): an optional status line for Claude Code, separate from the vault commands and hooks
- [`vault-config.md`](vault-config.md): per-vault settings the commands and hooks read
- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md): the manual workflows this automates
- [`../runbooks/daily-workflow.md`](../runbooks/daily-workflow.md): where hooks fit into a real session, and the worked example of catching up on unpushed commits
