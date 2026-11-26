# Claude Code 会话自动命名：用 Hook 实现 AI 生成标题

> **适用范围**：本文方案仅适用于 **Claude Code（CLI 及桌面版）**，依赖其专有的 Hook 系统和本地会话存储格式，不适用于 Cursor、Windsurf 等其他 AI 编辑器，也不需要用于已原生支持自动命名的 Claude.ai 网页版。

Claude Code 目前不支持自动命名会话（GitHub issue [#38856](https://github.com/anthropics/claude-code/issues/38856) 仍处于 open 状态），每次新建会话都是默认的 "New Conversation"，翻历史记录时完全不知道每个会话在做什么。

这篇文章介绍如何用 `UserPromptSubmit` Hook + Haiku API，在第一条消息发出后自动生成结构化标题，全程后台运行，不影响任何操作体验。

## 效果预览

新建会话，发第一条消息，几秒后会话列表自动出现标题：

```
[feat] 应用列表支持模板类型过滤
[fix]  登录页 SSO 回调 404 排查
[test] 告警事件覆盖回归测试
[plan] 增强智能体架构方案设计
[chore] 本地开发环境 Python 版本配置
```

## 背景：为什么官方还没支持

这是个高频需求，社区在 GitHub 上提了多个相关 issue（[#38856](https://github.com/anthropics/claude-code/issues/38856)、[#41851](https://github.com/anthropics/claude-code/issues/41851)、[#47176](https://github.com/anthropics/claude-code/issues/47176)），均已被标记为重复关闭，但功能本身尚未实现。

社区开发者 `yupoet` 在 issue 讨论中做了深入分析，找到了自实现的完整路径：

1. **标题存储机制已经存在**：向会话目录写入 `custom-title.json` 即可，`/resume` 和状态栏都会读取
2. **Hook 机制可以介入**：`UserPromptSubmit` Hook 在每条消息提交前触发，payload 包含 `session_id` 和 `transcript_path`
3. **只需要 ~350 tokens**：用 Haiku 生成标题，成本极低

## 原理

### Hook 触发时机

Claude Code 的 Hook 系统允许在特定生命周期事件上挂载 shell 命令。`UserPromptSubmit` 在每次用户提交消息时触发，stdin 收到如下 JSON payload：

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/you/.claude/projects/my-project/abc123.jsonl",
  "prompt": "用户输入的第一条消息内容"
}
```

### 标题的存储位置

Claude Code 从以下路径读取自定义标题：

```
<transcript_path 去掉 .jsonl 后缀>/custom-title.json
```

例如 transcript 路径是 `.../abc123.jsonl`，对应的标题文件就是 `.../abc123/custom-title.json`，内容格式：

```json
{ "customTitle": "[feat] 应用列表支持模板过滤" }
```

只要在第一条消息触发时写入这个文件，会话列表和顶部状态栏就会立即显示对应标题。

## 一键安装

如果不想手动操作，可以直接运行安装脚本（自动创建脚本文件并注册 Hook，不会覆盖 settings.json 里的其他配置）：

```bash
# LLM 版（生成 [type] 结构化标题，需要 Anthropic API key）
bash <(curl -fsSL https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa/raw/install.sh)

# 极简版（截取首条消息，零成本）
bash <(curl -fsSL https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa/raw/install.sh) --simple
```

以下是手动安装步骤（方便了解实现细节或按需调整）。

## 实现步骤

### 第一步：创建 Hook 脚本

**`~/.claude/hooks/auto-title.sh`** — 入口脚本，读取 stdin 并后台调用 Python：

```bash
#!/bin/bash
INPUT=$(cat)
python3 ~/.claude/hooks/auto_title.py "$INPUT" &
exit 0
```

立即返回 0，后台执行，不阻塞消息提交。

**`~/.claude/hooks/auto_title.py`** — 核心逻辑：

```python
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
    prompt = data.get("prompt", "")[:500]  # 只取前 500 字

    if not session_id or not transcript_path:
        return

    session_dir = transcript_path.removesuffix(".jsonl")
    title_file = os.path.join(session_dir, "custom-title.json")

    # 已有标题则跳过，只处理第一条消息
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
        return  # 静默失败，不影响正常使用

    if not title:
        return

    # 原子写入，避免写一半被读到
    tmp = tempfile.NamedTemporaryFile(mode="w", dir=session_dir, prefix=".title.", delete=False)
    json.dump({"customTitle": title}, tmp)
    tmp.close()
    os.replace(tmp.name, title_file)

if __name__ == "__main__":
    main()
```

赋予执行权限：

```bash
chmod +x ~/.claude/hooks/auto-title.sh ~/.claude/hooks/auto_title.py
```

### 第二步：注册 Hook

在 `~/.claude/settings.json` 顶层加入 `hooks` 字段：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-title.sh"
          }
        ]
      }
    ]
  }
}
```

如果 `settings.json` 里已有其他字段，注意合并而不是覆盖。

### 第三步：验证

不需要重启 Claude Code，直接运行命令验证脚本是否正常：

```bash
TEST='{"session_id":"test-1","transcript_path":"/tmp/test-1.jsonl","prompt":"帮我排查登录页 SSO 回调 404 的问题"}'
echo "$TEST" | bash ~/.claude/hooks/auto-title.sh
sleep 6
cat /tmp/test-1/custom-title.json
# → {"customTitle": "[fix] SSO回调404排查"}

# 清理测试文件
rm -rf /tmp/test-1 /tmp/test-1.jsonl
```

之后新开一个 Claude Code 会话，发第一条消息，几秒后刷新会话列表即可看到自动生成的标题。

## 自定义命名规范

所有规则都在 `~/.claude/hooks/auto_title.py` 的 `system` 变量里，直接修改即可，无需重启：

| 需求 | 修改方式 |
|------|---------|
| 改用英文标题 | 把"描述用中文"改为"描述用英文" |
| 增加 type 类型 | 在列表里加 `review`、`debug` 等 |
| 去掉 `[type]` 前缀 | 修改格式说明那一行 |
| 截取更多/更少上下文 | 修改 `[:500]` 的数字 |
| 换成其他模型 | 修改 `model` 变量或对应的环境变量 |

## 注意事项

**Token 消耗**：每次新 session 约 ~350 tokens（Haiku），官方定价约 $0.0003/次，每天 20 个 session 也不到 $0.01。

**失败处理**：API 调用超时或失败时脚本静默退出，不影响 Claude Code 正常使用，会话只是没有自动标题，和之前一样。

**仅对新 session 生效**：脚本检测到 `custom-title.json` 已存在就直接跳过，不会覆盖手动用 `/rename` 设置过的标题，也不会在同一 session 里重复调用 API。

**使用自定义 base URL**：如果配置了 `ANTHROPIC_BASE_URL`（指向代理或第三方服务），脚本会自动读取该环境变量，无需额外配置。

## 参考

- [Claude Code Hooks 文档](https://docs.anthropic.com/en/docs/claude-code/hooks)
- GitHub issue [#38856](https://github.com/anthropics/claude-code/issues/38856) — Auto-generate conversation titles
- GitHub issue [#47176](https://github.com/anthropics/claude-code/issues/47176) — 社区对实现路径的深度分析
