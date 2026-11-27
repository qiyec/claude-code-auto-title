#!/usr/bin/env python3
# Auto-generate Claude Code session title on first user message.
# Install path: ~/.claude/hooks/auto_title.py
# Requires Python 3.9+ (stdlib only, no extra dependencies).
import json
import os
import sys
import urllib.request
import tempfile

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    session_id = data.get("session_id", "")
    transcript_path = data.get("transcript_path", "")
    prompt = data.get("prompt", "").strip()[:500]

    # 空消息（如纯图片）跳过
    if not session_id or not transcript_path or len(prompt) < 5:
        return

    session_dir = transcript_path.removesuffix(".jsonl")
    title_file = os.path.join(session_dir, "custom-title.json")

    if os.path.exists(title_file):
        return

    os.makedirs(session_dir, exist_ok=True)

    base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
    api_key = os.environ.get("ANTHROPIC_AUTH_TOKEN") or os.environ.get("ANTHROPIC_API_KEY", "")
    model = os.environ.get("ANTHROPIC_DEFAULT_HAIKU_MODEL", "claude-haiku-4-5-20251001")

    system = (
        "你是会话标题生成器。根据用户消息，输出一行标题，格式严格为：[type] 简短描述\n\n"
        "type 只能是以下之一：feat / fix / test / refactor / docs / research / plan / setup / ops\n\n"
        "- feat     功能开发、需求实现\n"
        "- fix      bug 修复、问题排查、异常处理\n"
        "- test     测试编写、验证、回归\n"
        "- refactor 重构、代码优化、清理\n"
        "- docs     编写文档、注释、说明\n"
        "- research 技术调研、概念学习、信息查询\n"
        "- plan     方案设计、架构规划、技术选型\n"
        "- setup    环境配置、工具安装、依赖管理\n"
        "- ops      自动化脚本、部署、运维任务\n\n"
        "描述用中文，20字以内。\n"
        "只输出标题这一行，不要输出任何其他内容，不要解释，不要换行。\n"
        "示例输出：[feat] 应用列表支持模板过滤"
    )

    payload = json.dumps({
        "model": model,
        "max_tokens": 50,
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
        # 只取第一行，防止 LLM 多输出内容混进标题
        title = result["content"][0]["text"].strip().splitlines()[0].strip()
    except Exception:
        return

    if not title:
        return

    tmp = tempfile.NamedTemporaryFile(
        mode="w", dir=session_dir, prefix=".title.", delete=False
    )
    json.dump({"customTitle": title}, tmp)
    tmp.close()
    os.replace(tmp.name, title_file)


if __name__ == "__main__":
    main()
