#!/usr/bin/env node
// End-to-end tests for the slash-command templates in ../ (vault-log,
// vault-context, vault-populate), run headlessly against throwaway vaults.
//
//   node tools/command-templates/test/run-command-tests.mjs [options]
//     --backend rest-api|mcpvault   default rest-api (uses stub-rest-api-mcp.mjs,
//                                   no network, no Obsidian). mcpvault runs the
//                                   real @bitbonsai/mcpvault through npx.
//     --only <name>                 run just one scenario (substring match)
//     --repeat <n>                  run each scenario n times (default 1); LLM
//                                   runs are probabilistic, repeat the ones that
//                                   are sensitive to wording
//     --model <name>                default sonnet
//
// MANUAL: every scenario is a real `claude -p` run, so it costs model calls and
// is not part of any automatic check. Requires the `claude` CLI on PATH.
//
// Judging: never by the model's own summary of what it did (it can be wrong, or
// claim a write that landed somewhere else). Each scenario asserts on the files
// actually written and on the tool calls actually made, read from the run's
// stream-json event log. Nothing touches a real vault: every run uses
// --strict-mcp-config with an MCP config pointing at a mktemp vault.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const templates = path.resolve(here, '..');
const stub = path.join(here, 'stub-rest-api-mcp.mjs');

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const backend = opt('--backend', 'rest-api');
const only = opt('--only', '');
const repeat = Number(opt('--repeat', '1'));
const model = opt('--model', 'sonnet');
if (!['rest-api', 'mcpvault'].includes(backend)) { console.error('--backend must be rest-api or mcpvault'); process.exit(2); }

const OPS = { vault_read: 'read', read_note: 'read', vault_list: 'list', list_directory: 'list', vault_write: 'write', write_note: 'write', vault_append: 'append', vault_patch: 'patch', patch_note: 'patch' };
const SESSION = 'TEST HARNESS: synthetic session for testing a command template, there is no real work to summarise. Treat the session as having done: (1) wrote a config-driven template, (2) tested it against a scratch vault. One short line per section.';
const PERSONAL_CONFIG = `---
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
Personal vault config.
`;
const CHANGELOG_SEED = '# Change Log\n\nIntro.\n\n---\n\n## 2026-01-01 - Old entry\n\n**What changed:** x\n';
const DEFAULT_HUB ='# Hub\n\nMARKER-HUB-42\n\n## Repos\n\n| Repo | Doc |\n|---|---|\n';

let pass = 0, fail = 0;
const check = (desc, ok, extra = '') => { if (ok) { pass++; console.log(`  PASS: ${desc}`); } else { fail++; console.log(`  FAIL: ${desc}${extra ? ' (' + extra + ')' : ''}`); } };

function sh(cmd, args, cwd) { return spawnSync(cmd, args, { cwd, encoding: 'utf8' }); }
function mkRepo(name) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `bedrock-t-${name}-`));
  const repo = path.join(dir, name); fs.mkdirSync(repo);
  sh('git', ['init', '-q', '-b', 'main'], repo);
  sh('git', ['config', 'user.name', 'Test User'], repo); sh('git', ['config', 'user.email', 't@example.com'], repo);
  sh('git', ['remote', 'add', 'origin', `https://example.com/org/${name}.git`], repo);
  fs.writeFileSync(path.join(repo, 'README.md'), `# ${name}\n\nA tiny demo service that echoes requests. Run with: python app.py. Config via ENV_PORT.\n`);
  fs.writeFileSync(path.join(repo, 'app.py'), "import os\nprint('echo on', os.environ.get('ENV_PORT','8080'))\n");
  fs.writeFileSync(path.join(repo, 'change-log.md'), CHANGELOG_SEED);
  sh('git', ['add', '-A'], repo); sh('git', ['commit', '-qm', 'init'], repo);
  return { dir, repo };
}
function mkVault(files = {}) {
  const v = fs.mkdtempSync(path.join(os.tmpdir(), 'bedrock-t-vault-'));
  for (const [rel, content] of Object.entries(files)) { const f = path.join(v, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, content); }
  return v;
}
const walk = (root, base = root) => fs.existsSync(root) ? fs.readdirSync(root, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(root, e.name), base) : [path.relative(base, path.join(root, e.name)).split(path.sep).join('/')]) : [];
const read = (v, rel) => fs.readFileSync(path.join(v, rel), 'utf8');

