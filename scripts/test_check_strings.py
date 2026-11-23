"""Tests for check_strings. Forbidden strings are built at run time, so this file
passes the scan it tests."""

from __future__ import annotations

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_strings

SCRIPTS = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS.parent

VENDOR = "app" + "le"
EN_DASH = chr(0x2013)
EM_DASH = chr(0x2014)
KEY = "sk-ant-" + "a1_-" * 5


def flagged_files(output: str) -> list[str]:
    return [
        line.split(":")[0] for line in output.splitlines() if ": vendor-name: " in line
    ]


class TempTree(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def write(self, name: str, content: str | bytes) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")

    def check(self, *args: str, root: Path | None = None) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = check_strings.main(["--root", str(root or self.root), *args])
        return code, out.getvalue(), err.getvalue()

    def git(self, *args: str) -> None:
        subprocess.run(
            ["git", *args], cwd=self.root, check=True, capture_output=True, text=True
        )


class FileRules(TempTree):
    def test_clean_tree_passes(self) -> None:
        self.write("a.txt", "plain text\nsecond line\n")
        self.write("sub/b.py", "print('hello')\n")
        code, out, err = self.check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertEqual(out.strip(), "files 2, findings 0, allowed 0, exempt 0")

    def test_each_rule_triggers_with_path_line_rule_excerpt(self) -> None:
        cases = {
            "vendor-name": f"I like {VENDOR} pie",
            "dash": f"a {EN_DASH} b",
            "api-key": f"token {KEY}",
        }
        for rule, line in cases.items():
            with self.subTest(rule=rule):
                self.write("sub/f.txt", f"ok\n{line}\n")
                code, out, _ = self.check()
                self.assertEqual(code, 1)
                first = out.splitlines()[0]
                self.assertTrue(first.startswith(f"sub/f.txt:2: {rule}: "), first)
                self.assertIn(f"findings 1 ({rule} 1)", out)

    def test_both_dashes(self) -> None:
        for dash in (EN_DASH, EM_DASH):
            with self.subTest(dash=hex(ord(dash))):
                self.write("f.txt", dash + "\n")
                code, out, _ = self.check()
                self.assertEqual(code, 1)
                self.assertIn("f.txt:1: dash:", out)

    def test_case_and_in_word_variants(self) -> None:
        variants = (
            VENDOR.upper(),
            VENDOR.title(),
            "".join(c.upper() if i % 2 else c for i, c in enumerate(VENDOR)),
            "pine" + VENDOR,
            VENDOR.title() + "sauce",
            KEY.upper(),
        )
        for text in variants:
            with self.subTest(text=text):
                self.write("f.txt", f"x {text} y\n")
                code, _, _ = self.check()
                self.assertEqual(code, 1)

    def test_key_needs_twenty_characters_and_is_not_printed_in_full(self) -> None:
        self.write("short.txt", "sk-ant-" + "a" * 19 + "\n")
        self.assertEqual(self.check()[0], 0)
        self.write("long.txt", f"key = {KEY}\n")
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertNotIn(KEY[:20], out)
        self.assertIn("sk-ant-...", out)

    def test_binary_file_is_skipped(self) -> None:
        self.write("blob.bin", b"\x00\x01" + VENDOR.encode() + b"\xff\xfe")
        code, out, _ = self.check()
        self.assertEqual(code, 0)
        self.assertIn("files 0,", out)

    def test_undecodable_text_file_exits_2_and_names_the_file(self) -> None:
        self.write("latin.txt", b"caf\xe9\n")
        code, out, err = self.check()
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("latin.txt is not UTF-8", err)

    def test_missing_root_exits_2(self) -> None:
        code, _, err = self.check(root=self.root / "absent")
        self.assertEqual(code, 2)
        self.assertIn("is not a directory", err)


class Allowlist(TempTree):
    def entry(self, name: str, line: str) -> str:
        return f"{name}\t{line}\n"

    def test_suppresses_only_the_exact_path_and_line(self) -> None:
        allowed = f"allowed {VENDOR}"
        self.write("a.txt", f"{allowed}\nother {VENDOR}\n")
        self.write("b.txt", f"{allowed}\n")
        self.write(
            "scripts/string_allowlist.txt",
            "# comment\n\n" + self.entry("a.txt", allowed),
        )
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        findings = [line for line in out.splitlines() if ": vendor-name:" in line]
        self.assertEqual(len(findings), 2)
        self.assertTrue(findings[0].startswith("a.txt:2:"))
        self.assertTrue(findings[1].startswith("b.txt:1:"))
        self.assertIn("allowed 1", out)

    def test_whole_line_must_match(self) -> None:
        self.write("a.txt", f"  allowed {VENDOR}\n")
        self.write(
            "scripts/string_allowlist.txt", self.entry("a.txt", f"allowed {VENDOR}")
        )
        self.assertEqual(self.check()[0], 1)

    def test_every_listed_line_is_suppressed(self) -> None:
        line = f"allowed {VENDOR}"
        self.write("a.txt", f"{line}\n{line}\n")
        self.write("scripts/string_allowlist.txt", self.entry("a.txt", line))
        code, out, _ = self.check()
        self.assertEqual(code, 0)
        self.assertIn("allowed 2", out)

    def test_entries_are_not_findings_but_comments_in_the_file_are(self) -> None:
        self.write("a.txt", f"x {VENDOR}\n")
        self.write(
            "scripts/string_allowlist.txt",
            f"# {VENDOR}\n" + self.entry("a.txt", f"x {VENDOR}"),
        )
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertEqual(flagged_files(out), ["scripts/string_allowlist.txt"])
        self.assertIn(":1: vendor-name:", out)

    def test_entry_without_tab_exits_2(self) -> None:
        self.write("scripts/string_allowlist.txt", "a.txt no tab here\n")
        code, _, err = self.check()
        self.assertEqual(code, 2)
        self.assertIn("string_allowlist.txt:1: expected path<TAB>line text", err)


class Exempt(TempTree):
    def test_the_list_names_only_the_recorded_replies(self) -> None:
        self.assertEqual(check_strings.EXEMPT_DIRS, ("eval/raw/",))

    def test_hits_in_an_exempt_directory_are_not_findings(self) -> None:
        self.write("eval/raw/m/p1/d.json", f"x {VENDOR}\nb {EM_DASH}\n")
        code, out, _ = self.check()
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "files 1, findings 0, allowed 0, exempt 1")

    def test_exempt_files_are_counted_apart_from_the_others(self) -> None:
        self.write("eval/raw/a.json", "{}\n")
        self.write("eval/raw/m/b.json", "{}\n")
        self.write("c.txt", "plain\n")
        _, out, _ = self.check()
        self.assertEqual(out.strip(), "files 3, findings 0, allowed 0, exempt 2")

    def test_the_same_text_elsewhere_is_still_a_finding(self) -> None:
        # Only the path decides: a sibling, a shared prefix or a deeper copy is no match.
        elsewhere = ("eval/x.json", "eval/raw_old/x.json", "raw/x.json")
        elsewhere += ("sub/eval/raw/x.json",)
        for name in elsewhere:
            self.write(name, f"x {VENDOR}\n")
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertEqual(flagged_files(out), sorted(elsewhere))
        self.assertIn("exempt 0", out)

    def test_a_key_in_an_exempt_directory_is_a_finding(self) -> None:
        self.write("eval/raw/m/p1/d.json", f"token {KEY}\n")
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertIn("eval/raw/m/p1/d.json:1: api-key: ", out)
        self.assertIn("exempt 1", out)

    def test_a_loose_entry_is_refused(self) -> None:
        loose = ("", "/", "eval/raw", "/eval/raw/", "../raw/", "eval/*/", "eval/ra[w]/")
        for entry in loose:
            with self.subTest(entry=entry), self.assertRaises(check_strings.CheckError):
                check_strings.scan_files(self.root, (entry,))


