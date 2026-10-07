# Automation layer (optional)

> **Scope:** once the manual workflow in [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) feels natural, this is how to stop having to remember it. Everything here is optional — the vault is fully useful without any of it, and there's no shame in never installing any of this.

There are two independent layers here. Install either, both, or neither:

- **Slash commands and skills** (`tools/command-templates/`, `tools/skill-templates/`) — turn the plain-English prompts from the usage guide into named, one-word commands, and load the vault's conventions automatically so your assistant doesn't need reminding. Install once per machine; works from inside *any* repo you `cd` into.
- **Git hooks** (`tools/hook-templates/`) — a specific, heavier layer for a repo you deliberately want auto-documenting itself in the vault on every pull, unattended, without anyone asking. A real trade-off (a headless AI run kicks off on every pull of that repo), not something to install everywhere just because you can. Most repos should just use the commands/skills above and never need this.

## Slash commands and skills

**Easiest: the installer.** From a clone of this repo, on each machine:

```bash
bash tools/install-claude-config.sh --vault <absolute path to your vault>
```

It copies the three commands, the two skills and the hook templates into `~/.claude/`, writes `~/.claude/hook-configs/vault-root` so hooks installed in other repos can find the vault, and warns about anything missing (`claude`, `jq`, `timeout`). It is idempotent, so re-run it after pulling this repo; `--check` reports what is current, outdated or missing without changing anything, and `--dry-run` shows what it would do. Pass `--no-skills` for a vault whose layout differs from the team default: the two skills describe the team layout (`daily-notes/<author>/`, `repos/<name>/`) and trigger on any `obsidian` MCP call, so they would contradict a different layout. With `--backend mcpvault` it also writes the hook MCP config. On Windows, `tools\install-claude-config.ps1` takes the same arguments and runs it under Git for Windows' bash (you may need `powershell -ExecutionPolicy Bypass -File ...` on a machine where script execution is restricted). Commands and skills load in a **new** Claude Code session, and per-repo hooks (`post-merge`, `pre-commit`) still need copying into that repo's `.git/hooks` as described below. `bash tools/test-install-claude-config.sh` tests the installer against a throwaway directory.

Or by hand, once per machine:


```bash
cp tools/command-templates/vault-context.md ~/.claude/commands/vault-context.md
cp tools/command-templates/vault-log.md ~/.claude/commands/vault-log.md
cp tools/command-templates/vault-populate.md ~/.claude/commands/vault-populate.md
mkdir -p ~/.claude/skills/obsidian-mcp-setup ~/.claude/skills/obsidian-vault-conventions
cp tools/skill-templates/obsidian-mcp-setup/SKILL.md ~/.claude/skills/obsidian-mcp-setup/SKILL.md
cp tools/skill-templates/obsidian-vault-conventions/SKILL.md ~/.claude/skills/obsidian-vault-conventions/SKILL.md
```

(Windows/PowerShell: same idea with `Copy-Item`/`New-Item -ItemType Directory` in place of `cp`/`mkdir -p`.)

