# Per-vault configuration (`vault-config.md`)

> **Scope:** for a team whose vault is laid out differently from this one, or who want the slash commands to behave differently. `vault-config.md` is an optional note at the vault root that tells the commands in [`tools/command-templates/`](../tools/command-templates/) and two of the hooks about the vault's own conventions, so one set of templates serves vaults with different layouts. **You don't need this file.** Without it every setting takes its default, and the commands behave as documented in [`using-the-vault.md`](../runbooks/using-the-vault.md).

Terms on this page (see also [Terms](../README.md#terms)): the **vault** is the repo the notes live in. A **daily note** is a session log. The **repo doc** is a codebase's reference page, `repos/<name>/index.md` by default. A **hook** is a script that runs on a git event or a Claude Code session start, described in [`automation.md`](automation.md). An **MCP backend** is whichever server provides the `obsidian` MCP tools, described under [Backends](#backends).

## Where it lives and how to create it

It is a note called `vault-config.md` at the vault root. Its frontmatter holds the settings, and anything below the frontmatter is a description for humans. It has to be a note rather than JSON, because the `obsidian` MCP read tools only handle notes.

To use it:

1. Create `vault-config.md` at the vault root with a frontmatter block containing only the keys you want to change. See [Examples](#examples).
2. Commit and push it. In a shared, git-backed vault the file applies to **everyone** on the team, which is why the defaults never add anything (no extra frontmatter, no change-log edits): a team opts in deliberately, in a reviewed commit. A single-user vault can use it freely.
3. Run `/vault-log` or `/vault-context` and check the result follows the new setting. If part of the file cannot be read, the command says which part.

## Settings

All keys are optional. A missing key takes its default, unknown keys are ignored, and if part of the file is malformed the command uses what it can read, the default for the rest, and tells you which part it could not read. The last column says which command or hook reads each key. "Log", "context" and "populate" mean `/vault-log`, `/vault-context` and `/vault-populate`.

### Where things live

| Key | Default | Meaning | Read by |
|---|---|---|---|
| `dailyNotesPath` | `daily-notes/{author}` | Folder for daily notes. `{author}` (from `git config user.name`, or each contributor's subfolder when reading) and `{repo}` are filled in | log, context, populate, `session-start-vault-context` |
| `filenamePattern` | `{date}-{repo}-{topic}` | Note filename without `.md`. `session-start-vault-context` uses the `{repo}` part to tell which repo a note belongs to. A pattern without `{repo}` still works, but the hook then cannot tell which repo a note is about and treats every note as relevant, so use `{repo}` if the vault holds more than one repo | log, `session-start-vault-context` |
| `reposPath` | `repos/{repo}/index.md` | Where a repo's reference doc lives | context, populate, `post-merge`, `session-start-vault-context` |
| `repoNameCase` | `lower` | `lower`: the repo name used for `{repo}` is lowercased. `keep`: used exactly as the repo's folder is named (a repo called `Widget-Service` stays `Widget-Service`). Everything that reads it names notes and docs the same way, wherever they are written or found | log, context, populate, `session-start-vault-context`, `post-merge` |
| `hubNote` | `index.md` | The vault's hub note. `none` if there isn't one | context, populate |

### What a daily note contains

| Key | Default | Meaning | Read by |
|---|---|---|---|
| `tags` | `daily-note`, the repo, theme tags | A fixed list, e.g. `[daily-note, "{repo}"]` | log |
| `frontmatterExtras` | none | Extra fields to write. Supported: `machine` (lowercased `hostname`), `location` | log |
| `locationHomePrefix` | unset | IPv4 prefix of the "home" network, e.g. `"192.168.1."`. With `location` in `frontmatterExtras`: `home-lan` if the default gateway starts with it, otherwise `off-lan`. Unset, or gateway unknown: `location` is omitted and the command says so | log |
| `titleHeading` | `true` | Whether the body starts with a `# YYYY-MM-DD — Short title` heading | log |
| `bodySections` | the six sections in the runbook | Ordered list of `##` section names | log |
| `changeLog` | `off` | `compact`: also add a change-log entry to the current repo's `change-log.md`, if it has one (uncommitted) | log |

### How the commands and hooks behave

| Key | Default | Meaning | Read by |
|---|---|---|---|
| `appendRule` | `same-day-same-repo` | When `/vault-log` adds to an existing note instead of creating one. `same-day-same-repo`: append only to a note in your folder, dated today, for this repo. `same-day-any-topic`: any note from today in the folder (the old default). `exact-path`: only the exact path is appended to, otherwise a new note is created. Use `exact-path` where several notes per day on different topics is normal | log |
| `staleOpenItemDays` | `30` | An open item (`- [ ]`) older than this many days, counted from its `opened` date, is **stale**: `/vault-log` always puts it to you and the session-start hook lists it first, flagged | log, `session-start-vault-context` |
| `contextReadsRepoDoc` | `false` | If `true`, `/vault-context` also reads the current repo's doc at `reposPath` | context |
| `vaultSync` | `git` | How the vault reaches other machines. Changes only the closing reminder (`git` reminds you to commit and push) | log |
| `backend` | detected | `rest-api` or `mcpvault`. Normally leave it out: the command works out which `obsidian` MCP server it has from the tools actually available, because it has to know the tool names before it can read this file at all. Set it only to override | all commands, `post-merge` |

Not configurable, on every vault: **secrets are never written into a note**, even if one appears in the conversation.

## Hooks

Two of the [hook templates](../tools/hook-templates/) read this file too, in plain bash, because they run before (or outside) any MCP session. Both ignore a configured path that is absolute or contains `..` (the default is used instead), and both ignore a `vault-config.md` whose frontmatter has no closing `---`.

### `session-start-vault-context`

Reads `reposPath`, `dailyNotesPath`, `filenamePattern`, `repoNameCase` and `staleOpenItemDays`. For what it injects and how to switch modes, see [`automation.md`](automation.md#session-start-vault-context-point-a-session-at-its-repos-vault-context). The rules it follows when finding notes:

- **Repo name.** The name of the folder the repo lives in (its main checkout, so a linked worktree counts as the same repo), cased per `repoNameCase`.
- **Which notes belong to the repo.** It lists the part of `dailyNotesPath` before its first placeholder and picks out this repo's notes by filename. It matches the longest known repo name first, so `widget` never claims `widget-service`'s notes.
- **Whose notes are whose.** Only notes in an `{author}` folder can be yours, and only when `git config user.name` is set. In a flat folder, or with no `user.name`, every note is treated as someone else's, with an `unknown` owner. `{author}` should be the last placeholder in `dailyNotesPath`, because the hook reads each subfolder of the part before the first placeholder as a contributor.
- **Which note is latest.** The newest date in the filename, then the newest file modification time, because a git checkout gives every file the time it was pulled.
- **What is ignored.** Hidden files, non-`.md` files and Syncthing conflict copies.
- **When it stays silent.** On `resume` and `compact`.
- **No notes yet.** If the repo has no notes, the newest older note without a repo in its filename is shown and labelled, so a vault in the old naming still works. This fades out as repo-named notes appear.

In the two modes, the hook outputs:

- **Pointer mode (the default).** The vault path, the path of the repo doc, the path and date of your latest note, the latest note of each of up to three other contributors, and the open-item count with the top three (`CONTEXT_POINTER_MAX_ITEMS`), stale ones first, each with its owner and age and cut at 160 characters. It loads no note contents. The session reads a file when the task needs it, or you run `/vault-context`.
- **Full mode (`CONTEXT_MODE=full`).** The repo doc and **your** latest note in full, and the latest from each of up to three other contributors in a shorter form (`CONTEXT_MAX_CONTRIBUTORS`; your own note does not count towards it). Open items from all of those notes are listed once, stale ones first, capped at `CONTEXT_MAX_OPEN_ITEMS` (10) and cut at 300 characters per item. `CONTEXT_MAX_CHARS` (12000) bounds the whole output by dropping the furthest-back other note first, never your own note, the repo doc or the open-item list.

### `post-merge`

Reads three keys:

- `reposPath`: the doc it keeps up to date.
- `repoNameCase`: it names the repo after its folder, like the other hook and the commands, so the doc it writes is the doc they find.
- `backend`: which MCP tool names the headless run may use. With no `backend` it uses MCPVault if the hook's MCP config mentions `mcpvault`, otherwise the REST API tools.

It also needs to know *where the vault is* when the vault is not the repo the hook is installed in. `VAULT_ROOT` is taken from, in order:

1. the environment;
2. the hook's own repo, if its path is listed in `~/.claude/hook-configs/vault-root`;
3. the first line of that file;
4. the hook's own repo.

The file holds one absolute path per line, so a machine with several vaults lists them all and the first is the default. The installer writes and extends it.

**Unexpected writes are flagged, never undone.** After a run, `post-merge` compares the vault's state before and after (`git status` for a git vault, file modification times otherwise). Anything written outside the doc is listed in the log and recorded with exit code 3, and left exactly as it is. The hook cannot tell the model's write from a note you wrote in the same minutes. Only the doc itself is ever auto-committed, and only for a git vault.

**A vault that isn't a git repo** (for example a Syncthing-synced folder, detected by the absence of a `.git` at the vault root): `post-merge` still updates the doc and flags unexpected writes the same way, but commits nothing. Files under dot-folders such as `.obsidian` and `.stversions` are ignored. A sync tool bringing in another device's notes during a run can show up as a false alarm. The log names the files, so it is quick to check.

### A different layout

The conventions the assistant sees in the vault come from the vault's own [`CLAUDE.md`](../CLAUDE.md), which describes the team layout. A vault that overrides the layout here should edit its `CLAUDE.md` to match, or the assistant will be told the old layout.

## Backends

An **MCP backend** is the server that provides the `obsidian` MCP tools. Bedrock supports two.

| | Local REST API plugin | MCPVault |
|---|---|---|
| What it is | An Obsidian community plugin, the default in [`mcp-setup.md`](mcp-setup.md) | `@bitbonsai/mcpvault`, a standalone server |
| Needs Obsidian open | Yes | No, it reads the files directly |
| Tools the commands use | `vault_list`, `vault_read`, `vault_write`, `vault_append`, `vault_patch` | `list_directory`, `read_note`, `write_note` |
| `backend` value | `rest-api` | `mcpvault` |

The commands carry a small table mapping each operation to both and pick by what is available. The append operation differs deliberately. With the REST API backend the command reads and rewrites the whole note, because the surgical `vault_patch` tool is unreliable on some plugin versions (see the Known Gotchas table in [`mcp-setup.md`](mcp-setup.md#known-gotchas)). MCPVault uses `write_note` in `append` mode.

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

Command templates are prompts, so they are tested by running them for real. This is **manual**, because every scenario spends model calls, and it never touches a real vault.

```bash
node tools/command-templates/test/run-command-tests.mjs
```

- It runs each of the three commands headlessly (`claude -p`) against throwaway vaults and repos: once with no `vault-config.md` (the result must match the runbook), once with a config exercising the keys, plus a secrets check and a malformed-config check.
- `--backend rest-api` is the default. It uses `tools/command-templates/test/stub-rest-api-mcp.mjs`, a zero-dependency stand-in for the Local REST API plugin's MCP server with the same tool names and input schemas, so no Obsidian is needed. `--backend mcpvault` runs the real MCPVault server instead.
- `--repeat <n>` runs each scenario n times, worth doing for the wording-sensitive ones because model runs are probabilistic.
- It judges a run by the files actually written and the tool calls actually made, read from the event log, never by the model's own summary, which can claim a write that landed somewhere else.
- The stub does not reproduce the plugin's exact response shapes (they aren't documented) and always refuses `vault_patch`.

The hooks and the installer have ordinary shell test suites that need no model. [`testing.md`](testing.md) lists them all and what each checks.
