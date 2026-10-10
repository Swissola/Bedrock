#!/usr/bin/env node
// Tests for configure-settings.mjs, the helper that sets "statusLine" in a Claude Code
// settings.json. Every case works on a file in a temp folder; the real ~/.claude is never
// touched. No network, no model calls.
//
//   node tools/statusline/test-configure-settings.mjs

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const helper = path.join(path.dirname(fileURLToPath(import.meta.url)), 'configure-settings.mjs');
let pass = 0, fail = 0;
const check = (desc, ok, extra = '') => {
  if (ok) { pass++; console.log(`PASS: ${desc}`); return; }
  fail++;
  const detail = extra ? ' (' + extra + ')' : '';
  console.log(`FAIL: ${desc}${detail}`);
};

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bedrock-configure-settings-'));
process.on('exit', () => { try { fs.rmSync(root, { recursive: true, force: true }); } catch { /* best effort */ } });
let n = 0;
const fresh = () => { const d = path.join(root, `case${++n}`); fs.mkdirSync(d); return d; };

const CMD = 'node C:/Users/jane-doe/.claude/statusline.mjs';
const run = (args) => {
  const r = spawnSync(process.execPath, [helper, ...args], { encoding: 'utf8', timeout: 20000 });
  return { status: r.status, out: r.stdout ?? '', err: r.stderr ?? '', both: (r.stdout ?? '') + (r.stderr ?? '') };
};
const read = (p) => fs.readFileSync(p, 'utf8');
const json = (p) => JSON.parse(read(p));
const backups = (dir) => fs.readdirSync(dir).filter((f) => f.includes('.bak-'));
const leftovers = (dir) => fs.readdirSync(dir).filter((f) => f.includes('.tmp-'));
const expectStatusLine = { type: 'command', command: CMD };

// --- creating and adding ---------------------------------------------------------------

{
  const d = fresh(), f = path.join(d, 'nested', 'dir', 'settings.json');
  const r = run([f, CMD]);
  check('a missing file (and its folders) is created', r.status === 0 && JSON.stringify(json(f)) === JSON.stringify({ statusLine: expectStatusLine }), r.both);
  check('a created file ends with a newline and is reported as installed', read(f).endsWith('}\n') && r.out.includes('installed'), r.out);
  check('creating a file makes no backup and leaves no temp file', backups(path.dirname(f)).length === 0 && leftovers(path.dirname(f)).length === 0);
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, '');
  const r = run([f, CMD]);
  check('an empty file is treated as an empty object', r.status === 0 && JSON.stringify(json(f)) === JSON.stringify({ statusLine: expectStatusLine }), r.both);
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  const original = { model: 'widget-1', permissions: { allow: ['Bash(ls:*)'], deny: [] }, env: { A: '1' }, hooks: { Stop: [{ hooks: [{ type: 'command', command: 'true' }] }] } };
  fs.writeFileSync(f, JSON.stringify(original, null, 2) + '\n');
  const before = read(f);
  const r = run([f, CMD]);
  const after = json(f);
  check('every other key survives, unchanged', r.status === 0 && JSON.stringify({ ...after, statusLine: undefined }) === JSON.stringify({ ...original, statusLine: undefined }), r.both);
  check('the original key order is kept, with statusLine added last', Object.keys(after).join() === 'model,permissions,env,hooks,statusLine');
  check('the statusLine is the documented shape', JSON.stringify(after.statusLine) === JSON.stringify(expectStatusLine));
  check('an existing file is backed up first, byte for byte', backups(d).length === 1 && read(path.join(d, backups(d)[0])) === before, backups(d).join());
  check('the backup is named in the output', r.out.includes('backed up') && r.out.includes('.bak-'), r.out);
  check('no temporary file is left behind', leftovers(d).length === 0, leftovers(d).join());
}

// --- formatting is preserved --------------------------------------------------------------

