"""Runs the calls in registered order. One raw file per call; a recorded call is never repeated."""

import base64
import copy
import fcntl
import http.client
import json
import threading
import time
import urllib.error
from collections import Counter
from collections.abc import Callable, Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import anthropic

from plate_eval import config, data, sampler
from plate_eval.data import sha256
from plate_eval.parse import classify, usage_tokens

IMAGE_ERROR = "ImageUnavailable"
STATUSES = ("ok", "invalid", "error", "refusal", "substituted")


@dataclass(frozen=True)
class Prompt:
    id: str
    text: str
    sha256: str


def load_prompts() -> dict[str, Prompt]:
    prompts = {}
    for prompt_id in config.PROMPTS:
        raw = (config.PROMPTS_DIR / f"{prompt_id}.txt").read_bytes()
        prompts[prompt_id] = Prompt(prompt_id, raw.decode().strip(), sha256(raw))
    return prompts


def estimate_tokens(prompt: Prompt) -> tuple[int, int]:
    """Expected input and output tokens of one call."""
    image = config.image_tokens(*config.DATASET_IMAGE_SIZE)
    return image + config.prompt_tokens(prompt.text), config.EXPECTED_OUTPUT_TOKENS[prompt.id]


def dry_run_report() -> str:
    prompts = load_prompts()
    n = len(sampler.read_ids(config.SAMPLE_FILE))
    lines = [
        f"cells: {len(config.CELLS)}",
        f"dishes: {n}",
        f"requests: {len(config.CELLS) * n}",
    ]
    total = worst = 0.0
    for key, model, prompt_id in config.CELLS:
        tokens_in, tokens_out = estimate_tokens(prompts[prompt_id])
        cost = n * config.cost_usd(model, tokens_in, tokens_out)
        total += cost
        worst += n * config.cost_usd(model, tokens_in, config.MAX_TOKENS)
        per_call = tokens_in + tokens_out
        lines.append(
            f"{key} {prompt_id}: input {tokens_in} tokens, expected output {tokens_out} tokens, "
            f"estimated cost {cost:.4f} USD, first {config.PAUSE_AFTER_CALLS} calls "
            f"{config.PAUSE_AFTER_CALLS * per_call} tokens "
            f"(pause above {config.PAUSE_FACTOR * per_call:.1f} tokens per call)"
        )
    lines += [
        f"estimated total cost: {total:.4f} USD",
        f"total cost if every call used max_tokens ({config.MAX_TOKENS}): {worst:.4f} USD",
        f"stop threshold: {config.COST_STOP_USD:.2f} USD",
    ]
    return "\n".join(lines)


def logged_request(request: dict) -> dict:
    """The request as sent, with each image's data replaced by its sha256. Pixels are not stored."""
    logged = copy.deepcopy(request)
    for turn in logged["messages"]:
        for block in turn["content"]:
            if block["type"] == "image":
                source = block["source"]
                source["sha256"] = sha256(base64.b64decode(source.pop("data")))
    return logged


def error_record(e: anthropic.APIError) -> dict:
    """What is kept of an API error. The response body is never stored."""
    return {
        "type": type(e).__name__,
        "status": getattr(e, "status_code", None),
        "request_id": getattr(e, "request_id", None),
        "message": e.message[: config.ERROR_MESSAGE_MAX_CHARS],
    }


def new_record(model: str, prompt: Prompt, dish_id: str) -> dict:
    """A raw record with every key present and the fields of a call still empty."""
    return {
        "dish_id": dish_id,
        "model": model,
        "prompt_id": prompt.id,
        "prompt_sha256": prompt.sha256,
        "image_sha256": None,
        "image_width": None,
        "image_height": None,
        "request": None,
        "attempts": [],
        "response": None,
        "error": None,
        "started_utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "elapsed_s": 0.0,
        "sdk_version": anthropic.__version__,
    }


