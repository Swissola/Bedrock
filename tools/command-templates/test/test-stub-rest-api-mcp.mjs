#!/usr/bin/env node
// Tests for stub-rest-api-mcp.mjs: the tool names it serves, and above all that a
// tool call can never reach outside the vault folder. No model calls, no network.
//
//   node tools/command-templates/test/test-stub-rest-api-mcp.mjs

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const stub = path.join(path.dirname(fileURLToPath(import.meta.url)), 'stub-rest-api-mcp.mjs');
let pass = 0, fail = 0;
const check = (desc, ok, extra = '') => {
  if (ok) { pass++; console.log(`PASS: ${desc}`); } else { fail++; console.log(`FAIL: ${desc}${extra ? ` (${extra})` : ''}`); }
};

// Sends the requests to a fresh stub over stdin and returns the responses by id.
function talk(vault, requests) {
  const input = requests.map((r, i) => JSON.stringify({ jsonrpc: '2.0', id: i + 1, ...r })).join('\n') + '\n';
  const r = spawnSync(process.execPath, [stub, vault], { input, encoding: 'utf8', timeout: 20000 });
  const out = {};
  for (const line of (r.stdout || '').split('\n').filter(Boolean)) { const j = JSON.parse(line); out[j.id] = j.result ?? j.error; }
  return out;
}
const call = (name, args) => ({ method: 'tools/call', params: { name, arguments: args } });
const textOf = (res) => res?.content?.[0]?.text ?? '';

const vault = fs.mkdtempSync(path.join(os.tmpdir(), 'bedrock-stub-vault-'));
const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'bedrock-stub-outside-'));
fs.writeFileSync(path.join(vault, 'a.md'), 'inside\n');
fs.writeFileSync(path.join(outside, 'secret.md'), 'outside\n');
let linked = true;
try { fs.symlinkSync(outside, path.join(vault, 'link'), process.platform === 'win32' ? 'junction' : 'dir'); } catch { linked = false; }

const names = ['vault_list', 'vault_read', 'vault_write', 'vault_append', 'vault_patch'];
const res = talk(vault, [
  { method: 'tools/list' },
  call('vault_read', { path: 'a.md' }),
  call('vault_read', { path: '../' + path.basename(outside) + '/secret.md' }),
  call('vault_read', { path: path.join(outside, 'secret.md') }),
  call('vault_write', { path: 'new/dir/n.md', content: 'z' }),
  call('vault_write', { path: '../escaped.md', content: 'z' }),
  call('vault_read', { path: 'link/secret.md' }),
  call('vault_write', { path: 'link/planted.md', content: 'z' }),
  call('vault_list', {}),
  call('vault_patch', { path: 'a.md' }),
]);

check('serves the five REST API tool names', names.every((n) => res[1].tools.some((t) => t.name === n)));
check('reads a file inside the vault', textOf(res[2]) === 'inside\n', textOf(res[2]));
check('refuses a ../ path', res[3].isError === true && /escapes/.test(textOf(res[3])), textOf(res[3]));
check('refuses an absolute path elsewhere', res[4].isError === true && /escapes/.test(textOf(res[4])), textOf(res[4]));
check('creates a file in a new nested folder', fs.existsSync(path.join(vault, 'new/dir/n.md')) && !res[5].isError);
check('refuses to write outside the vault', res[6].isError === true && !fs.existsSync(path.join(path.dirname(vault), 'escaped.md')));
if (linked) {
  check('refuses to read through a symlink that points outside', res[7].isError === true && !textOf(res[7]).includes('outside'), textOf(res[7]));
  check('refuses to write through a symlink that points outside', res[8].isError === true && !fs.existsSync(path.join(outside, 'planted.md')));
} else {
  console.log('SKIP: symlink checks (this machine cannot create a symlink)');
}
check('lists the vault root', textOf(res[9]).includes('a.md'), textOf(res[9]));
check('vault_patch is registered but always an error', res[10].isError === true);

const noArg = spawnSync(process.execPath, [stub], { encoding: 'utf8', timeout: 20000, input: '' });
const badArg = spawnSync(process.execPath, [stub, path.join(vault, 'does-not-exist')], { encoding: 'utf8', timeout: 20000, input: '' });
check('no folder argument: usage error, exit 2', noArg.status === 2, `status ${noArg.status}`);
check('nonexistent folder: usage error, exit 2', badArg.status === 2, `status ${badArg.status}`);

// --- protocol and tool behaviour (added on top of the path guard above) -------------
//
// The command-template harness trusts this stub to behave like the plugin's tools, so
// the stub's own behaviour is pinned here: the MCP handshake, the shape of each tool's
// answer, and that every error path is an error and not a silent success.

const v2 = fs.mkdtempSync(path.join(os.tmpdir(), 'bedrock-stub-vault2-'));
fs.mkdirSync(path.join(v2, 'zeta'));
fs.mkdirSync(path.join(v2, 'alpha'));
fs.mkdirSync(path.join(v2, '.obsidian'));
fs.writeFileSync(path.join(v2, 'b.md'), 'B\n');
fs.writeFileSync(path.join(v2, 'a.md'), 'A\n');
fs.writeFileSync(path.join(v2, '.hidden.md'), 'H\n');
fs.writeFileSync(path.join(v2, 'alpha', 'inner.md'), 'I\n');
const logFile = path.join(v2, '..', `stub-calls-${process.pid}.log`);

// Raw conversation, so notifications, junk lines and replies can be inspected as sent.
function raw(vault, lines, env = {}) {
  const r = spawnSync(process.execPath, [stub, vault], { input: lines.join('\n') + '\n', encoding: 'utf8', timeout: 20000, env: { ...process.env, ...env } });
  return (r.stdout || '').split('\n').filter(Boolean).map((l) => JSON.parse(l));
}
const rpc = (id, method, params) => JSON.stringify({ jsonrpc: '2.0', id, method, params });

