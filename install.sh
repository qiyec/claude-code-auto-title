#!/bin/bash
# One-command installer for Claude Code auto session title.
#
# Usage:
#   bash install.sh          # LLM version: [type] structured title (needs Anthropic API key)
#   bash install.sh --simple # Lite version: truncate first message, no API call, zero cost
#
# Source: https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
MODE="llm"

for arg in "$@"; do
  [ "$arg" = "--simple" ] && MODE="simple"
done

echo "Installing Claude Code auto-title hook (${MODE} mode)..."

# 1. Create hooks directory
mkdir -p "$HOOK_DIR"

# 2. Write auto-title.sh
if [ "$MODE" = "simple" ]; then
  PYTHON_SCRIPT="auto_title_simple.py"
else
  PYTHON_SCRIPT="auto_title.py"
fi

cat > "$HOOK_DIR/auto-title.sh" << EOF
#!/bin/bash
INPUT=\$(cat)
python3 ~/.claude/hooks/${PYTHON_SCRIPT} "\$INPUT" &
exit 0
EOF

# 3. Write Python script(s)
cat > "$HOOK_DIR/auto_title.py" << 'PYEOF'
#!/usr/bin/env python3
import json, os, sys, urllib.request, tempfile

def main():
    if len(sys.argv) < 2:
        return
    try:
        data = json.loads(sys.argv[1])
    except Exception:
        return

    session_id = data.get("session_id", "")
    transcript_path = data.get("transcript_path", "")
    prompt = data.get("prompt", "")[:500]

    if not session_id or not transcript_path:
        return

    session_dir = transcript_path.removesuffix(".jsonl")
    title_file = os.path.join(session_dir, "custom-title.json")

    if os.path.exists(title_file):
        return

    os.makedirs(session_dir, exist_ok=True)

    base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
    api_key = os.environ.get("ANTHROPIC_AUTH_TOKEN") or os.environ.get("ANTHROPIC_API_KEY", "")
    model = os.environ.get("ANTHROPIC_DEFAULT_HAIKU_MODEL", "claude-haiku-4-5-20251001")

    system = """你是一个会话标题生成器。根据用户的第一条消息，生成一个简短的会话标题。

格式：[type] 简短描述
type 从以下选择：
- feat     新功能开发、需求实现
- fix      bug 修复、问题排查
- test     测试、验证、回归
- plan     方案设计、架构规划
- refactor 重构、代码优化
- skill    工具/技能配置
- agent    自动化、Agent 任务
- docs     文档、说明
- chore    配置、环境、杂项

规则：
- 描述用中文，20字以内
- 只输出标题本身，不要解释
- 示例：[feat] 应用列表支持模板过滤"""

    payload = json.dumps({
        "model": model,
        "max_tokens": 30,
        "system": system,
        "messages": [{"role": "user", "content": prompt}]
    }).encode()

    req = urllib.request.Request(
        f"{base_url}/v1/messages",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
        title = result["content"][0]["text"].strip()
    except Exception:
        return

    if not title:
        return

    tmp = tempfile.NamedTemporaryFile(mode="w", dir=session_dir, prefix=".title.", delete=False)
    json.dump({"customTitle": title}, tmp)
    tmp.close()
    os.replace(tmp.name, title_file)

if __name__ == "__main__":
    main()
PYEOF

cat > "$HOOK_DIR/auto_title_simple.py" << 'PYEOF'
#!/usr/bin/env python3
import json, os, sys, re, tempfile

MAX_LEN = 30

def clean(text: str) -> str:
    text = text.strip()
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"[#*`>]+", "", text)
    return text[:MAX_LEN].rstrip()

def main():
    if len(sys.argv) < 2:
        return
    try:
        data = json.loads(sys.argv[1])
    except Exception:
        return

    transcript_path = data.get("transcript_path", "")
    prompt = data.get("prompt", "")

    if not transcript_path or not prompt:
        return

    session_dir = transcript_path.removesuffix(".jsonl")
    title_file = os.path.join(session_dir, "custom-title.json")

    if os.path.exists(title_file):
        return

    os.makedirs(session_dir, exist_ok=True)

    title = clean(prompt)
    if not title:
        return

    tmp = tempfile.NamedTemporaryFile(mode="w", dir=session_dir, prefix=".title.", delete=False)
    json.dump({"customTitle": title}, tmp)
    tmp.close()
    os.replace(tmp.name, title_file)

if __name__ == "__main__":
    main()
PYEOF

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
