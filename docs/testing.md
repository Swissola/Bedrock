# Testing the tools

> **Scope:** everything under `tools/` that does something (the five git and session hooks, the installer, the MCP setup scripts, the wiki staging script and the test stub) has an isolated test suite, and this page says what each one checks, in plain English. It also lists what is deliberately not tested, the defects the suites found and how they were fixed, and the one rule that keeps the whole set honest: a hook with no suite, or a suite nobody runs, fails a check.

## Running them

```bash
bash tools/testing/run-all-tests.sh              # everything, one suite after another
bash tools/testing/run-all-tests.sh --parallel   # everything at once (much quicker; each suite uses its own temp folders)
bash tools/testing/run-all-tests.sh --only hook  # just the suites whose name contains "hook"
bash tools/testing/run-all-tests.sh --list       # what there is
```

Or run any suite on its own, for example `bash tools/hook-templates/test-pre-push.sh`. Each prints one `PASS:` or `FAIL:` line per check and ends with a summary; the exit status is 0 only if nothing failed.

On Windows the suites run under Git for Windows' bash, and the PowerShell suite runs with `pwsh tools/testing/test-powershell-scripts.ps1` (and, because most Windows users start scripts with the built-in one, `powershell -File tools/testing/test-powershell-scripts.ps1`). The `post-merge` suite is slow on Windows, about seven minutes, because every check starts several git processes. `--parallel` brings the whole set to roughly that.

Nothing here touches a real vault, a real `~/.claude`, a real `claude` or a real network. Hooks run against throwaway git repos under `mktemp`, with `HOME` pointed at a temp folder where a hook keeps state, and `claude`, `curl` and `betterleaks` are stubs on `PATH`. Every suite removes its fixtures from an exit trap, so a failing check does not leave them behind.

## What is deliberately not covered

- **The model-driven command harness** (`tools/command-templates/test/run-command-tests.mjs`). Every scenario is a real `claude -p` call: it costs money, it is probabilistic, and it needs the CLI. It is run by hand or from the manual "model harness" workflow, not as an automatic check. The stub it talks to (`stub-rest-api-mcp.mjs`) is tested, though.
- **A real Obsidian, a real Local REST API plugin, a real `claude` run.** The suites prove each script's own logic and the arguments it passes on. They cannot prove that Obsidian accepts the file `setup-mcp` edits, or that a real model behaves.
- **`betterleaks`' own detection.** Only the hook's handling of the scanner is tested, plus an optional pair of checks that run the real scanner if it is installed (see below).
- **The CI workflows themselves.** They have not been run on GitHub from this branch. The commands they contain are the ones that were run locally.

## Defects the suites found, and how they were fixed

Writing the suites turned up four defects in the tools themselves. Each was found by a check that failed, confirmed by hand, and then fixed with a separate go-ahead. Each fix has a regression test, so it stays fixed.

| Where | What was wrong | Fix |
|---|---|---|
| `tools/hook-templates/pre-commit` | A file **renamed and edited in the same commit** was not scanned. The hook listed staged files with `--diff-filter=ACM`, which leaves out renames, so if that was all that was staged the hook saw nothing and exited 0, even in strict mode. Confirmed against the real `betterleaks`: it found an AWS key in such a file, the hook did not. | `--diff-filter=ACMR` |
| `tools/wiki/prepare-wiki-docs.ps1` | The heading-stripping regex had no "first only" limit, so it also deleted **every line starting `# `** in the body, including shell comments inside fenced code blocks. | Only the first match (the title) is stripped |
| `tools/setup-mcp.ps1` under **Windows PowerShell 5.1** | `Set-Content -Encoding utf8` wrote a **byte order mark**, so the plugin's `data.json` started with U+FEFF, which a strict JSON parser rejects (that Obsidian then failed to read its own settings is the likely result but was never checked). The read side was also wrong: `Get-Content` there reads BOM-less UTF-8 as ANSI. | Read with `ReadAllText`, write with `WriteAllText` and `UTF8Encoding($false)` |
| `tools/install-claude-config.ps1` | When Git for Windows' bash was not found it set `$ErrorActionPreference = 'Stop'`, so `Write-Error` ended the script with exit 1 before the intended `exit 2`. | `Write-Error ... -ErrorAction Continue` |

The suites can also record a confirmed, not-yet-fixed defect as an expected failure (`expect_defect` in the bash suites, `Expect-Defect` in the PowerShell one). It prints `KNOWN DEFECT:` without turning the run red, `run-all-tests.sh` repeats the line in its summary, and the check turns into a real failure the moment the tool is fixed, which is the prompt to make it a plain assertion. None is open at the moment.

Two behaviours are pinned as they are rather than as defects, but are worth knowing: in strict mode `pre-commit` still lets a commit through when `betterleaks` is not installed (there is nothing to enforce with, so it warns), and any non-zero exit from the scanner, including a crash, counts as a finding.

## Skipped checks

A skip is printed as `SKIP:` and is never counted as a pass.