def make_record(
    client: anthropic.Anthropic,
    model: str,
    prompt: Prompt,
    dish_id: str,
    image: bytes,
    sleep: Callable[[float], None],
) -> dict:
    record = new_record(model, prompt, dish_id)
    width, height = data.png_size(image)
    request = {
        "model": model,
        "max_tokens": config.MAX_TOKENS,
        "thinking": config.THINKING[model],
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/png",
                            "data": base64.b64encode(image).decode(),
                        },
                    },
                    {"type": "text", "text": prompt.text},
                ],
            }
        ],
    }
    clock = time.monotonic()
    attempts, response, error = [], None, None
    for attempt in range(len(config.RETRY_WAITS_S) + 1):
        try:
            response = client.messages.create(**request).model_dump(mode="json")
            attempts.append({"status": 200, "retry_after": None})
            break
        except anthropic.APIStatusError as e:
            hint = config.parse_retry_after(e.response.headers.get("retry-after"))
            attempts.append({"status": e.status_code, "retry_after": hint})
            if config.is_retryable(e.status_code) and attempt < len(config.RETRY_WAITS_S):
                sleep(config.retry_wait_s(attempt, hint))
                continue
            error = error_record(e)
            break
        except anthropic.APIError as e:  # connection error, timeout: never retried
            attempts.append({"status": None, "retry_after": None})
            error = error_record(e)
            break
    record.update(
        image_sha256=sha256(image),
        image_width=width,
        image_height=height,
        request=logged_request(request),
        attempts=attempts,
        response=response,
        error=error,
        elapsed_s=round(time.monotonic() - clock, 3),
    )
    return record


@dataclass(frozen=True)
class ImageProblem:
    status: int | None  # HTTP status of the failed download, None for any other cause
    message: str


def image_error_record(model: str, prompt: Prompt, dish_id: str, problem: ImageProblem) -> dict:
    """The record of a dish whose image is unusable: an error call that made no API request."""
    record = new_record(model, prompt, dish_id)
    record["error"] = {
        "type": IMAGE_ERROR,
        "status": problem.status,
        "request_id": None,
        "message": problem.message[: config.ERROR_MESSAGE_MAX_CHARS],
    }
    return record


def raw_path(model: str, prompt_id: str, dish_id: str) -> Path:
    return config.RAW_DIR / model / prompt_id / f"{dish_id}.json"


def halt_path() -> Path:
    return config.RAW_DIR / config.HALT_FILE_NAME


def current_hashes() -> dict[str, str]:
    """sha256 of the files that define the experiment, under the names used in run.json."""
    paths = {f"{p}.txt": config.PROMPTS_DIR / f"{p}.txt" for p in config.PROMPTS}
    paths["sample_ids.txt"] = config.SAMPLE_FILE
    paths["evaluation-protocol.md"] = config.PROTOCOL_FILE
    return {name: sha256(path.read_bytes()) for name, path in paths.items()}


def changed_files(recorded: dict[str, str]) -> list[str]:
    """Names of the experiment files whose current hash differs from the recorded one."""
    return [name for name, digest in current_hashes().items() if recorded.get(name) != digest]


def write_run_info() -> None:
    path = config.RAW_DIR / "run.json"
    if path.exists():  # a restart continues the same run
        return
    info = {
        "utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "sdk_version": anthropic.__version__,
        "sha256": current_hashes(),
        "config": {
            "sample_seed": config.SAMPLE_SEED,
            "sample_size": config.SAMPLE_SIZE,
            "bootstrap_seed": config.BOOTSTRAP_SEED,
            "bootstrap_resamples": config.BOOTSTRAP_RESAMPLES,
            "min_ref_kcal": config.MIN_REF_KCAL,
            "max_tokens": config.MAX_TOKENS,
            "models": [list(m) for m in config.MODELS],
            "prompts": list(config.PROMPTS),
            "prices_usd_per_million_tokens": config.PRICES,
            "cost_stop_usd": config.COST_STOP_USD,
            "workers_per_cell": config.WORKERS_PER_CELL,
        },
    }
    data.atomic_write(path, (json.dumps(info, indent=2, sort_keys=True) + "\n").encode())


