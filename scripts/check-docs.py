"""Fail if a document or code comment points at a path or anchor that doesn't exist.

    python3 scripts/check-docs.py

Checks Markdown links and their #anchors, backticked repository paths, and
docs/ paths mentioned outside docs/. External URLs aren't fetched. The AI usage
logs are records: their links are checked, but the paths they mention in passing
aren't. Moving the implementation plan twice left 25 broken links, which is why
this exists. Used by `make docs-check`.
"""

import os
import re
import subprocess
import sys

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)")
FENCE = re.compile(r"^\s*```.*?^\s*```\s*$", re.M | re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*$", re.M)
TOP_LEVEL = r"(?:backup|db|deploy|docs|frontend|infra|scripts|services|\.github)"
BACKTICKED = re.compile(rf"`({TOP_LEVEL}/[^`\s*<>{{}}]+)`")
DOCS_PATH = re.compile(r"\bdocs/[\w./#-]*\w")
RECORDS = "docs/ai_usage/"
# Generated files: nothing here is written by hand.
SKIP_COMMENT_SCAN = (".lock", "package-lock.json", ".gitignore")


def tracked_files():
    command = ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    output = subprocess.check_output(command, text=True)
    return [path for path in output.split("\0") if path and os.path.exists(path)]


def is_ignored(path):
    return subprocess.run(["git", "check-ignore", "-q", path]).returncode == 0


def slug(heading):
    """GitHub's anchor for a heading."""
    text = re.sub(r"[`*]", "", heading.strip().lower())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return re.sub(r"[^\w\- ]", "", text).replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        found, seen = set(), {}
        with open(path, encoding="utf-8") as f:
            for heading in HEADING.findall(FENCE.sub("", f.read())):
                base = slug(heading)
                count = seen.get(base, 0)
                seen[base] = count + 1
                found.add(f"{base}-{count}" if count else base)
        cache[path] = found
    return cache[path]


def main():
    files = tracked_files()
    directories = {os.path.dirname(path) for path in files}
    for path in list(directories):
        while path:
            path = os.path.dirname(path)
            directories.add(path)
    known = set(files) | directories
    problems = []

    def check(source, target, label):
        path, _, anchor = target.partition("#")
        path = os.path.normpath(path).rstrip("/")
        if path not in known and not is_ignored(path):
            problems.append(f"{source}: {label} {target}: no such path")
        elif anchor and path.endswith(".md") and anchor not in anchors(path):
            problems.append(f"{source}: {label} {target}: no such heading")

    for source in files:
        if source.endswith(".md"):
            with open(source, encoding="utf-8") as f:
                text = f.read()
            prose = FENCE.sub("", text)
            for target in LINK.findall(INLINE_CODE.sub("", prose)):
                if re.match(r"[a-z]+:", target):
                    continue
                if target.startswith("#"):
                    check(source, source + target, "link")
                else:
                    check(source, os.path.join(os.path.dirname(source), target), "link")
            if not source.startswith(RECORDS):
                for target in BACKTICKED.findall(prose):
                    check(source, target.rstrip("/.,:"), "path")
        elif not source.startswith("docs/") and not source.endswith(SKIP_COMMENT_SCAN):
            try:
                with open(source, encoding="utf-8") as f:
                    text = f.read()
            except UnicodeDecodeError:
                continue
            for target in DOCS_PATH.findall(text):
                check(source, target, "path")

    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("All document paths and links resolve.")


main()
