"""Pool of usable dishes and the fixed random sample drawn from it."""

import random
from collections import Counter
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from plate_eval import config, data


def build_pool(
    get: Callable[[str], bytes], head: Callable[[str], int]
) -> tuple[list[str], dict[str, str]]:
    """Return the sorted pool and the excluded dishes with their reason.

    get takes a bucket path and returns its bytes. head takes a bucket path and returns the HTTP
    status.
    """
    ids = sorted(set(get(config.SPLIT_PATH).decode().split()))
    reference = data.parse_reference([get(rel).decode() for rel in config.METADATA_PATHS])
    excluded = {i: "no_reference_energy" for i in ids if i not in reference}
    candidates = [i for i in ids if i in reference]
    with ThreadPoolExecutor(config.HEAD_WORKERS) as executor:
        codes = list(executor.map(lambda i: head(config.image_path(i)), candidates))
    for dish_id, code in zip(candidates, codes, strict=True):
        if code != 200:
            excluded[dish_id] = "no_image" if code == 404 else f"head_status_{code}"
    return [i for i in candidates if i not in excluded], excluded


def read_ids(path: Path) -> list[str]:
    return path.read_text().split()


def write_ids(path: Path, ids: list[str]) -> None:
    path.write_text("".join(f"{i}\n" for i in ids))


def draw_sample(pool: list[str]) -> list[str]:
    if len(pool) < config.SAMPLE_SIZE:
        raise ValueError(f"expected at least {config.SAMPLE_SIZE} pool dishes, got {len(pool)}")
    return sorted(random.Random(config.SAMPLE_SEED).sample(sorted(pool), config.SAMPLE_SIZE))


def cmd_build_pool() -> int:
    def get(rel: str) -> bytes:
        return data.fetch_cached(rel, Path(rel).name)

    pool, excluded = build_pool(get, lambda rel: data.http_head(config.BASE_URL + rel))
    write_ids(config.POOL_FILE, pool)
    rows = "".join(f"{i}\t{reason}\n" for i, reason in sorted(excluded.items()))
    config.EXCLUDED_FILE.write_text("dish_id\treason\n" + rows)
    print(f"pool: {len(pool)} dishes, excluded: {len(excluded)}")
    for reason, n in sorted(Counter(excluded.values()).items()):
        print(f"  {reason}: {n}")
    return 0


def cmd_sample(check: bool) -> int:
    sample = draw_sample(read_ids(config.POOL_FILE))
    if not check:
        write_ids(config.SAMPLE_FILE, sample)
        print(f"wrote {len(sample)} ids to {config.SAMPLE_FILE.name}")
        return 0
    committed = read_ids(config.SAMPLE_FILE)
    if committed != sample:
        print(
            f"{config.SAMPLE_FILE.name} differs from the draw: "
            f"{len(set(committed) ^ set(sample))} ids differ, "
            f"{len(committed)} committed, {len(sample)} drawn"
        )
        return 1
    print(f"{config.SAMPLE_FILE.name} matches the draw ({len(sample)} ids)")
    return 0