def cell_label(key: str, prompt_id: str) -> str:
    return f"{key}/{prompt_id}"


@dataclass
class CellState:
    """The records of one cell, by dish id."""

    status: dict[str, str] = field(default_factory=dict)
    tokens: dict[str, int] = field(default_factory=dict)  # input + output, records with a response


@dataclass(frozen=True)
class Stop:
    exit_code: int
    rule: str
    detail: str


@dataclass
class Guard:
    """The records of the whole study and the stop rules. All updates happen under one lock.

    Records of earlier invocations are added first, so cost and counts cover the study."""

    first: tuple[str, ...]  # the first dishes of every cell in sample order, for stop rule 2
    estimates: dict[str, int]  # expected tokens per call, by cell label
    halt_file: Path
    cost: float = 0.0
    live_calls: int = 0  # recorded by this invocation
    cells: dict[str, CellState] = field(
        default_factory=lambda: {cell_label(k, p): CellState() for k, _, p in config.CELLS}
    )
    stop: Stop | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)
    stopped: threading.Event = field(default_factory=threading.Event)

    def add(self, label: str, model: str, dish_id: str, record: dict, *, live: bool = True) -> None:
        tokens_in, tokens_out = usage_tokens(record)
        with self.lock:
            self.cost += config.cost_usd(model, tokens_in, tokens_out)
            cell = self.cells[label]
            cell.status[dish_id] = classify(record).status
            if record["response"] is not None:
                cell.tokens[dish_id] = tokens_in + tokens_out
            if live:
                self.live_calls += 1
                self.decide(self.check_cost() or self.check_cell(label, cell, dish_id))

    def counts(self) -> Counter:
        return Counter(s for cell in self.cells.values() for s in cell.status.values())

    def decide(self, stop: Stop | None) -> None:
        """Keep the first stop. Its marker file is written now, not when the cell ends, so an
        interrupted or crashed run still leaves it. The marker holds counts per status, cost,
        the rule and the exit code: nothing from the replies."""
        if stop is None or self.stop is not None:
            return
        self.stop = stop
        self.stopped.set()
        counts = self.counts()
        utc = datetime.now(UTC).isoformat(timespec="seconds")
        text = (
            f"rule: {stop.rule}\nexit_code: {stop.exit_code}\ndetail: {stop.detail}\n"
            f"records: {', '.join(f'{s} {counts[s]}' for s in STATUSES)}\n"
            f"cost_usd: {self.cost:.4f}\nutc: {utc}\n"
        )
        data.atomic_write(self.halt_file, text.encode())

    def check_cost(self) -> Stop | None:
        if self.cost > config.COST_STOP_USD:
            detail = f"cost {self.cost:.4f} USD is above {config.COST_STOP_USD:.2f} USD"
            return Stop(config.EXIT_STOP, "cost", detail)
        return None

    def check_cell(self, label: str, cell: CellState, dish_id: str) -> Stop | None:
        # Rule 2 fires once, when the record that completes the first dishes arrives, whatever
        # the order of completion. Later invocations do not repeat it.
        if dish_id in self.first and all(d in cell.status for d in self.first):
            tokens = [cell.tokens[d] for d in self.first if d in cell.tokens]
            limit = config.PAUSE_FACTOR * self.estimates[label]
            if tokens and sum(tokens) / len(tokens) > limit:
                detail = (
                    f"cell {label}: mean {sum(tokens) / len(tokens):.1f} tokens per call over "
                    f"its first {len(self.first)} dishes is above {limit:.1f} "
                    f"({config.PAUSE_FACTOR} x the {self.estimates[label]} expected)"
                )
                return Stop(config.EXIT_PAUSE, "token_overrun", detail)
        completed = len(cell.status)
        counts = Counter(cell.status.values())
        bad = counts["error"] + counts["refusal"] + counts["substituted"]
        if completed >= config.ERROR_SHARE_MIN_CALLS and bad / completed > config.ERROR_SHARE_MAX:
            detail = (
                f"cell {label}: error {counts['error']}, refusal {counts['refusal']} and "
                f"substituted {counts['substituted']} in {completed} completed calls "
                f"is above {config.ERROR_SHARE_MAX:.0%}"
            )
            return Stop(config.EXIT_STOP, "error_share", detail)
        return None


