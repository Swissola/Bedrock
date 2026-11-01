# Per-repo vault notes and open-item tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the vault hook, the three vault commands and the repo-doc hook work per repo, per author and per team, with open items closed down rather than left to pile up.

**Architecture:** The session-start hook (plain bash, no model) does the heavy lifting and is built first because it is fully testable offline. `post-merge` is then aligned with the new repo-doc format. The three command templates (model prompts) move to version 4 and follow the same rules, checked by the manual command tests. Docs come last.

**Tech Stack:** bash 3.2-compatible shell (macOS CI), awk/sed, the repo's `assert_*` shell test harnesses, `run-mutation-tests.sh`, Node (`run-command-tests.mjs`, manual, uses model calls), Markdown.

**Spec:** `docs/superpowers/specs/2026-11-01-per-repo-vault-notes-design.md` (approved). Read it with this plan; where this plan says "the spec", it means that file.

## Global Constraints

- Branch: `design/per-repo-vault-notes` (already holds the spec). One PR at the end.
- Shell: bash 3.2 compatible (no associative arrays, `mapfile`, `${v,,}`, `declare -A`); `shellcheck -S warning -x` clean; use `return 0` not `return $?`; use `[[ ]]` in new code.
- British English and no em dashes in every file written, comments and docs included.
- New defaults: `filenamePattern` `{date}-{repo}-{topic}`; `appendRule` `same-day-same-repo`; `staleOpenItemDays` 30.
- Hook limits (environment variables): `CONTEXT_MAX_CONTRIBUTORS` 3 (counts others, not you), `UPDATE_MAX_LINES` 40, new `CONTEXT_MAX_OPEN_ITEMS` 10, new `CONTEXT_MAX_CHARS` 12000.
- Open-item markers: `- [ ]` open, `- [x]` done, `- [-]` dropped, `- [>]` carried. A carried line reads `- [ ] text (from [[old note]], opened YYYY-MM-DD)`.
- Repo name: folder of the main checkout via `git rev-parse --path-format=absolute --git-common-dir`, never `--show-toplevel`.
- Command templates carry `<!-- bedrock-template: <name>, version 4 -->` and stay under the line ceilings in Task 10.
- Commit after each task. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Every task that changes a shell file (the hook, `post-merge`, a test script) ends with `shellcheck -S warning -x <each changed file>`, expected to print nothing, before its commit. The final task repeats it for every shell file in the diff.
- Verify with `bash tools/testing/run-all-tests.sh` before the final task is called done. It includes the repo's own shellcheck gate (`test_shellcheck_reports_no_warnings` in `test-structure.sh`), which is the CI check.

## Review Focus

Failure modes the spec implies that no single task would otherwise pin, most likely first. Each has its test in the task named.

1. No `git config user.name`, or a name that matches no folder: no note is "yours", others still load, nothing crashes (Task 2).
2. Repo names where one is a prefix of another (`widget`, `widget-ui`, `widgetry`) and names holding glob characters (Task 1).
3. Open-item lines with CRLF endings, trailing spaces, an upper-case `[X]`, no `opened` date, or a malformed or future date: must not crash and must never read as stale by accident (Task 4).
4. A budget smaller than the parts that are never cut (repo doc, your note, the open-item list): still printed in full, with a line saying the budget was exceeded (Task 5).
5. A vault with only older notes, and one older note whose frontmatter names a different repo: the fallback skips it and never loads another repo's note (Task 6).

## File Structure

| File | Responsibility |
|---|---|
| `tools/hook-templates/session-start-vault-context` | Select, trim and print repo context. Tasks 1 to 6. |
| `tools/hook-templates/test-session-start-vault-context.sh` | Offline tests for the hook. Tasks 1 to 6. |
| `tools/testing/mutation/mutants.txt` | Mutants for the new hook rules. Task 7. |
| `tools/hook-templates/post-merge`, `test-post-merge.sh` | Repo-doc prompt aligned with `/vault-populate`. Task 8. |
| `tools/command-templates/vault-populate.md`, `vault-context.md`, `vault-log.md` | Version 4 prompts. Tasks 9 to 11. |
| `tools/command-templates/test/run-command-tests.mjs` | Manual model-backed cases for the three commands. Tasks 9 to 11. |
| `tools/testing/test-structure.sh` | Version 4 stamps and line ceilings. Task 10. |
| Docs (listed in Task 12) | Describe the new behaviour. |

