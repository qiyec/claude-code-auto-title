# claude-code-auto-title

Automatically name your [Claude Code](https://claude.ai/code) sessions using AI — no more "New Conversation".

[中文文档](README.zh.md)

## Demo

Send your first message in a new session, and the title appears in seconds:

```
[feat] Add template filter to app list
[fix]  Debug SSO callback 404
[test] Regression test for alert events
[plan] Design enhanced agent architecture
```

## Background

Claude Code doesn't support auto-naming sessions yet ([issue #38856](https://github.com/anthropics/claude-code/issues/38856)). This project hooks into the `UserPromptSubmit` event, calls the Haiku model in the background, and writes the generated title to Claude Code's local session storage — no UI changes, no process restart needed.

## How It Works

**Hook trigger**: `UserPromptSubmit` fires on every message. The payload includes `session_id` and `transcript_path`.

**Title storage**: Claude Code reads custom titles from:
```
<transcript_path without .jsonl>/custom-title.json
{"customTitle": "..."}
```

Writing this file on the first message is all it takes.

## Prerequisites

| Requirement | Details |
|---|---|
| OS | macOS or Linux (**Windows not supported**; WSL / Git Bash untested) |
| Claude Code | v2.x, CLI or Desktop |
| Python | 3.9+ (pre-installed on macOS/Linux) |
| Anthropic API key | LLM version only — set `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` in env or `~/.claude/settings.json` |
| curl | For one-liner install (pre-installed on macOS/Linux) |

The lite version (`--simple`) has no extra dependencies beyond Python and Claude Code.

## Installation

**Option A — LLM version** (structured `[type] title`, requires Anthropic API key):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/install.sh)
```

**Option B — Lite version** (truncates first message, zero cost, no API call):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/install.sh) --simple
```

Or install manually — see [Manual Installation](#manual-installation).

**Uninstall:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyec/claude-code-auto-title/main/uninstall.sh)
```

## Comparison

|  | LLM version | Lite version |
|--|---|---|
| Title format | `[feat] Add template filter` | `Add template filter to app li...` |
| Token cost | ~350 tokens/session | 0 |
| Network | Anthropic API | None |
| Latency | 3–8 s | Instant |

## Type Labels (LLM version)

| type | When |
|------|------|
| `feat` | Feature development & implementation |
| `fix` | Bug fix, debugging, error handling |
| `test` | Writing tests, validation, regression |
| `refactor` | Code refactoring & cleanup |
| `docs` | Writing documentation & comments |
| `research` | Tech research, concept learning, info lookup |
| `plan` | Architecture design & technical planning |
| `setup` | Environment config, tool install, dependencies |
| `ops` | Automation scripts, deployment, ops tasks |

## Customization

Edit `~/.claude/hooks/auto_title.py` — change the `system` prompt to adjust language, type labels, or title length. No restart needed.

## Manual Installation

**1. Create the hook scripts**

`~/.claude/hooks/auto-title.sh`:
```bash
#!/bin/bash
INPUT=$(cat)
python3 ~/.claude/hooks/auto_title.py "$INPUT" &
exit 0
```

`~/.claude/hooks/auto_title.py`: copy from [auto_title.py](auto_title.py)

```bash
chmod +x ~/.claude/hooks/auto-title.sh ~/.claude/hooks/auto_title.py
```

**2. Register the hook in `~/.claude/settings.json`**

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

**3. Verify**

```bash
T='{"session_id":"test","transcript_path":"/tmp/test.jsonl","prompt":"Debug the login SSO redirect issue"}'
echo "$T" | bash ~/.claude/hooks/auto-title.sh
sleep 6 && cat /tmp/test/custom-title.json
# → {"customTitle": "[fix] Debug SSO redirect"}
rm -rf /tmp/test /tmp/test.jsonl
```

## Notes

- **Idempotent**: skips if `custom-title.json` already exists; won't overwrite titles set via `/rename`
- **Silent failure**: if the API call fails, the hook exits quietly — no impact on normal usage
- **Custom base URL**: reads `ANTHROPIC_BASE_URL` automatically if set
- **Requires**: Python 3.9+, Claude Code 2.x

## Compatibility

| Environment | Status |
|---|---|
| macOS / Linux — Claude Code CLI or Desktop | ✅ Supported |
| Windows — cmd / PowerShell (native) | ✗ Not supported |
| Windows — WSL / Git Bash | Untested |
| Claude.ai web | ✗ Not needed (already has auto-title) |
| Cursor / Windsurf / other editors | ✗ Not applicable |

## References

- [Claude Code Hooks documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- GitHub issue [#38856](https://github.com/anthropics/claude-code/issues/38856) — Auto-generate conversation titles
- GitHub issue [#47176](https://github.com/anthropics/claude-code/issues/47176) — Community analysis of implementation path

## License

MIT