const proto = raw(v2, [
  rpc(1, 'initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 't', version: '1' } }),
  JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
  'this is not json',
  '',
  rpc(2, 'ping'),
  rpc(3, 'no/such/method'),
  rpc(4, 'tools/call', { name: 'no_such_tool', arguments: {} }),
]);
const byId = Object.fromEntries(proto.map((m) => [m.id, m]));
check('answers initialize with the protocol version it was offered', byId[1].result.protocolVersion === '2024-11-05', JSON.stringify(byId[1].result));
check('initialize advertises the tools capability and a server name', !!byId[1].result.capabilities.tools && byId[1].result.serverInfo.name === 'stub-rest-api-mcp');
check('a notification (no id) gets no reply, and junk lines are ignored', proto.length === 4, `got ${proto.length} replies`);
check('ping is answered with an empty result', byId[2].result && Object.keys(byId[2].result).length === 0);
check('an unknown method is a JSON-RPC -32601 error', byId[3].error?.code === -32601, JSON.stringify(byId[3]));
check('an unknown tool is a tool error, not a crash', byId[4].result?.isError === true && /Unknown tool/.test(byId[4].result.content[0].text));

const t = talk(v2, [
  { method: 'tools/list' },
  call('vault_list', {}),
  call('vault_list', { path: '' }),
  call('vault_list', { path: 'alpha' }),
  call('vault_list', { path: 'nope' }),
  call('vault_read', { path: 'nope.md' }),
  call('vault_read', { path: 'alpha' }),
  call('vault_write', { path: 'a.md', content: 'overwritten\n' }),
  call('vault_read', { path: 'a.md' }),
  call('vault_append', { path: 'b.md', content: 'more\n' }),
  call('vault_read', { path: 'b.md' }),
  call('vault_append', { path: 'missing.md', content: 'x' }),
  call('vault_write', { path: 'uni.md', content: 'é€' }),
  call('vault_patch', { path: 'a.md', operation: 'replace', content: 'x' }),
  call('vault_read', { path: '.hidden.md' }),
]);
check('every tool declares an object input schema', t[1].tools.every((x) => x.inputSchema?.type === 'object' && x.description));
check('vault_read and write and append require a path (and content where it is written)',
  t[1].tools.find((x) => x.name === 'vault_read').inputSchema.required.includes('path') &&
  t[1].tools.find((x) => x.name === 'vault_write').inputSchema.required.join() === 'path,content' &&
  t[1].tools.find((x) => x.name === 'vault_append').inputSchema.required.join() === 'path,content');
check('list: root listing is sorted, directories end with /, dot entries are hidden', textOf(t[2]) === JSON.stringify(['a.md', 'alpha/', 'b.md', 'zeta/']), textOf(t[2]));
check('list: an empty path means the root', textOf(t[3]) === textOf(t[2]), textOf(t[3]));
check('list: a subfolder lists its own files', textOf(t[4]) === JSON.stringify(['inner.md']), textOf(t[4]));
check('list: a missing folder is an error naming it', t[5].isError === true && /Directory not found: nope/.test(textOf(t[5])), textOf(t[5]));
check('read: a missing file is an error naming it', t[6].isError === true && /File not found: nope.md/.test(textOf(t[6])), textOf(t[6]));
check('read: a directory is not a file', t[7].isError === true, textOf(t[7]));
check('write: replaces the whole file and reports the byte count', textOf(t[8]) === 'Wrote a.md (12 bytes)' && !t[8].isError, textOf(t[8]));
check('write then read returns exactly what was written', textOf(t[9]) === 'overwritten\n', textOf(t[9]));
check('append: adds to the end of an existing file', textOf(t[11]) === 'B\nmore\n', textOf(t[11]));
check('append: a missing file is an error and is not created', t[12].isError === true && !fs.existsSync(path.join(v2, 'missing.md')), textOf(t[12]));
check('write: byte count is bytes, not characters', textOf(t[13]) === 'Wrote uni.md (5 bytes)', textOf(t[13]));
check('patch: always refused, and leaves the file as it was', t[14].isError === true && fs.readFileSync(path.join(v2, 'a.md'), 'utf8') === 'overwritten\n');
check('read: a dot-file is still reachable by exact path (only listings hide them)', textOf(t[15]) === 'H\n', textOf(t[15]));

raw(v2, [rpc(1, 'tools/call', { name: 'vault_read', arguments: { path: 'a.md' } }), rpc(2, 'tools/call', { name: 'vault_read', arguments: { path: 'nope.md' } }), rpc(3, 'tools/call', { name: 'vault_patch', arguments: { path: 'a.md' } })], { STUB_LOG: logFile });
const logged = fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : [];
check('STUB_LOG gets one JSON line per tool call', logged.length === 3, `got ${logged.length}`);
check('STUB_LOG records tool, path and whether it was an error', logged[0]?.tool === 'vault_read' && logged[0]?.path === 'a.md' && logged[0]?.isError === false && logged[1]?.isError === true && logged[2]?.tool === 'vault_patch');
const noLog = raw(v2, [rpc(1, 'tools/call', { name: 'vault_read', arguments: { path: 'a.md' } })]);
check('without STUB_LOG nothing extra is written and the call still works', noLog[0]?.result?.content?.[0]?.text === 'overwritten\n');
fs.rmSync(logFile, { force: true });

for (const d of [vault, outside, v2]) fs.rmSync(d, { recursive: true, force: true });

console.log(`--- ${pass} passed, ${fail} failed ---`);
process.exit(fail ? 1 : 0);
