# Per-repo vault notes and open-item tracking: design

Written 2026-11-01. Status: awaiting final approval, nothing built.

## Why

The vault commands assume one repo per session and one note per day. Neither holds for a person who works across several repos in a day, or for a team sharing one vault. Four things go wrong today:

- `/vault-log` names notes `{date}-{topic}` and, by default, appends to any note from today, so a day spent in three repos ends up as one note, or as a note about the wrong repo.
- `/vault-context` reads the newest file in the vault whatever repo it is about, so it can load a note that is worthless to the repo you are in.
- Open items (follow-ups and decisions still to make) are never closed. They sit unticked in old notes, drop out of what gets loaded, or get retyped by hand into the next note and go stale.
- `/vault-populate` has the same single-user assumptions: it names the repo differently from the hook in a linked worktree, records nothing about when a doc was last checked, and two people refreshing the same doc can overwrite each other.

The session-start hook already filters by repo (when the filename pattern has `{repo}`) and loads the latest note per contributor. This design brings the commands and the hook into line with each other and adds the missing pieces.

## Goals

1. One note per repo, per day, per author, named and tagged for that repo, holding only the work done in that repo.
2. A session that works in several repos writes a note for each one in a single `/vault-log` run.
3. Theme tags that span repos appear on every note the theme applies to.
4. Starting work in a repo loads that repo's context: the author's own latest note, always, plus the latest notes from up to three other contributors.
5. Open items are tracked to completion. Each is done, carried forward, dropped, or put to the user, and the old note says which.
6. All of this works for a solo install (one contributor, so one note loaded) and for a team, with no config needed beyond the defaults.
7. Cheap to run. Notes are found by listing folders, not by reading content. Only the notes that matter are read, only the lines that change are edited, and the loaded output has a size cap.

## Non-goals and anti-goals

