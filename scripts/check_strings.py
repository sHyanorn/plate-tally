"""Fail when a repository file contains a forbidden string.

    python3 scripts/check_strings.py [--root DIR]

Exit 0: clean. Exit 1: findings. Exit 2: the check could not run.

Each pattern is written as a character class or an escape, so this file never
contains the text it looks for and passes its own scan.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import NamedTuple

ALLOWLIST = "scripts/string_allowlist.txt"
# Recorded model replies are data and stay as received (protocol, What is published).
EXEMPT_DIRS = ("eval/raw/",)
SKIPPED_DIRS = frozenset(
    {
        ".git",
        ".cache",
        ".venv",
        "__pycache__",
        ".pytest_cache",
        ".ruff_cache",
        ".build",
        "node_modules",
    }
)
BINARY_PROBE = 8192
EXCERPT_WIDTH = 100


class Rule(NamedTuple):
    name: str
    pattern: re.Pattern[str]


def rule(name: str, pattern: str) -> Rule:
    return Rule(name, re.compile(pattern, re.IGNORECASE))


API_KEY = rule("api-key", r"sk-ant-[A-Za-z0-9_-]{20,}")
RULES = (
    rule("vendor-name", r"a[p][p]le"),
    rule("dash", r"[\U00002013\U00002014]"),
    API_KEY,
)
# A key must never reach a record, so exempt files are still scanned for it.
EXEMPT_RULES = (API_KEY,)


class CheckError(Exception):
    """The check could not run to the end."""


class Hit(NamedTuple):
    line_no: int
    line: str
    rule: str
    excerpt: str


class Finding(NamedTuple):
    where: str
    rule: str
    excerpt: str

    def render(self) -> str:
        return f"{self.where}: {self.rule}: {self.excerpt}"


def hide_key(match: re.Match[str]) -> str:
    return match.group()[:7] + "..."


def hits(text: str, rules: tuple[Rule, ...] = RULES) -> Iterator[Hit]:
    """One hit per line and rule. Keys are cut short so a log never holds one."""
    for line_no, line in enumerate(text.split("\n"), 1):
        shown = API_KEY.pattern.sub(hide_key, line).strip()
        if len(shown) > EXCERPT_WIDTH:
            shown = shown[:EXCERPT_WIDTH] + "..."
        for r in rules:
            if r.pattern.search(line):
                yield Hit(line_no, line, r.name, shown)


def git(root: Path, *args: str) -> bytes:
    command = ["git", *args]
    try:
        done = subprocess.run(command, cwd=root, capture_output=True, check=False)
    except OSError as exc:
        raise CheckError(f"cannot run git: {exc}") from exc
    if done.returncode != 0:
        detail = done.stderr.decode(errors="replace").strip()
        raise CheckError(f"{' '.join(command)} exited with {done.returncode}: {detail}")
    return done.stdout


def unlistable(exc: OSError) -> None:
    raise CheckError(f"cannot list {exc.filename}: {exc.strerror}") from exc


def list_files(root: Path) -> list[str]:
    """Relative paths with forward slashes, sorted."""
    if (root / ".git").exists():
        out = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
        names = {os.fsdecode(name) for name in out.split(b"\0") if name}
    else:
        names = set()
        for folder, dirs, files in os.walk(root, onerror=unlistable):
            dirs[:] = [d for d in dirs if d not in SKIPPED_DIRS]
            for name in files:
                names.add((Path(folder) / name).relative_to(root).as_posix())
    return sorted(names)


def read_text(root: Path, name: str) -> str | None:
    """File text, or None for a binary file (a NUL byte in the first 8192 bytes)."""
    try:
        data = (root / name).read_bytes()
    except OSError as exc:
        raise CheckError(f"cannot read {name}: {exc.strerror or exc}") from exc
    if b"\0" in data[:BINARY_PROBE]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        saw = f"byte {data[exc.start]:#04x} at offset {exc.start}"
        raise CheckError(
            f"{name} is not UTF-8: expected UTF-8 text, saw {saw}"
        ) from exc


def load_allowlist(root: Path) -> set[tuple[str, str]]:
    if not (root / ALLOWLIST).is_file():
        return set()
    text = read_text(root, ALLOWLIST)
    if text is None:
        raise CheckError(f"{ALLOWLIST} contains a NUL byte; expected a text file")
    entries = set()
    for line_no, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        name, tab, content = line.partition("\t")
        if not tab:
            raise CheckError(
                f"{ALLOWLIST}:{line_no}: expected path<TAB>line text, saw {line!r}"
            )
        entries.add((name, content))
    return entries


def check_exempt_dirs(exempt_dirs: tuple[str, ...]) -> None:
    """An empty entry matches every file and one without a trailing slash also matches
    sibling directories that share its prefix, so both are refused."""
    for entry in exempt_dirs:
        parts = Path(entry).parts
        if (
            not entry.endswith("/")
            or entry.startswith("/")
            or ".." in parts
            or any(c in entry for c in "*?[")
        ):
            raise CheckError(
                f"exempt entry {entry!r}: expected a relative directory path that "
                "ends in '/' and has no '..' or wildcard"
            )


def scan_files(
    root: Path, exempt_dirs: tuple[str, ...] = EXEMPT_DIRS
) -> tuple[int, list[Finding], int, int]:
    """Returns (files scanned, findings, findings suppressed by the allowlist, files
    under an exempt directory). Exempt files count as scanned."""
    check_exempt_dirs(exempt_dirs)
    allowed = load_allowlist(root)
    findings: list[Finding] = []
    scanned = suppressed = exempt = 0
    for name in list_files(root):
        # A tracked file deleted from the work tree, or a submodule, is not a file here.
        if not (root / name).is_file():
            continue
        text = read_text(root, name)
        if text is None:
            continue
        scanned += 1
        is_exempt = name.startswith(exempt_dirs)
        if is_exempt:
            exempt += 1
        for hit in hits(text, EXEMPT_RULES if is_exempt else RULES):
            # An entry holds the string it allows, so only comments are checked there.
            if name == ALLOWLIST and not hit.line.startswith("#"):
                continue
            if (name, hit.line) in allowed:
                suppressed += 1
            else:
                findings.append(Finding(f"{name}:{hit.line_no}", hit.rule, hit.excerpt))
    return scanned, findings, suppressed, exempt


def summary(files: int, findings: list[Finding], suppressed: int, exempt: int) -> str:
    by_rule = Counter(f.rule for f in findings)
    detail = ", ".join(f"{name} {n}" for name, n in sorted(by_rule.items()))
    count = f"{len(findings)} ({detail})" if detail else "0"
    return f"files {files}, findings {count}, allowed {suppressed}, exempt {exempt}"


def run(root: Path) -> int:
    if not root.is_dir():
        raise CheckError(f"--root {root} is not a directory")
    files, findings, suppressed, exempt = scan_files(root)
    for finding in findings:
        print(finding.render())
    print(summary(files, findings, suppressed, exempt))
    return 1 if findings else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Reject forbidden strings in repository files."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="directory to scan (default: the parent of scripts/)",
    )
    args = parser.parse_args(argv)
    try:
        return run(args.root.resolve())
    except CheckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
