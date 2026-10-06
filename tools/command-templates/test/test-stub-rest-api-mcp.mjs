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

console.log(`--- ${pass} passed, ${fail} failed ---`);
process.exit(fail ? 1 : 0);