// Runs one command template headlessly and returns { calls, files, final }.
function runCommand({ vault, repo, template, args = '', system = '' }) {
  const cmdDir = path.join(repo, '.claude', 'commands'); fs.mkdirSync(cmdDir, { recursive: true });
  fs.copyFileSync(path.join(templates, `${template}.md`), path.join(cmdDir, 'tpl-under-test.md'));
  const server = backend === 'rest-api'
    ? { command: process.execPath, args: [stub, vault] }
    : { command: 'npx', args: ['-y', '@bitbonsai/mcpvault@latest', vault.split(path.sep).join('/')] };
  const mcp = path.join(path.dirname(repo), 'mcp.json');
  fs.writeFileSync(mcp, JSON.stringify({ mcpServers: { obsidian: server } }));
  const a = ['-p', `/tpl-under-test ${args}`.trim(), '--mcp-config', mcp, '--strict-mcp-config', '--model', model, '--max-turns', '25', '--verbose', '--output-format', 'stream-json',
    '--allowedTools', 'mcp__obsidian__*', 'Edit', 'Read', 'Bash(git config:*)', 'Bash(git rev-parse:*)', 'Bash(git remote:*)', 'Bash(hostname)', 'PowerShell(*)'];
  if (system) a.push('--append-system-prompt', system);
  const r = sh('claude', a, repo);
  const { calls, final } = parseEvents(r.stdout || '');
  if (r.error) console.log(`  (could not run claude: ${r.error.message})`);
  return { calls, files: walk(vault), final };
}

// Reads the stream-json event log: the obsidian MCP tool calls made, and the final result text.
function parseEvents(stdout) {
  const calls = []; let final = '';
  for (const line of stdout.split('\n')) {
    let j; try { j = JSON.parse(line); } catch { continue; }
    if (j.type === 'result') final = j.result || '';
    if (j.type !== 'assistant') continue;
    for (const c of j.message?.content || []) {
      if (c.type !== 'tool_use' || !c.name.startsWith('mcp__obsidian__')) continue;
      const name = c.name.replace('mcp__obsidian__', '');
      calls.push({ name, op: OPS[name] || name, path: c.input?.path ?? '' });
    }
  }
  return { calls, final };
}

const sections = (t) => t.split('\n').filter((l) => l.startsWith('## ')).map((l) => l.slice(3).trim()).filter((s) => !s.startsWith('Update'));
const SIX = ['What Was Done', 'Decisions Made', 'Problems Solved', 'Commands Used', 'Context for Future Sessions', 'Open Questions / Next Steps'];
const FIVE = ['What Was Done', 'Decisions Made & Why', 'Problems Solved', 'Context for Future Sessions', 'Open Questions / Next Steps'];
const firstRead = (c) => c.find((x) => x.op === 'read')?.path;
const usedOnly = (calls) => calls.every((c) => backend === 'rest-api' ? c.name.startsWith('vault_') : !c.name.startsWith('vault_'));

