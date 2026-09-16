---
name: obsidian-mcp-setup
description: Use when setting up, troubleshooting, or explaining the connection between Claude Code and this vault (the `obsidian` MCP server). Trigger on requests to connect Claude Code to Obsidian, register the obsidian MCP server, or fix "obsidian: Failed to connect" errors.
---

# Obsidian MCP setup

Quick-reference pointer, not the source of truth — the canonical, maintained version of everything below lives in this vault's own `docs/mcp-setup.md`. If the two ever disagree, the repo doc wins.

## Core facts

- MCP server name: `obsidian`, backed by the Obsidian **Local REST API** community plugin running inside Obsidian itself. Obsidian must be open for the MCP connection to work at all.
- Registration command: `claude mcp add --transport http obsidian "http://localhost:27123/mcp/" --header "Authorization: Bearer <api-key>" --scope user` — `--scope user` so it's available in every Claude Code session on the machine, not just one project.
- The API key + self-signed cert live in `.obsidian/plugins/obsidian-local-rest-api/data.json` inside the vault, generated on first plugin load — never commit that file; confirm it's gitignored before the first commit on any new clone.
- The vault repo ships `tools/setup-mcp.ps1` (Windows) and `tools/setup-mcp.sh` (macOS/Linux), which automate all of the above end-to-end (auto-detect the vault path, read the API key themselves) — point people at those scripts first rather than the manual steps.
- If this Claude Code deployment restricts MCP server URLs to an allowlist and rejects `localhost`, see the "Enterprise MCP allowlists" section of `docs/mcp-setup.md` for a hosts-file-mapped-hostname workaround.

## Common failure modes

- `claude mcp list` shows `obsidian: ... Failed to connect` → almost always Obsidian isn't open, or `<api-key>` was left as a literal placeholder when registering. Fix: `claude mcp remove obsidian --scope user`, then re-add with the real key from `data.json`.
- MCP cert errors → the Local REST API plugin defaults to HTTPS on 27124 (self-signed cert, causes cert-validation pain for MCP); switch to plain HTTP on 27123 via `"enableInsecureServer": true` in `data.json` instead.

For anything not covered above — the full step-by-step walkthrough and every known gotcha with its exact fix — read `docs/mcp-setup.md` in this vault repo directly.
