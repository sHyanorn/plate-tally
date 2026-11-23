import shutil
from collections.abc import Callable
from pathlib import Path

import pytest
from fakes import png

from plate_eval import config, data
from plate_eval.sampler import draw_sample, write_ids


def no_network(url: str) -> bytes:
    raise AssertionError(f"tests must not download anything: {url}")


@pytest.fixture
def workspace(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Callable[[int], list[str]]:
    """Point every input and output path at tmp_path: a sample of n dishes drawn from a pool of
    2n, one cached image per sampled dish, a copy of the prompts. The network is closed."""

    def setup(n: int = 30) -> list[str]:
        prompts = tmp_path / "workspace_prompts"
        shutil.copytree(config.PROMPTS_DIR, prompts)
        monkeypatch.setattr(config, "PROMPTS_DIR", prompts)
        monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
        monkeypatch.setattr(config, "CACHE_DIR", tmp_path / "cache")
        monkeypatch.setattr(config, "RESULTS_DIR", tmp_path / "results")
        monkeypatch.setattr(config, "RESULTS_MD", tmp_path / "evaluation-results.md")
        monkeypatch.setattr(config, "POOL_FILE", tmp_path / "pool_ids.txt")
        monkeypatch.setattr(config, "SAMPLE_FILE", tmp_path / "sample_ids.txt")
        monkeypatch.setattr(config, "PROTOCOL_FILE", tmp_path / "evaluation-protocol.md")
        monkeypatch.setattr(config, "SAMPLE_SIZE", n)
        monkeypatch.setattr(config, "EXPECTED_SHA256", {})  # fake reference files
        monkeypatch.setattr(data, "http_get", no_network)
        pool = [f"dish_{i:03d}" for i in range(2 * n)]
        ids = draw_sample(pool)
        write_ids(config.POOL_FILE, pool)
        write_ids(config.SAMPLE_FILE, ids)
        config.PROTOCOL_FILE.write_text("protocol\n")
        for dish_id in ids:
            path = config.CACHE_DIR / data.image_cache_name(dish_id)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(png(tag=dish_id))
        return ids

    return setup
