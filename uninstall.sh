#!/bin/bash
# Uninstall Claude Code auto session title hook.
# Source: https://github.com/qiyec/claude-code-auto-title

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "Uninstalling Claude Code auto-title hook..."

# 1. Remove scripts
rm -f "$HOOK_DIR/auto-title.sh" "$HOOK_DIR/auto_title.py" "$HOOK_DIR/auto_title_simple.py"
echo "Scripts removed."

# 2. Remove hook entry from settings.json
if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
entries = hooks.get("UserPromptSubmit", [])
filtered = [
    e for e in entries
    if not any(h.get("command", "").endswith("auto-title.sh") for h in e.get("hooks", []))
]

if filtered:
    hooks["UserPromptSubmit"] = filtered
elif "UserPromptSubmit" in hooks:
    del hooks["UserPromptSubmit"]

if not hooks and "hooks" in settings:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("Hook entry removed from settings.json.")
PYEOF
fi

echo "Done."
