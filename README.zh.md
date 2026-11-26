# Claude Code 会话自动命名：用 Hook 实现 AI 生成标题

[English](README.md)

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

## 前置条件

| 条件 | 说明 |
|---|---|
| Claude Code | v2.x，CLI 或桌面版 |
| Python | 3.9+（macOS/Linux 已预装） |
| Anthropic API key | 仅 LLM 版需要，在环境变量或 `~/.claude/settings.json` 中配置 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN` |
| curl | 一键安装命令需要（macOS/Linux 已预装） |

极简版（`--simple`）除 Python 和 Claude Code 外无额外依赖。

## 一键安装

如果不想手动操作，可以直接运行安装脚本（自动创建脚本文件并注册 Hook，不会覆盖 settings.json 里的其他配置）：

```bash
# LLM 版（生成 [type] 结构化标题，需要 Anthropic API key）
bash <(curl -fsSL https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa/raw/install.sh)

# 极简版（截取首条消息，零成本）
bash <(curl -fsSL https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa/raw/install.sh) --simple
```

**卸载：**

```bash
bash <(curl -fsSL https://gist.github.com/qiyec/71e742075a11493a4c2c68a9bf88daaa/raw/uninstall.sh)
```

以下是手动安装步骤（方便了解实现细节或按需调整）。

## 实现步骤

### 第一步：创建 Hook 脚本

将 [auto-title.sh](auto-title.sh) 和 [auto_title.py](auto_title.py) 复制到 `~/.claude/hooks/`，然后赋予执行权限：

```bash
chmod +x ~/.claude/hooks/auto-title.sh ~/.claude/hooks/auto_title.py
```

`auto-title.sh` 负责接收 Hook payload 并在后台调用 Python 脚本，立即返回 0 不阻塞消息提交；`auto_title.py` 是核心逻辑，调用 Haiku API 生成标题并写入会话目录。

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

**type 分类（9 种）：**

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

**其他自定义：**

| 需求 | 修改方式 |
|------|---------|
| 改用英文标题 | 把"描述用中文"改为"描述用英文" |
| 增加 type 类型 | 在 system prompt 列表里添加 |
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