{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, '{\n    "model": "widget-1"\n}\n');
  run([f, CMD]);
  check('four-space indentation is kept', read(f).includes('\n    "statusLine": {'), read(f));
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, '{\n\t"model": "widget-1"\n}\n');
  run([f, CMD]);
  check('tab indentation is kept', read(f).includes('\n\t"statusLine": {'), JSON.stringify(read(f)));
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, '\uFEFF{"model":"widget-1"}');
  const r = run([f, CMD]);
  check('a file starting with a byte order mark is read and rewritten as valid JSON', r.status === 0 && json(f).model === 'widget-1' && json(f).statusLine.command === CMD, r.both);
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  const awkward = 'node "C:/Users/Jane Doe/.claude/statusline.mjs" --a=\'b\'';
  run([f, awkward]);
  check('a command with spaces and quotes round-trips through the JSON', json(f).statusLine.command === awkward, read(f));
}

// --- already configured, or something else configured ---------------------------------------

for (const [desc, command] of [
  ['the hand-installed ~ form', 'node ~/.claude/statusline.mjs'],
  ['an absolute path form', 'node C:/Users/jane-doe/.claude/statusline.mjs'],
  ['a quoted path with spaces', 'node "C:/Users/Jane Doe/.claude/statusline.mjs"'],
]) {
  const d = fresh(), f = path.join(d, 'settings.json');
  const text = JSON.stringify({ model: 'widget-1', statusLine: { type: 'command', command } }, null, 2) + '\n';
  fs.writeFileSync(f, text);
  const r = run([f, CMD, '--force']);
  check(`${desc} counts as already installed: file untouched even with --force`, r.status === 0 && read(f) === text && backups(d).length === 0 && r.out.includes('unchanged'), r.both);
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  const text = JSON.stringify({ statusLine: { type: 'command', command: 'bash ~/other-line.sh' } }, null, 2) + '\n';
  fs.writeFileSync(f, text);
  const r = run([f, CMD]);
  check('a different statusLine is kept: exit 0, file untouched, no backup', r.status === 0 && read(f) === text && backups(d).length === 0, r.both);
  check('...and the snippet and the --force hint are printed', r.out.includes('--force') && r.out.includes(JSON.stringify(CMD)), r.out);
  const forced = run([f, CMD, '--force']);
  check('--force replaces a different statusLine', forced.status === 0 && JSON.stringify(json(f).statusLine) === JSON.stringify(expectStatusLine), forced.both);
  check('...after backing the old file up, byte for byte', backups(d).length === 1 && read(path.join(d, backups(d)[0])) === text);
  const again = run([f, CMD, '--force']);
  check('running it again changes nothing and adds no backup', again.status === 0 && backups(d).length === 1 && again.out.includes('unchanged'), again.both);
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, JSON.stringify({ statusLine: { type: 'command', command: 'bash a.sh' } }));
  run([f, 'node /one/statusline.mjs', '--force']);
  fs.writeFileSync(f, JSON.stringify({ statusLine: { type: 'command', command: 'bash b.sh' } }));
  run([f, 'node /two/statusline.mjs', '--force']);
  check('two replacements in the same second keep two distinct backups', backups(d).length === 2, backups(d).join());
}
{
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, JSON.stringify({ statusLine: 'not-an-object' }));
  const r = run([f, CMD]);
  check('a statusLine of the wrong type is treated as a different one and kept', r.status === 0 && json(f).statusLine === 'not-an-object', r.both);
}

// --- files that must not be touched ----------------------------------------------------------

for (const [desc, text] of [
  ['invalid JSON', '{"model": '],
  ['a trailing comma', '{"model": "widget-1",}'],
  ['a comment', '{\n  // a comment\n  "model": "widget-1"\n}'],
  ['a JSON array', '[]'],
  ['JSON null', 'null'],
  ['a JSON string', '"text"'],
]) {
  const d = fresh(), f = path.join(d, 'settings.json');
  fs.writeFileSync(f, text);
  const r = run([f, CMD, '--force']);
  check(`${desc}: exit 3, file untouched, no backup or temp file`, r.status === 3 && read(f) === text && backups(d).length === 0 && leftovers(d).length === 0, `status ${r.status}`);
  check(`${desc}: says so and prints the snippet to add by hand`, r.err.includes('left alone') && r.err.includes('"statusLine"'), r.err);
}
{
  const d = fresh(), f = path.join(d, 'a-folder');
  fs.mkdirSync(f);
  const r = run([f, CMD]);
  check('a path that is a folder fails with exit 3 and a message', r.status === 3 && r.err.includes('cannot read'), r.both);
}