| Check | Skipped when | Why |
|---|---|---|
| `post-merge`, perl timeout, hung-run | Running under Git Bash on Windows | MSYS perl loses the alarm across `exec`; Windows always has a real `timeout` so the branch is not used there. No ticket: it cannot be tested on that platform. |
| `post-merge`, `gtimeout` | `gtimeout` not installed | The macOS CI job installs it. |
| `pre-commit`, real `betterleaks` | `betterleaks` not installed | Needs the real binary. CI installs a pinned, checksum-verified copy (v1.9.0) on the Ubuntu job only, so they run there and skip on macOS and Windows. |
| Installer, backslash vault path | No `cygpath` (not Windows) | Only meaningful with a Windows path. |
| Installer, double quote in vault path | The filesystem cannot create such a folder | Windows. |
| Structure, `shellcheck` | Not installed | Advisory locally. CI turns it into a gate on the Ubuntu job (see below). |

## The suites, test by test

### `tools/hook-templates/test-pre-push.sh`: the `pre-push` hook

The hook warns, never blocks, when the vault has commits not yet on origin at the moment you push some other repo.

| Test | What it checks |
|---|---|
| `silent_and_exit_0_when_vault_root_cannot_be_derived` | Outside any repo, with no `VAULT_ROOT`, it says nothing and exits 0. |
| `silent_when_the_repo_being_pushed_is_the_vault_itself` | Pushing the vault itself gives no warning (its commits are what is being sent) and writes no throttle marker. |
| `silent_when_vault_has_no_main_branch` | A vault on a branch called something other than `main` is left alone. |
| `silent_when_vault_has_no_origin` | A vault with no `origin` remote is left alone. |
| `silent_when_vault_is_in_sync_with_origin` | Nothing unpushed: silence, no marker. |
| `silent_when_vault_is_only_behind_origin` | Origin ahead of the vault is not "unpushed commits". |
| `warns_with_count_path_and_push_command` | With three pending: exit 0, the count, the vault path and the exact `git -C ... push` command appear on stderr, stdout stays empty, the marker is written. |
| `warns_for_a_single_pending_commit` | The one-commit case. |
| `counts_only_local_commits_when_origin_has_diverged` | When origin has a commit the vault lacks, only the vault's own unpushed commits are counted. |
| `commit_subjects_are_never_echoed` | A commit message never appears in the warning (commit messages are chosen by whoever can commit). |
| `creates_its_state_directory_when_missing` | A fresh `HOME` with no `.claude` still works. |
| `vault_path_with_a_space_is_handled` | A vault path with a space is quoted correctly. |
| `second_warning_within_cooldown_is_suppressed` | Two pushes in a row warn once. |
| `throttled_run_does_not_move_the_marker` | Being throttled does not extend the throttle. |
| `warns_again_once_cooldown_has_passed` | At 700 seconds of a 600 second cooldown it warns again and refreshes the marker. |
| `cooldown_boundary_just_inside_is_throttled` / `..._just_outside_warns` | 570 seconds is still quiet, 630 seconds warns. |
| `multi_ref_stdin_is_consumed_without_hanging` | The several lines git sends on stdin do not hang or break it. |
| `empty_stdin_still_works` | Nothing on stdin still works. |
| `installed_as_a_real_hook_warns_but_the_push_succeeds` | Installed as `.git/hooks/pre-push`, a real `git push` succeeds, the warning reaches the terminal and the other repo's commits arrive. |

### `tools/hook-templates/test-session-start-vault-check.sh`: the `session-start-vault-check` hook

The hook reminds you, at session start and (throttled) after tool calls, that the vault has unpushed commits.

| Test | What it checks |
|---|---|
| `silent_and_exit_0_when_vault_root_cannot_be_derived` / `..._no_main_branch` / `..._no_origin` | The three "nothing to check" cases are silent, exit 0 and record no check. |
| `in_sync_is_silent_but_records_that_a_check_ran` | Up to date: nothing printed, but the marker is written because a real check happened. |
| `silent_when_vault_is_only_behind_origin` | Behind origin is not unpushed. |
| `compact_source_skips_even_with_pending_commits` | A `/compact` is skipped entirely, no marker. |
| `session_start_reports_count_hashes_and_commands` | Count, path, the review command and the push command, all on stdout. |
| `reminder_lists_exactly_the_pending_short_hashes` | The short hashes of the pending commits, newest first. |
| `single_pending_commit_is_reported` | The one-commit case. |
| `counts_only_local_commits_when_origin_has_diverged` | Only the vault's own unpushed commits are counted. |
| `commit_subjects_are_never_echoed` | No commit message text reaches the output. |
| `vault_path_with_a_space_is_handled` | Quoting. |
| `session_start_is_never_throttled` | A session start reminds even with a five second old marker. |
| `post_tool_use_first_check_is_not_throttled` | The first periodic check reminds and writes the marker. |
| `post_tool_use_within_cooldown_is_silent_and_leaves_marker` | Within the hour: quiet, marker untouched. |
| `post_tool_use_after_cooldown_reminds_and_refreshes_marker` | Past the hour: reminds, marker refreshed. |
| `cooldown_boundary_just_inside_is_throttled` / `..._just_outside_reminds` | 3570 seconds is quiet, 3630 seconds reminds. |
| `throttled_post_tool_use_still_reminds_at_next_session_start` | Being throttled on tool calls never silences the next session start. |
| `without_jq_it_still_checks_and_never_throttles` | No `jq`: the event is unknown, so it checks every time. |
| `without_jq_compact_cannot_be_detected_so_it_still_checks` | No `jq`: it cannot see `compact`, and errs on the side of checking. |
| `malformed_stdin_still_checks` / `empty_stdin_still_checks` | Bad or missing input fails open. |
| `json_without_an_event_name_is_treated_as_unthrottled` | JSON with no `hook_event_name` is treated like a session start. |