This gives you three commands — `/vault-context` (read the hub note + recent daily notes at session start), `/vault-log` (write today's session as a daily note), and `/vault-populate` (bootstrap a `repos/<name>/` doc for a codebase) — plus two skills that load this vault's conventions and MCP setup facts automatically whenever they're relevant, rather than requiring you to go find them.

Installed at **user scope** (`~/.claude/commands/`, `~/.claude/skills/`), not this repo's own project-level `.claude/`, since `/vault-populate` in particular needs to work from inside whichever *other* repo you're documenting, not just from within the vault itself. Claude Code doesn't track either folder in git (they live in your home directory, outside any repo), so each clone needs this one-time copy step, and a restart to pick up new commands/skills.

These are deliberately condensed pointers back to the runbooks, not a second copy of the full content to keep in sync — if the two ever disagree, the runbooks win.

`/vault-log` also reads an optional `vault-config.md` at the vault root, for vaults that lay their notes out differently from the defaults in the runbook; see [`vault-config.md`](vault-config.md). With no such file it behaves exactly as described above, and it works with either `obsidian` MCP backend (the Local REST API plugin, or MCPVault). Each template carries a `bedrock-template: <name>, version N` comment so a machine's installed copy can be compared against the one in this repo.

## Git hooks

Four optional hooks, each independently installable, tracked (as source) under `tools/hook-templates/`. Git never tracks the installed copies themselves (`.git/hooks/` isn't part of a repo's history), so each clone that wants a hook needs this one-time copy step.

### `pre-commit`: secret scan before it enters history

Scans staged changes for likely secrets (API keys, tokens, private key blocks, connection strings with embedded passwords) before a commit lands, even locally. This is the cheapest point to catch one, since an uncommitted change costs nothing to fix and a pushed one is genuinely harder to walk back (see the "Redact real credentials, tenant IDs, and personal data" line in [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md)).

```bash
cp tools/hook-templates/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Uses [`betterleaks`](https://betterleaks.com/) only, no other engine. Betterleaks is a newer secrets scanner with substantially better recall than older entropy-based tools (its token-efficiency detection scored around 98.6% versus roughly 70% for plain entropy detection on the CredData benchmark).

**No hand-rolled regex fallback if it isn't installed, deliberately.** A home-grown pattern set would be weaker than a real tool (the whole reason betterleaks is used here is that regex/entropy detection alone has poor recall), while adding real code and test surface of its own, for a false sense of coverage arguably worse than knowing plainly there's none. Instead, no scanner found means no scan at all, just a loud, *unthrottled* reminder every commit to go install it. That's a small enough per-commit cost, and honest about the actual gap, unlike a throttled nag that could let "we're not really checking anything" go unnoticed for a while.

**Deliberately scoped to secrets, not general PII.** Names, emails, and phone numbers don't have a regex-tractable shape in prose the way a key or token does, and a general PII scanner here would false-positive on ordinary sentences constantly and still miss creative phrasing, which teaches people to reach for `--no-verify` on every commit. PII redaction stays the documented human-review discipline it already is; this hook only adds a machine-checkable backstop for the narrower, more mechanically-detectable case.

**Non-blocking by default**, same philosophy as `pre-push` below. A real finding prints a loud warning but still lets the commit through, because a hard block on a false positive in a personal-notes vault trains people to bypass the hook entirely. Set `PRECOMMIT_SECRET_SCAN_STRICT=1` (shell profile, or a repo-local `.envrc`) to make a real finding block the commit instead, which is worth it for a team vault where "warn and trust everyone to act on it" isn't a strong enough guarantee. A confirmed false positive can still go through with `git commit --no-verify`, or by adding an allowlist rule, a `.gitleaksignore` entry or a repo `.gitleaks.toml` (betterleaks reads that same config file format even though it isn't the gitleaks tool itself), if it's a recurring one.

**Testing this hook:** `bash tools/hook-templates/test-pre-commit.sh`. It stubs `betterleaks` on `PATH`, so nothing needs installing, and covers the no-staged-changes and no-scanner cases (and that the install notice is never throttled), warn versus strict (which values of `PRECOMMIT_SECRET_SCAN_STRICT` block), what happens for each scanner exit code, the exact scanner arguments, deletions, first commits and awkward file names, and a real `git commit` being blocked, allowed with a warning, or bypassed with `--no-verify`. If `betterleaks` is installed it also runs two checks against the real scanner. A regression test covers a file renamed and edited in one commit (once missed by the scan). See [`testing.md`](testing.md).

### `post-merge` — self-documenting repo

After a pull lands on the default branch, this backgrounds a headless AI run that updates `repos/<this-repo-name>/index.md` from the diff — a repo documenting its own tooling changes automatically, with no one having to ask.

```bash
cp tools/hook-templates/post-merge .git/hooks/post-merge
chmod +x .git/hooks/post-merge
```

It needs a standalone `--mcp-config` file naming just the `obsidian` server (not your full Claude Code config, which may have other servers configured) at `~/.claude/hook-configs/obsidian-mcp-config.json` — ask your assistant to generate this from your existing MCP registration if it doesn't exist yet.

This hook runs with `--restricted` plus an explicit, minimal `--mcp-config`/`--strict-mcp-config` pair — confined to the checkout, with only the vault-write tools it actually needs, never broad unattended access. It also treats every changed filename as untrusted data rather than an instruction (a maliciously-named file shouldn't be able to redirect what the hook does), and verifies after every run — independent of what the run's own output claims — that only the intended doc was actually written. A brand-new unexpected file is removed outright (provably safe, it didn't exist before the run); an unexpected modification to a file that already existed is reverted to its last-committed content via `git checkout --`, which only works on already-tracked content — confirmed by this project's own test suite, see below.

A successful update is **auto-committed locally** (so it can't be silently lost or overwritten before you notice it) but **never auto-pushed** — pushing stays a manual, human-reviewed step (see [`runbooks/daily-workflow.md`](../runbooks/daily-workflow.md)), so nothing reaches the shared vault without someone having looked at `git status` first.

**Install `pre-commit` alongside this hook, not as a separate optional extra.** The auto-commit above is a plain `git commit`, which triggers whatever `pre-commit` hook is installed, same as any commit — but if you've installed `post-merge` without also installing `pre-commit`, that auto-commit has no secret-scanning at all. The output-validation check earlier only confirms *which* file the run touched, never *what's in it*; a real secret written into the doc by an unattended run would sail straight into local history unscanned. Install both in the same pass:

```bash
cp tools/hook-templates/post-merge .git/hooks/post-merge
cp tools/hook-templates/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/post-merge .git/hooks/pre-commit
```

**Installing this into a repo other than the vault itself, deliberately:** the repo name and doc target auto-derive from wherever the hook is actually installed (its own git remote), so copying it unmodified into another repo's `.git/hooks/post-merge` already names and targets that repo correctly. The one thing that never auto-derives is `VAULT_ROOT` at the top of the script — set it as an environment variable (or edit the script's own default) to an explicit absolute path to your vault's own checkout, since the default (deriving from the current repo) would otherwise resolve to that *other* repo, not the vault. `HOOK_LOG_DIR`, `MCP_CONFIG`, `TIMEOUT_SECS`, `RETRY_DELAY`, and `KILL_SWITCH` are all environment-overridable the same way, mainly useful for the test suite below rather than day-to-day use. The hook also refuses to run at all until `repos/<that-repo>/index.md` already exists in the vault — bootstrap it once via `/vault-populate` (or ask your assistant directly) before installing this hook; it refines an existing doc rather than creating one from nothing. That same check is also what catches a forgotten `VAULT_ROOT` edit: it fails safe (logs and exits) rather than silently running against the wrong repo.

**Per-vault settings:** `post-merge` also reads the optional [`vault-config.md`](vault-config.md) (`reposPath` for where the doc lives, `backend` for which MCP tool names the run may use), and can find the vault from a one-line `~/.claude/hook-configs/vault-root` file when `VAULT_ROOT` isn't set. If the vault is **not a git repo** it only flags unexpected writes (never reverts, removes or commits), see [Hooks in `vault-config.md`](vault-config.md#hooks).

**Testing this hook:** `bash tools/hook-templates/test-post-merge.sh` is a real, isolated test suite covering the branch guard, the diff filter (every kind of noise and secret-shaped file, one by one), the kill switch, the `jq`-fencing requirement, the retry-on-127 behaviour, the prompt and arguments sent to `claude`, the run log, the local-only commit, the failures log, repo-name derivation, and the output-validation logic in detail, including the new-file-vs-modified-file distinction above, plus a vault that is not a git repo, a configurable doc path, `VAULT_ROOT_FILE`, and both MCP backends. It builds its own temp git fixtures and a stub `claude` binary, nothing it does touches this machine's real vault or logs. Worth running after any edit to `post-merge` itself, it caught two real bugs during development (see the `post-merge` script's own comments on the output-validation section for the details) that comments and manual testing alone had missed. It takes several minutes on Windows. See [`testing.md`](testing.md).

### `session-start-vault-check` — unpushed-commit reminder

The gap this closes: a `post-merge` hook running in some *other* repo can auto-commit a doc update into this vault as a background side effect, on a day you never consciously open this vault at all. Nothing about "I finished working in repo X" naturally surfaces "the vault now has an unpushed commit" — this hook is how you'd still find out. It never pushes anything itself, only reminds.

Because it needs to fire regardless of which repo you're actually in, it can't live in this repo's own project-level settings — it's a one-time, per-machine step in your **user-scope** Claude Code settings (typically `~/.claude/settings.json`), registered twice: once under `SessionStart` (fires at the start of every session, anywhere), and once under `PostToolUse` (fires periodically during a long session that never restarts, throttled so it nags rather than spams):

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

Replace both `<path-to-your-vault-clone>` placeholders with your real, absolute vault path — this script can't derive it from the current working directory the way `post-merge` can, since it's designed to fire from sessions in *other* repos. Merge this into your existing settings file rather than overwriting it if you already have other hooks configured there. Requires a restart to take effect.

**Testing this hook:** `bash tools/hook-templates/test-session-start-vault-check.sh`. It builds a vault with a local bare `origin` so there is a real unpushed gap, and covers the silent cases, the count, hashes and commands in the reminder, that commit subjects are never echoed, that `SessionStart` is never throttled while `PostToolUse` is (including both sides of the cooldown), `compact`, and failing open without `jq` or on bad input. See [`testing.md`](testing.md).

### `session-start-vault-context` — auto-load a repo's own vault context

**Not the same hook as `session-start-vault-check` above** — that one fires everywhere and only ever reminds you the vault has unpushed commits, it never loads content. This one auto-loads `repos/<this-repo-name>/index.md` plus the single most recent daily note (across every contributor, by actual file modification time — not a filename sort, which would pick the wrong note on any day with more than one written) at the start of a session in a *specific* repo you've deliberately opted in, so work resumes without asking for `/vault-context` every time.

Opt-in **per repo**, the same model as `post-merge` — a repo asks for this deliberately, it isn't on by default anywhere. Unlike `post-merge` and `pre-push`, though, this isn't a native git hook (`SessionStart` is a Claude Code hook, not a git one, so there's no `.git/hooks/` copy step and no `chmod +x`). It's registered the same way as `session-start-vault-check` above, but in *that other repo's own* `.claude/settings.json` rather than your user-scope one, pointing straight at this file's path in your vault clone:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "VAULT_ROOT=\"<path-to-your-vault-clone>\" bash \"<path-to-your-vault-clone>/tools/hook-templates/session-start-vault-context\""
          }
        ]
      }
    ]
  }
}
```

Because Claude Code project settings **are** version-controlled (unlike `.git/hooks/`, which never are), this can genuinely be committed into that other repo's own tracked `.claude/settings.json` and shared with the whole team in one commit — but only if `VAULT_ROOT` resolves the same way on every contributor's machine (e.g. everyone clones the vault to the same path by convention). If your team's vault path isn't consistent across machines, keep this a manual per-machine step instead, the same as `session-start-vault-check`.

Silent no-op until that repo already has a `repos/<name>/index.md` in the vault (or the doc at the vault's configured `reposPath`) — bootstrap it first via `/vault-populate`, same precondition as `post-merge`. Where that doc and the daily notes live can be set per vault in the optional [`vault-config.md`](vault-config.md); If the note also has appended `## Update ...` sections (what `/vault-log` adds when a note for the same session already exists), the most recent one is loaded too (capped at 40 lines, override with `UPDATE_MAX_LINES`) with a count of earlier ones left out, since an append can't rewrite the two forward-looking sections. `bash tools/hook-templates/test-session-start-vault-context.sh` tests the defaults, the config keys and the update handling. Also silently skips on a mid-session `/compact` (its own summary already carries whatever this injected earlier), and fails open — still injects — on malformed or missing stdin, rather than risk silently going dark on a genuine session start.

Reads the vault directly off disk, same deliberate MCP-only exception as `session-start-vault-check`: this runs before the model's own tool-calling loop begins.

### `pre-push` — a nudge at the moment you're already pushing

A genuine git `pre-push` hook: warns (never blocks) if the vault has unpushed commits sitting around, at the exact moment you push something else — on the theory that you're already in a "pushing" mindset right then, so the reminder is more likely to actually get acted on.

```bash
cp tools/hook-templates/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Stays silent if the repo you're actually pushing *is* the vault — its own unpushed commits are exactly what that push is about to send.

**Testing this hook:** `bash tools/hook-templates/test-pre-push.sh`. It checks that the hook always exits 0, speaks only on stderr, stays silent unless there is really something unpushed, throttles repeat warnings (both sides of the cooldown), never echoes commit subjects, and works as a real installed hook during a real `git push`. See [`testing.md`](testing.md).

### Why not just auto-push?

Deliberately rejected. Having a hook push its own commit immediately would remove the one human-review checkpoint the whole "no PR gate" governance model depends on (see [Push policy](../runbooks/using-the-vault.md#push-policy-direct-to-main-no-required-pr)) — specifically for AI-generated content landing in a shared knowledge base — and risks unattended non-fast-forward races between multiple people's machines with nobody there to resolve them. These hooks shrink the window an update can sit unpushed and unseen; they don't close it completely. Someone who goes quiet across every repo for a long stretch is still a blind spot, and that's an accepted, known limitation rather than something solved here.

## Related

- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) — the manual workflows this automates
- [`../runbooks/daily-workflow.md`](../runbooks/daily-workflow.md) — where hooks fit into an actual session, and the worked example of catching up on unpushed commits

## Running the model-driven harness from GitHub Actions (optional)

`tools/command-templates/test/run-command-tests.mjs` makes real `claude -p` calls, so it is not part of the automatic CI checks. `.github/workflows/model-harness.yml` runs it on demand, using a Claude subscription token. This repository is public, so the setup keeps that token away from anything but a deliberate, approved run on `main`.

One-time setup (repository admin):

1. In **Settings → Environments**, create `model-harness`. Add yourself as a **required reviewer**, and under **Deployment branches and tags** choose *Selected branches and tags* and allow only `main`.
2. Generate a token with `claude setup-token` and store it as an **environment** secret, not a repository secret:

   ```bash
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --env model-harness --repo <owner>/<repo>
   ```

   A repository-level secret with the same name would also be readable from any branch, which defeats the environment, so delete it if one exists (`gh secret delete CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>`).
3. Run it from **Actions → model harness (manual) → Run workflow** on `main`, pick a scenario (start with one), and approve the pending deployment.

What the workflow does and does not allow: it only starts from `workflow_dispatch`; it refuses to run off `main` or for another actor; inputs are fixed choices; permissions are read-only; actions and the `claude` CLI version are pinned; it uses the stub REST API backend only, so nothing is fetched from a package registry at run time; and it has a 30-minute limit and one run at a time. The token is visible to the `claude` process during a run, so only run scenarios you have read. Revoke the token and delete the environment secret if you stop using this.
