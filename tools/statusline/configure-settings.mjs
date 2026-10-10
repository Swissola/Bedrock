#!/usr/bin/env node
// Sets "statusLine" in a Claude Code settings.json without disturbing anything else in it.
// Used by tools/install-claude-config.sh --statusline; kept as a script of its own because
// quoting JSON edits inline is fragile under Git Bash and jq is not guaranteed to exist.
//
//   node configure-settings.mjs <settings.json> <command> [--force] [--dry-run] [--check]
//
// Behaviour:
//   - no statusLine set                    -> set it
//   - a statusLine that already runs a
//     statusline.mjs (any path)            -> leave it alone ("unchanged")
//   - a different statusLine               -> keep it and print the snippet; with --force,
//                                             replace it
//   - --check                              -> report which of those applies, change nothing
//   - --dry-run                            -> say what would happen, change nothing
//
// Before changing an existing file it copies it to settings.json.bak-<timestamp>. The new
// content is written to a temporary file in the same folder and renamed over the original,
// so a crash cannot leave a half-written settings.json. A file that is not valid JSON (or
// not a JSON object) is never touched. Every other key is preserved, and so is the file's
// indentation.
//
// Exit status: 0 done or nothing to do, 1 --check found no statusLine, 3 the file could
// not be read as JSON or written (nothing was changed), 2 usage error.

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const flags = new Set(args.filter((a) => a.startsWith('--')));
const [settingsPath, command] = args.filter((a) => !a.startsWith('--'));
for (const f of flags) {
  if (!['--force', '--dry-run', '--check'].includes(f)) { console.error(`Unknown option: ${f}`); process.exit(2); }
}
if (!settingsPath || (!command && !flags.has('--check'))) {
  console.error('Usage: configure-settings.mjs <settings.json> <command> [--force] [--dry-run] [--check]');
  process.exit(2);
}
const force = flags.has('--force'), dry = flags.has('--dry-run'), check = flags.has('--check');
const label = 'settings.json statusLine';
const snippet = () => `  "statusLine": { "type": "command", "command": ${JSON.stringify(command)} }`;

// settings.json can hold secrets (env values, tokens), so a file we create is private to its
// owner, and an existing file keeps whatever mode it already had.
let mode = 0o600;
try { mode = fs.statSync(settingsPath).mode & 0o777; } catch { /* not there yet */ }

let raw = null;
try { raw = fs.readFileSync(settingsPath, 'utf8'); } catch (e) {
  if (e.code !== 'ENOENT') { console.error(`cannot read ${settingsPath}: ${e.message}`); process.exit(3); }
}

let settings = {};
let indent = 2;
if (raw !== null && raw.trim() !== '') {
  try { settings = JSON.parse(raw.replace(/^﻿/, '')); } catch (e) {
    console.error(`left alone ${settingsPath}: it is not valid JSON (${e.message}). Add this to it by hand:\n${snippet()}`);
    process.exit(3);
  }
  if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
    console.error(`left alone ${settingsPath}: it is not a JSON object. Add this to it by hand:\n${snippet()}`);
    process.exit(3);
  }
  const m = /^([ \t]+)"/m.exec(raw);
  if (m) indent = m[1].includes('\t') ? '\t' : m[1].length;
}

const current = settings.statusLine;
// True only for `node <path>/statusline.mjs`, so a command that merely mentions the file name
// somewhere does not count as installed. The path may be bare (safe characters only), in single
// quotes (anything but a single quote) or in double quotes (nothing a shell would expand).
const SAFE_BARE = /^[\w./:~\\-]+$/;
function isStatuslineCommand(command) {
  if (typeof command !== 'string' || command.includes('\n')) return false;
  const trimmed = command.trim();
  if (!trimmed.startsWith('node ')) return false;
  const target = trimmed.slice('node '.length).trim();
  const quote = target[0];
  let file = target;
  if (quote === "'" || quote === '"') {
    if (target.length < 2 || !target.endsWith(quote)) return false;
    file = target.slice(1, -1);
    const forbidden = quote === "'" ? "'" : '"$`';
    if ([...file].some((c) => forbidden.includes(c))) return false;
  } else if (!SAFE_BARE.test(target)) {
    return false;
  }
  return file === 'statusline.mjs' || file.endsWith('/statusline.mjs') || file.endsWith(String.raw`\statusline.mjs`);
}
const runsStatusline = current && typeof current === 'object' && isStatuslineCommand(current.command);

if (current === undefined) {
  if (check) { console.log(`missing  ${label}`); process.exit(1); }
} else if (runsStatusline) {
  console.log(check ? `current  ${label}` : `unchanged ${settingsPath} (statusLine already runs statusline.mjs)`);
  process.exit(0);
} else if (!force || check) {
  console.log(check
    ? `kept     ${label} (a different status line is configured; --force would replace it)`
    : `kept      ${settingsPath} (a different statusLine is configured; pass --force to replace it, or switch by hand:\n${snippet()})`);
  process.exit(0);
}

// From here the file will be created or changed.
let verb = 'replace';
if (current === undefined) verb = raw === null ? 'create' : 'update';
if (dry) { console.log(`would ${verb} ${settingsPath}`); process.exit(0); }

try {
  fs.mkdirSync(path.dirname(path.resolve(settingsPath)), { recursive: true });
  if (raw !== null) {
    const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');
    let backup = `${settingsPath}.bak-${stamp}`;
    let n = 1;
    while (fs.existsSync(backup)) backup = `${settingsPath}.bak-${stamp}-${++n}`;
    fs.copyFileSync(settingsPath, backup);
    fs.chmodSync(backup, mode);
    console.log(`backed up ${backup}`);
  }
  settings.statusLine = { type: 'command', command };
  const tmp = `${settingsPath}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(settings, null, indent) + '\n', { mode });
  fs.chmodSync(tmp, mode);
  fs.renameSync(tmp, settingsPath);
} catch (e) {
  console.error(`could not write ${settingsPath}: ${e.message}`);
  process.exit(3);
}
console.log(`${verb === 'create' ? 'installed' : 'updated'} ${settingsPath}`);