class FileList(TempTree):
    def test_ignored_directories_are_skipped_without_git(self) -> None:
        bad = f"{VENDOR}\n"
        skipped = (".cache", ".venv", "__pycache__", ".pytest_cache")
        skipped += (".ruff_cache", ".build", "node_modules")
        for folder in skipped:
            self.write(f"{folder}/f.txt", bad)
            self.write(f"sub/{folder}/f.txt", bad)
        # A .git directory at the root would switch to the git file list.
        self.write("sub/.git/f.txt", bad)
        self.write("cache/f.txt", bad)
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertEqual(flagged_files(out), ["cache/f.txt"])

    def test_directory_that_cannot_be_listed_exits_2(self) -> None:
        (self.root / "locked").mkdir()
        scandir = os.scandir

        def fake_scandir(path: str) -> object:
            if Path(path).name == "locked":
                raise PermissionError(13, "Permission denied", str(path))
            return scandir(path)

        with mock.patch("os.scandir", fake_scandir):
            code, _, err = self.check()
        self.assertEqual(code, 2)
        self.assertIn("cannot list", err)
        self.assertIn("locked", err)

    def test_git_root_uses_the_git_file_list(self) -> None:
        self.git("init", "-q")
        self.write(".gitignore", "ignored.txt\n")
        self.write("ignored.txt", f"{VENDOR}\n")
        self.write(".cache/tracked.txt", f"{VENDOR}\n")
        self.write("untracked.txt", f"{VENDOR}\n")
        self.write("clean.txt", "fine\n")
        self.git("add", ".gitignore", "clean.txt")
        self.git("add", "-f", ".cache/tracked.txt")
        code, out, _ = self.check()
        self.assertEqual(code, 1)
        self.assertEqual(flagged_files(out), [".cache/tracked.txt", "untracked.txt"])

    def test_file_deleted_from_work_tree_is_not_an_error(self) -> None:
        self.git("init", "-q")
        self.write("gone.txt", "text\n")
        self.git("add", "gone.txt")
        (self.root / "gone.txt").unlink()
        code, out, _ = self.check()
        self.assertEqual(code, 0)
        self.assertIn("files 0,", out)


class CommandLine(TempTree):
    def test_default_root_is_the_parent_of_scripts(self) -> None:
        (self.root / "scripts").mkdir()
        shutil.copy(SCRIPTS / "check_strings.py", self.root / "scripts")
        self.write("bad.txt", f"{VENDOR}\n")
        script = self.root / "scripts" / "check_strings.py"
        done = subprocess.run(
            [sys.executable, str(script)], capture_output=True, text=True, check=False
        )
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("bad.txt:1: vendor-name: ", done.stdout)
        # The copied script is part of the tree and must be clean.
        self.assertEqual(len(done.stdout.splitlines()), 2, done.stdout)


class RepositoryRoot(unittest.TestCase):
    @unittest.skipUnless(
        (REPO_ROOT / "docs").is_dir(),
        f"{REPO_ROOT} has no docs/ directory: not a full repository checkout",
    )
    def test_repository_is_clean(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_strings.main(["--root", str(REPO_ROOT)])
        self.assertEqual(code, 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()
