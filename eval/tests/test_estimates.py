import urllib.request
from collections.abc import Callable
from pathlib import Path

import anthropic
import pytest

from plate_eval import cli, config, runner


def test_image_tokens() -> None:
    assert config.image_tokens(640, 480) == 414
    assert config.image_tokens(1024, 768) == 37 * 28


def test_prompt_tokens_round_up() -> None:
    assert config.prompt_tokens("a" * 9) == 3
    assert config.prompt_tokens("a" * 10) == 4


def test_cost_from_usage() -> None:
    assert config.cost_usd("claude-haiku-5-5", 1_000_000, 1_000_000) == pytest.approx(0.60)
    assert config.cost_usd("claude-sonnet-5-5", 1000, 200) == pytest.approx(0.004)
    assert config.cost_usd("claude-sonnet-5-5", 0, 0) == 0.0


def test_dry_run_totals_match_hand_calculation(
    workspace: Callable[[int], list[str]], tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(10)
    prompts = tmp_path / "prompts"
    prompts.mkdir()
    (prompts / "p1.txt").write_text("a" * 300 + "\n")  # 100 estimated tokens
    (prompts / "p2.txt").write_text("a" * 600 + "\n")  # 200 estimated tokens
    monkeypatch.setattr(config, "PROMPTS_DIR", prompts)

    report = runner.dry_run_report()

    # Per call, input tokens = 414 + prompt tokens; expected output 40 (p1) and 300 (p2).
    # haiku p1 514 in 40 out, p2 614 in 300 out; prices 0.10/0.50 haiku, 2.00/10.00 sonnet.
    # Per dish: 7.14e-5 + 2.114e-4 + 1.428e-3 + 4.228e-3 = 5.9388e-3 USD, times 10 dishes.
    # At max_tokens 600: 3.514e-4 + 3.614e-4 + 7.028e-3 + 7.228e-3 = 1.4969e-2, times 10.
    assert "cells: 4" in report
    assert "dishes: 10" in report
    assert "requests: 40" in report
    lines = report.splitlines()
    assert lines[3] == (
        "haiku p1: input 514 tokens, expected output 40 tokens, estimated cost 0.0007 USD, "
        "first 20 calls 11080 tokens (pause above 831.0 tokens per call)"
    )
    assert lines[6] == (
        "sonnet p2: input 614 tokens, expected output 300 tokens, estimated cost 0.0423 USD, "
        "first 20 calls 18280 tokens (pause above 1371.0 tokens per call)"
    )
    assert "estimated total cost: 0.0594 USD" in report
    assert "total cost if every call used max_tokens (600): 0.1497 USD" in report
    assert "stop threshold: 3.50 USD" in report


def test_dry_run_builds_no_client_and_uses_no_network(
    workspace: Callable[[int], list[str]],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    workspace(3)

    def refuse(*args: object, **kwargs: object) -> None:
        raise AssertionError("dry run must not reach the API or the network")

    monkeypatch.setattr(anthropic, "Anthropic", refuse)
    monkeypatch.setattr(urllib.request, "urlopen", refuse)

    assert cli.main(["run", "--dry-run"]) == 0
    assert "requests: 12" in capsys.readouterr().out
