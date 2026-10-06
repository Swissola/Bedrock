# Per-vault configuration (`vault-config.md`)

> **Scope:** an optional note at the vault root that tells the slash commands in [`tools/command-templates/`](../tools/command-templates/) about this vault's own conventions, so one set of command templates serves vaults laid out differently. **You don't need this file.** Without it every setting takes its default and the commands behave exactly as documented in [`runbooks/using-the-vault.md`](../runbooks/using-the-vault.md).

## Where it lives and what it is

`vault-config.md` at the vault root. It is a normal Obsidian note whose frontmatter holds the settings; anything below the frontmatter is just a description for humans. It has to be a note (not JSON) because the `obsidian` MCP read tools only handle notes.

In a shared, git-backed vault the file is committed, so a setting applies to **everyone** on the team. That is why the defaults never add anything (no extra frontmatter, no change-log edits): a team opts in deliberately, in a reviewed commit. A single-user vault can use it freely.

## Settings

All keys are optional. Each command reads only the keys it needs, noted in the last column. A key that is missing takes its default, unknown keys are ignored, and if part of the file is malformed the command uses what it can read, the default for the rest, and tells you which part it could not read.

| Key | Default | Meaning | Read by |
|---|---|---|---|
| `backend` | detected | `rest-api` or `mcpvault`. Normally leave it out: the command works out which `obsidian` MCP server it has from the tools actually available, because it has to know the tool names before it can read this file at all. Set it only to override | all commands, `post-merge` |
| `dailyNotesPath` | `daily-notes/{author}` | Folder for daily notes. `{author}` (from `git config user.name`, or each contributor's subfolder when reading) and `{repo}` are filled in | log, context, populate, `session-start-vault-context` |
| `filenamePattern` | `{date}-{topic}` | Note filename without `.md` | log |
| `appendRule` | `same-day-any-topic` | `same-day-any-topic`: any note from today in the folder is appended to. `exact-path`: only the exact path is appended to, otherwise a new note is created. Use `exact-path` where several notes per day on different topics is normal | log |
| `tags` | chosen per note | A fixed list, e.g. `[daily-note, "{repo}"]` | log |
| `frontmatterExtras` | none | Extra fields to write. Supported: `machine` (lowercased `hostname`), `location` | log |
| `locationHomePrefix` | unset | IPv4 prefix of the "home" network, e.g. `"192.168.1."`. With `location` in `frontmatterExtras`: `home-lan` if the default gateway starts with it, otherwise `off-lan`. Unset, or gateway unknown: `location` is omitted and the command says so | log |
| `titleHeading` | `true` | Whether the body starts with a `# YYYY-MM-DD — Short title` heading | log |
| `bodySections` | the six sections in the runbook | Ordered list of `##` section names | log |
| `changeLog` | `off` | `compact`: also add a change-log entry to the current repo's `change-log.md`, if it has one (uncommitted) | log |
| `vaultSync` | `git` | How the vault reaches other machines; changes only the closing reminder (`git` reminds you to commit and push) | log |
| `hubNote` | `index.md` | The vault's hub note. `none` if there isn't one | context, populate |
| `reposPath` | `repos/{repo}/index.md` | Where a repo's reference doc lives | context, populate, `post-merge`, `session-start-vault-context` |
| `contextReadsRepoDoc` | `false` | If `true`, `/vault-context` also reads the current repo's doc at `reposPath` | context |

Not configurable, on every vault: **secrets are never written into a note**, even if one appears in the conversation.

## Hooks

Two of the [hook templates](../tools/hook-templates/) read this file too, in plain bash, because they run before (or outside) any MCP session:

- **`session-start-vault-context`** reads `reposPath` and `dailyNotesPath`. It scans for the most recent daily note under the part of `dailyNotesPath` before its first placeholder, so `daily-notes/{author}` scans every contributor's subfolder and `Inbox/daily-notes` scans just that folder.
- **`post-merge`** reads `reposPath` (the doc it keeps up to date) and `backend` (which MCP tool names the headless run is allowed; with no `backend` it uses MCPVault if the hook's MCP config mentions `mcpvault`, otherwise the REST API tools). It also needs to know *where the vault is* when the vault isn't the repo the hook is installed in: set `VAULT_ROOT` in the environment, or put the vault's absolute path on one line in `~/.claude/hook-configs/vault-root`. A per-machine installer can write that file once instead of editing every repo's hook.

In both, a configured path must be relative and contain no `..` (otherwise it is ignored and the default is used), and a `vault-config.md` whose frontmatter has no closing `---` is ignored entirely.

**A vault that isn't a git repo** (for example a Syncthing-synced folder, detected by the absence of a `.git` at the vault root): `post-merge` still updates the doc, but there is no safe way to undo a write, so it only **flags** unexpected writes (it lists every file written during the run other than the doc, and records exit code 3) and never reverts, removes or commits anything. Files under dot-folders such as `.obsidian` and `.stversions` are ignored. A sync tool bringing in another device's notes during a run can show up as a false alarm; the log names the files, so it is quick to check.
**Skills and a different layout.** The two skills in [	ools/skill-templates/](../tools/skill-templates/) describe the team vault's layout and trigger on any obsidian MCP call. A vault that overrides the layout in ault-config.md should install with --no-skills (see [utomation.md](automation.md)), or the skill will tell the model the old layout in every session.

## Backends

Bedrock's setup ([`mcp-setup.md`](mcp-setup.md)) uses the Obsidian **Local REST API** plugin, whose tools are `vault_list`, `vault_read`, `vault_write`, `vault_append` and `vault_patch`, and which needs Obsidian open. A vault can instead use **MCPVault** (`@bitbonsai/mcpvault`), which reads the files directly with no app running and has `list_directory`, `read_note` and `write_note`. The commands carry a small table mapping each operation to both, and pick by what is available. The append operation differs deliberately: the REST API column reads and rewrites the whole note (the surgical `vault_patch` tool is unreliable on some plugin versions, see the Known Gotchas table in `mcp-setup.md`), while MCPVault uses `write_note` in `append` mode.

## Examples

**A team vault (this one):** no `vault-config.md` at all.

**A personal, non-git vault with a PARA layout** (daily notes in `Inbox/daily-notes`, several per day, a `change-log.md` kept per repo):

```yaml
---
dailyNotesPath: Inbox/daily-notes
filenamePattern: "{date}-{repo}-{topic}"
appendRule: exact-path
tags: [daily-note, "{repo}"]
frontmatterExtras: [machine, location]
locationHomePrefix: "192.168.1."
titleHeading: false
bodySections:
  - What Was Done
  - Decisions Made & Why
  - Problems Solved
  - Context for Future Sessions
  - Open Questions / Next Steps
changeLog: compact
vaultSync: syncthing
hubNote: none
reposPath: "Projects/{repo}/index.md"
contextReadsRepoDoc: true
---
```

## Testing

Command templates are prompts, so they are tested by running them for real. `node tools/command-templates/test/run-command-tests.mjs` runs each of the three commands headlessly (`claude -p`) against throwaway vaults and repos, once with no `vault-config.md` (the result must match the runbook) and once with a config exercising the keys, plus a secrets check and a malformed-config check. It defaults to `--backend rest-api`, which uses `tools/command-templates/test/stub-rest-api-mcp.mjs`, a zero-dependency stand-in for the Local REST API plugin's MCP server with the same tool names and input schemas (no Obsidian needed); `--backend mcpvault` runs the real MCPVault server instead. `--repeat <n>` runs each scenario n times, worth doing for the wording-sensitive ones because model runs are probabilistic.

It is **manual** (every scenario spends model calls) and never touches a real vault. It judges a run by the files actually written and the tool calls actually made, read from the event log, never by the model's own summary, which can claim a write that landed somewhere else. The stub does not reproduce the plugin's exact response shapes (they aren't documented) and always refuses `vault_patch`.

The hooks and the installer have ordinary shell test suites that need no model: `tools/hook-templates/test-post-merge.sh`, `test-session-start-vault-context.sh`, `test-pre-commit.sh`, and `tools/test-install-claude-config.sh`.
