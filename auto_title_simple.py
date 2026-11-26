#!/usr/bin/env python3
# Lite version: no API call, no cost.
# Derives title by cleaning up the first user message (max 30 chars).
# Install path: ~/.claude/hooks/auto_title_simple.py
import json, os, sys, re, tempfile

MAX_LEN = 30

def clean(text: str) -> str:
    text = text.strip()
    text = re.sub(r"\s+", " ", text)   # collapse whitespace / newlines
    text = re.sub(r"[#*`>]+", "", text) # strip common markdown symbols
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
