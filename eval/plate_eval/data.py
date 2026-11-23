"""Nutrition5k download, cache and parsing. Read-only GET and HEAD against the public bucket."""

import csv
import hashlib
import os
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

from plate_eval import config

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
HTTP_TIMEOUT_S = 60


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def http_get(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT_S) as response:
        return response.read()


def download(rel_path: str, sleep: Callable[[float], None] = time.sleep) -> bytes:
    """GET with the retry rule of the API calls: only HTTP 429 and 5xx, up to 5 retries."""
    attempt = 0
    while True:
        try:
            return http_get(config.BASE_URL + rel_path)
        except urllib.error.HTTPError as e:
            if not config.is_retryable(e.code) or attempt == len(config.RETRY_WAITS_S):
                raise
            hint = config.parse_retry_after(e.headers.get("retry-after"))
            sleep(config.retry_wait_s(attempt, hint))
            attempt += 1


def http_head(url: str) -> int:
    request = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_S) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code


def atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "wb") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())  # the rename must not outlive a crash with empty content
    os.replace(tmp, path)


def verified(name: str, content: bytes) -> bytes:
    """The content, refused unless its sha256 is the expected one. Images have none to check."""
    expected = config.EXPECTED_SHA256.get(name)
    if expected is not None and (seen := sha256(content)) != expected:
        raise ValueError(f"expected {name} to have sha256 {expected}, got {seen}")
    return content


def fetch_cached(
    rel_path: str, cache_name: str, sleep: Callable[[float], None] = time.sleep
) -> bytes:
    path = config.CACHE_DIR / cache_name
    if path.exists():
        return verified(cache_name, path.read_bytes())
    content = verified(cache_name, download(rel_path, sleep))
    atomic_write(path, content)
    return content


def metadata_texts() -> list[str]:
    return [fetch_cached(rel, Path(rel).name).decode() for rel in config.METADATA_PATHS]


def image_cache_name(dish_id: str) -> str:
    return f"images/{dish_id}.png"


def image_bytes(dish_id: str, sleep: Callable[[float], None] = time.sleep) -> bytes:
    return fetch_cached(config.image_path(dish_id), image_cache_name(dish_id), sleep)


def png_size(data: bytes) -> tuple[int, int]:
    """Width and height from the IHDR chunk. Refuses anything that is not a PNG."""
    if data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError(f"expected a PNG file with an IHDR chunk, got {data[:16]!r}")
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def parse_reference(texts: list[str]) -> dict[str, float]:
    """total_calories (second column) by dish id from the metadata CSVs, which have no header."""
    reference: dict[str, float] = {}
    for text in texts:
        for row in csv.reader(text.splitlines()):
            if len(row) < 2:
                continue
            try:
                kcal = float(row[1])
            except ValueError:
                continue
            if reference.setdefault(row[0], kcal) != kcal:
                raise ValueError(
                    f"conflicting total_calories for {row[0]}: {reference[row[0]]} and {kcal}"
                )
    return reference


def load_reference() -> dict[str, float]:
    return parse_reference(metadata_texts())