### `tools/hook-templates/test-pre-commit.sh`: the `pre-commit` hook

The secret scan on staged changes. Warns by default, blocks with `PRECOMMIT_SECRET_SCAN_STRICT=1`.

| Test | What it checks |
|---|---|
| `no_staged_changes_exits_zero_silently` | Nothing staged: silent, exit 0. |
| `no_scanner_installed_warns_every_time_but_never_blocks` | No `betterleaks`: the install notice shows on every commit (not throttled), exit 0. |
| `betterleaks_clean_exits_zero_no_banner` | A clean scan shows nothing. |
| `betterleaks_dirty_warns_but_does_not_block_by_default` | A finding shows the banner and the scanner's own text but exits 0. |
| `betterleaks_dirty_strict_mode_blocks` | The same finding with strict mode on exits 1. |
| `scanner_is_called_to_scan_the_staged_changes_with_redaction` | On betterleaks 1.x the scanner is called as `git --staged --redact -v`: staged changes only, secrets redacted, `-v` for per-finding detail. |
| `betterleaks_2x_is_never_given_the_verbose_flag` | On 2.x (including release candidates) the call is `git --staged --redact` with no `-v`, because in 2.x `-v` switches on live validation of any credential found, not verbose output. |
| `an_unreadable_betterleaks_version_gets_no_verbose_flag` | If the version cannot be read, or has no number in it, the safe form without `-v` is used. |
| `a_2x_finding_still_blocks_in_strict_mode` | A finding reported by a 2.x scanner blocks the commit in strict mode and its text is shown. |
| `deleted_files_alone_are_not_scanned` | A commit that only deletes files never invokes the scanner, even in strict mode. |
| `modified_files_are_scanned` | A modified file is scanned. |
| `renamed_and_edited_file_is_scanned` | Regression test for the rename bug above: a renamed-and-edited file is scanned and, in strict mode, blocked. |
| `first_commit_in_an_empty_repo_is_scanned` | No `HEAD` yet: staged files are still scanned and strict still blocks. |
| `strict_accepts_1_and_true_only` | `1` and `true` block; `0`, `false`, empty, `yes`, `TRUE` and `on` do not. |
| `strict_with_a_clean_scan_still_passes` | Strict mode does not block clean commits. |
| `strict_without_a_scanner_warns_but_cannot_block` | Pins today's behaviour: strict with no scanner warns and exits 0. |
| `any_nonzero_scanner_exit_is_treated_as_a_finding` | Exit codes 1, 2, 126 and 127: strict blocks, default warns, the scanner's message is shown. |
| `scanner_output_on_both_streams_reaches_the_banner` | Both stdout and stderr from the scanner are shown. |
| `banner_tells_the_user_what_to_do` | The banner names the unstage command, `--no-verify` and the allowlist file. |
| `clean_scan_prints_nothing` | The scanner's chatter is swallowed when it finds nothing. |
| `hook_works_from_a_subdirectory_and_with_spaces_in_filenames` | Run from a nested folder, with an awkward file name. |
| `real_commit_is_blocked_in_strict_mode_and_nothing_is_committed` | Through a real `git commit`: it fails, `HEAD` does not move, the file stays staged. |
| `real_commit_goes_through_with_a_warning_by_default` | Through a real `git commit`: it succeeds and the warning was shown. |
| `no_verify_skips_the_hook_even_in_strict_mode` | `--no-verify` bypasses it and the scanner never runs. |
| `real_betterleaks_flags_a_staged_secret_in_strict_mode` | **Only if `betterleaks` is installed.** A realistic fake AWS key is blocked and its value is redacted in the output. |
| `real_betterleaks_passes_a_clean_staged_file` | **Only if installed.** Ordinary prose passes silently. |

### `tools/hook-templates/test-post-merge.sh`: the `post-merge` hook

The hook that, after a pull to the default branch, has an AI assistant update the repo's vault doc, unattended.

The original scenarios are unchanged:

| Test | What it checks |
|---|---|
| `not_default_branch_exits_immediately` | A pull on a feature branch does nothing. |
| `doc_target_missing_aborts_without_running` | No `repos/<name>/index.md` yet: it logs why and never calls `claude`. |
| `no_relevant_changes_does_not_invoke_claude` | A `.gitignore`-only change is ignored. |
| `secret_shaped_files_do_not_invoke_claude` | `.env` and `.pem` changes alone are ignored. |
| `kill_switch_short_circuits` | The disabled-marker file stops it. |
| `missing_jq_aborts_without_running_unfenced` | No `jq`: it will not run rather than interpolate filenames unfenced. |
| `relevant_change_invokes_claude_and_commits` | A relevant change runs `claude`, updates the doc and commits it locally. |
| `retries_once_on_exit_127` | Exit 127 (command not found) is retried once. |
| `mcp_unavailable_marker_downgrades_exit_code` | A "vault unreachable" message turns a reported success into exit 2. |
| `unexpected_new_file_is_removed_not_reverted` / `unexpected_modification_to_tracked_file_is_reverted` / `no_unexpected_writes_stays_success` | Anything the run wrote outside the doc is undone, and a clean run stays a success. |
| `invocation_security_shape` | `--restricted`, `--mcp-config`, `--strict-mcp-config`, `--model sonnet`, and never `--dangerously-skip-permissions`. |
| `hostile_filename_is_fenced_not_executed` | A filename that reads like an instruction is passed as quoted data inside a fence. |
| `non_git_vault_*` (four) | A vault that is a plain folder: updates succeed with no commit, unexpected writes are flagged and not deleted, dot-folder churn is ignored. |
| `repos_path_*`, `vault_root_*`, `*_backend_*` | The `vault-config.md` doc path (and the unsafe-path fallback), where `VAULT_ROOT` comes from, and the two MCP backends' tool names. |
| `with_timeout_every_branch` | `timeout`, `gtimeout`, `perl` and no limit each work, and a hung run is cut off. |