class Refused(Exception):
    """The run must not start. Nothing has been spent."""


def read_records(ids: list[str]) -> Iterator[tuple[str, str, str, dict]]:
    """Every raw record of the study as (cell label, model, dish id, record), in run order."""
    for key, model, prompt_id in config.CELLS:
        for dish_id in ids:
            path = raw_path(model, prompt_id, dish_id)
            if path.exists():
                yield cell_label(key, prompt_id), model, dish_id, json.loads(path.read_text())


def earlier_image_errors(ids: list[str]) -> dict[str, ImageProblem]:
    """Dishes already recorded as ImageUnavailable in any cell: they stay so in all four."""
    found = {}
    for _, _, dish_id, record in read_records(ids):
        error = record["error"]
        if error is not None and error["type"] == IMAGE_ERROR:
            found.setdefault(dish_id, ImageProblem(error["status"], error["message"]))
    return found


def fetch_image(dish_id: str, sleep: Callable[[float], None]) -> ImageProblem | None:
    """Download the image into the cache unless it is there. None when it is a PNG."""
    try:
        data.png_size(data.image_bytes(dish_id, sleep))
    except urllib.error.HTTPError as e:
        return ImageProblem(e.code, f"download failed: {e}")
    except (OSError, http.client.HTTPException) as e:
        return ImageProblem(None, f"download failed with {type(e).__name__}: {e}")
    except ValueError as e:  # not a PNG
        (config.CACHE_DIR / data.image_cache_name(dish_id)).unlink(missing_ok=True)
        return ImageProblem(None, str(e))
    return None


def prefetch_images(ids: list[str], sleep: Callable[[float], None]) -> dict[str, ImageProblem]:
    """Download every image once, before the first call. Returns the dishes without a usable
    image, which get an error record in every cell."""
    decided = earlier_image_errors(ids)
    todo = [i for i in ids if i not in decided]
    with ThreadPoolExecutor(config.DOWNLOAD_WORKERS) as pool:
        problems = list(pool.map(lambda i: fetch_image(i, sleep), todo))
    return decided | {i: p for i, p in zip(todo, problems, strict=True) if p is not None}


def preflight(
    ack_halt: bool, sleep: Callable[[float], None]
) -> tuple[list[str], dict[str, Prompt], dict[str, ImageProblem]]:
    """Every check that must pass before the first call. Raises Refused."""
    halt = halt_path()
    if halt.exists() and not ack_halt:
        raise Refused(
            f"{halt} exists, a stop or pause was decided earlier:\n{halt.read_text()}"
            "read it, then pass --ack-halt to delete it and continue"
        )
    info = config.RAW_DIR / "run.json"
    if info.exists():
        changed = changed_files(json.loads(info.read_text())["sha256"])
        if changed:
            raise Refused(
                f"{', '.join(changed)} changed since {info} was written; "
                "a restart must continue the same experiment"
            )
    ids = sampler.read_ids(config.SAMPLE_FILE)
    drawn = sampler.draw_sample(sampler.read_ids(config.POOL_FILE))
    if ids != drawn:
        raise Refused(
            f"{config.SAMPLE_FILE.name} differs from the draw of {config.POOL_FILE.name}: "
            f"{len(set(ids) ^ set(drawn))} ids differ, {len(ids)} in the file, {len(drawn)} drawn"
        )
    unavailable = prefetch_images(ids, sleep)
    if halt.exists():  # only now: a refused start keeps the reason of the halt
        halt.unlink()
        print(f"removed {halt}")
    write_run_info()
    return ids, load_prompts(), unavailable


