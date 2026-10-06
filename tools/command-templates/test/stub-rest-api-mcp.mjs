#!/usr/bin/env node
// Test stub for the Obsidian Local REST API plugin's built-in MCP server.
//
// Why this exists: the command templates in ../ run against either of two
// `obsidian` MCP backends with different tool names (see docs/vault-config.md).
// The Local REST API backend needs the Obsidian app plus the plugin, so it can't
// be run in CI or on a machine without Obsidian. This stub exposes the same
// tool NAMES and INPUT SCHEMAS (taken from the plugin's own source,
// src/mcpHandler.ts registerTools()) over a plain folder, so a template's
// tool-name mapping can be exercised for real.
//
// What it does NOT reproduce: the plugin's exact response shapes (they are not
// documented), vault_patch's behaviour (registered, always returns an error, as
// a template must never depend on it), or any Obsidian-side behaviour such as
// link updating.
//
// Usage:  node stub-rest-api-mcp.mjs <vault-folder>
// Env:    STUB_LOG=<file>  append one JSON line per tool call (for assertions)
// Zero dependencies: a minimal MCP stdio server (newline-delimited JSON-RPC).

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

const root = path.resolve(process.argv[2] || '');
if (!process.argv[2] || !fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error('usage: stub-rest-api-mcp.mjs <existing vault folder>');
  process.exit(2);
}
const logFile = process.env.STUB_LOG || '';

const pathProp = { type: 'string', description: 'Path relative to the vault root' };
const tools = [
  { name: 'vault_list', description: "List files and subdirectories inside a vault directory. Returns an array of names; directory entries end with '/'. Omit path or pass an empty string to list the vault root.",
    inputSchema: { type: 'object', properties: { path: { type: 'string', description: 'Directory path relative to vault root (default: root)' } } } },
  { name: 'vault_read', description: 'Reads vault file content and metadata, with optional targeting by heading, block, or frontmatter section.',
    inputSchema: { type: 'object', properties: { path: pathProp, targetType: { type: 'string', enum: ['heading', 'block', 'frontmatter'] }, target: { type: 'string' }, scope: { type: 'string', enum: ['content', 'marker', 'markerAndContent'] } }, required: ['path'] } },
  { name: 'vault_write', description: 'Create or overwrite a vault file with the given content. Text only.',
    inputSchema: { type: 'object', properties: { path: pathProp, content: { type: 'string', description: 'Full file content (markdown text)' } }, required: ['path', 'content'] } },
  { name: 'vault_append', description: 'Append content to the end of a vault file.',
    inputSchema: { type: 'object', properties: { path: pathProp, content: { type: 'string', description: 'Content to append' } }, required: ['path', 'content'] } },
  { name: 'vault_patch', description: 'Edits a vault file with structured operations (replace/prepend/append/delete) on heading, block, or frontmatter targets.',
    inputSchema: { type: 'object', properties: { path: pathProp, targetType: { type: 'string' }, target: { type: 'string' }, operation: { type: 'string' }, content: { type: 'string' } }, required: ['path'] } },
];

// Resolve a vault-relative path, refusing anything that lands outside the vault:
// `..` segments, absolute paths, or a symlink inside the vault that points out.
const isInside = (base, target) => {
  const r = path.relative(base, target);
  return r === '' || (!r.startsWith('..') && !path.isAbsolute(r));
};
function resolveInside(rel) {
  const p = path.resolve(root, String(rel || ''));
  if (!isInside(root, p)) throw new Error('path escapes the vault');
  let probe = p; // nearest existing ancestor, so a new file's parent is checked too
  while (!fs.existsSync(probe) && probe !== root) probe = path.dirname(probe);
  if (!isInside(fs.realpathSync(root), fs.realpathSync(probe))) throw new Error('path escapes the vault');
  return p;
}
const text = (s, isError = false) => ({ content: [{ type: 'text', text: s }], isError });

function callTool(name, args) {
  switch (name) {
    case 'vault_list': {
      const dir = resolveInside(args.path);
      if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return text(`Directory not found: ${args.path || '/'}`, true);
      const names = fs.readdirSync(dir, { withFileTypes: true })
        .filter((e) => !e.name.startsWith('.')) // the real plugin hides dot-folders from vault tools
        .map((e) => (e.isDirectory() ? e.name + '/' : e.name)).sort();
      return text(JSON.stringify(names));
    }
    case 'vault_read': {
      const f = resolveInside(args.path);
      if (!fs.existsSync(f) || !fs.statSync(f).isFile()) return text(`File not found: ${args.path}`, true);
      return text(fs.readFileSync(f, 'utf8'));
    }
    case 'vault_write': {
      const f = resolveInside(args.path);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, args.content, 'utf8');
      return text(`Wrote ${args.path} (${Buffer.byteLength(args.content)} bytes)`);
    }
    case 'vault_append': {
      const f = resolveInside(args.path);
      if (!fs.existsSync(f)) return text(`File not found: ${args.path}`, true);
      fs.appendFileSync(f, args.content, 'utf8');
      return text(`Appended to ${args.path}`);
    }
    case 'vault_patch':
      return text('vault_patch is not supported by this test stub', true);
    default:
      return text(`Unknown tool: ${name}`, true);
  }
}

const send = (obj) => process.stdout.write(JSON.stringify(obj) + '\n');
const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  const { id, method, params } = msg;
  if (id === undefined) return; // notification (e.g. notifications/initialized), no reply
  try {
    if (method === 'initialize') {
      send({ jsonrpc: '2.0', id, result: { protocolVersion: params?.protocolVersion || '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'stub-rest-api-mcp', version: '1.0.0' } } });
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools } });
    } else if (method === 'tools/call') {
      const args = params?.arguments || {};
      let result;
      try { result = callTool(params?.name, args); } catch (e) { result = text(String(e.message || e), true); }
      if (logFile) fs.appendFileSync(logFile, JSON.stringify({ tool: params?.name, path: args.path, isError: !!result.isError }) + '\n');
      send({ jsonrpc: '2.0', id, result });
    } else if (method === 'ping') {
      send({ jsonrpc: '2.0', id, result: {} });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } });
    }
  } catch (e) {
    send({ jsonrpc: '2.0', id, error: { code: -32603, message: String(e.message || e) } });
  }
});