Added:

| Test | What it checks |
|---|---|
| `noise_and_secret_shaped_files_never_reach_the_prompt` | One commit holding 23 filtered files (lock, log, tmp, tfstate and its backup, `.cache/`, `.terraform/`, `.ansible/`, `.env*`, `.pem`, `.key`, `.pfx`, `.p12`, `settings.local.json`, `credentials.json`, `id_*`, `.gitignore`) plus five ordinary ones that must stay (`src/cache/data.json`, `package-lock.json` and others). Each name is checked in the captured prompt individually. |
| `prompt_and_arguments_carry_the_right_context` | The prompt names the repo, the commit range, the doc, today's date and the new sha, forbids patch edits and says what to print if the vault is unreachable; only the changed file is listed; the allowed tools include read and write and no patch tool and no shell. |
| `log_records_range_files_commit_and_output` | The run log's header, changed-file list, the "auto-committed locally (not pushed)" line, the model's output and the end marker. |
| `auto_commit_touches_only_the_doc_and_is_never_pushed` | The commit contains exactly the doc, its message names the doc and sha, and a bare origin does not move. |
| `a_failed_run_is_logged_and_never_committed_and_never_blocks_the_pull` | `claude` exiting 1: the hook still exits 0, the log shows `exit=1`, nothing is committed, the failure is recorded for the next session. |
| `each_vault_unreachable_message_downgrades_to_exit_2_and_skips_the_commit` | The other three "unreachable" messages each give exit 2 and no commit. |
| `the_hook_returns_before_a_slow_claude_finishes` | With a `claude` that waits until the test releases it, the hook itself returns (exit 0) while the run is still going, so no run log exists yet; once released, the background run completes and is logged. It uses no clock, so a busy machine cannot make it flake. |
| `unacknowledged_failures_are_surfaced_once_then_only_new_ones` | Earlier failures are printed once, not repeated, and only new ones appear afterwards. |
| `no_default_branch_or_a_detached_head_does_nothing` | No `origin/HEAD`, or a detached `HEAD`: `claude` is never called. |
| `the_repo_is_named_after_its_folder_not_its_remote` | A folder and a remote with different names: the log and the doc it asks for use the folder's. |
| `a_repo_with_no_origin_is_named_after_its_folder` | No remote needed. |
| `the_repo_name_is_lowercased_by_default_and_kept_with_repo_name_case_keep` | Default and `lower` lowercase the log name and the doc path, `keep` uses the folder's case. |
| `the_global_kill_switch_stops_the_hook_in_every_repo` | `~/.claude/hook-templates/DISABLED` (or `VAULT_HOOK_DISABLED_FILE`) stops the run before it starts, and removing it lets the hook run again. |

### `tools/hook-templates/test-session-start-vault-context.sh`: the `session-start-vault-context` hook

Loads the repo's vault doc and, for each contributor, the latest daily note about this repo (forward-looking sections only) at session start.

Original scenarios: no vault root, no repo doc, the default layout, the latest note from each contributor, `compact` and malformed stdin, a note with no forward sections, no notes, `vault-config.md` paths and quoting and CRLF, an unclosed config, unsafe config paths, the `{author}` placeholder, and the appended-update handling (latest only, truncation, position, update-only notes).

Added:

