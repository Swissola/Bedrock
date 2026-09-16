# Automation layer (optional)

> **Scope:** once the manual workflow in [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) feels natural, this is how to stop having to remember it. Everything here is optional — the vault is fully useful without any of it, and there's no shame in never installing any of this.

There are two independent layers here. Install either, both, or neither:

- **Slash commands and skills** (`tools/command-templates/`, `tools/skill-templates/`) — turn the plain-English prompts from the usage guide into named, one-word commands, and load the vault's conventions automatically so your assistant doesn't need reminding. Install once per machine; works from inside *any* repo you `cd` into.
- **Git hooks** (`tools/hook-templates/`) — a specific, heavier layer for a repo you deliberately want auto-documenting itself in the vault on every pull, unattended, without anyone asking. A real trade-off (a headless AI run kicks off on every pull of that repo), not something to install everywhere just because you can. Most repos should just use the commands/skills above and never need this.

## Slash commands and skills

Install once, per machine:

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

## Git hooks

Three optional hooks, each independently installable, tracked (as source) under `tools/hook-templates/`. Git never tracks the installed copies themselves (`.git/hooks/` isn't part of a repo's history), so each clone that wants a hook needs this one-time copy step.

### `post-merge` — self-documenting repo

After a pull lands on the default branch, this backgrounds a headless AI run that updates `repos/<this-repo-name>/index.md` from the diff — a repo documenting its own tooling changes automatically, with no one having to ask.

```bash
cp tools/hook-templates/post-merge .git/hooks/post-merge
chmod +x .git/hooks/post-merge
```

It needs a standalone `--mcp-config` file naming just the `obsidian` server (not your full Claude Code config, which may have other servers configured) at `~/.claude/hook-configs/obsidian-mcp-config.json` — ask your assistant to generate this from your existing MCP registration if it doesn't exist yet.

This hook runs with `--restricted` plus an explicit, minimal `--mcp-config`/`--strict-mcp-config` pair — confined to the checkout, with only the vault-write tools it actually needs, never broad unattended access. It also treats every changed filename as untrusted data rather than an instruction (a maliciously-named file shouldn't be able to redirect what the hook does), and verifies after every run — independent of what the run's own output claims — that only the intended doc was actually written. A brand-new unexpected file is removed outright (provably safe, it didn't exist before the run); an unexpected modification to a file that already existed is reverted to its last-committed content via `git checkout --`, which only works on already-tracked content — confirmed by this project's own test suite, see below.

A successful update is **auto-committed locally** (so it can't be silently lost or overwritten before you notice it) but **never auto-pushed** — pushing stays a manual, human-reviewed step (see [`runbooks/daily-workflow.md`](../runbooks/daily-workflow.md)), so nothing reaches the shared vault without someone having looked at `git status` first.

**Installing this into a repo other than the vault itself, deliberately:** the repo name and doc target auto-derive from wherever the hook is actually installed (its own git remote), so copying it unmodified into another repo's `.git/hooks/post-merge` already names and targets that repo correctly. The one thing that never auto-derives is `VAULT_ROOT` at the top of the script — set it as an environment variable (or edit the script's own default) to an explicit absolute path to your vault's own checkout, since the default (deriving from the current repo) would otherwise resolve to that *other* repo, not the vault. `HOOK_LOG_DIR`, `MCP_CONFIG`, `TIMEOUT_SECS`, `RETRY_DELAY`, and `KILL_SWITCH` are all environment-overridable the same way, mainly useful for the test suite below rather than day-to-day use. The hook also refuses to run at all until `repos/<that-repo>/index.md` already exists in the vault — bootstrap it once via `/vault-populate` (or ask your assistant directly) before installing this hook; it refines an existing doc rather than creating one from nothing. That same check is also what catches a forgotten `VAULT_ROOT` edit: it fails safe (logs and exits) rather than silently running against the wrong repo.

**Testing this hook:** `tools/hook-templates/test-post-merge.sh` (run with `bash tools/hook-templates/test-post-merge.sh`) is a real, isolated test suite, 30 assertions covering the branch guard, the diff filter, the kill switch, the `jq`-fencing requirement, the retry-on-127 behaviour, and the output-validation logic in detail, including the new-file-vs-modified-file distinction above. It builds its own temp git fixtures and a stub `claude` binary, nothing it does touches this machine's real vault or logs. Worth running after any edit to `post-merge` itself, it caught two real bugs during development (see the `post-merge` script's own comments on the output-validation section for the details) that comments and manual testing alone had missed.

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

Silent no-op until that repo already has a `repos/<name>/index.md` in the vault — bootstrap it first via `/vault-populate`, same precondition as `post-merge`. Also silently skips on a mid-session `/compact` (its own summary already carries whatever this injected earlier), and fails open — still injects — on malformed or missing stdin, rather than risk silently going dark on a genuine session start.

Reads the vault directly off disk, same deliberate MCP-only exception as `session-start-vault-check`: this runs before the model's own tool-calling loop begins.

### `pre-push` — a nudge at the moment you're already pushing

A genuine git `pre-push` hook: warns (never blocks) if the vault has unpushed commits sitting around, at the exact moment you push something else — on the theory that you're already in a "pushing" mindset right then, so the reminder is more likely to actually get acted on.

```bash
cp tools/hook-templates/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Stays silent if the repo you're actually pushing *is* the vault — its own unpushed commits are exactly what that push is about to send.

### Why not just auto-push?

Deliberately rejected. Having a hook push its own commit immediately would remove the one human-review checkpoint the whole "no PR gate" governance model depends on (see [Push policy](../runbooks/using-the-vault.md#push-policy-direct-to-main-no-required-pr)) — specifically for AI-generated content landing in a shared knowledge base — and risks unattended non-fast-forward races between multiple people's machines with nobody there to resolve them. These hooks shrink the window an update can sit unpushed and unseen; they don't close it completely. Someone who goes quiet across every repo for a long stretch is still a blind spot, and that's an accepted, known limitation rather than something solved here.

## Related

- [`../runbooks/using-the-vault.md`](../runbooks/using-the-vault.md) — the manual workflows this automates
- [`../runbooks/daily-workflow.md`](../runbooks/daily-workflow.md) — where hooks fit into an actual session, and the worked example of catching up on unpushed commits
