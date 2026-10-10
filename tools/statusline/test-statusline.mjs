#!/usr/bin/env node
// Tests for statusline.mjs, the Claude Code status line script. Every case feeds the
// script the JSON Claude Code would send on stdin and checks what it prints. No network,
// no model calls, and nothing outside temp folders is touched (the real ~/.claude
// included). Needs Node 18 or later; git is needed for the repository cases and bash for
// the "exact command" cases, and each of those is skipped with a message when missing.
//
//   node tools/statusline/test-statusline.mjs

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'statusline.mjs');
let pass = 0, fail = 0, skips = 0;
const check = (desc, ok, extra = '') => {
  if (ok) { pass++; console.log(`PASS: ${desc}`); } else { fail++; console.log(`FAIL: ${desc}${extra ? ` (${extra})` : ''}`); }
};
const skip = (desc) => { skips++; console.log(`SKIP: ${desc}`); };

const tmpDirs = [];
const mkTmp = (prefix) => { const d = fs.mkdtempSync(path.join(os.tmpdir(), `bedrock-statusline-${prefix}-`)); tmpDirs.push(d); return d; };
process.on('exit', () => { for (const d of tmpDirs) { try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* best effort */ } } });

const ANSI = /\x1b\[[0-9;]*m/g;
const plain = (s) => s.replace(ANSI, '');
const cleanEnv = () => {
  const env = { ...process.env };
  for (const k of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE']) delete env[k];
  return env;
};

// Runs the script with `input` on stdin (an object is serialised, a string is sent as is).
function run(input, { cwd = os.tmpdir() } = {}) {
  const r = spawnSync(process.execPath, [script], {
    input: typeof input === 'string' ? input : JSON.stringify(input),
    encoding: 'utf8', cwd, env: cleanEnv(), timeout: 20000,
  });
  const raw = r.stdout ?? '';
  const lines = plain(raw).split('\n');
  return { raw, status: r.status, stderr: r.stderr ?? '', line1: lines[0] ?? '', line2: lines[1] ?? '', text: plain(raw) };
}

// Sends the JSON in several chunks with pauses between them, the way a slow writer would.
function runChunked(json, cuts, { cwd = os.tmpdir() } = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [script], { cwd, env: cleanEnv(), stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', (c) => { out += c; });
    child.on('close', (status) => { const t = plain(out).split('\n'); resolve({ status, line1: t[0], line2: t[1] }); });
    const buf = Buffer.from(JSON.stringify(json), 'utf8');
    const pieces = [];
    let from = 0;
    for (const c of [...cuts, buf.length]) { pieces.push(buf.subarray(from, c)); from = c; }
    let i = 0;
    const next = () => {
      if (i >= pieces.length) { child.stdin.end(); return; }
      child.stdin.write(pieces[i++]);
      setTimeout(next, 120);
    };
    next();
  });
}

const git = (cwd, ...args) => spawnSync('git', ['-c', 'user.name=test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', ...args], { cwd, encoding: 'utf8', env: cleanEnv() });
const hasGit = git(os.tmpdir(), '--version').status === 0;
const gitVersion = (() => { const m = /(\d+)\.(\d+)/.exec(git(os.tmpdir(), '--version').stdout ?? ''); return m ? [Number(m[1]), Number(m[2])] : [0, 0]; })();

const nowSec = () => Math.floor(Date.now() / 1000);

// --- this repo is public and generic: no personal paths in the shipped files --------------

for (const file of [script, fileURLToPath(import.meta.url)]) {
  const hits = fs.readFileSync(file, 'utf8').split('\n')
    .map((l, i) => [i + 1, l]).filter(([, l]) => /[A-Za-z]:[\\/]+Users[\\/]|\/Users\/\w|\/home\/\w/.test(l));
  check(`${path.basename(file)} contains no user home paths`, hits.length === 0, hits.map(([n]) => `line ${n}`).join(', '));
}

// --- robustness: nothing sensible on stdin ------------------------------------------------

for (const [desc, input] of [
  ['empty input', ''],
  ['whitespace only', '   \n'],
  ['invalid JSON', '{"model": '],
  ['JSON null', 'null'],
  ['a JSON array', '[]'],
  ['a bare JSON number', '42'],
]) {
  const r = run(input);
  check(`${desc}: exits 0 and prints two lines`, r.status === 0 && r.text.split('\n').length === 3 && r.text.endsWith('\n'), `status ${r.status}, stderr ${r.stderr.trim()}`);
  check(`${desc}: renders an empty model, 0% context and a $0.00 cost`, r.line1.startsWith('[]') && r.line2.includes('0%') && r.line2.includes('$0.00'), JSON.stringify(r.text));
}

// --- line 1: model, effort, thinking ----------------------------------------------------

{
  const r = run({ model: { display_name: 'Widget 1' }, effort: { level: 'high' }, thinking: { enabled: true } });
  check('model, effort and thinking are shown together', r.line1.startsWith('[Widget 1 ·high 🧠]'), r.line1);
  const bare = run({ model: { display_name: 'Widget 1' } });
  check('effort and thinking are omitted when absent', bare.line1.startsWith('[Widget 1]'), bare.line1);
  const off = run({ model: { display_name: 'Widget 1' }, thinking: { enabled: false } });
  check('thinking disabled shows no marker', !off.line1.includes('🧠'), off.line1);
}

// --- context bar and its colours ---------------------------------------------------------

{
  const at = (pct) => run({ context_window: { used_percentage: pct } });
  check('context 0% draws an empty bar', at(0).line2.startsWith('░░░░░░░░░░ 0%'), at(0).line2);
  check('context 50% fills half the bar', at(50).line2.startsWith('▓▓▓▓▓░░░░░ 50%'), at(50).line2);
  check('context 100% fills the bar', at(100).line2.startsWith('▓▓▓▓▓▓▓▓▓▓ 100%'), at(100).line2);
  check('context above 100% is clamped to a full bar', at(140).line2.startsWith('▓▓▓▓▓▓▓▓▓▓'), at(140).line2);
  check('a fractional percentage is floored', at(42.9).line2.startsWith('▓▓▓▓░░░░░░ 42%'), at(42.9).line2);
  check('a non-numeric percentage is treated as 0', at('lots').line2.startsWith('░░░░░░░░░░ 0%'), at('lots').line2);
  check('context below 70% is green', at(69).raw.includes('\x1b[32m'));
  check('context from 70% is yellow', at(70).raw.includes('\x1b[33m') && !at(70).raw.includes('\x1b[32m'));
  check('context from 90% is red', at(90).raw.includes('\x1b[31m') && !at(90).raw.includes('\x1b[33m'));
}

// --- usage block: subscription -----------------------------------------------------------

{
  const r = run({ rate_limits: { five_hour: { used_percentage: 0 }, seven_day: { used_percentage: 0 } }, cost: { total_cost_usd: 1.23 } });
  check('0% on both subscription windows still shows the bars (0 is a valid reading)', r.line2.includes('5h ░░░░░░░░░░ 0%') && r.line2.includes('7d ░░░░░░░░░░ 0%'), r.line2);
  check('0% on both subscription windows does not fall through to the cost', !r.line2.includes('$'), r.line2);

  const fiveOnly = run({ rate_limits: { five_hour: { used_percentage: 0 } } });
  check('a five-hour window alone is shown, with no cost and no 7d bar', fiveOnly.line2.includes('5h ') && !fiveOnly.line2.includes('7d') && !fiveOnly.line2.includes('$'), fiveOnly.line2);

  const resets = run({ rate_limits: {
    five_hour: { used_percentage: 41.6, resets_at: nowSec() + 3 * 3600 + 5 * 60 + 30 },
    seven_day: { used_percentage: 55, resets_at: nowSec() + 2 * 86400 + 4 * 3600 + 30 * 60 },
  } });
  check('the five-hour percentage is rounded and its reset shown as hours and minutes', resets.line2.includes('5h ▓▓▓▓░░░░░░ 42% (3h 5m)'), resets.line2);
  check('the seven-day reset is shown from 50% as days and hours', resets.line2.includes('7d ▓▓▓▓▓░░░░░ 55% (2d 4h)'), resets.line2);

  const low = run({ rate_limits: { seven_day: { used_percentage: 49, resets_at: nowSec() + 86400 } } });
  check('the seven-day reset is hidden below 50%', low.line2.includes('7d ') && !low.line2.includes('('), low.line2);

  const past = run({ rate_limits: { five_hour: { used_percentage: 10, resets_at: nowSec() - 500 } } });
  check('a reset time in the past is shown as 0h 0m, not a negative', past.line2.includes('(0h 0m)'), past.line2);

  check('usage below 60% is green', run({ rate_limits: { five_hour: { used_percentage: 59 } } }).raw.includes('\x1b[32m▓'));
  check('usage from 60% is yellow', run({ rate_limits: { five_hour: { used_percentage: 60 } } }).raw.includes('\x1b[33m▓'));
  check('usage from 80% is red', run({ rate_limits: { five_hour: { used_percentage: 80 } } }).raw.includes('\x1b[31m▓'));
}

// --- usage block: gateway spend limit ----------------------------------------------------

{
  const r = run({ rate_limits: { spend_limit: { used_percentage: 25, used_usd: 12.5, limit_usd: 50, resets_at: nowSec() + 5 * 3600 + 5 * 60 + 30 } } });
  check('a spend limit shows a spend bar, the amounts and the reset', r.line2.includes('spend ▓▓░░░░░░░░ 25%') && r.line2.includes('($12.50/$50.00)') && r.line2.includes('(5h 5m)'), r.line2);
  check('a spend limit replaces the cost display', !r.line2.includes('💰'), r.line2);

  const zero = run({ rate_limits: { spend_limit: { used_percentage: 0 } } });
  check('0% spend is shown and does not fall through to the cost', zero.line2.includes('spend ░░░░░░░░░░ 0%') && !zero.line2.includes('💰'), zero.line2);
  check('spend without amounts or a reset shows only the bar', !zero.line2.includes('$') && !zero.line2.includes('(') , zero.line2);

  for (const [which, fields] of [['used only', { used_usd: 5 }], ['limit only', { limit_usd: 50 }]]) {
    const partial = run({ rate_limits: { spend_limit: { used_percentage: 10, ...fields } } });
    check(`spend amounts are shown only when both are supplied (${which})`, partial.status === 0 && partial.line2.includes('spend ▓░░░░░░░░░ 10%') && !partial.line2.includes('$'), partial.line2);
  }
}

// --- usage block: API / pay as you go ----------------------------------------------------

{
  const r = run({ cost: { total_cost_usd: 0.4567 } });
  check('with no rate limits the session cost is shown to two places', r.line2.includes('💰 $0.46'), r.line2);
  check('an empty rate_limits object also shows the cost', run({ rate_limits: {}, cost: { total_cost_usd: 2 } }).line2.includes('💰 $2.00'));
  check('a rate_limits value that is not a number is ignored', run({ rate_limits: { five_hour: { used_percentage: 'high' } }, cost: { total_cost_usd: 1 } }).line2.includes('💰 $1.00'));
}

// --- tags after the usage block ----------------------------------------------------------

{
  const r = run({ worktree: { name: 'try-it', branch: 'worktree-try-it' }, agent: { name: 'reviewer' } });
  check('worktree name, its branch and the agent name are appended', r.line2.endsWith('| 🌳 try-it (worktree-try-it) | 👤 reviewer'), r.line2);
  check('a worktree with no branch shows just its name', run({ worktree: { name: 'try-it' } }).line2.endsWith('🌳 try-it'));
  check('no worktree or agent adds nothing', !run({}).line2.includes('🌳') && !run({}).line2.includes('👤'));
}

// --- repository, branch and folder -------------------------------------------------------

if (!hasGit) {
  skip('repository, branch and folder cases (git is not installed)');
} else {
  const base = mkTmp('repos');
  const mkRepo = (name) => {
    const dir = path.join(base, name);
    fs.mkdirSync(dir, { recursive: true });
    git(dir, 'init', '-q');
    git(dir, 'symbolic-ref', 'HEAD', 'refs/heads/main');
    git(dir, 'commit', '-q', '--allow-empty', '-m', 'first');
    return dir;
  };
  const repo = mkRepo('widget-service');

  const inRepo = run({ workspace: { current_dir: repo, repo: { owner: 'jane-doe', name: 'widget-service' } } });
  check('repository: owner/name and branch are shown', inRepo.line1.includes('📦 jane-doe/widget-service 🌿 main'), inRepo.line1);
  check('repository: the folder tag is hidden when the folder name matches the repo name', !inRepo.line1.includes('📁'), inRepo.line1);

  const renamed = run({ workspace: { current_dir: repo, repo: { name: 'other-name' } } });
  check('repository: the folder tag is shown when the folder differs from the repo name', renamed.line1.includes('| 📁 widget-service |') && renamed.line1.includes('📦 other-name 🌿 main'), renamed.line1);

  const noRepoInfo = run({ workspace: { current_dir: repo } });
  check('no repo info from Claude Code: folder and branch are still shown', noRepoInfo.line1.includes('📁 widget-service') && noRepoInfo.line1.endsWith('🌿 main') && !noRepoInfo.line1.includes('📦'), noRepoInfo.line1);

  const sub = path.join(repo, 'src', 'deep');
  fs.mkdirSync(sub, { recursive: true });
  check('branch is found from a subdirectory of the repository', run({ workspace: { current_dir: sub } }).line1.includes('🌿 main'));

  git(repo, 'checkout', '-q', '-b', 'feature/status-line');
  check('a branch name containing a slash is shown whole', run({ workspace: { current_dir: repo } }).line1.includes('🌿 feature/status-line'));

  check('the cwd field is used when workspace.current_dir is absent', run({ cwd: repo }).line1.includes('🌿 feature/status-line'));

  // The branch must come from the session's directory, not from where the process runs.
  const other = mkRepo('gadget-service');
  git(other, 'checkout', '-q', '-b', 'gadget-branch');
  const mixed = run({ workspace: { current_dir: repo } }, { cwd: other });
  check('the branch is read from the session directory, not the process directory', mixed.line1.includes('🌿 feature/status-line') && !mixed.line1.includes('gadget-branch'), mixed.line1);
  const fallback = run({}, { cwd: other });
  check('with no directory in the JSON the process directory is used', fallback.line1.includes('🌿 gadget-branch'), fallback.line1);

  // A real linked worktree: .git is a file holding an absolute gitdir path.
  const wt = path.join(base, 'widget-service-wt');
  const added = git(repo, 'worktree', 'add', '-q', '-b', 'wt-branch', wt);
  if (added.status !== 0) {
    skip(`linked worktree (git worktree add failed: ${(added.stderr ?? '').trim()})`);
  } else {
    check('the .git entry of a linked worktree is a file, as the case assumes', fs.statSync(path.join(wt, '.git')).isFile());
    const r = run({ workspace: { current_dir: wt, repo: { name: 'widget-service' } } });
    check('a linked worktree shows its own branch and a folder tag', r.line1.includes('📁 widget-service-wt') && r.line1.includes('🌿 wt-branch'), r.line1);
  }

  // Detached HEAD shows the short SHA.
  const sha = git(repo, 'rev-parse', 'HEAD').stdout.trim();
  git(repo, 'checkout', '-q', '--detach');
  const det = run({ workspace: { current_dir: repo } });
  check('a detached HEAD shows the first seven characters of the commit', det.line1.endsWith(`🌿 ${sha.slice(0, 7)}`), det.line1);

  // Not a repository at all.
  const plainDir = path.join(mkTmp('plain'), 'just-a-folder');
  fs.mkdirSync(plainDir);
  const noRepo = run({ workspace: { current_dir: plainDir } });
  check('outside a repository there is no branch, and the folder tag is shown', !noRepo.line1.includes('🌿') && noRepo.line1.includes('📁 just-a-folder'), noRepo.line1);

  // A .git entry that is not usable must not crash the line.
  const broken = path.join(mkTmp('broken'), 'broken');
  fs.mkdirSync(broken);
  fs.writeFileSync(path.join(broken, '.git'), 'not a gitdir line\n');
  const b = run({ workspace: { current_dir: broken } });
  check('a .git file with no gitdir line gives no branch and no error', b.status === 0 && !b.line1.includes('🌿'), b.line1);
  const dangling = path.join(mkTmp('dangling'), 'dangling');
  fs.mkdirSync(dangling);
  fs.writeFileSync(path.join(dangling, '.git'), 'gitdir: ../does-not-exist\n');
  const dg = run({ workspace: { current_dir: dangling } });
  check('a gitdir that does not exist gives no branch and no error', dg.status === 0 && !dg.line1.includes('🌿'), dg.line1);

  // Reftable: HEAD holds a placeholder, so the script has to ask git.
  const reftable = path.join(base, 'reftable-repo');
  fs.mkdirSync(reftable);
  const [major, minor] = gitVersion;
  const reftableOk = (major > 2 || (major === 2 && minor >= 45)) && git(reftable, 'init', '-q', '--ref-format=reftable').status === 0;
  if (!reftableOk) {
    skip(`reftable repository (git ${major}.${minor} cannot create one)`);
  } else {
    git(reftable, 'checkout', '-q', '-b', 'reftable-branch');
    git(reftable, 'commit', '-q', '--allow-empty', '-m', 'first');
    const head = fs.readFileSync(path.join(reftable, '.git', 'HEAD'), 'utf8');
    check('a reftable repository really does keep the placeholder in .git/HEAD', head.includes('.invalid'), head.trim());
    const rt = run({ workspace: { current_dir: reftable } });
    check('a reftable repository shows the real branch, not ".invalid"', rt.line1.includes('🌿 reftable-branch') && !rt.line1.includes('.invalid'), rt.line1);
  }
  // The placeholder in a repository git cannot resolve must never be shown as a branch.
  const fake = path.join(base, 'fake-placeholder');
  fs.mkdirSync(fake);
  fs.mkdirSync(path.join(fake, '.git'));
  fs.writeFileSync(path.join(fake, '.git', 'HEAD'), 'ref: refs/heads/.invalid\n');
  const fk = run({ workspace: { current_dir: fake } });
  check('the ".invalid" placeholder is never printed as a branch', fk.status === 0 && !fk.line1.includes('.invalid'), fk.line1);
}

// --- stdin arriving slowly, in pieces ----------------------------------------------------

{
  const json = { model: { display_name: 'Wïdget ✨' }, context_window: { used_percentage: 33 }, rate_limits: { five_hour: { used_percentage: 12 } } };
  const text = JSON.stringify(json);
  const at = Buffer.from(text, 'utf8').indexOf(Buffer.from('✨', 'utf8')) + 1; // inside the multi-byte character
  const r = await runChunked(json, [10, at, at + 40]);
  check('JSON arriving in slow chunks, one split inside a multi-byte character, still renders', r.status === 0 && r.line1.startsWith('[Wïdget ✨]') && r.line2.includes('33%') && r.line2.includes('5h '), `${r.line1} / ${r.line2}`);
}

// --- the exact command from settings.json, in each runner's shell ------------------------

{
  const home = mkTmp('home');
  fs.mkdirSync(path.join(home, '.claude'));
  fs.copyFileSync(script, path.join(home, '.claude', 'statusline.mjs'));
  const bash = spawnSync('bash', ['--version'], { encoding: 'utf8' });
  if (bash.status !== 0) {
    skip('node ~/.claude/statusline.mjs under bash (bash is not on PATH)');
  } else {
    const r = spawnSync('bash', ['-c', 'node ~/.claude/statusline.mjs'], {
      input: JSON.stringify({ model: { display_name: 'Widget 1' }, context_window: { used_percentage: 20 } }),
      encoding: 'utf8', cwd: os.tmpdir(), timeout: 20000,
      env: { ...cleanEnv(), HOME: home, USERPROFILE: home },
    });
    const t = plain(r.stdout ?? '').split('\n');
    check('"node ~/.claude/statusline.mjs" expands and runs under bash', r.status === 0 && t[0].startsWith('[Widget 1]') && t[1].includes('20%'), `status ${r.status}, ${r.stderr?.trim()}`);
  }
}

console.log(`--- ${pass} passed, ${fail} failed${skips ? `, ${skips} skipped` : ''} ---`);
process.exit(fail ? 1 : 0);