| Test | What it checks |
|---|---|
| `the_hook_always_exits_zero` | Exit 0 with no vault, on compact, on a normal load, with no repo doc and with a vault that does not exist. |
| `every_source_except_compact_injects_context` | `startup`, `resume`, `clear`, `fork` and an unknown source all load. |
| `compact_is_recognised_whatever_the_json_layout` | Spaces around the colon, other fields, several lines; and the word "compact" in another field does not skip. |
| `repo_name_falls_back_to_the_folder_name_without_an_origin` | No `origin`: the folder name is used. |
| `the_repo_is_named_after_its_folder_not_its_remote` | A folder and a remote with different names: the folder's doc is loaded. |
| `the_repo_name_is_lowercased_by_default_and_kept_with_repo_name_case_keep` | Default and `lower` lowercase, `keep` uses the folder's case, an unknown value is the default. |
| `the_case_setting_also_decides_which_notes_belong_to_the_repo` | With `keep`, a note named in a different case is a different repo's. |
| `a_linked_worktree_is_the_same_repo_as_its_main_checkout` / `a_subfolder_of_the_repo_is_still_the_repo` / `claude_project_dir_wins_over_the_working_directory` / `outside_a_git_repo_the_folder_name_is_used` | The ways the hook can be started, all naming the repo correctly. |
| `every_contributors_latest_note_is_loaded_most_recent_first` / `only_each_contributors_newest_note_is_loaded` | One note per contributor, newest first, labelled with who wrote it. |
| `the_contributor_limit_defaults_to_three_and_can_be_changed` | Three by default with a "more contributors" line, `CONTEXT_MAX_CONTRIBUTORS` 1 and 9, and a non-number falling back to three. |
| `the_filename_date_beats_the_modification_time` / `the_modification_time_breaks_a_tie_on_the_same_date` | A git checkout's pull times do not decide which note is latest; same date: the newer file. |
| `another_repos_newer_note_is_never_loaded` / `a_repo_with_no_notes_says_so_even_when_others_have_some` | The repo filter, and "No daily notes yet for this repo." |
| `the_repo_filter_needs_the_whole_name_between_separators` / `glob_characters_in_a_repo_name_match_literally` | `widgetry` and `mywidget` are not `widget`; brackets and a star in a repo name are literal. |
| `the_repo_filter_works_together_with_contributor_folders` / `without_a_repo_in_the_pattern_every_note_is_a_candidate` | Contributors with no note about this repo are skipped; with no `{repo}` in the pattern nothing is filtered. |
| `hidden_conflict_and_non_markdown_files_are_never_candidates` | Dot-files, files in dot-folders, Syncthing conflict copies, `.txt` and temp files. |
| `the_personal_vault_layout_end_to_end` | A flat vault, repo in the filename, `repoNameCase: keep`: another repo's newer note never reaches this session. |
| `output_starts_with_the_context_header` | The exact first line. |
| `a_note_with_only_one_forward_section_loads_just_that_one` | Context only, and next-steps only, without the history. |
| `sections_end_at_the_next_heading_and_keep_their_subheadings` | A section stops at the next `##` and keeps its `###` content. |
| `non_markdown_files_are_never_picked_as_the_latest_note` | A newer `.txt` file is ignored. |
| `notes_in_nested_folders_and_with_spaces_in_the_name_are_found` | Deep folders and spaces. |
| `an_empty_daily_notes_folder_says_there_are_no_notes` | The "no daily notes" message, with the repo doc still loaded. |
| `a_note_with_windows_line_endings_is_still_loaded` | CRLF notes still reach the session. |
| `the_hook_never_writes_to_the_vault` | Every vault file keeps its content, none added or removed. |
| `update_cap_can_be_changed_with_update_max_lines` | The cap can be lowered and raised. |
| `update_stops_at_the_next_heading_and_counts_earlier_updates` | Only the last update, nothing after it, and "2 earlier update(s)". |
| `a_repos_path_without_a_placeholder_names_one_fixed_doc` | A fixed doc path. |
| `config_values_with_trailing_comments_and_empty_values` | Trailing `# comment` stripped; empty values use defaults. |
| `a_longer_config_key_is_not_mistaken_for_a_shorter_one` | `reposPathExtra` is not read as `reposPath`. |

### `tools/testing/test-install-claude-config.sh`: the installer

Original scenarios: dry run, fresh install, idempotence, `--check`, update of a stale copy, the vault-root file and `--force`, a missing vault, the `mcpvault` config written once, the REST API note, unknown options, nothing written to `HOME` without `--prefix`, the session-start wrapper end to end, and `--no-skills`.

Added:

| Test | What it checks |
|---|---|
| `every_command_skill_and_hook_in_the_repo_is_installed_byte_for_byte` | Every source file is installed, identical, hooks executable, wrapper executable. |
| `invalid_backend_is_a_usage_error` / `empty_prefix_is_a_usage_error` | Exit 2 with a clear message, nothing installed. |
| `help_prints_usage_and_exits_zero` | `-h` and `--help`. |
| `option_order_does_not_matter` | Options in any order. |
| `vault_root_is_idempotent_for_the_same_vault` | The same vault twice: "unchanged", one line in the file. |
| `crlf_in_an_existing_vault_root_file_still_counts_as_the_same_vault` | A CRLF file is not mistaken for a different vault. |
| `dry_run_with_a_vault_reports_but_writes_nothing` | "would write" for both files, nothing created. |
| `check_mode_never_writes_anything_even_with_a_vault` | `--check` creates nothing and exits 1 on an empty prefix. |
| `check_lists_every_missing_item_by_label` | Command, skill, hook and wrapper each named. |
| `installed_copy_newer_than_the_repo_is_reported_as_differs_not_outdated` | A higher installed version is not called outdated. |
| `outdated_message_gives_both_version_numbers` | "installed version 0, repo has N". |
| `update_keeps_a_replaced_hook_executable` | A stale, non-executable hook is replaced and made executable. |
| `unwritable_destination_fails_loudly_with_exit_1` | A prefix under a regular file: "FAILED to write", exit 1. |
| `no_skills_leaves_already_installed_skills_alone` | `--no-skills` does not remove skills. |
| `mcpvault_without_a_vault_writes_no_config` | No vault, no config. |
| `mcpvault_config_points_at_the_vault_and_is_exact` | The exact JSON written. |
| `backslashes_in_a_windows_vault_path_are_normalised` | Windows-style paths are stored with forward slashes. |
| `vault_path_with_a_double_quote_is_not_written_into_the_json` | No invalid JSON is produced. |
| `wrapper_prefers_vault_root_from_the_environment_over_the_file` | The environment wins. |
| `wrapper_reads_a_crlf_vault_root_file` | CRLF in the file still resolves. |
| `wrapper_without_any_vault_root_is_silent` | No vault anywhere: silent, exit 0. |
| `statusline_is_opt_in` | Without `--statusline` nothing is installed, `settings.json` is untouched and no backup is made. |
| `statusline_install_copies_the_script_and_sets_settings` | The script is copied byte for byte; the command is `node` plus an absolute, forward-slash path (never `~`); no backup when there was no file. |
| `statusline_second_run_changes_nothing` | Unchanged, no backup, no re-install. |
| `statusline_keeps_other_settings_and_backs_up` | Every other key survives in order; the backup is the original, byte for byte. |
| `statusline_keeps_a_different_status_line_unless_forced` | A different `statusLine` is kept, the snippet and `--force` are printed; `--force` replaces it after a backup. |
| `statusline_hand_installed_tilde_form_is_left_alone` | An existing `node ~/.claude/statusline.mjs` is not rewritten, even with `--force`. |
| `statusline_invalid_json_is_never_touched` | Exit 1, file untouched, no backup or temp file, the snippet is given; the script is still copied. |
| `statusline_dry_run_writes_nothing` | "would install" and "would create"; nothing written, even with `--force`. |
| `statusline_check_mode` / `..._check_does_not_fail_for_a_different_status_line` | Missing is exit 1, current is exit 0, a modified script is "differs"; a different line is not a failure because re-running would not change it. |
| `statusline_relative_prefix_gives_an_absolute_command` / `..._path_with_a_space_is_quoted` | A relative `--prefix` still gives an absolute path; a path with a space or a `$(...)` is single-quoted so a shell expands nothing in it, and one with a single quote is refused. |
| `statusline_without_node_copies_the_script_and_warns` | With no `node` on `PATH` the script is copied, `settings.json` is not created, the snippet is printed, exit 0. Skipped under Git Bash, where a node-free `PATH` cannot be built. |
| `help_documents_the_statusline_flag` / `force_without_statusline_never_edits_settings` | `--help` lists the flag; `--force` alone never touches `settings.json`. |

