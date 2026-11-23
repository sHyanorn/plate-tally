"""Constants of the evaluation. The protocol quotes these values."""

import math
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = EVAL_DIR.parent
PROMPTS_DIR = EVAL_DIR / "prompts"
CACHE_DIR = EVAL_DIR / ".cache"
RAW_DIR = EVAL_DIR / "raw"
HALT_FILE_NAME = "HALTED.txt"  # in RAW_DIR; written when a stop or pause is decided
LOCK_FILE_NAME = ".lock"  # in RAW_DIR; held for the duration of a real run
RESULTS_DIR = EVAL_DIR / "results"
POOL_FILE = EVAL_DIR / "pool_ids.txt"
EXCLUDED_FILE = EVAL_DIR / "pool_excluded.tsv"
SAMPLE_FILE = EVAL_DIR / "sample_ids.txt"
PROTOCOL_FILE = REPO_DIR / "docs" / "evaluation-protocol.md"
RESULTS_MD = REPO_DIR / "docs" / "evaluation-results.md"

BASE_URL = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/"
SPLIT_PATH = "dish_ids/splits/depth_test_ids.txt"
METADATA_PATHS = ("metadata/dish_metadata_cafe1.csv", "metadata/dish_metadata_cafe2.csv")
HEAD_WORKERS = 16
DOWNLOAD_WORKERS = 16
# SHA-256 of the reference files by cache file name. Other bytes are refused.
EXPECTED_SHA256 = {
    "depth_test_ids.txt": "6e43a5334a72bd06fa9c0d4b3bc86e2f57e5342b0b260d3fa003a76f7e39eca2",
    "dish_metadata_cafe1.csv": "881df31f27c2343d0ce219964527e0796f6ddadd60701ce6840fa801e8c2a960",
    "dish_metadata_cafe2.csv": "ef9f800d7b9c2e7e9a9e7cda5cbb4cfe51c760a8c1af4c05786ccf051bf5d77d",
}


def image_path(dish_id: str) -> str:
    return f"imagery/realsense_overhead/{dish_id}/rgb.png"


SAMPLE_SEED = 20261122
SAMPLE_SIZE = 300
BOOTSTRAP_SEED = 20261123
BOOTSTRAP_RESAMPLES = 10000
MIN_REF_KCAL = 50

MAX_TOKENS = 600
TIMEOUT_S = 120.0
MODELS = (("haiku", "claude-haiku-5-5"), ("sonnet", "claude-sonnet-5-5"))
PROMPTS = ("p1", "p2")
CELLS = tuple((key, model, prompt) for key, model in MODELS for prompt in PROMPTS)
# Sonnet 5.5 rejects {"type": "disabled"}; between_tools turns off up-front thinking.
THINKING = {
    "claude-haiku-5-5": {"type": "disabled"},
    "claude-sonnet-5-5": {"type": "between_tools"},
}

# USD per million tokens (input, output). Haiku's are for prompts up to 100,000 tokens.
# Vendor pricing page, read 2026-11-22.
PRICES = {"claude-haiku-5-5": (0.10, 0.50), "claude-sonnet-5-5": (2.00, 10.00)}

DATASET_IMAGE_SIZE = (640, 480)  # for the token estimate; an image of another size is sent as is
EXPECTED_OUTPUT_TOKENS = {"p1": 40, "p2": 300}

WORKERS_PER_CELL = 4
RETRY_WAITS_S = (2, 4, 8, 16, 32)
RETRY_AFTER_MAX_S = 60
COST_STOP_USD = 3.50
PAUSE_AFTER_CALLS = 20
PAUSE_FACTOR = 1.5
ERROR_SHARE_MAX = 0.05
ERROR_SHARE_MIN_CALLS = 20
ERROR_MESSAGE_MAX_CHARS = 500
EXIT_STOP = 2
EXIT_REFUSED = 2  # the run did not start; nothing was spent
EXIT_PAUSE = 3


def image_tokens(width: int, height: int) -> int:
    return math.ceil(width / 28) * math.ceil(height / 28)


def prompt_tokens(text: str) -> int:
    # The vendor says the current tokenizer gives about 30% more tokens than the old one;
    # 3 characters per token is an assumption (protocol, Cost).
    return math.ceil(len(text) / 3)


def is_retryable(status: int) -> bool:
    return status == 429 or status >= 500


def parse_retry_after(value: str | None) -> float | None:
    """The retry-after header in seconds; None when absent or not a non-negative number."""
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return None
    return seconds if seconds >= 0 else None


def retry_wait_s(attempt: int, retry_after: float | None) -> float:
    """Seconds before the next try: retry-after if present, else the schedule; at most 60."""
    wait = RETRY_WAITS_S[attempt] if retry_after is None else retry_after
    return min(wait, RETRY_AFTER_MAX_S)


def cost_usd(model: str, input_tokens: int, output_tokens: int) -> float:
    price_in, price_out = PRICES[model]
    return input_tokens * price_in / 1e6 + output_tokens * price_out / 1e6
