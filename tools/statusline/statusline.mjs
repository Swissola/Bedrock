// Claude Code status line: model, effort, thinking, repo/branch, context bar,
// worktree/agent (when in use), and one usage block that depends on the account:
//   - Pro/Max subscription: 5h and 7d rate-limit bars (rate_limits.*)
//   - Claude apps gateway with a spend limit: spend bar (rate_limits.spend_limit)
//   - API / pay-as-you-go / anything else: estimated session cost (list price,
//     may differ from the bill)
//
// Needs only Node 18+. No dependencies and no child processes: the branch is
// read straight from .git/HEAD, so each refresh is a single short-lived process
// and nothing in the directory being viewed is ever executed. (A reftable
// repository keeps only a placeholder in HEAD, so its branch is left out.)
//
// Registered via settings.json (see docs/statusline.md for the exact line):
//   "statusLine": { "type": "command", "command": "node ~/.claude/statusline.mjs" }

import { readFileSync, statSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';

const ESC = '\x1b[';
const C = { cyan: ESC + '36m', green: ESC + '32m', yellow: ESC + '33m', red: ESC + '31m', dim: ESC + '2m', reset: ESC + '0m' };

const read = (p) => { try { return readFileSync(p, 'utf8'); } catch { return null; } };
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// Read stdin as a stream rather than with readFileSync(0): on a non-blocking
// pipe the latter can throw EAGAIN, which would silently render the defaults.
async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

let d = {};
try { d = JSON.parse((await readStdin()) || '{}') ?? {}; } catch { /* render with defaults */ }

// Green below yellowAt, yellow up to redAt, red at or above. Context uses 70/90;
// usage limits use 60/80 because running out mid-session is more disruptive
// than a compaction.
const color = (pct, y = 70, r = 90) => {
  if (pct >= r) return C.red;
  return pct >= y ? C.yellow : C.green;
};
const bar = (pct, w = 10) => {
  const filled = Math.floor((Math.min(100, Math.max(0, pct)) * w) / 100);
  return '▓'.repeat(filled) + '░'.repeat(w - filled);
};
const gauge = (pct, y = 70, r = 90) => `${color(pct, y, r)}${bar(pct)}${C.reset} ${pct}%`;

// "Xd Xh" or "Xh Ym" from an epoch-seconds reset time.
const until = (epoch) => {
  const s = Math.max(0, Math.floor(epoch - Date.now() / 1000));
  const days = Math.floor(s / 86400);
  const hours = Math.floor((s % 86400) / 3600);
  return days > 0 ? `${days}d ${hours}h` : `${hours}h ${Math.floor((s % 3600) / 60)}m`;
};

const HEADS = 'refs/heads/';

// The nearest .git (a folder, or a file for a worktree or submodule) at or above
// `start`, as { dir, dotGit, isFile }, or null.
function findDotGit(start) {
  let dir = resolve(start);
  for (;;) {
    const dotGit = join(dir, '.git');
    try { return { dir, dotGit, isFile: statSync(dotGit).isFile() }; } catch { /* not here, try the parent */ }
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// The real git directory: the .git folder itself, or the target of a .git file's
// "gitdir:" line. null when the file has no such line.
function gitDirOf({ dir, dotGit, isFile }) {
  if (!isFile) return dotGit;
  const line = (read(dotGit) ?? '').split('\n').find((l) => l.startsWith('gitdir:'));
  return line ? resolve(dir, line.slice('gitdir:'.length).trim()) : null;
}

// Branch name from HEAD, the short SHA when detached, or '' when HEAD points
// somewhere that is not a branch. A reftable repository keeps the fixed
// placeholder ".invalid" here, which is never a real branch name (a ref
// component cannot start with a dot), so it is treated as unknown.
function branchFromHead(head) {
  if (!head.startsWith('ref:')) return head.slice(0, 7);
  const target = head.slice('ref:'.length).trim();
  const name = target.startsWith(HEADS) ? target.slice(HEADS.length) : '';
  return name === '.invalid' ? '' : name;
}

// Branch (or short SHA when detached) without spawning git.
function branchOf(start) {
  const found = findDotGit(start);
  const gitDir = found && gitDirOf(found);
  return gitDir ? branchFromHead((read(join(gitDir, 'HEAD')) ?? '').trim()) : '';
}

const model = d.model?.display_name ?? '';
const effort = d.effort?.level ? ` ·${d.effort.level}` : '';
const thinking = d.thinking?.enabled === true ? ' 🧠' : '';
const ctxPct = Math.floor(num(d.context_window?.used_percentage) ?? 0);

const dir = d.workspace?.current_dir ?? d.cwd ?? process.cwd();
const branch = branchOf(dir);
const repoName = d.workspace?.repo?.name ?? '';
const owner = d.workspace?.repo?.owner;
const slug = owner ? `${owner}/${repoName}` : repoName;
const repo = repoName ? `📦 ${slug} ` : '';

// Folder name only when it differs from the repo name, so it earns its space.
const folder = basename(resolve(dir));
const folderTag = folder && folder !== repoName ? ` | 📁 ${folder}` : '';

const line1 = `${C.cyan}[${model}${effort}${thinking}]${C.reset}${folderTag}` + (branch ? ` | ${repo}🌿 ${branch}` : '');

const parts = [gauge(ctxPct)];
const rl = d.rate_limits ?? {};
const five = num(rl.five_hour?.used_percentage);
const week = num(rl.seven_day?.used_percentage);
const spend = num(rl.spend_limit?.used_percentage);

// Compare against null, not truthiness: 0% used is a valid reading and must
// not fall through to the cost display.
if (five === null && week === null && spend === null) {
  parts.push(`💰 $${(num(d.cost?.total_cost_usd) ?? 0).toFixed(2)}`);
}
if (spend !== null) {
  const s = rl.spend_limit;
  let t = `spend ${gauge(Math.round(spend), 60, 80)}`;
  if (num(s.used_usd) !== null && num(s.limit_usd) !== null) {
    t += ` ${C.dim}($${s.used_usd.toFixed(2)}/$${s.limit_usd.toFixed(2)})${C.reset}`;
  }
  if (num(s.resets_at) !== null) t += ` (${until(s.resets_at)})`;
  parts.push(t);
}
if (five !== null) {
  const p = Math.round(five);
  parts.push(`5h ${gauge(p, 60, 80)}` + (num(rl.five_hour.resets_at) !== null ? ` (${until(rl.five_hour.resets_at)})` : ''));
}
if (week !== null) {
  const p = Math.round(week);
  parts.push(`7d ${gauge(p, 60, 80)}` + (p >= 50 && num(rl.seven_day.resets_at) !== null ? ` (${until(rl.seven_day.resets_at)})` : ''));
}

let line2 = parts.join(' | ');
if (d.worktree?.name) line2 += ` | 🌳 ${d.worktree.name}` + (d.worktree.branch ? ` (${d.worktree.branch})` : '');
if (d.agent?.name) line2 += ` | 👤 ${d.agent.name}`;

process.stdout.write(`${line1}\n${line2}\n`);