### `tools/testing/test-setup-mcp.sh`: `setup-mcp.sh`

The five steps of the Obsidian MCP setup, with `claude` and `curl` stubbed and a fixture `data.json`.

| Test | What it checks |
|---|---|
| `fails_when_claude_is_not_installed` | Exit 1, the message and the install command. |
| `reports_the_vault_path_and_claude_version` | Vault path is the folder above `tools/`; step 1 shows the version. |
| `fails_when_the_plugin_is_not_installed` | Exit 1, names the missing file, nothing registered. |
| `switches_the_http_server_on_and_stops_for_a_restart` | `false` becomes `true`, a `.bak` is kept, exit 0, and it stops before registering or probing. |
| `changes_nothing_else_in_data_json_when_enabling` | Every other line is preserved. |
| `continues_when_the_http_server_is_already_on` | No rewrite. |
| `fails_when_the_plugin_config_has_no_enable_setting` | Exit 1, says the format may have changed. |
| `fails_when_there_is_no_api_key` / `fails_when_the_api_key_is_empty` | Exit 1, nothing registered. |
| `the_api_key_is_never_printed` | The key is not in stdout or stderr. |
| `default_port_is_used_when_the_config_has_none` / `a_custom_port_is_used_for_registration_and_the_probe` | Port 27123 by default, the configured port otherwise, for both the registration and the probe. |
| `api_key_is_read_from_compact_json_formatting` | `"apiKey":"..."` with no space. |
| `removes_then_adds_the_registration_with_the_key_and_user_scope` | The exact two `claude mcp` calls, in order. |
| `a_failing_remove_does_not_stop_registration` | First-time setup, where there is nothing to remove, still works. |
| `running_twice_re_registers_each_time` | Safe to re-run. |
| `succeeds_when_the_endpoint_answers_200` | Exit 0, bearer key sent to `/vault/`. |
| `fails_when_the_endpoint_answers_anything_but_200` | 401, 404, 500 and 000 each exit 1 and name the status. |

### `tools/command-templates/test/test-stub-rest-api-mcp.mjs`: the stub MCP server

The stand-in for the Obsidian plugin that the command harness uses. Run with `node`.

- **Path guard:** the five tool names; reads and writes inside the vault; refusal of `../`, absolute paths and symlinks or junctions that point outside, for both reads and writes; the usage errors.
- **Protocol:** `initialize` echoes the offered protocol version and advertises tools; notifications get no reply and junk lines are ignored; `ping`; an unknown method gives `-32601`; an unknown tool is a tool error, not a crash.
- **Tools:** every tool declares an object schema; list is sorted, marks folders with `/`, hides dot entries and treats an empty path as the root; missing files and folders and reading a folder are errors that name the path; write replaces and reports bytes, not characters; append adds to an existing file and refuses a missing one; patch is always refused and changes nothing; a dot-file is readable by exact path.
- **Logging:** `STUB_LOG` gets one JSON line per call with tool, path and error flag; without it nothing extra is written.

### `tools/statusline/test-statusline.mjs`: the Claude Code status line

Run with `node` (18 or later). Each case feeds the script the JSON Claude Code would send and checks what it prints, with colour codes stripped except where the colour is the point. It builds throwaway repositories in temp folders and never touches the real `~/.claude`. `git` and `bash` are needed for the repository and command cases, and each of those skips with a message when missing. See [`statusline.md`](statusline.md).

