#!/usr/bin/env bash
# Docs check (factory ADR 0015): every relative link and #anchor in the factory's Markdown resolves. Run from the
# repo root; pass files to check only those.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  set -- README.md SECURITY.md docs/*.md docs/factory-adr/*.md plugins/java-pipeline/README.md \
    plugins/java-pipeline/CHANGELOG.md parents/factory-parent/CHANGELOG.md
fi
python3 -I - "$@" <<'PY'
import os, re, sys

def slug(heading):
    s = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return s.replace(" ", "-")

def anchors(path):
    found, fenced = set(), False
    for line in open(path, encoding="utf-8"):
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("#"):
            found.add(slug(line.lstrip("#")))
    return found

link = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
bad = 0
for path in sys.argv[1:]:
    fenced = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        for target in link.findall(re.sub(r"`[^`]*`", "", line)):
            if re.match(r"^[a-z]+:", target):
                continue  # http(s), mailto: not checked offline
            file_part, _, anchor = target.partition("#")
            dest = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
            if not os.path.exists(dest):
                print(f"FAIL: {path}:{n}: {target}: {dest} does not exist")
                bad = 1
            elif anchor and dest.endswith(".md") and anchor not in anchors(dest):
                print(f"FAIL: {path}:{n}: {target}: no heading '#{anchor}' in {dest}")
                bad = 1
print("docs links: OK" if not bad else "docs links: broken links above")
sys.exit(bad)
PY