// --- dry run ------------------------------------------------------------------------------------

{
  const d = fresh(), missing = path.join(d, 'sub', 'settings.json');
  const r = run([missing, CMD, '--dry-run']);
  check('--dry-run on a missing file creates nothing, not even folders', r.status === 0 && !fs.existsSync(path.join(d, 'sub')) && r.out.includes('would create'), r.both);
  const f = path.join(d, 'settings.json');
  const text = '{"model":"widget-1"}';
  fs.writeFileSync(f, text);
  const u = run([f, CMD, '--dry-run']);
  check('--dry-run on an existing file changes nothing and makes no backup', u.status === 0 && read(f) === text && backups(d).length === 0 && u.out.includes('would update'), u.both);
  fs.writeFileSync(f, JSON.stringify({ statusLine: { type: 'command', command: 'bash a.sh' } }));
  const w = run([f, CMD, '--dry-run', '--force']);
  check('--dry-run --force says it would replace and changes nothing', w.status === 0 && json(f).statusLine.command === 'bash a.sh' && backups(d).length === 0 && w.out.includes('would replace'), w.both);
}

// --- check ----------------------------------------------------------------------------------------

{
  const d = fresh(), f = path.join(d, 'settings.json');
  const missingFile = run([f, '--check']);
  check('--check with no file: reports missing, exit 1, creates nothing', missingFile.status === 1 && missingFile.out.includes('missing') && !fs.existsSync(f), missingFile.both);
  fs.writeFileSync(f, '{"model":"widget-1"}');
  const noLine = run([f, '--check']);
  check('--check with no statusLine: reports missing, exit 1', noLine.status === 1 && noLine.out.includes('missing'), noLine.both);
  fs.writeFileSync(f, JSON.stringify({ statusLine: { type: 'command', command: 'node ~/.claude/statusline.mjs' } }));
  const ours = run([f, '--check']);
  check('--check with ours configured: reports current, exit 0', ours.status === 0 && ours.out.includes('current'), ours.both);
  fs.writeFileSync(f, JSON.stringify({ statusLine: { type: 'command', command: 'bash a.sh' } }));
  const other = run([f, '--check']);
  check('--check with a different line: reports kept, exit 0 (nothing the installer would change)', other.status === 0 && other.out.includes('kept'), other.both);
  const withForce = run([f, '--check', '--force']);
  check('--check never replaces, even with --force', withForce.status === 0 && json(f).statusLine.command === 'bash a.sh' && backups(d).length === 0, withForce.both);
  fs.writeFileSync(f, '{bad');
  const bad = run([f, '--check']);
  check('--check on invalid JSON: exit 3, file untouched', bad.status === 3 && read(f) === '{bad', bad.both);
  check('--check needs no command argument', run([f, '--check']).status !== 2);
}

// --- usage ---------------------------------------------------------------------------------------

{
  check('no arguments: usage error, exit 2', run([]).status === 2 && run([]).err.includes('Usage'));
  check('a settings path but no command: usage error, exit 2', run([path.join(fresh(), 'settings.json')]).status === 2);
  check('an unknown option: exit 2 and names it', run([path.join(fresh(), 'settings.json'), CMD, '--frobnicate']).status === 2 && run([path.join(fresh(), 'settings.json'), CMD, '--frobnicate']).err.includes('--frobnicate'));
}

console.log(`--- ${pass} passed, ${fail} failed ---`);
process.exit(fail ? 1 : 0);