- **Bad input:** empty, whitespace, invalid JSON, `null`, an array and a bare number all exit 0 and print two lines with the defaults.
- **Line 1:** model, effort and thinking marker together and individually.
- **Context bar:** empty, half, full and clamped above 100%; fractions floored; a non-number treated as 0; green below 70%, yellow from 70%, red from 90%.
- **Subscription:** a reading of 0% on either window still shows the bar and does not fall through to the cost (a regression test); percentages rounded; the five hour reset in hours and minutes; the seven day reset in days and hours, shown only from 50%; a reset in the past shown as `0h 0m`; usage colours at 60% and 80%.
- **Gateway spend limit:** the bar, amounts and reset; a 0% spend shown; amounts shown only when both are supplied; the cost display replaced.
- **Pay-as-you-go:** the cost to two places; an empty `rate_limits` and a non-numeric value both give the cost.
- **Tags:** worktree name and branch, agent name, and nothing added when absent.
- **Repository and branch:** owner and name; the folder marker hidden when it matches the repo name and shown when it does not; a subdirectory; a branch containing a slash; the `cwd` fallback; the branch read from the session directory and not the process directory (a regression test); a real linked worktree; a detached HEAD; no repository; an unusable or dangling `.git` file; a real reftable repository (when git is 2.45 or later) and the `.invalid` placeholder both showing no branch, a `HEAD` that points outside `refs/heads` showing none, and a fake `git` first on `PATH` that must never fire (the script runs nothing).
- **Slow stdin:** JSON arriving in chunks with pauses, one cut inside a multi-byte character.
- **The exact command:** `node ~/.claude/statusline.mjs` run under bash with `HOME` pointed at a temp folder.

CI also runs this suite on Node 18, 20 and 22 (Ubuntu), since 18 is the minimum the script claims.

### `tools/statusline/test-configure-settings.mjs`: the settings helper

The helper behind `install-claude-config.sh --statusline`: it sets `statusLine` in a `settings.json` and nothing else. Run with `node`; every case works on a file in a temp folder.

- **Creating and adding:** a missing file and its folders are created; an empty file counts as `{}`; every other key survives, in order, with `statusLine` last; the file's indentation (two spaces, four, or tabs) and a leading byte order mark are handled; a command containing spaces and quotes round-trips.
- **Backups and writes:** an existing file is copied to `settings.json.bak-<timestamp>` first, byte for byte; two changes in the same second keep two backups; the new content goes through a temp file and a rename, and nothing is left behind.
- **Already configured:** a line that already runs a `statusline.mjs` (the `~` form, an absolute path, a quoted path) is left alone, even with `--force`. A different line, or one of the wrong type, is kept unless `--force` is given, which replaces it after a backup.
- **Files that are never touched:** invalid JSON, a trailing comma, a comment, an array, `null`, a string and a folder in place of the file all exit 3 with the file unchanged and the snippet to add by hand.
- **`--dry-run` and `--check`:** neither writes anything (not even folders), and `--check` never replaces, even with `--force`. Missing is exit 1.
- **Usage:** no arguments, no command, or an unknown option is exit 2.

### `tools/testing/test-powershell-scripts.ps1`: the PowerShell scripts

A self-contained script in the same style as the bash suites (no Pester, so nothing to install). Each scenario runs the script under test in a child PowerShell.

- **`setup-mcp.ps1`:** the same journey as the bash version (no `claude`, no plugin, server off then on, missing setting, missing key, default and custom ports, the exact registration calls, the probe with a real local listener answering 200 and 401, the key never printed), plus the no-BOM and non-ASCII checks (regression tests for the bugs above).
- **`prepare-wiki-docs.ps1`:** front matter (space, title, parent), the configured title winning over the heading, the heading as the fallback and then the file name, the H1 stripped, the body kept, a stale output folder emptied, `-ConfigFile` and `-OutputDir`, the missing-config and missing-source errors, and that `# ` lines inside a code block are kept (a regression test for the bug above).
- **`install-claude-config.ps1`** (Windows only): exit codes pass through from the installer (`--help` 0, a bad option 2, `--check` on an empty prefix 1), arguments arrive unchanged, nothing is created by `--check`, and the "no Git bash" branch.

### `tools/testing/test-structure.sh`: the set as a whole

Checks that no single suite can make:

- every hook in `hook-templates/` has a `test-<hook>.sh`, and every such suite tests a hook that exists;
- the installer's hook list matches the hooks that exist;
- every suite is in `run-all-tests.sh`, in a CI workflow and in this page;
- every shell script parses, has LF endings, is tracked as executable and has `eol=lf` in `.gitattributes`; JavaScript (including the status line files) and PowerShell files parse; the example wiki config is valid;
- every command template carries a version stamp;
- the test scripts use nothing that the macOS system bash (3.2) lacks, and none of the GNU-only commands (`touch -d`, `readlink -f`, `date -d` without a fallback, `sed -i` without a suffix) that would fail there;
- every suite cleans up from an exit trap;
- `shellcheck`, if installed, reports no error-level findings. Locally it is advisory; set `STRUCTURE_SHELLCHECK_STRICT=1` to make it a gate, which CI does on the Ubuntu job (shellcheck comes preinstalled there). Error level is clean across every script (checked with shellcheck 0.11.0). You can run it without installing anything: `docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable -S error -x tools/hook-templates/pre-push` (and so on for each script). Warning level has ten findings left, listed in the pull request notes, none of which is an error.