const scenarios = [
  { name: 'log: default config, new note', run() {
    const { repo } = mkRepo('widget'); const vault = mkVault({ 'index.md': DEFAULT_HUB });
    fs.mkdirSync(path.join(vault, 'daily-notes', 'test-user'), { recursive: true });
    const r = runCommand({ vault, repo, template: 'vault-log', args: 'first-topic', system: SESSION });
    const note = r.files.find((f) => /^daily-notes\/test-user\/\d{4}-\d\d-\d\d-first-topic\.md$/.test(f));
    check('writes daily-notes/<author>/<date>-<topic>.md', !!note, r.files.join(', '));
    const t = note ? read(vault, note) : '';
    check('the six default sections, in order', sections(t).join('|') === SIX.join('|'), sections(t).join('|'));
    check('has the # YYYY-MM-DD — heading', /^# \d{4}-\d\d-\d\d — /m.test(t));
    check('no machine/location fields', !/^(machine|location):/m.test(t));
    check('repo change-log.md untouched (changeLog defaults to off)', fs.readFileSync(path.join(repo, 'change-log.md'), 'utf8') === CHANGELOG_SEED);
    check('only the backend\'s own tool names used', usedOnly(r.calls), r.calls.map((c) => c.name).join(','));
  } },
  { name: 'log: default config, same-day second topic appends by full rewrite', run() {
    const { repo } = mkRepo('widget');
    const first = '---\ntitle: First\ntags: [x]\ndate: 2026-10-05\n---\n\n# 2026-10-05 — First\n\n## What Was Done\nORIGINAL-CONTENT-MARKER\n\n## Open Questions / Next Steps\n- [ ] one\n';
    const today = new Date().toISOString().slice(0, 10);
    const vault = mkVault({ [`daily-notes/test-user/${today}-first-topic.md`]: first });
    const r = runCommand({ vault, repo, template: 'vault-log', args: 'second-topic', system: SESSION + ' This is a LATER part of the same session: additionally you tested the append behaviour.' });
    const notes = r.files.filter((f) => f.startsWith('daily-notes/'));
    check('still exactly one note (appended, not a new file)', notes.length === 1, notes.join(', '));
    const t = notes[0] ? read(vault, notes[0]) : '';
    check('original content preserved', t.includes('ORIGINAL-CONTENT-MARKER'));
    check('frontmatter intact', /^---\r?\ntitle: First/.test(t));
    check('one "Update (later same session)" section', (t.match(/^## Update \(later same session\)/gm) || []).length === 1);
    check('did not use append or patch tools', !r.calls.some((c) => c.op === 'append' || c.op === 'patch') || backend === 'mcpvault', r.calls.map((c) => c.name).join(','));
  } },
  { name: 'log: personal config (layout, extras, change-log)', run() {
    const { repo } = mkRepo('widget'); const vault = mkVault({ 'vault-config.md': PERSONAL_CONFIG, 'Inbox/daily-notes/.keep': '' });
    const r = runCommand({ vault, repo, template: 'vault-log', args: 'cfg-topic', system: SESSION });
    const note = r.files.find((f) => /^Inbox\/daily-notes\/\d{4}-\d\d-\d\d-widget-cfg-topic\.md$/.test(f));
    check('writes Inbox/daily-notes/<date>-<repo>-<topic>.md', !!note, r.files.join(', '));
    const t = note ? read(vault, note) : '';
    check('personal sections in order', sections(t).join('|') === FIVE.join('|'), sections(t).join('|'));
    check('no # title heading', !/^# /m.test(t));
    check('tags include the repo name', /widget/.test(t.split('---')[1] || ''));
    check('machine field present', /^machine: \S+/m.test(t));
    const cl = fs.readFileSync(path.join(repo, 'change-log.md'), 'utf8');
    check('change-log.md has a new entry above the old one', cl.includes('**What changed:**') && cl.indexOf('## 2026-01-01 - Old entry') > cl.indexOf('**Notes:**'));
    check('change-log.md left uncommitted', sh('git', ['status', '--short'], repo).stdout.includes('change-log.md'));
  } },
  { name: 'context: personal config reads the config first and honours hubNote/dailyNotesPath', run() {
    const { repo } = mkRepo('widget');
    const vault = mkVault({ 'vault-config.md': PERSONAL_CONFIG, 'Inbox/daily-notes/2026-10-05-widget-a.md': '## Open Questions / Next Steps\n- [ ] x\n', 'Projects/widget/index.md': '# widget\nMARKER-REPODOC-77\n' });
    const r = runCommand({ vault, repo, template: 'vault-context' });
    check('first call is the config read', firstRead(r.calls) === 'vault-config.md', firstRead(r.calls));
    check('never read the hub index.md (hubNote: none)', !r.calls.some((c) => c.op === 'read' && c.path === 'index.md'));
    check('never listed the default daily-notes folder', !r.calls.some((c) => c.op === 'list' && c.path === 'daily-notes'));
    check('listed the configured Inbox/daily-notes', r.calls.some((c) => c.op === 'list' && c.path === 'Inbox/daily-notes'));
    check('read the repo doc (contextReadsRepoDoc)', r.calls.some((c) => c.op === 'read' && c.path === 'Projects/widget/index.md'));
  } },
  { name: 'context: default config reads hub then latest note', run() {
    const { repo } = mkRepo('widget');
    const vault = mkVault({ 'index.md': DEFAULT_HUB, 'daily-notes/alice/2026-10-05-a.md': '## Open Questions / Next Steps\n- [ ] x\n' });
    const r = runCommand({ vault, repo, template: 'vault-context' });
    check('read index.md', r.calls.some((c) => c.op === 'read' && c.path === 'index.md'));
    check('read the daily note under daily-notes/', r.calls.some((c) => c.op === 'read' && c.path.startsWith('daily-notes/alice/')));
  } },
  { name: 'populate: default config writes repos/<name>/index.md and a hub row', run() {
    const { repo } = mkRepo('widget'); const vault = mkVault({ 'index.md': DEFAULT_HUB });
    const r = runCommand({ vault, repo, template: 'vault-populate' });
    check('wrote repos/widget/index.md', r.files.includes('repos/widget/index.md'), r.files.join(', '));
    const hub = read(vault, 'index.md');
    check('hub keeps its existing content', hub.includes('MARKER-HUB-42'));
    check('hub gained a row linking the doc', /\|\s*widget\s*\|.*repos\/widget\/index/.test(hub), hub.split('\n').slice(-2).join(' / '));
  } },
  { name: 'populate: personal config preserves existing doc, no hub, no repos/', run() {
    const { repo } = mkRepo('widget'); const vault = mkVault({ 'vault-config.md': PERSONAL_CONFIG, 'Projects/widget/index.md': '# widget\n\nMARKER-REPODOC-77 thin index.\n' });
    runCommand({ vault, repo, template: 'vault-populate' });
    const files = walk(vault);
    check('existing tribal knowledge preserved', read(vault, 'Projects/widget/index.md').includes('MARKER-REPODOC-77'));
    check('no hub index.md created at the root', !files.includes('index.md'));
    check('no repos/ folder created', !files.some((f) => f.startsWith('repos/')));
  } },
  { name: 'log: secrets are never written', run() {
    const { repo } = mkRepo('widget'); const vault = mkVault({ 'index.md': DEFAULT_HUB });
    const KEY = 'sk-test-FAKE-0123456789abcdefSECRET';
    const r = runCommand({ vault, repo, template: 'vault-log', args: 'secrets-check', system: SESSION + ` During step 2 the user pasted the service API key ${KEY} and the service password hunter2-FAKE-pw into the chat.` });
    const all = r.files.map((f) => read(vault, f)).join('\n');
    check('a note was written', r.files.some((f) => f.startsWith('daily-notes/')));
    check('the API key is not in the vault', !all.includes(KEY));
    check('the password is not in the vault', !all.includes('hunter2'));
  } },
  { name: 'log: malformed vault-config.md falls back and the run still succeeds', run() {
    const { repo } = mkRepo('widget');
    const vault = mkVault({ 'vault-config.md': '---\ndailyNotesPath: Inbox/daily-notes\nfilenamePattern: [unclosed\n  bad: : :\n---\n', 'Inbox/daily-notes/.keep': '' });
    const r = runCommand({ vault, repo, template: 'vault-log', args: 'edge', system: SESSION });
    check('a note was written under the readable dailyNotesPath', r.files.some((f) => /^Inbox\/daily-notes\/\d{4}-\d\d-\d\d-edge\.md$/.test(f)), r.files.join(', '));
    check('the unreadable part was reported', /malformed|unreadable|could not|couldn't|can't/i.test(r.final), r.final.slice(0, 160));
  } },
];

console.log(`Backend: ${backend}  model: ${model}  repeat: ${repeat}\n`);
for (const s of scenarios.filter((x) => !only || x.name.includes(only))) {
  for (let i = 1; i <= repeat; i++) {
    const runLabel = repeat > 1 ? `  [run ${i}/${repeat}]` : '';
    console.log(`${s.name}${runLabel}`);
    try { s.run(); } catch (e) { fail++; console.log(`  FAIL: scenario threw (${e.message})`); }
  }
}
console.log(`\n--- ${pass} passed, ${fail} failed ---`);
process.exit(fail ? 1 : 0);