- No automatic renaming or rewriting of existing notes.
- No monorepo support (one repo name per git repository).
- No support for two repos with the same folder name (for example two clients' `api` repos) sharing one vault. They would share notes.
- No writing a note for a repo that was only glanced at.
- Never edit another person's note beyond closing their open items (see Open items).
- Never close an item without evidence. When unsure, carry it forward or ask.
- Secrets still never go in a note. That rule is unchanged and not configurable.

## Note identity

Path: `daily-notes/{author}/{date}-{repo}-{topic}.md`. The new defaults are:

| Setting | New default | Was |
| --- | --- | --- |
| `filenamePattern` | `{date}-{repo}-{topic}` | `{date}-{topic}` |
| `appendRule` | `same-day-same-repo` (new value) | `same-day-any-topic` |

`same-day-same-repo` appends to a note only if it is in the author's folder, dated today, and is for this repo. `same-day-any-topic` and `exact-path` keep their meanings. A vault whose `vault-config.md` sets these keys explicitly is unaffected.

Every note gets `repo: <name>` in its frontmatter as well as `repo` in its tags, so the repo can be found by name, by tag, or by filename. `repoNameCase` applies to all three.

**Finding notes is a directory listing.** Because the date and repo are in the filename, "today's note for this repo" and "each author's latest note for this repo" are answered by listing folders and matching names. No note body is read until it is known to be needed.

**Matching a filename to a repo.** The filename is a first filter, not the authority. A note belongs to a repo if its name, after the date, starts with that repo's name followed by `-`, taking the longest match among the known repo names (the vault has one repo doc per repo). That stops `bedrock` claiming a `bedrock-tools` note. If a note's frontmatter `repo` is read and disagrees with its filename, the frontmatter wins. A note whose name starts with no known repo name is classed as older (see Context loading), by filename alone, without reading it.

The repo name is the folder of the main checkout, found through the git common directory, so a linked worktree gets its main repo's name. This is how the hook already does it. The commands and `post-merge` use the same rule; today `/vault-log` and `/vault-populate` use `git rev-parse --show-toplevel`, which differs in a worktree.

## `/vault-log`

1. **Find the repos worked in.** Start from the working directory, then go through the conversation for every path touched by a tool call, `cd`, `git -C`, and repo named in the discussion. Resolve each to a repo name by the rule above. The vault itself is never a repo.
2. **Decide which count.** A repo counts if you read its code, ran commands in it, or made decisions about it, with or without edits. A one-line glance to answer a question does not. If it is unclear whether a repo counts, ask once, naming the repo.
3. **Reconcile open items** for each repo (see below), before writing.
4. **Write one note per repo.** Find or create it by the append rule. Append without reading the note where the backend can append; the only read is the one section being rewritten in step 6. Each holds only that repo's work. A decision that spans repos goes in each affected note, with a `See also` wikilink to its siblings from the same run.
5. **Tags.** Every note carries `daily-note`, the repo, and theme tags. Theme tags are lowercase and hyphenated. Reuse a tag from the notes already loaded in the conversation, or from the vault's tag list, before inventing one. Do not read extra notes for this. A theme that ran across repos gets the same tag on each note it applies to.
6. **Keep notes small.** "Context for Future Sessions" is rewritten in place on each run, not added to, reading only that section. Same-day additions go under `## Update`, which the loaders trim to the latest.
7. **Report.** One line per note written (path, count of items carried forward silently), then the usual sync reminder. Extra lines appear only for things that need your attention, at most 10 in total, then "and N more":
   - each edit to another author's note: whose note, which item, which marker, and the evidence;
   - each skipped edit (the line had changed since it was read), naming the item;
   - each repo looked at but judged a glance, so you can say it counted after all;
   - each stale item still open, by name;
   - each older-note item carried forward or dropped in adoption;
   - each question left unanswered, with the default that was applied.

A session in one repo behaves as today apart from the naming.

## Open items

An open item is a `- [ ]` line in the `## Open Questions / Next Steps` section of a note. Decisions to make are open items too.

**Invariant:** at any time, an unticked `- [ ]` exists only in the latest note of each author for each repo. Everything older is closed in one of three ways, which is what the reconcile step maintains:

| Marker | Meaning | Line gets |
| --- | --- | --- |
| `- [x]` | Done | `(done YYYY-MM-DD, see [[note]])` |
| `- [-]` | Dropped or superseded | `(dropped YYYY-MM-DD: reason)` |
| `- [>]` | Carried forward | `(carried to [[new note]] YYYY-MM-DD)` |

The item's age is counted from the date it was first opened, not from the date of the note it sits in. A carried line keeps that date: `- [ ] text (from [[old note]], opened YYYY-MM-DD)`. Without this, every carry-forward would reset the age and nothing would ever go stale.

**Reconcile step.** Before writing, `/vault-log` finds the open items for each repo in scope. If the open-item list from the hook or `/vault-context` is already in the conversation, it starts from that. Otherwise it lists the author folders, takes each author's latest note for the repo, and searches those notes for `- [ ]` lines. The invariant means nothing older can hold an open item, so older notes are never read. If there are no hits, the step ends there.

Your own items are sorted like this:

- **Done:** this session shows it finished (a commit, a passing test, a change in the code, or the user saying so). Tick it in the old note.
- **Dropped or superseded:** the user said so, or the work made it moot. Mark it `[-]` with the reason.
- **Untouched:** nothing in the session relates to it. Carry it into the new note silently, as `- [ ] text (from [[old note]], opened YYYY-MM-DD)`, and mark the old line `[>]`. It is listed in the report, not asked about.
- **Partly touched:** the session worked on its subject but did not clearly finish it. Put it to the user.

All questions go in one message, each with a proposed answer, defaulting to carry forward.

Other authors' items are only closed when there is evidence (this session shows it done) or the user says so. Otherwise they are left exactly as they are: not carried forward, not asked about. Carrying them would change their owner and would hide them from the person who wrote them.

A stale item (open for more than `staleOpenItemDays`, default 30, counted from `opened`), whoever owns it, is always put to the user. This is how abandoned items from people who have left get cleared.

**Adopting older notes (one-off).** Notes written before this change have no repo, so the invariant does not hold for them and their `- [ ]` items would stay open for good. So reconcile also takes your own newest older note, once, and puts its `- [ ]` items to the user in the same single message, each with a proposed answer: belongs to this repo (carry forward, the default), belongs to another repo (leave it for that repo's session), or drop. Items carried forward are marked `[>]` in the old note, and items dropped `[-]`. The note is not offered again once it has no `- [ ]` left. Other authors' older notes are adopted when they run `/vault-log` themselves. Bullets under "Next Steps" that are not checkboxes are left alone, since there is nothing safe to tick. The cost is one extra note read, and it ends by itself.

**What may be edited in someone else's note:** only the marker of a `- [ ]` line, and a parenthetical appended to that same line. Nothing else. In your own notes, reconcile may do the same and the normal append applies as well. The edit is made to that one line with a line-level edit where the backend has one (`patch_note` on MCPVault), and by rewriting the note only where it does not. A rewrite must change nothing but that line. Markers for several items in the same old note are changed in one edit call, not one call per item. Just before editing, the line is read again, and the edit is skipped and reported if it has changed since it was first read. This covers a colleague editing the same note in a synced vault.

## Context loading (`/vault-context` and the session-start hook)

For the repo you are in:

1. The repo doc, as now.
2. **Your own latest note for this repo, always.** Your author is found from `git config user.name`, slugged as `/vault-log` does it. With no `user.name`, nothing counts as yours.
3. **Plus the latest note for this repo from each of up to three other contributors**, most recent first. `CONTEXT_MAX_CONTRIBUTORS` (default 3) now counts others, not you. A solo install loads one note, a team of four up to four.
4. **Two trim levels, and each open item appears once.** Your own note gets the full trim: its forward-looking sections plus the latest appended update, as the hook does today. Other contributors' notes get a tighter one: "Context for Future Sessions" only. In every loaded note the checkbox lines (`- [ ]`, `[x]`, `[-]`, `[>]`) are left out, because the open-item list in step 5 is the one place open items appear and closed ones are history. Each loaded note also shows its tag line, so `/vault-log` can reuse tags without reading anything more.
5. **Open items for the repo, as a short list** (marker line, owner, age), from each contributor's latest note, even those beyond the three loaded. Items past `staleOpenItemDays` are flagged as stale and listed first. At most `CONTEXT_MAX_OPEN_ITEMS` (default 10) are shown, followed by "and N more".
6. **Fallback for older notes.** If the repo has no notes of its own, the newest note with no `repo` in its filename or frontmatter (one written before this change) is loaded in its place, labelled as an older note of unknown repo. Older notes are identified by filename alone, so the search stays a listing. Only the newest few (at most 5) have their frontmatter read, to confirm none belongs to a different repo. A note that belongs to a different repo is never used. With neither kind, it says there are no notes yet.

**Size cap.** The hook's output has a total budget, `CONTEXT_MAX_CHARS` (default 12000). Over budget, others' notes are dropped first (furthest back first), then trimmed further, and the output says what was left out. Your own note and the open-item list are never cut.

**No double loading.** Like `compact`, a `resume` session start loads nothing, because the transcript already holds what was loaded (the builder confirms the harness replays it); `startup` and `clear` still load. If the hook's output for this repo is already in the conversation, `/vault-context` says so and loads only what is missing, such as a topic search or a note the hook left out for size.

`/vault-context` with a topic or person still searches the whole vault, because that is the one case where crossing repos is wanted. It returns at most 5 notes, each trimmed as in step 4, with a line saying how many more matched. The hook cannot ask questions, so it only reports.

Notes written before this change have no `repo` in the filename or frontmatter. They are used only through the fallback in step 6, and the output says "at least N" older notes exist, counted from filenames without reading them. Once a repo has a note of its own, older notes are no longer loaded for it, so the fallback fades out as notes are written.

## `/vault-populate`

All five agreed:

1. **Same repo identity rule** as above, so a worktree documents the main repo under the right name.
2. **Frontmatter** on the doc: `repo`, `last-populated` (date) and `source-commit` (short SHA). The hook can then say how stale the doc is.
3. **A protected section.** The doc gets a `## Hand-written notes` section that a refresh never changes; the rest may be regenerated. This replaces the current "try to preserve tribal knowledge" instruction, which relies on judgement.
4. **Re-read just before writing**, and stop and report if the doc changed since it was first read, so two people refreshing at once cannot overwrite each other.
5. **Tags** on the doc: `repo-doc` and the repo name, matching the notes.

**Skip work that isn't needed** (follows from change 2):

- If the doc's `source-commit` equals `HEAD`, report "up to date" and stop, with no survey and no write.
- If it differs, read only the files in `git diff --name-only <source-commit>..HEAD` and update the parts of the doc they affect, leaving the rest as written. A full survey is used only when there is no `source-commit` (a first run or an older doc), or when the user asks for one. If `source-commit` is no longer in the history (a rebase or squash), it falls back to a full survey.

## Settings and versions

- New key `staleOpenItemDays` (default 30), read by log, context and the hook.
- New hook limits `CONTEXT_MAX_OPEN_ITEMS` (default 10) and `CONTEXT_MAX_CHARS` (default 12000), set as environment variables like the existing `CONTEXT_MAX_CONTRIBUTORS` and `UPDATE_MAX_LINES`.
- New value `same-day-same-repo` for `appendRule`, now the default.
- Changed defaults: `filenamePattern`.
- Command templates move to version 4, so the installer's stale-copy check offers the update.
- Docs to update: `docs/vault-config.md`, `runbooks/using-the-vault.md`, `tools/skill-templates/obsidian-vault-conventions/SKILL.md`, `docs/testing.md`.

## Testing

- **Older notes and matching:** longest known repo name wins (`bedrock` against `bedrock-tools`); frontmatter beats filename; older notes counted by filename; at most 5 frontmatter reads in the fallback; adoption offers each author's newest older note once, marks `[>]` or `[-]`, and does not offer it again; non-checkbox bullets untouched; only your own older note is adopted.
- **Hook suite** (`test-session-start-vault-context.sh`): own note always loaded, then up to three others; own note not displaced by busier contributors; no `user.name`; repo filter by filename and by frontmatter `repo`; open items gathered from contributors beyond the loaded ones; stale flag; legacy-note count; worktree gets the main repo's name; others' notes get the tighter trim; open-item cap and "and N more"; total size cap drops others' notes first and never cuts your own note or the open-item list; loaded notes contain no checkbox lines and each open item appears once, in the list; tag lines are printed; nothing is loaded on `resume`; topic search stops at 5 notes and reports the rest.
- **Command tests** (`run-command-tests.mjs`, manual, uses model calls): a multi-repo session produces one note per repo with the right tags and no cross-contamination; a glanced repo gets no note; reconcile closes, carries forward and drops as expected; in another author's note only checkbox lines and their parentheticals change; reconcile reads no older notes and does nothing when there are no open items; a carried item keeps its `opened` date and goes stale on schedule; other authors' items are neither carried nor asked about unless done, stale or the user says so; untouched own items carry silently and appear in the report; partly touched ones are asked; reconcile starts from the open-item list already in the conversation; an edit is skipped when the line changed since it was read; `/vault-populate` stops at "up to date" when `source-commit` equals `HEAD` and reads only changed files otherwise; `/vault-context` does not reload what the hook already gave.
- **Report:** a quiet run prints one line per note plus the sync reminder; each of the six attention cases adds its line; more than 10 extra lines collapse to "and N more"; silent carry-forwards appear only as a count.
- **Structure test:** the version stamp bump, and a line-count ceiling for each command template, so the prompt cost of the new rules is visible and held.

## Left to the builder

- How to read open items across all notes for a repo cheaply on each backend (search for `- [ ]` on the REST API, `search_notes` on MCPVault, a plain `grep` in the hook).
- Exact wording of the command prompts, and the order of steps within them.
- Author identity: the commands and the session-start hook must use one identical rule to name the author folder (today the hook uses `git config user.name`). If a person's name differs between machines or repos their notes split across folders and "yours always loaded" would miss some. No new setting is proposed for this.
- Template size: set each command template's line ceiling from the measured v3 length plus an allowance (my starting suggestion is 40%). Keep the adoption and fallback wording terse, and once older notes are gone from the team's vault, remove that wording in a later template version.
- Whether `post-merge` needs a change to match the repo identity rule (it was aligned in `f6bcd21`, so probably not).

## Calls I made, for you to check

1. A glanced repo is a one-off read or lookup with no further work in it.
2. Repos found from the conversation are written without a confirmation prompt, listed in the final report, and only queried when it is unclear whether one counts.
3. `[>]` for carried forward, so only the newest copy of an item is ever unticked.
4. Stale threshold of 30 days, always put to the user.
5. The efficiency measures (listing over searching, reconcile on latest notes only, line-level edits, two trim levels, size caps, skip-if-unchanged populate, no double loading) change how notes are fetched, not what they contain. The numbers (10 open items, 12000 characters) are my starting values.
6. Older-note handling (filename-only classification, 5-note frontmatter cap, one-off adoption defaulting to carry forward) is my design for keeping the old-note problem finite without reading the whole vault.
7. Carrying your untouched items forward silently, and leaving other authors' items alone unless there is evidence or they are stale, are my calls to keep the questions few and ownership clear.
8. The further token measures (each open item shown once and checkbox lines left out of loaded notes, no load on `resume`, one edit call per old note, tags reused from what is loaded, topic search capped at 5 notes, template line ceilings) are my additions. The 5 and the 40% are starting values.
9. The report's attention cases and the cap of 10 extra lines are my choices.
10. "Fall back to the newest note" is read as: the newest repo-less (pre-change) note, only when the repo has none of its own. A note known to belong to another repo is never used.
