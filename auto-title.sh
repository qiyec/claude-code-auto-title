#!/bin/bash
# Auto-generate Claude Code session title on first user message.
# Install path: ~/.claude/hooks/auto-title.sh
# Source: https://github.com/qiyec/claude-code-auto-title
cat | python3 ~/.claude/hooks/auto_title.py &
exit 0