---

### Task 1: Hook foundations (defaults, resume, author, repo matching)

**Files:**
- Modify: `tools/hook-templates/session-start-vault-context` (defaults at line 171, source check at line 86, `latest_in` at line 201)
- Test: `tools/hook-templates/test-session-start-vault-context.sh`

**Interfaces:**
- Produces (shell functions in the hook, used by Tasks 2 to 6):
  - `AUTHOR_SLUG` (variable): `git config user.name` read in `${CLAUDE_PROJECT_DIR:-.}`, lowercased, spaces to hyphens; empty if unset.
  - `known_repos` (function): prints one repo name per line, found by listing the entries under the part of `reposPath` before `{repo}` and stripping the part after it, cased per `repoNameCase`. Always includes `$REPO_NAME`.
  - `glob_for <repo>`: the filename glob for that repo (today's `NOTE_GLOB` logic, including glob-character escaping, made a function).
  - `belongs_to_repo <filename>`: exit 0 if the name matches `glob_for "$REPO_NAME"` and does not match the glob of any longer known repo whose name starts with `"$REPO_NAME-"`.
  - `is_older_note <filename>`: exit 0 if the name matches no known repo's glob.

- [ ] **Step 1: Write the failing tests** (add to the test file, register at the bottom list). Add helper `fx_named_note <vault> <author> <date> <repo> <topic> <MARKER> <mtime>` that writes `daily-notes/<author>/<date>-<repo>-<topic>.md` through `fx_note`.
  - `test_the_default_pattern_names_the_repo`: no `vault-config.md`; alice has `2026-10-05-widget-a.md` (WIDGETNOTE) and `2026-10-06-gadget-b.md` (GADGETNOTE); output contains `CONTEXT-WIDGETNOTE`, not `CONTEXT-GADGETNOTE`.
  - `test_a_longer_repo_name_does_not_claim_a_shorter_ones_notes`: repos docs exist for `widget` and `widget-ui`; note `2026-10-06-widget-ui-x.md`; hook run in `widget` does not load it, run in `widget-ui` does.
  - `test_resume_loads_nothing_but_startup_and_clear_do`: stdin `{"source":"resume"}` gives empty output; `startup` and `clear` load.
  - `test_known_repos_come_from_the_repos_path_listing`: with `reposPath: Projects/{repo}/index.md`, notes for another listed repo are not loaded (extends the existing flat-vault fixture).
  - `test_repo_names_with_glob_characters_still_match_literally`: keep the existing glob-character test passing with the refactor.
- [ ] **Step 2: Run to confirm they fail.** `bash tools/hook-templates/test-session-start-vault-context.sh`. Expected: the new tests FAIL (and existing tests that rely on the old `{date}-{topic}` default fail until Step 3 fixes their fixtures).
- [ ] **Step 3: Implement the functions above.** Change the default `NAME_PATTERN` to `{date}-{repo}-{topic}`; skip on `compact` and `resume`; replace the single `find -name "$NOTE_GLOB"` with `find -name '*.md'` plus a per-file `belongs_to_repo` check in `latest_in` (a bash `[[ $name == $glob ]]` match, no subprocess per note). Then sweep the existing tests: rename their note fixtures to the new `<date>-<repo>-<topic>` shape through `fx_named_note`; tests that deliberately cover repo-less names set `filenamePattern: "{date}-{topic}"` in their config.
- [ ] **Step 4: Run.** Same command. Expected: `--- N passed, 0 failed ---`.
- [ ] **Step 5: Lint.** `bash tools/testing/test-structure.sh`. Expected: shellcheck test passes.
- [ ] **Step 6: Commit.** `git add tools/hook-templates && git commit -m "feat: session-start hook names notes by repo, skips resume, matches longest repo name"`

---

### Task 2: Your note always, plus others

**Files:**
- Modify: `session-start-vault-context` (candidate selection around lines 224 to 247)
- Test: `test-session-start-vault-context.sh`

**Interfaces:**
- Consumes: `AUTHOR_SLUG`, `belongs_to_repo` (Task 1).
- Produces: `SELECTED` lists your latest note first (when one exists), then up to `MAX_CONTRIBUTORS` other contributors, most recent first. `ALL_SORTED` keeps every contributor's latest note for Task 4. Labels: `Your latest note` for yours, `Latest note from <who>` for others. The trailing line says how many other contributors were left out.

- [ ] **Step 1: Write the failing tests.**
  - `test_your_note_loads_first_even_when_others_are_newer`: git `user.name` "Alice Smith" (set in the fixture repo with `git config user.name`), folders `alice-smith`, `bob`, `carol`; bob and carol newer; output order is `CONTEXT-ALICE`, `CONTEXT-CAROL`, `CONTEXT-BOB`; header contains `Your latest note`.
  - `test_the_limit_counts_others_not_you`: four others plus you, default limit: you plus three others load; the line `1 more contributor(s)` appears; with `CONTEXT_MAX_CONTRIBUTORS=1` you plus one.
  - `test_busier_contributors_never_displace_your_note`: you have the oldest note; five newer contributors; yours still loads.
  - `test_no_user_name_means_nothing_is_yours` (Review Focus 1): `git config user.name` unset (use `GIT_CONFIG_GLOBAL=/dev/null` and a repo with none); up to three load, none labelled `Your`; exit 0. Same with a name that matches no folder.
  - `test_a_solo_install_loads_one_note`.
- [ ] **Step 2: Run, expect the new tests to FAIL.**
- [ ] **Step 3: Implement.** Pull yours out of the sorted candidates by contributor folder equal to `AUTHOR_SLUG`; limit applies to the rest. Update the existing contributor-limit tests to the new meaning (limit counts others).
- [ ] **Step 4: Run, expect all PASS.**
- [ ] **Step 5: Commit** `feat: session-start hook always loads your own note, then up to three others`.

---

### Task 3: Trim levels, no checkbox lines, tag line

**Files:**
- Modify: `session-start-vault-context` (`render_note`, line 280)
- Test: `test-session-start-vault-context.sh`

**Interfaces:**
- Produces: `render_note <path> <contributor> <mine 0|1>`. Yours: Context section, Open Questions section, latest `## Update`, as now. Others: Context section only. In every case lines matching `^- \[[ xX>-]\]` are removed and the note's `tags:` frontmatter line is printed under the heading as `Tags: ...`. Notes with neither forward-looking section still load in full (existing behaviour; their checkbox lines are also removed).

- [ ] **Step 1: Write the failing tests.** Extend `write_note` fixtures with an extra non-checkbox line `PROSE-<marker>` in Open Questions and a `[x]` line `DONE-<marker>`; add a `tags: [daily-note, widget, hooks]` line.
  - `test_others_notes_get_context_only`: yours shows `PROSE-ALICE` and an update; bob's shows `CONTEXT-BOB` but not `PROSE-BOB` and no update.
  - `test_no_checkbox_lines_appear_in_loaded_notes`: no output line starts with `- [ ]`, `- [x]`, `- [-]` or `- [>]`, for yours, others and a full-load note.
  - `test_the_tag_line_is_shown_for_each_loaded_note`: output contains `Tags: [daily-note, widget, hooks]` once per loaded note.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** with `sed -E '/^- \[[ xX>-]\]/d'` applied to extracted sections; read the tag line with an awk pass over the first frontmatter block only.
- [ ] **Step 4: Run, expect PASS.** Existing tests that assert `NEXT-<marker>` is printed must be changed to assert it appears in the open-item list instead (Task 4); mark them with a temporary `skip` until then, and remove the skips in Task 4.
- [ ] **Step 5: Commit** `feat: session-start hook trims others' notes and strips checkbox lines`.

---

### Task 4: Open-item list

**Files:**
- Modify: `session-start-vault-context`
- Test: `test-session-start-vault-context.sh`

**Interfaces:**
- Consumes: `ALL_SORTED` (Task 2).
- Produces: `day_number <YYYY-MM-DD>` (pure bash arithmetic, prints an integer, prints nothing on a malformed date); `open_items_of <path> <contributor>` printing `<age_days><TAB><stale 0|1><TAB><owner><TAB><text>`; a printed section `## Open items for <repo>` listing stale items first, then by age, at most `CONTEXT_MAX_OPEN_ITEMS`, then `and N more`. `CONTEXT_TODAY` (YYYY-MM-DD) overrides today's date, for tests only. `staleOpenItemDays` read with `config_value`, default 30, non-numeric falls back to 30. Items are read from the `## Open Questions / Next Steps` section of each contributor's latest note, whether or not that note was loaded. Age counts from `opened YYYY-MM-DD` on the line, else from the note's filename date.

- [ ] **Step 1: Write the failing tests.**
  - `test_open_items_are_listed_once_with_owner_and_age`: two contributors, items in both; each `- [ ]` text appears exactly once in the output, with the owner name and an `Nd` age.
  - `test_items_from_contributors_beyond_the_limit_are_still_listed`: six contributors, limit 1; all six owners' items appear.
  - `test_an_item_older_than_the_threshold_is_flagged_stale_and_listed_first` (`CONTEXT_TODAY=2026-11-01`; note dated 2026-09-01 gives `stale`; one dated 2026-10-25 does not); `staleOpenItemDays: 5` in `vault-config.md` changes the outcome.
  - `test_opened_date_beats_the_note_date`: a line with `(from [[x]], opened 2026-08-01)` in a note dated 2026-10-30 is stale.
  - `test_the_list_is_capped_with_an_and_n_more_line`: 12 items, default cap gives 10 plus `and 2 more`; `CONTEXT_MAX_OPEN_ITEMS=3` honoured.
  - `test_odd_item_lines_never_crash_or_read_stale_by_accident` (Review Focus 3): CRLF endings, trailing spaces, `- [X]`, a line with `opened 2026-13-45`, a note dated in the future: exit 0, the malformed and future items are not flagged stale.
  - `test_closed_items_are_not_listed`: `[x]`, `[-]`, `[>]` lines never appear.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the functions above. `day_number` uses the civil-from-days style integer formula so it needs no `date -d`.
- [ ] **Step 4: Run, expect PASS.** Remove the temporary skips from Task 3 (their assertions now hold via the list).
- [ ] **Step 5: Commit** `feat: session-start hook lists open items across contributors with stale flags`.

---

### Task 5: Output budget

**Files:**
- Modify: `session-start-vault-context` (build output into variables, then print)
- Test: `test-session-start-vault-context.sh`

**Interfaces:**
- Produces: `CONTEXT_MAX_CHARS` (default 12000, non-numeric or 0 falls back). Output is assembled as fixed parts (repo doc, your note, open-item list) plus others' rendered notes. While the total exceeds the budget, drop the other contributors' notes furthest back first. Print `(N other note(s) left out to stay within CONTEXT_MAX_CHARS=<n>)` for what was dropped. The fixed parts are never cut; if they alone exceed the budget print `(context exceeds CONTEXT_MAX_CHARS=<n> on its own; nothing more was dropped)`. This is the plan's reading of "dropped first, then trimmed further": drop whole notes, never trim yours or the list.

- [ ] **Step 1: Write the failing tests.**
  - `test_over_budget_drops_the_furthest_back_other_note_first`: three others with padded context; `CONTEXT_MAX_CHARS` set so only two fit; the oldest other is missing and named in the left-out line.
  - `test_your_note_and_the_open_items_are_never_cut` (Review Focus 4): `CONTEXT_MAX_CHARS=50`; repo doc, your note and the list are still complete; the exceeds-on-its-own line appears; exit 0.
  - `test_within_budget_prints_everything_and_no_left_out_line`.
  - `test_a_bad_budget_value_falls_back_to_the_default` (`abc`, `0`, empty).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Measure with `${#var}`; keep the existing `echo` order in the final print.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat: session-start hook output has a size budget`.

---

### Task 6: Older-note fallback

**Files:**
- Modify: `session-start-vault-context`
- Test: `test-session-start-vault-context.sh`

**Interfaces:**
- Consumes: `is_older_note` (Task 1), `render_note` (Task 3).
- Produces: `fm_repo <path>` (prints the `repo:` value from the first frontmatter block, lower-cased per `repoNameCase`, or nothing); `older_fallback` which, only when the repo has no notes of its own and the pattern holds `{repo}`, takes the newest older-classified notes (at most 5 frontmatter reads, newest first by filename date then mtime), loads the first whose `fm_repo` is empty or equal to this repo, labelled `Older note (repo unknown, written before per-repo notes)`, and prints `(at least N older note(s) have no repo in the filename)` counted from filenames only. A note whose frontmatter names this repo is treated as this repo's own note. With nothing usable it prints `(No daily notes yet for this repo.)`.

- [ ] **Step 1: Write the failing tests.**
  - `test_a_repo_with_no_notes_loads_the_newest_older_note`: only `2026-10-05-a.md` and `2026-10-06-b.md` (no repo); the newer loads with the older label and the `at least 2` line.
  - `test_the_fallback_stops_once_the_repo_has_a_note` (Review Focus 5 partly): add `2026-10-07-widget-x.md`; the older notes no longer load and the label is gone.
  - `test_an_older_note_naming_another_repo_is_skipped_and_never_loaded` (Review Focus 5): newest older note has `repo: gadget`; the next older one loads.
  - `test_at_most_five_older_notes_are_opened`: eight older notes, all `repo: gadget`; nothing loads, `(No daily notes yet for this repo.)`, and a counting stub (a `repo:` line unreadable past the fifth) proves only five were read.
  - `test_a_note_whose_frontmatter_names_this_repo_counts_as_its_own`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat: session-start hook falls back to the newest older note when a repo has none`.

---

### Task 7: Hook mutants and test docs

**Files:**
- Modify: `tools/testing/mutation/mutants.txt` (group `session-start-vault-context`, currently `cx1` to `cx18`), `docs/testing.md` (hook table around line 185)

- [ ] **Step 1: Run the existing mutants.** `bash tools/testing/run-mutation-tests.sh --hook session-start-vault-context --check-applies`. Expected: any mutant that no longer applies (`cx4`, `cx5`, `cx7`, `cx8` are the likely ones after the refactor) is reported as broken. Rewrite each against the new text, keeping its stated intent.
- [ ] **Step 2: Add mutants `cx19` onwards**, one per rule, each written as `session-start-vault-context@@cxN@@tools/hook-templates/session-start-vault-context@@<sed>@@<what it breaks>`: your note not loaded first; limit counting you; `resume` not skipped; checkbox lines not stripped; stale threshold off by one; opened date ignored; open-item cap ignored; budget ignored; own note cut when over budget; older note with another repo's frontmatter loaded; fallback reading more than five notes; longest-prefix match removed.
- [ ] **Step 3: Run.** `bash tools/testing/run-mutation-tests.sh --hook session-start-vault-context`. Expected: every mutant killed. A survivor means a missing assertion: add it to the matching task's test, not a weaker mutant.
- [ ] **Step 4: Update `docs/testing.md`** with a row per new test (name and what it checks), replacing the rows for tests whose meaning changed.
- [ ] **Step 5: Commit** `test: mutants and test docs for the new hook rules`.

---

### Task 8: `post-merge` aligned with the repo-doc format

**Files:**
- Modify: `tools/hook-templates/post-merge` (prompt, lines 295 to 325)
- Test: `tools/hook-templates/test-post-merge.sh` (the test near line 891 that asserts the `Last updated` stamp, using `has_text`)

- [ ] **Step 1: Write the failing tests** next to the existing prompt tests:
  - `test_prompt_updates_the_frontmatter_fields`: `has_text "last-populated: $(date +%Y-%m-%d)"` and `has_text "source-commit: ${new}"` both `yes`.
  - `test_prompt_protects_the_hand_written_section`: prompt contains `## Hand-written notes` and the word `never` in the same instruction.
  - `test_prompt_keeps_the_doc_tags`: prompt names `repo-doc` and `$REPO_NAME`.
  - Replace the existing stamp assertion with: the old `*Last updated:` instruction is no longer in the prompt.
- [ ] **Step 2: Run** `bash tools/hook-templates/test-post-merge.sh`. Expected: new tests FAIL.
- [ ] **Step 3: Edit the prompt.** Replace instruction 5 with: set `last-populated` and `source-commit` in the frontmatter (add the frontmatter if the doc has none, and remove any old `*Last updated: ...*` line); never change anything under `## Hand-written notes`; keep tags `repo-doc` and the repo name.
- [ ] **Step 4: Run.** Expected: all PASS, including the untrusted-data and validation tests.
- [ ] **Step 5: Commit** `feat: post-merge keeps the repo doc's frontmatter and leaves hand-written notes alone`.

---

### Task 9: `/vault-populate` version 4

**Files:**
- Modify: `tools/command-templates/vault-populate.md` (stamp to version 4)
- Test: `tools/command-templates/test/run-command-tests.mjs` (manual; model calls)

- [ ] **Step 1: Write the failing cases** (same `{ name, run() }` shape as the existing ones, using `mkVault` and `runCommand`):
  - `populate: writes repo, last-populated, source-commit and tags`: frontmatter has all four; tags include `repo-doc` and the repo name.
  - `populate: second run at the same commit stops with 'up to date' and writes nothing`: no `write` call on the second run.
  - `populate: hand-written notes section is untouched after a refresh`: a marker under `## Hand-written notes` survives after a commit changes a file.
  - `populate: aborts when the doc changed between read and write`: the stub changes the doc between the two calls (extend `stub-rest-api-mcp.mjs` with a hook for this if absent); no write happens, the report says so.
  - `populate: a worktree is documented under the main repo's name`: repo created through `git worktree add`; the doc path uses the main folder's name.
  - `populate: unknown source-commit falls back to a full survey`: frontmatter holds a SHA not in history; the run still writes a doc.
- [ ] **Step 2: Run the cases** (`node tools/command-templates/test/run-command-tests.mjs`; the runner's options are at the top of the file). Expected: the new cases FAIL against version 3.
- [ ] **Step 3: Rewrite the template** to the spec's `/vault-populate` section: repo name via `git rev-parse --path-format=absolute --git-common-dir` (folder of the main checkout, `repoNameCase` applied); frontmatter fields; the `## Hand-written notes` rule replacing the "preserve tribal knowledge" sentence; `git diff --name-only <source-commit>..HEAD` when the doc has a `source-commit` in history; "up to date" stop; re-read and abort before writing; tags. Bump the stamp to 4.
- [ ] **Step 4: Run the cases.** Expected: all PASS.
- [ ] **Step 5: Commit** `feat: /vault-populate version 4`.

---

### Task 10: `/vault-context` version 4 and the structure test

**Files:**
- Modify: `tools/command-templates/vault-context.md` (stamp 4), `tools/testing/test-structure.sh`
- Test: `run-command-tests.mjs`, `test-structure.sh`

- [ ] **Step 1: Write the failing tests.**
  - Structure, `test_vault_command_templates_are_at_version_4` and `test_vault_command_templates_stay_under_their_line_ceilings`: stamps equal 4; ceilings are `vault-log.md` 134, `vault-context.md` 56, `vault-populate.md` 54 (measured v3 length 96, 40, 39, plus 40%). If a template cannot fit, tighten its wording first; raising a ceiling needs the user told.
  - Command cases: `context: loads your latest note and up to three others for this repo only`; `context: a note for another repo is never loaded`; `context: open items are listed once with owner and age, stale first`; `context: with nothing for the repo it loads the newest older note and labels it`; `context: hook output already in the conversation is not reloaded` (the system prompt carries a hook block; no `read` calls for the same notes); `context: a topic search returns at most 5 notes and says how many more matched`.
- [ ] **Step 2: Run, expect FAIL** (`bash tools/testing/test-structure.sh`, then the command cases).
- [ ] **Step 3: Rewrite `vault-context.md`** to the spec's Context loading section, including the common-dir repo rule (line 31 uses `--show-toplevel` today) and the `staleOpenItemDays` setting row. Keep the backend table and settings step as they are.
- [ ] **Step 4: Run.** Expected: the `vault-context` cases and the structure test for this template PASS (the `vault-log` ceiling test stays red until Task 11).
- [ ] **Step 5: Commit** `feat: /vault-context version 4 and template size checks`.

---

### Task 11: `/vault-log` version 4

**Files:**
- Modify: `tools/command-templates/vault-log.md` (96 lines now; stamp 4; ceiling 134)
- Test: `run-command-tests.mjs`

- [ ] **Step 1: Write the failing cases:**
  - `log: three repos in one session give three notes, each with its own tags and only its own work`: path `daily-notes/<author>/<date>-<repo>-<topic>.md` for each; frontmatter `repo:`; tags include `daily-note`, the repo and a theme tag shared by all three; no repo's marker text appears in another's note.
  - `log: a repo that was only glanced at gets no note`.
  - `log: a repo investigated with no edits gets a note`.
  - `log: default config appends only to today's note for the same repo` (`same-day-same-repo`).
  - `log: reconcile ticks a done item, drops a dropped one, carries an untouched own item silently with its opened date`: old note markers become `[x]`, `[-]`, `[>]` with the parentheticals from the spec; the new note carries `(from [[...]], opened YYYY-MM-DD)`.
  - `log: another author's items are only closed with evidence`: an untouched item in bob's note is unchanged; a done one is ticked; only checkbox lines and their parentheticals differ.
  - `log: partly touched and stale items are put to the user in one message`.
  - `log: adoption offers your newest older note once`: carried items marked `[>]`, never offered again.
  - `log: the report is one line per note plus extras for attention cases, capped at 10` (edit to another's note, skipped edit, glanced repo, stale item, adoption, unanswered question).
  - `log: an edit is skipped when the line changed since it was read`.
  - `log: no open items means no reads of older notes`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Rewrite `vault-log.md`** to the spec's `/vault-log` and Open items sections. Decisions already fixed by the spec: repo from the common dir; repo discovery from the conversation; step order (find repos, decide which count, reconcile, write one note per repo, tags, keep notes small, report); new defaults in the settings table (`filenamePattern`, `appendRule` with its new value, `staleOpenItemDays`); on `rest-api` the append and the marker edits are a read then a full rewrite changing only the intended lines, on `mcpvault` use `mode: append` and `patch_note` for markers.
- [ ] **Step 4: Run the cases and `bash tools/testing/test-structure.sh`.** Expected: all PASS, including the ceiling.
- [ ] **Step 5: Commit** `feat: /vault-log version 4`.

---

### Task 12: Docs, example note and full run

**Files:**
- Modify: `docs/vault-config.md` (rows at lines 18 to 20 and the "read by" notes at 39 and 40), `runbooks/using-the-vault.md` (template at line 97 and the same-day rule), `tools/skill-templates/obsidian-vault-conventions/SKILL.md` (naming and same-day lines), `docs/automation.md` (command blurbs at lines 34 to 40, hook section at 134 to 160), `runbooks/daily-workflow.md` (lines 17 to 29 and 114), `runbooks/adopting-for-a-new-team.md` (checklist at line 28), `daily-notes/example-person/2026-01-01-example-note.md`

- [ ] **Step 1: Update each file** to the spec: new defaults and the `same-day-same-repo` value; `staleOpenItemDays`; the four hook limits; the marker table and `opened` rule; `repo:` frontmatter and tag; yours-plus-three loading; `resume` skip; the older-note fallback and its fade-out; `/vault-populate` frontmatter, protected section and skip-if-unchanged; the note that the line-level and append savings apply on MCPVault only, with full rewrites on the REST API. For the example note, keep its path and add `repo: widget-service`, tag `widget-service` and a carried item showing the `opened` format.
- [ ] **Step 2: Check the docs.** `grep -rn "same-day-any-topic\|{date}-{topic}\|show-toplevel" docs runbooks tools/skill-templates tools/command-templates`. Expected: only mentions that describe the old value as an alternative or as the legacy default.
- [ ] **Step 3: Run everything.** First `git diff --name-only main... | grep -v '\.md$'` and run `shellcheck -S warning -x` on each shell file listed (expected: no output). Then `bash tools/testing/run-all-tests.sh`. Expected: all suites pass. Then `bash tools/testing/run-mutation-tests.sh --hook session-start-vault-context`. Expected: no survivors.
- [ ] **Step 4: Commit** `docs: describe per-repo notes, open-item tracking and the new hook limits`.
- [ ] **Step 5: Hand back.** Report the results and the manual command-test run; do not open the PR until asked.

---

## Self-Review

- **Spec coverage:** note identity and defaults (Tasks 1, 11, 12); finding by listing and longest-prefix matching (1); own plus others (2); trim levels, checkbox stripping, tags (3); open-item list, stale, cap, `staleOpenItemDays` (4); budget (5); older-note fallback and count (6); resume skip (1); reconcile, adoption, ownership rules, silent carry, report, safe edits (11); populate changes and skip logic (9); `post-merge` alignment (8); versions, ceilings, mutants, docs (7, 10, 12). Author identity as one shared rule: the hook uses `AUTHOR_SLUG` from `git config user.name` and the template step 1 already does the same, so no extra task.
- **Plan decisions to check:** budget means whole-note dropping (Task 5); `CONTEXT_TODAY` test seam (Task 4); `post-merge` replaces the body stamp with frontmatter (Task 8); ceilings 134, 56 and 54 (Task 10); the hook sets no behaviour on a note whose frontmatter `repo` disagrees with its filename except in the fallback (Task 6).
- **Proportion:** the plan is a list of interfaces, test names with assertions and the decisions the spec fixes; function bodies are left to the implementer.
