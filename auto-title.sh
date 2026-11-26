#!/bin/bash
# Auto-generate Claude Code session title on first user message.
# Install path: ~/.claude/hooks/auto-title.sh
# See: https://gist.github.com/... for full setup guide.
cat | python3 ~/.claude/hooks/auto_title.py &
exit 0
