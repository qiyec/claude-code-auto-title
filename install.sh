#!/bin/bash
# One-command installer for Claude Code auto session title.
#
# Usage:
#   bash install.sh          # LLM version: [type] structured title (requires Anthropic API key)
#   bash install.sh --simple # Lite version: truncate first message, zero cost, no API call
#
# Source: https://github.com/qiyec/claude-code-auto-title

set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main"
HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
MODE="llm"

for arg in "$@"; do
  [ "$arg" = "--simple" ] && MODE="simple"
done

echo "Installing Claude Code auto-title hook (${MODE} mode)..."

# 1. Create hooks directory
mkdir -p "$HOOK_DIR"

# 2. Download scripts from repository
curl -fsSL "$RAW_BASE/auto-title.sh" -o "$HOOK_DIR/auto-title.sh"
curl -fsSL "$RAW_BASE/auto_title.py" -o "$HOOK_DIR/auto_title.py"
curl -fsSL "$RAW_BASE/auto_title_simple.py" -o "$HOOK_DIR/auto_title_simple.py"

# 3. Switch entry point for simple mode
if [ "$MODE" = "simple" ]; then
  sed -i.bak 's/auto_title\.py/auto_title_simple.py/' "$HOOK_DIR/auto-title.sh" && \
    rm -f "$HOOK_DIR/auto-title.sh.bak"
fi

chmod +x "$HOOK_DIR/auto-title.sh" "$HOOK_DIR/auto_title.py" "$HOOK_DIR/auto_title_simple.py"

# 4. Inject hook into settings.json
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hook_entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": "~/.claude/hooks/auto-title.sh"}]
}

hooks = settings.setdefault("hooks", {})
entries = hooks.setdefault("UserPromptSubmit", [])

already = any(
    any(h.get("command", "").endswith("auto-title.sh") for h in e.get("hooks", []))
    for e in entries
)

if not already:
    entries.append(hook_entry)
    with open(path, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
    print("Hook registered in settings.json")
else:
    print("Hook already registered, skipped.")
PYEOF

echo "Done. Open a new Claude Code session and send your first message to test."
