#!/usr/bin/env bash
# Installs this repo's Claude Code commands, skills and hook templates into
# ~/.claude on THIS machine, and keeps them current.
#
# Why this exists: ~/.claude lives in your home directory, outside any repo,
# and neither git nor Claude Code syncs it. A new machine therefore starts with
# none of the vault commands or hooks, and a SessionStart hook that points at a
# missing script fails silently. Run this once per machine (it is idempotent),
# and again after pulling this repo, or use --check to see what is stale.
# See docs/automation.md and docs/vault-config.md.
#
# Runs under bash on Linux, macOS, and Git Bash on Windows.

set -u

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${CLAUDE_HOME:-$HOME/.claude}"
VAULT=""
BACKEND=""
CHECK=0
DRY=0
FORCE=0
SKIP_SKILLS=0
STATUSLINE=0

usage() {
  cat <<'EOF'
Usage: install-claude-config.sh [options]

  --vault <path>       the vault's absolute path. Written to
                       <prefix>/hook-configs/vault-root so hooks installed in
                       other repos can find the vault without VAULT_ROOT.
  --backend <name>     rest-api | mcpvault. With mcpvault and --vault, also
                       writes the hook MCP config (<prefix>/hook-configs/
                       obsidian-mcp-config.json) if there isn't one. The
                       rest-api backend needs an API key, see tools/setup-mcp.sh.
  --check              report whether installed files are current; change nothing.
                       Exit 1 if anything is missing, outdated or modified.
  --dry-run            say what would be installed; change nothing.
  --force              allow replacing an existing vault-root file, and (with
                       --statusline) a different statusLine in settings.json.
  --statusline         also install the Claude Code status line: copies
                       tools/statusline/statusline.mjs to <prefix>/statusline.mjs
                       and sets "statusLine" in <prefix>/settings.json if none is
                       set (an existing different one is kept and the snippet
                       printed; --force replaces it, after a backup). Needs Node
                       18 or later. See docs/statusline.md.
  --no-skills          do not install the two skills. They describe the TEAM vault
                       layout (daily-notes/<author>/, repos/<name>/) and trigger on
                       any obsidian MCP call, so leave them out for a vault laid
                       out differently (see docs/vault-config.md).
  --prefix <dir>       install into <dir> instead of ~/.claude (used by tests).
  -h, --help           this text.
EOF
  return $?
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT="${2:-}"; shift 2 ;;
    --backend) BACKEND="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --force) FORCE=1; shift ;;
    --no-skills) SKIP_SKILLS=1; shift ;;
    --statusline) STATUSLINE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$BACKEND" ]] && [[ "$BACKEND" != "rest-api" ]] && [[ "$BACKEND" != "mcpvault" ]]; then
  echo "--backend must be rest-api or mcpvault" >&2; exit 2
fi
if [[ -n "$VAULT" ]] && [[ ! -d "$VAULT" ]]; then
  echo "--vault '$VAULT' is not a directory" >&2; exit 2
fi
[[ -n "$PREFIX" ]] || { echo "empty --prefix" >&2; exit 2; }

NEED_ATTENTION=0

# bedrock-template stamp, e.g. "<!-- bedrock-template: vault-log, version 2 -->"
stamp_version() { local f="$1"; grep -o 'bedrock-template: [a-z-]*, version [0-9]*' "$f" 2>/dev/null | head -n1 | sed -E 's/.*version //'; return $?; }