def run_cell(
    client: anthropic.Anthropic,
    guard: Guard,
    prompts: dict[str, Prompt],
    cell: tuple[str, str, str],
    ids: list[str],
    unavailable: dict[str, ImageProblem],
    sleep: Callable[[float], None],
) -> None:
    key, model, prompt_id = cell
    label = cell_label(key, prompt_id)

    def work(dish_id: str) -> None:
        if guard.stopped.is_set():
            return
        try:
            problem = unavailable.get(dish_id)
            image = None if problem else data.image_bytes(dish_id, sleep)
            path = raw_path(model, prompt_id, dish_id)
            if path.exists():  # a recorded call is never repeated
                return
            if problem:
                record = image_error_record(model, prompts[prompt_id], dish_id, problem)
            else:
                record = make_record(client, model, prompts[prompt_id], dish_id, image, sleep)
            content = json.dumps(record, indent=2, sort_keys=True) + "\n"
            data.atomic_write(path, content.encode())
            guard.add(label, model, dish_id, record)
        except BaseException:
            guard.stopped.set()  # a crash must not leave the other workers calling the API
            raise

    todo = [i for i in ids if not raw_path(model, prompt_id, i).exists()]
    with ThreadPoolExecutor(config.WORKERS_PER_CELL) as pool:
        list(pool.map(work, todo))
    print(
        f"{label}: {len(guard.cells[label].status)}/{len(ids)} recorded, cost {guard.cost:.4f} USD"
    )


def execute(
    client: anthropic.Anthropic,
    ids: list[str],
    prompts: dict[str, Prompt],
    unavailable: dict[str, ImageProblem],
    sleep: Callable[[float], None],
) -> int:
    estimates = {cell_label(k, p): sum(estimate_tokens(prompts[p])) for k, _, p in config.CELLS}
    guard = Guard(tuple(ids[: config.PAUSE_AFTER_CALLS]), estimates, halt_path())
    for label, model, dish_id, record in read_records(ids):  # earlier invocations
        guard.add(label, model, dish_id, record, live=False)
    guard.decide(guard.check_cost())

    for cell in config.CELLS:
        if guard.stop is not None:
            break
        run_cell(client, guard, prompts, cell, ids, unavailable, sleep)

    counts = guard.counts()
    print(
        f"calls this run: {guard.live_calls}; records: "
        f"{', '.join(f'{s} {counts[s]}' for s in STATUSES)}; total cost {guard.cost:.4f} USD"
    )
    if guard.stop is None:
        print("finished")
        return 0
    stop = guard.stop
    print(
        f"halted by rule {stop.rule}, exit code {stop.exit_code}: {stop.detail}; "
        f"marker {guard.halt_file}"
    )
    return stop.exit_code


def run(
    client: anthropic.Anthropic,
    *,
    ack_halt: bool = False,
    sleep: Callable[[float], None] = time.sleep,
) -> int:
    """Exit code: 0 finished, 2 stopped or refused to start, 3 paused."""
    config.RAW_DIR.mkdir(parents=True, exist_ok=True)
    lock_path = config.RAW_DIR / config.LOCK_FILE_NAME
    with open(lock_path, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"refusing to start: {lock_path} is held by another run")
            return config.EXIT_REFUSED
        try:
            ids, prompts, unavailable = preflight(ack_halt, sleep)
        except Refused as e:
            print(f"refusing to start: {e}")
            return config.EXIT_REFUSED
        print(f"images: {len(ids) - len(unavailable)} usable, {len(unavailable)} unavailable")
        return execute(client, ids, prompts, unavailable, sleep)
