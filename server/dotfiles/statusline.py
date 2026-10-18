#!/usr/bin/env python3
"""Claude Code status line: the model, and how many tokens the current context holds."""
import json
import sys

info = json.load(sys.stdin)
used = None
try:
    # The last response's usage is the current context; only the file's end is needed
    with open(info["transcript_path"], "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 500_000))
        for line in f.read().decode("utf-8", "ignore").splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            usage = (entry.get("message") or {}).get("usage") if isinstance(entry, dict) else None
            if isinstance(usage, dict) and not entry.get("isSidechain"):
                used = sum(usage.get(k, 0) for k in
                           ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
except (OSError, KeyError):
    pass
model = info.get("model", {}).get("display_name", "")
print(f"{model}  ctx {used / 1000:.0f}k" if used is not None else model)
