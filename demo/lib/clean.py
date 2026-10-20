#!/usr/bin/env python3
"""Turn a raw pty log from console.exp into the text a person saw on screen.

  clean.py <raw-log>   (prints to stdout)
"""
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
text = text.replace("\r", "")

# IEx's line editor echoes the typed line(s), then moves the cursor up n lines
# (ESC[A per line), clears (ESC[J) and redraws them. Keep only the redrawn copy.
def drop_redrawn(text):
    out = ""
    pos = 0
    for m in re.finditer(r"((?:\x1b\[A)+)\x1b\[J", text):
        out += text[pos:m.start()]
        n = m.group(1).count("\x1b[A")
        lines = out.split("\n")
        # `out` ends with "\n", so the last element is "" (the cursor line).
        out = "\n".join(lines[: len(lines) - 1 - n] + [""])
        pos = m.end()
    return out + text[pos:]

text = drop_redrawn(text)
# Any other escape sequences (cursor moves, colours).
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)

# Shell commands run "in another terminal" between two IEx inputs: move them
# before the prompt that was already on screen, and show them as a separate
# block.
def run_block(m):
    body = m.group(1).strip("\n")
    return f"\n# --- in another terminal ---\n{body}\n# ---------------------------\n\n"

# The prompt on screen before the block is drawn again by the line editor when
# the next line is typed, so drop the stale copy.
text = re.sub(r"[^\n]*> \n@@RUN@@ (.*?)\n@@END@@\n", run_block, text, flags=re.S)

lines = text.split("\n")
# Drop the trailing empty prompt left when the session closed.
while lines and (lines[-1].strip() == "" or re.fullmatch(r"\S*> ?", lines[-1])):
    lines.pop()
print("\n".join(l.rstrip() for l in lines))