## Adding a hook or a suite

Add the hook, then add `tools/hook-templates/test-<hook>.sh`, then add it to `tools/testing/run-all-tests.sh`, `.github/workflows/shell-tests.yml` and this page. `bash tools/testing/test-structure.sh` tells you which of those you have not done yet. If the hook is worth mutation-checking, add a few mutants for it too (see [Mutation checks](#mutation-checks)).

Where things live: a suite sits next to the thing it tests when that thing has its own folder (`hook-templates/`, `statusline/`, `command-templates/test/`). The runners, the structure check, the mutation list and the suites for the top-level installer and setup scripts live in `tools/testing/`. The installer and `setup-mcp` themselves stay at the top of `tools/`, because the setup guides and the README quote those paths.

New suites follow the shape of the existing ones: a throwaway fixture per test, `HOME` redirected if the hook keeps state, stubs on `PATH`, specific expected values rather than "did not crash", names that say the scenario and the outcome, and cleanup from an exit trap.

## Mutation checks

A suite that cannot fail is worth nothing. A mutation check proves each one can: it takes a script, makes one small deliberate break (flip a condition, drop a line, change a number, which is a "mutant"), and runs that script's own suite against the broken copy. The suite should fail. If it still passes, that behaviour is not really being checked, and the mutant is a "survivor".

It is slow on purpose, a full suite run per mutant (minutes each, so hours for everything), so it is **not part of the normal build**.

```bash
bash tools/testing/run-mutation-tests.sh --list                 # the groups and how many mutants each has
bash tools/testing/run-mutation-tests.sh --hook pre-push        # one group (repeat, or comma-separate, for several)
bash tools/testing/run-mutation-tests.sh                        # everything
bash tools/testing/run-mutation-tests.sh --hook pre-push --jobs 4   # four mutants at once
bash tools/testing/run-mutation-tests.sh --check-applies        # fast: does every mutant still apply? runs no suite
```

- **The mutants** are in `tools/testing/mutation/mutants.txt`, one per line: the group (the hook or script name), a short name, the file to change, a `sed` expression, and what it breaks. Add one by adding a line; the file explains the format.
- **Nothing in the repo is changed.** Each mutant is applied to a copy of `tools/` in a temp folder, with a throwaway `HOME`.
- **A broken suite baseline is reported, not hidden.** Each group's suite is run once unmodified first. If that fails, the group's mutants are not run, because "the suite failed" would prove nothing.
- **A mutant that stops applying is reported as broken**, as is one that leaves invalid bash. A refactor that moves the target text cannot quietly turn a mutant into a no-op, and `tools/testing/test-structure.sh` runs the same fast check on every build.
- **Exit status** is 0 only if every mutant applied and was killed.

### In CI: manual only

`.github/workflows/mutation-tests.yml` runs it. The only trigger is **Run workflow** on the Actions tab (`workflow_dispatch`), so no push, pull request or schedule ever starts it. The form asks for:

- **hook:** one hook or script by name, or `all`. For `all`, each group becomes its own job and they run side by side, so the wall-clock time is the slowest group, not the sum.
- **jobs_per_group:** how many mutants to run at once within a group (1, 2 or 4).

`tools/testing/test-structure.sh` checks that the dropdown lists exactly the groups in `mutants.txt`, so adding a group without adding it to the workflow fails the normal build.

### What has been checked

When this was set up, every mutant was confirmed to apply cleanly (`--check-applies`), and the runner itself was tested end to end: it reports a harmless change as a survivor, a real break as killed, a mutant tagged `not-observable-on-windows` as skipped on Windows, and exits 1 if anything survived. All 32 mutants were then run against their suites on a Windows machine: 31 killed, none survived, and the 32nd (`in2`, installed hooks losing their executable bit) was skipped, because Windows Git Bash reports any file starting with `#!` as executable and the suite cannot see the difference there.

The manual workflow has since been run for all groups on GitHub (Ubuntu, run 37660645269 on commit `3abb325`): **all 32 mutants were killed, none survived, none were broken and no baseline failed**. That includes `in2`, so the Windows-only skip is confirmed to be caught where file modes are real. The planning job, the group dropdown and the per-group parallel jobs all behaved as designed, and the whole run took three minutes.

Two mutants were added afterwards (`pc5` reworked and `pc7` new, for the `git --staged --redact` invocation and the 1.x-only `-v`), making 33. The `pre-commit` group was re-run on GitHub (Ubuntu, run 37666004118 on commit `c35126f`): all 7 killed, none survived, none broken, no baseline failed, in nine seconds.

Running the `post-merge` group also exposed two timing-based checks in its suite (one pre-existing, one of mine) that failed whenever the machine was busy, which stopped the group at its baseline. Both now use no clock: the hung-run check uses a stub that would hang for two minutes and prints a marker if it ever finishes, and the slow-`claude` check uses a stub that waits for a release file.

Which mutants are killed changes whenever a suite does, so treat the result of a run, not this paragraph, as the current answer.

Stryker is not used: it supports C#, JavaScript/TypeScript and Scala, and these scripts are bash and PowerShell, which it cannot mutate.
