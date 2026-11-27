# Claude Code 会话自动命名：用 Hook 实现 AI 生成标题

[English](README.md)

Claude Code 目前不支持自动命名会话（GitHub issue [#38856](https://github.com/anthropics/claude-code/issues/38856) 仍处于 open 状态），每次新建会话都是默认的 "New Conversation"，翻历史记录时完全不知道每个会话在做什么。

## 效果预览

新建会话，发第一条消息，几秒后会话列表自动出现标题：

```
[feat] 应用列表支持模板类型过滤
[fix]  登录页 SSO 回调 404 排查
[research] AI4S 概念调研
[plan] 增强智能体架构方案设计
[setup] 本地开发环境 Python 版本配置
```

## 背景

这是个高频需求，社区在 GitHub 上提了多个相关 issue（[#38856](https://github.com/anthropics/claude-code/issues/38856)、[#41851](https://github.com/anthropics/claude-code/issues/41851)、[#47176](https://github.com/anthropics/claude-code/issues/47176)），均已被标记为重复关闭，但功能本身尚未实现。

社区开发者 `yupoet` 在 issue 讨论中找到了自实现的完整路径：

1. **标题存储机制已经存在**：向会话目录写入 `custom-title.json` 即可，`/resume` 和状态栏都会读取
2. **Hook 机制可以介入**：`UserPromptSubmit` Hook 在每条消息提交时触发，payload 包含 `session_id` 和 `transcript_path`
3. **只需要 ~350 tokens**：用 Haiku 生成标题，成本极低

## 原理

`UserPromptSubmit` 在每次用户提交消息时触发，stdin 收到如下 JSON payload：

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/you/.claude/projects/my-project/abc123.jsonl",
  "prompt": "用户输入的消息"
}
```

Claude Code 从以下路径读取自定义标题：

```
<transcript_path 去掉 .jsonl 后缀>/custom-title.json
{"customTitle": "[feat] 应用列表支持模板过滤"}
```

在第一条消息触发时写入这个文件，会话列表和状态栏就会立即显示对应标题。

## 前置条件

| 条件 | 说明 |
|---|---|
| 操作系统 | macOS 或 Linux（**Windows 暂不支持**，WSL / Git Bash 未经测试） |
| Claude Code | v2.x，CLI 或桌面版 |
| Python | 3.9+（macOS / Linux 已预装） |
| Anthropic API key | 仅 LLM 版需要，配置 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN` |
| curl | 一键安装命令需要（macOS / Linux 已预装） |

极简版（`--simple`）除 Python 和 Claude Code 外无额外依赖。

## 安装

**LLM 版**（生成 `[type]` 结构化标题，需要 Anthropic API key）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/install.sh)
```

**极简版**（截取首条消息，零成本，无需 API key）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/install.sh) --simple
```

**卸载：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/uninstall.sh)
```

手动安装步骤见 [手动安装](#手动安装)。

## 两种版本对比

| | LLM 版 | 极简版 |
|--|---|---|
| 标题格式 | `[feat] 应用列表支持模板过滤` | `帮我在应用列表页加一个按模板类` |
| Token 消耗 | ~350 tokens/session | 0 |
| 网络依赖 | 需要（调 Haiku API） | 无 |
| 生效延迟 | 3–8 秒 | 即时 |

## type 分类（LLM 版）

| type | 适用场景 |
|------|---------|
| `feat` | 功能开发、需求实现 |
| `fix` | bug 修复、问题排查、异常处理 |
| `test` | 测试编写、验证、回归 |
| `refactor` | 重构、代码优化、清理 |
| `docs` | 编写文档、注释、说明 |
| `research` | 技术调研、概念学习、信息查询 |
| `plan` | 方案设计、架构规划、技术选型 |
| `setup` | 环境配置、工具安装、依赖管理 |
| `ops` | 自动化脚本、部署、运维任务 |

## 自定义

修改 `~/.claude/hooks/auto_title.py` 的 `system` 变量，无需重启：

| 需求 | 修改方式 |
|------|---------|
| 改用英文标题 | 把"描述用中文"改为"描述用英文" |
| 增加 type 类型 | 在 system prompt 列表里添加 |
| 去掉 `[type]` 前缀 | 修改格式说明那一行 |
| 截取更多/更少上下文 | 修改 `[:500]` 的数字 |
| 换成其他模型 | 修改 `model` 变量或对应的环境变量 |

## 手动安装

**1. 创建 Hook 脚本**

将 [auto-title.sh](auto-title.sh) 和 [auto_title.py](auto_title.py) 复制到 `~/.claude/hooks/`：

```bash
chmod +x ~/.claude/hooks/auto-title.sh ~/.claude/hooks/auto_title.py
```

**2. 注册 Hook**

在 `~/.claude/settings.json` 顶层加入（注意与已有字段合并，不要覆盖）：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/auto-title.sh" }
        ]
      }
    ]
  }
}
```

**3. 验证**

```bash
T='{"session_id":"test-1","transcript_path":"/tmp/test-1.jsonl","prompt":"帮我排查登录页 SSO 回调 404 的问题"}'
echo "$T" | bash ~/.claude/hooks/auto-title.sh
sleep 6 && cat /tmp/test-1/custom-title.json
# → {"customTitle": "[fix] 排查登录页SSO回调404"}
rm -rf /tmp/test-1 /tmp/test-1.jsonl
```

## 注意事项

- **幂等**：检测到 `custom-title.json` 已存在直接跳过，不会覆盖 `/rename` 手动设置的标题
- **静默失败**：API 调用失败时脚本退出，不影响 Claude Code 正常使用
- **自定义 base URL**：自动读取 `ANTHROPIC_BASE_URL` 环境变量，无需额外配置
- **仅限本地 CLI 会话**：Hook 写入的标题不会同步到 desktop / mobile app（见 [#107094](https://github.com/anthropics/claude-code/issues/107094)）
- **依赖**：Python 3.9+，Claude Code v2.x

## 兼容性

| 环境 | 状态 |
|---|---|
| macOS / Linux — Claude Code CLI 或桌面版 | ✅ 支持 |
| Windows（原生 cmd / PowerShell） | ✗ 不支持 |
| Windows（WSL / Git Bash） | 未测试 |
| Claude.ai 网页版 | ✗ 无需（已原生支持自动命名） |
| Cursor / Windsurf 等其他编辑器 | ✗ 不适用 |

## 参考

- [Claude Code Hooks 文档](https://docs.anthropic.com/en/docs/claude-code/hooks)
- GitHub issue [#38856](https://github.com/anthropics/claude-code/issues/38856) — 自动命名功能请求
- GitHub issue [#47176](https://github.com/anthropics/claude-code/issues/47176) — 社区对实现路径的深度分析

## 许可证

MIT
