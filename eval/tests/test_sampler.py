import hashlib
import os
import random
import urllib.error
from pathlib import Path

import pytest
from fakes import http_error, png

from plate_eval import config, data, sampler

POOL = [f"dish_{1000 + i}" for i in range(507)]


def test_draw_is_deterministic_sorted_unique_and_a_subset() -> None:
    first = sampler.draw_sample(POOL)
    assert first == sampler.draw_sample(POOL)
    assert len(first) == config.SAMPLE_SIZE == 300
    assert first == sorted(first)
    assert len(set(first)) == 300
    assert set(first) <= set(POOL)


def test_draw_does_not_depend_on_pool_order() -> None:
    shuffled = POOL[:]
    random.Random(1).shuffle(shuffled)
    assert sampler.draw_sample(shuffled) == sampler.draw_sample(POOL)


def test_draw_from_a_small_pool_fails() -> None:
    with pytest.raises(ValueError, match="at least 300"):
        sampler.draw_sample(POOL[:299])


def test_sample_check_passes_on_the_committed_files() -> None:
    if not config.POOL_FILE.exists():
        pytest.skip("eval/pool_ids.txt is absent; run build-pool first")
    assert sampler.cmd_sample(check=True) == 0


def test_sample_check_fails_on_any_difference(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(config, "POOL_FILE", tmp_path / "pool_ids.txt")
    monkeypatch.setattr(config, "SAMPLE_FILE", tmp_path / "sample_ids.txt")
    sampler.write_ids(config.POOL_FILE, POOL)
    assert sampler.cmd_sample(check=False) == 0
    assert sampler.cmd_sample(check=True) == 0

    sample = sampler.read_ids(config.SAMPLE_FILE)
    sampler.write_ids(config.SAMPLE_FILE, sample[:-1] + ["dish_9999"])
    assert sampler.cmd_sample(check=True) == 1
    assert "2 ids differ" in capsys.readouterr().out


CAFE1 = "dish_a,100.0,50,1,2,3,ing_1,rice\ndish_b,200.5,50,1\ndish_c,300.0,1\ndish_d,80,1\n"
CAFE2 = "dish_c,300.0,1,1,1,1\ndish_x,10,1,1,1,1\n"


def fake_bucket(cafe1: str = CAFE1, cafe2: str = CAFE2) -> dict[str, bytes]:
    ids = "dish_a\ndish_b\ndish_c\ndish_d\ndish_e\n"
    return {
        config.SPLIT_PATH: ids.encode(),
        config.METADATA_PATHS[0]: cafe1.encode(),
        config.METADATA_PATHS[1]: cafe2.encode(),
    }


def test_build_pool_reports_each_exclusion_reason() -> None:
    files = fake_bucket()
    status = {
        config.image_path("dish_a"): 200,
        config.image_path("dish_b"): 404,
        config.image_path("dish_c"): 200,
        config.image_path("dish_d"): 403,
    }
    pool, excluded = sampler.build_pool(files.__getitem__, status.__getitem__)
    assert pool == ["dish_a", "dish_c"]
    assert excluded == {
        "dish_b": "no_image",
        "dish_d": "head_status_403",
        "dish_e": "no_reference_energy",
    }


def test_build_pool_fails_on_conflicting_duplicates() -> None:
    files = fake_bucket(cafe2="dish_c,301.0,1,1,1,1\n")
    with pytest.raises(ValueError, match="conflicting total_calories for dish_c"):
        sampler.build_pool(files.__getitem__, lambda path: 200)


def test_parse_reference_skips_rows_without_a_number() -> None:
    text = "dish_a,12.5,1\ndish_b,\ndish_c\ndish_d,n/a,1\n\n"
    assert data.parse_reference([text]) == {"dish_a": 12.5}


def test_png_size_reads_the_ihdr_chunk() -> None:
    assert data.png_size(png(640, 480)) == (640, 480)
    assert data.png_size(png(1024, 768)) == (1024, 768)


def test_png_size_refuses_other_files() -> None:
    with pytest.raises(ValueError, match="expected a PNG"):
        data.png_size(b"\xff\xd8\xff\xe0" + b"\x00" * 40)


def test_atomic_write_flushes_and_syncs_the_file_before_the_rename(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    target = tmp_path / "sub" / "a.json"
    events: list[object] = []
    real_fsync, real_replace = os.fsync, os.replace

    def fsync(fd: int) -> None:
        events.append(("fsync", target.with_name("a.json.tmp").read_bytes()))
        real_fsync(fd)

    def replace(src: Path, dst: Path) -> None:
        events.append("replace")
        real_replace(src, dst)

    monkeypatch.setattr(os, "fsync", fsync)
    monkeypatch.setattr(os, "replace", replace)
    data.atomic_write(target, b"content")
    assert events == [("fsync", b"content"), "replace"]  # the bytes were flushed before fsync
    assert target.read_bytes() == b"content"
    assert [p.name for p in target.parent.iterdir()] == ["a.json"]


CACHED_NAMES = ("depth_test_ids.txt", "dish_metadata_cafe1.csv", "dish_metadata_cafe2.csv")


def sha(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


@pytest.fixture
def cache(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setattr(config, "CACHE_DIR", tmp_path / "cache")
    return config.CACHE_DIR


def serve(monkeypatch: pytest.MonkeyPatch, outcomes: list[object]) -> list[str]:
    """http_get answers with the given bytes or raises the given errors, in order."""
    urls: list[str] = []

    def get(url: str) -> bytes:
        urls.append(url)
        outcome = outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    monkeypatch.setattr(data, "http_get", get)
    return urls


def test_reference_file_with_other_bytes_is_refused_when_read_from_the_cache(
    cache: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    good = b"dish_a,1.0\n"
    monkeypatch.setattr(config, "EXPECTED_SHA256", {"dish_metadata_cafe1.csv": sha(good)})
    cache.mkdir()
    (cache / "dish_metadata_cafe1.csv").write_bytes(good)
    assert data.fetch_cached("metadata/dish_metadata_cafe1.csv", "dish_metadata_cafe1.csv") == good

    (cache / "dish_metadata_cafe1.csv").write_bytes(b"dish_a,2.0\n")
    with pytest.raises(ValueError) as e:
        data.fetch_cached("metadata/dish_metadata_cafe1.csv", "dish_metadata_cafe1.csv")
    message = str(e.value)
    assert "dish_metadata_cafe1.csv" in message
    assert sha(good) in message  # expected
    assert sha(b"dish_a,2.0\n") in message  # seen


def test_reference_file_with_other_bytes_is_refused_after_a_download_and_not_cached(
    cache: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(config, "EXPECTED_SHA256", {"depth_test_ids.txt": sha(b"dish_a\n")})
    serve(monkeypatch, [b"dish_b\n", b"dish_a\n"])
    with pytest.raises(ValueError) as e:
        data.fetch_cached(config.SPLIT_PATH, "depth_test_ids.txt")
    assert "depth_test_ids.txt" in str(e.value)
    assert sha(b"dish_a\n") in str(e.value)  # expected
    assert sha(b"dish_b\n") in str(e.value)  # seen
    assert not (cache / "depth_test_ids.txt").exists()
    assert data.fetch_cached(config.SPLIT_PATH, "depth_test_ids.txt") == b"dish_a\n"
    assert (cache / "depth_test_ids.txt").read_bytes() == b"dish_a\n"


def test_build_pool_and_score_refuse_other_reference_bytes(
    cache: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(config, "EXPECTED_SHA256", {n: "0" * 64 for n in CACHED_NAMES})
    cache.mkdir()
    for name in CACHED_NAMES:
        (cache / name).write_bytes(b"x\n")
    monkeypatch.setattr(data, "http_get", lambda url: pytest.fail("no download expected"))
    with pytest.raises(ValueError, match="expected depth_test_ids.txt to have sha256"):
        sampler.cmd_build_pool()
    with pytest.raises(ValueError, match="expected dish_metadata_cafe1.csv to have sha256"):
        data.load_reference()


def test_expected_hashes_are_the_registered_ones() -> None:
    assert config.EXPECTED_SHA256 == {
        "depth_test_ids.txt": "6e43a5334a72bd06fa9c0d4b3bc86e2f57e5342b0b260d3fa003a76f7e39eca2",
        "dish_metadata_cafe1.csv": (
            "881df31f27c2343d0ce219964527e0796f6ddadd60701ce6840fa801e8c2a960"
        ),
        "dish_metadata_cafe2.csv": (
            "ef9f800d7b9c2e7e9a9e7cda5cbb4cfe51c760a8c1af4c05786ccf051bf5d77d"
        ),
    }


def test_cached_reference_files_match_the_expected_hashes() -> None:
    cached = [config.CACHE_DIR / name for name in CACHED_NAMES]
    if not all(path.exists() for path in cached):
        pytest.skip("eval/.cache holds no reference files; run build-pool first")
    for path in cached:
        assert data.verified(path.name, path.read_bytes())


def test_download_retries_only_429_and_5xx_and_waits_as_the_api_calls_do(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    urls = serve(monkeypatch, [http_error(429), http_error(500), http_error(503), b"ok"])
    sleeps: list[float] = []
    assert data.download("a/b.png", sleeps.append) == b"ok"
    assert sleeps == [2, 4, 8]
    assert urls == [config.BASE_URL + "a/b.png"] * 4


def test_download_gives_up_after_five_retries(monkeypatch: pytest.MonkeyPatch) -> None:
    urls = serve(monkeypatch, [http_error(503)] * 7)
    sleeps: list[float] = []
    with pytest.raises(urllib.error.HTTPError) as e:
        data.download("a/b.png", sleeps.append)
    assert e.value.code == 503
    assert sleeps == [2, 4, 8, 16, 32]
    assert len(urls) == 6


@pytest.mark.parametrize(
    "error",
    [
        http_error(400),
        http_error(403),
        http_error(404),
        urllib.error.URLError("down"),
        TimeoutError(),
    ],
)
def test_download_does_not_retry_other_errors(
    monkeypatch: pytest.MonkeyPatch, error: Exception
) -> None:
    urls = serve(monkeypatch, [error, b"never reached"])
    sleeps: list[float] = []
    with pytest.raises(type(error)):
        data.download("a/b.png", sleeps.append)
    assert sleeps == []
    assert len(urls) == 1


def test_download_retry_after_replaces_the_scheduled_wait_and_is_capped(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    serve(
        monkeypatch,
        [
            http_error(429, {"retry-after": "7"}),
            http_error(503, {"retry-after": "500"}),
            http_error(429, {"retry-after": "0"}),
            http_error(500, {"retry-after": "soon"}),
            b"ok",
        ],
    )
    sleeps: list[float] = []
    assert data.download("a/b.png", sleeps.append) == b"ok"
    assert sleeps == [7, 60, 0, 16]  # an unreadable header falls back to the scheduled wait


def test_retry_wait_is_the_header_capped_at_60_or_the_schedule() -> None:
    assert [config.retry_wait_s(i, None) for i in range(5)] == [2, 4, 8, 16, 32]
    assert config.retry_wait_s(0, 59.5) == 59.5
    assert config.retry_wait_s(4, 3.0) == 3.0
    assert config.retry_wait_s(0, 60.0) == 60.0
    assert config.retry_wait_s(0, 61.0) == 60
    assert [config.parse_retry_after(v) for v in ("5", "1.5", "x", "-3", None)] == [
        5.0,
        1.5,
        None,
        None,
        None,
    ]