# install_file <source> <destination> [exec]
install_file() {
  local src="$1" dst="$2" mode="${3:-}" verb
  if [[ -e "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "unchanged $dst"; return 0
  fi
  [[ -e "$dst" ]] && verb="update" || verb="install"
  if [[ "$DRY" = "1" ]]; then echo "would $verb $dst"; return 0; fi
  mkdir -p "$(dirname "$dst")" && cp "$src" "$dst" || { echo "FAILED to write $dst" >&2; NEED_ATTENTION=1; return 1; }
  [[ "$mode" = "exec" ]] && chmod +x "$dst"
  [[ "$verb" = "update" ]] && echo "updated $dst" || echo "installed $dst"
}

# check_file <source> <destination> <label>
check_file() {
  local src="$1" dst="$2" label="$3" sv iv
  if [[ ! -e "$dst" ]]; then echo "missing  $label"; NEED_ATTENTION=1; return; fi
  if cmp -s "$src" "$dst"; then echo "current  $label"; return; fi
  sv="$(stamp_version "$src")"; iv="$(stamp_version "$dst")"
  if [[ -n "$sv" ]] && [[ -n "$iv" ]] && [[ "$iv" -lt "$sv" ]] 2>/dev/null; then
    echo "outdated $label (installed version $iv, repo has $sv)"
  else
    echo "differs  $label (installed copy is not byte-identical to this repo's)"
  fi
  NEED_ATTENTION=1
}

# A path in the form node itself understands: Git Bash's /c/Users/... becomes C:/Users/...
native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$p"; else printf '%s' "$p"; fi
  return 0
}

# The status line command to write into settings.json. An absolute, forward-slash path,
# not "~": Claude Code on Windows may run it through PowerShell, which does not expand ~.
# Claude Code hands the command to a shell, so a path with anything unusual in it is wrapped
# in SINGLE quotes (nothing inside them is expanded by bash or PowerShell). A path holding a
# single quote or a line break cannot be quoted safely, so none is written for it.
statusline_command() {
  local abs script
  case "$PREFIX" in /*|[A-Za-z]:*) abs="$PREFIX" ;; *) abs="$PWD/${PREFIX#./}" ;; esac
  script="$(native_path "$abs/statusline.mjs")"
  case "$script" in
    *"'"*|*$'\n'*|*$'\r'*) return 1 ;;
    *[!A-Za-z0-9_./:~-]*) printf "node '%s'" "$script" ;;
    *) printf 'node %s' "$script" ;;
  esac
  return 0
}

# configure_statusline [--check]: sets (or checks) "statusLine" in <prefix>/settings.json
# through the Node helper, which backs the file up, preserves every other key and refuses
# to touch a file that is not valid JSON. Honours --dry-run and --force.
configure_statusline() {
  local mode="${1:-}" settings="$PREFIX/settings.json" cmd extra="" helper rc major check=0
  [[ "$mode" = "--check" ]] && check=1
  if ! cmd="$(statusline_command)"; then
    echo "warning: not configuring settings.json: the install path contains a single quote or a line break, which cannot be quoted safely in a command."; NEED_ATTENTION=1; return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    if [[ "$check" = "1" ]]; then echo "unknown  settings.json statusLine (node is not on PATH, so it cannot be read)"
    else
      echo "warning: node is not on PATH, so $settings was not changed. The status line needs Node 18 or later; once it is installed, re-run this, or add this to settings.json:"
      echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\" }"
    fi
    return 0
  fi
  if [[ "$check" != "1" ]]; then
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)"
    [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -lt 18 ]] && echo "warning: node $major is older than 18; the status line may not run."
  fi
  [[ "$FORCE" = "1" ]] && extra="$extra --force"
  [[ "$DRY" = "1" ]] && extra="$extra --dry-run"
  [[ "$check" = "1" ]] && extra="$extra --check"
  helper="$(native_path "$SRC_ROOT/tools/statusline/configure-settings.mjs")"
  # $extra is a short list of fixed flags, deliberately split into words.
  # shellcheck disable=SC2086
  node "$helper" "$(native_path "$settings")" "$cmd" $extra
  rc=$?
  if [[ "$rc" = "3" ]]; then NEED_ATTENTION=1
  elif [[ "$rc" = "1" ]] && [[ "$check" = "1" ]]; then NEED_ATTENTION=1
  elif [[ "$rc" != "0" ]]; then echo "warning: configure-settings.mjs exited $rc" >&2; NEED_ATTENTION=1; fi
  return 0
}

# The wrapper a project's SessionStart hook can call without knowing the vault
# path: it falls back to <prefix>/hook-configs/vault-root when VAULT_ROOT is
# unset, then hands over to the real hook (stdin passes straight through).
wrapper_content() {
  cat <<'EOF'
#!/usr/bin/env bash
# Installed by Bedrock's tools/install-claude-config.sh. Runs
# session-start-vault-context with VAULT_ROOT taken from this machine's
# hook-configs/vault-root file when it isn't already set.
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${VAULT_ROOT:-}" ] && [ -f "$d/../hook-configs/vault-root" ]; then
  VAULT_ROOT="$(head -n1 "$d/../hook-configs/vault-root" | tr -d '\r')"
  export VAULT_ROOT
fi
exec bash "$d/session-start-vault-context"
EOF
  return $?
}

# --- the file lists --------------------------------------------------------
COMMAND_SRCS=("$SRC_ROOT"/tools/command-templates/*.md)
HOOKS=(post-merge pre-commit pre-push session-start-vault-check session-start-vault-context)
SKILL_DIRS=("$SRC_ROOT"/tools/skill-templates/*/)

echo "Source:  $SRC_ROOT"
echo "Install: $PREFIX"
[[ "$CHECK" = "1" ]] && echo "(check only, nothing will be changed)"
[[ "$DRY" = "1" ]] && echo "(dry run, nothing will be changed)"
echo

# --- prerequisites (warnings only) -----------------------------------------
if [[ "$CHECK" != "1" ]]; then
  command -v claude >/dev/null 2>&1 || echo "warning: 'claude' is not on PATH here (a terminal opened before installing it won't see it)."
  command -v jq >/dev/null 2>&1 || echo "warning: jq is not installed; the post-merge hook refuses to run without it."
  command -v timeout >/dev/null 2>&1 || echo "warning: 'timeout' is not installed; the post-merge hook needs it."
  if [[ "$BACKEND" = "mcpvault" ]]; then
    command -v npx >/dev/null 2>&1 || echo "warning: npx is not on PATH; the mcpvault MCP server runs through it. After installing Node, fully close and reopen the terminal."
  fi
fi

# --- commands, skills, hooks -----------------------------------------------
if [[ "$CHECK" = "1" ]]; then
  for f in "${COMMAND_SRCS[@]}"; do [[ -f "$f" ]] && check_file "$f" "$PREFIX/commands/$(basename "$f")" "commands/$(basename "$f")"; done
  [[ "$SKIP_SKILLS" = "1" ]] || for d in "${SKILL_DIRS[@]}"; do [[ -f "${d}SKILL.md" ]] && check_file "${d}SKILL.md" "$PREFIX/skills/$(basename "$d")/SKILL.md" "skills/$(basename "$d")/SKILL.md"; done
  for h in "${HOOKS[@]}"; do check_file "$SRC_ROOT/tools/hook-templates/$h" "$PREFIX/hook-templates/$h" "hook-templates/$h"; done
  tmpw="$(mktemp)"; wrapper_content > "$tmpw"
  check_file "$tmpw" "$PREFIX/hook-templates/session-start-vault-context.sh" "hook-templates/session-start-vault-context.sh"
  rm -f "$tmpw"
  if [[ "$STATUSLINE" = "1" ]]; then
    check_file "$SRC_ROOT/tools/statusline/statusline.mjs" "$PREFIX/statusline.mjs" "statusline.mjs"
    configure_statusline --check
  fi
  echo
  [[ "$NEED_ATTENTION" = "0" ]] && echo "Everything is current." || echo "Re-run without --check to bring these up to date."
  exit "$NEED_ATTENTION"
fi

for f in "${COMMAND_SRCS[@]}"; do [[ -f "$f" ]] && install_file "$f" "$PREFIX/commands/$(basename "$f")"; done
[[ "$SKIP_SKILLS" = "1" ]] || for d in "${SKILL_DIRS[@]}"; do [[ -f "${d}SKILL.md" ]] && install_file "${d}SKILL.md" "$PREFIX/skills/$(basename "$d")/SKILL.md"; done
for h in "${HOOKS[@]}"; do install_file "$SRC_ROOT/tools/hook-templates/$h" "$PREFIX/hook-templates/$h" exec; done
tmpw="$(mktemp)"; wrapper_content > "$tmpw"
install_file "$tmpw" "$PREFIX/hook-templates/session-start-vault-context.sh" exec
rm -f "$tmpw"
if [[ "$STATUSLINE" = "1" ]]; then
  install_file "$SRC_ROOT/tools/statusline/statusline.mjs" "$PREFIX/statusline.mjs"
  configure_statusline
fi

# --- vault-root file and hook MCP config -----------------------------------
if [[ -n "$VAULT" ]]; then
  vault_norm="$(printf '%s' "$VAULT" | tr '\\' '/')"
  root_file="$PREFIX/hook-configs/vault-root"
  if [[ -f "$root_file" ]] && [[ "$(head -n1 "$root_file" | tr -d '\r')" != "$vault_norm" ]] && [[ "$FORCE" != "1" ]]; then
    echo "kept      $root_file (already points at '$(head -n1 "$root_file" | tr -d '\r')'; pass --force to change it to '$vault_norm')"
  elif [[ -f "$root_file" ]] && [[ "$(head -n1 "$root_file" | tr -d '\r')" = "$vault_norm" ]]; then
    echo "unchanged $root_file"
  elif [[ "$DRY" = "1" ]]; then
    echo "would write $root_file"
  else
    mkdir -p "$PREFIX/hook-configs" && printf '%s\n' "$vault_norm" > "$root_file" && echo "wrote     $root_file"
  fi

  if [[ "$BACKEND" = "mcpvault" ]]; then
    cfg="$PREFIX/hook-configs/obsidian-mcp-config.json"
    if [[ -e "$cfg" ]]; then
      echo "kept      $cfg (never overwritten)"
    elif [[ "$DRY" = "1" ]]; then
      echo "would write $cfg"
    elif printf '%s' "$vault_norm" | grep -q '"'; then
      echo "not writing $cfg: the vault path contains a double quote" >&2
    else
      mkdir -p "$PREFIX/hook-configs"
      printf '{"mcpServers":{"obsidian":{"command":"npx","args":["-y","@bitbonsai/mcpvault@latest","%s"]}}}\n' "$vault_norm" > "$cfg" && echo "wrote     $cfg"
    fi
  fi
fi
if [[ "$BACKEND" = "rest-api" ]]; then
  echo "note: the REST API backend needs the plugin's API key, so its MCP config can't be generated here; run tools/setup-mcp.sh (see docs/mcp-setup.md)."
fi

echo
echo "Done. Commands and skills load in a NEW Claude Code session; hook templates are copied, not enabled."
echo "Per-repo hooks (post-merge, pre-commit) still need copying into that repo's .git/hooks, see docs/automation.md."
[[ "$STATUSLINE" = "1" ]] && [[ "$DRY" != "1" ]] && echo "The status line appears in a NEW Claude Code session (see docs/statusline.md)."
exit "$NEED_ATTENTION"
