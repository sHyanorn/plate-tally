import base64
import copy
import fcntl
import hashlib
import json
import re
import shutil
import threading
import time
import urllib.error
from collections import deque
from collections.abc import Callable
from pathlib import Path

import anthropic
import pytest
from fakes import (
    FakeClient,
    connection_error,
    http_error,
    message,
    png,
    reply_for,
    status_error,
)

from plate_eval import cli, config, data, runner, sampler
from plate_eval.parse import classify

HAIKU = "claude-haiku-5-5"
SONNET = "claude-sonnet-5-5"
IMAGE = png(tag="x")
RECORD_KEYS = """dish_id model prompt_id prompt_sha256 image_sha256 image_width image_height request
attempts response error started_utc elapsed_s sdk_version"""
REQUEST_KEYS = "model max_tokens thinking messages"
PROMPT = runner.load_prompts()["p1"]


def record_for(client: FakeClient) -> tuple[dict, list[float]]:
    sleeps: list[float] = []
    record = runner.make_record(client, HAIKU, PROMPT, "dish_000", IMAGE, sleeps.append)
    return record, sleeps


def scripted(outcomes: list) -> FakeClient:
    """A client that raises or returns the given outcomes in order."""
    queue = deque(outcomes)

    def handler(kwargs: dict) -> object:
        outcome = queue.popleft()
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    return FakeClient(handler)


def test_retries_429_and_500_then_succeeds() -> None:
    client = scripted(
        [
            status_error(anthropic.RateLimitError, 429),
            status_error(anthropic.InternalServerError, 500),
            message(),
        ]
    )
    record, sleeps = record_for(client)
    assert sleeps == [2, 4]
    assert [a["status"] for a in record["attempts"]] == [429, 500, 200]
    assert record["error"] is None
    assert classify(record).status == "ok"


def test_retry_after_header_is_honoured_and_capped() -> None:
    client = scripted(
        [
            status_error(anthropic.RateLimitError, 429, {"retry-after": "7"}),
            status_error(anthropic.RateLimitError, 429, {"retry-after": "500"}),
            status_error(anthropic.RateLimitError, 429, {"retry-after": "soon"}),
            message(),
        ]
    )
    record, sleeps = record_for(client)
    assert sleeps == [7, 60, 8]  # an unreadable header falls back to the fixed wait
    assert [a["retry_after"] for a in record["attempts"]] == [7.0, 500.0, None, None]


def test_gives_up_after_five_retries() -> None:
    client = scripted([status_error(anthropic.InternalServerError, 503)] * 6)
    record, sleeps = record_for(client)
    assert sleeps == [2, 4, 8, 16, 32]
    assert len(client.calls) == 6
    assert record["response"] is None
    assert record["error"]["type"] == "InternalServerError"
    assert record["error"]["status"] == 503


def test_no_retry_on_400() -> None:
    client = scripted([status_error(anthropic.BadRequestError, 400)])
    record, sleeps = record_for(client)
    assert sleeps == []
    assert len(client.calls) == 1
    assert record["error"]["type"] == "BadRequestError"
    assert record["error"]["status"] == 400
    assert classify(record).status == "error"


def test_no_retry_on_connection_error() -> None:
    client = scripted([connection_error()])
    record, sleeps = record_for(client)
    assert sleeps == []
    assert len(client.calls) == 1
    assert record["error"]["type"] == "APIConnectionError"
    assert record["error"]["status"] is None


def test_refusal_and_max_tokens_are_classified_from_the_raw_record() -> None:
    refusal, _ = record_for(FakeClient(lambda kw: message("", stop_reason="refusal")))
    assert classify(refusal).status == "refusal"
    truncated = message('{"total_kcal": 1', stop_reason="max_tokens")
    cut, _ = record_for(FakeClient(lambda kw: truncated))
    assert (classify(cut).status, classify(cut).reason) == ("invalid", "max_tokens")


def test_request_parameters_are_exactly_the_registered_ones() -> None:
    for model, thinking in ((HAIKU, {"type": "disabled"}), (SONNET, {"type": "between_tools"})):
        client = FakeClient()
        runner.make_record(client, model, PROMPT, "dish_000", IMAGE, lambda s: None)
        (request,) = client.calls
        assert set(request) == {"model", "max_tokens", "thinking", "messages"}
        assert request["model"] == model
        assert request["max_tokens"] == 600
        assert request["thinking"] == thinking
        (turn,) = request["messages"]
        assert turn["role"] == "user"
        image, text = turn["content"]
        assert image == {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": base64.b64encode(IMAGE).decode(),
            },
        }
        assert text == {"type": "text", "text": PROMPT.text}
        assert PROMPT.text == PROMPT.text.strip()


def test_raw_record_has_no_pixels_and_no_credentials() -> None:
    record, _ = record_for(FakeClient())
    assert set(record) == set(RECORD_KEYS.split())
    assert set(record["request"]) == set(REQUEST_KEYS.split())
    assert (record["image_width"], record["image_height"]) == (640, 480)
    text = json.dumps(record).lower()
    assert base64.b64encode(IMAGE).decode().lower() not in text
    for forbidden in ("sk-ant", "api-key", "api_key", "authorization", "bearer"):
        assert forbidden not in text


def test_recorded_request_is_the_request_sent_with_the_image_hashed() -> None:
    client = FakeClient()
    record, _ = record_for(client)
    (sent,) = client.calls
    expected = copy.deepcopy(sent)
    source = expected["messages"][0]["content"][0]["source"]
    assert base64.b64decode(source.pop("data")) == IMAGE
    source["sha256"] = hashlib.sha256(IMAGE).hexdigest()
    assert record["request"] == expected
    assert record["image_sha256"] == source["sha256"]


def test_error_record_keeps_type_status_request_id_and_a_truncated_message() -> None:
    body = {"error": {"type": "invalid_request_error", "message": "BODY-ONLY-TEXT"}}
    error = status_error(
        anthropic.BadRequestError, 400, {"request-id": "req_123"}, message="m" * 2000, body=body
    )
    record, _ = record_for(scripted([error]))
    assert record["error"] == {
        "type": "BadRequestError",
        "status": 400,
        "request_id": "req_123",
        "message": "m" * 500,
    }
    assert "BODY-ONLY-TEXT" not in json.dumps(record)

    record, _ = record_for(scripted([connection_error()]))
    assert record["error"] == {
        "type": "APIConnectionError",
        "status": None,
        "request_id": None,
        "message": "Connection error.",
    }


def run_all(
    client: FakeClient, ack_halt: bool = False, sleep: Callable[[float], None] = lambda s: None
) -> int:
    return runner.run(client, ack_halt=ack_halt, sleep=sleep)


def halt_file() -> Path:
    return config.RAW_DIR / "HALTED.txt"


def test_run_writes_one_file_per_call_and_run_info(workspace: Callable[[int], list[str]]) -> None:
    ids = workspace(3)
    client = FakeClient()
    assert run_all(client) == 0
    assert len(client.calls) == 12
    for _, model, prompt_id in config.CELLS:
        for dish_id in ids:
            path = config.RAW_DIR / model / prompt_id / f"{dish_id}.json"
            assert json.loads(path.read_text())["dish_id"] == dish_id
    info = json.loads((config.RAW_DIR / "run.json").read_text())
    assert set(info["sha256"]) == {"p1.txt", "p2.txt", "sample_ids.txt", "evaluation-protocol.md"}
    assert info["sdk_version"] == anthropic.__version__
    assert info["config"]["max_tokens"] == 600


def test_existing_raw_files_are_skipped(workspace: Callable[[int], list[str]]) -> None:
    workspace(3)
    assert run_all(FakeClient()) == 0
    again = FakeClient()
    assert run_all(again) == 0
    assert again.calls == []


def test_calls_run_in_registered_order(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(4)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    dish_of = {base64.b64encode(png(tag=i)).decode(): i for i in ids}  # each image is unique
    order = []

    def handler(kwargs: dict) -> object:
        image, text = kwargs["messages"][0]["content"]
        prompt_id = "p1" if "total_kcal" in text["text"] else "p2"
        order.append((kwargs["model"], prompt_id, dish_of[image["source"]["data"]]))
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == 0
    expected = [(m, p, i) for _, m, p in config.CELLS for i in sorted(ids)]
    assert order == expected
    cells = [(m, p) for m, p, _ in order[::4]]
    assert cells == [(HAIKU, "p1"), (HAIKU, "p2"), (SONNET, "p1"), (SONNET, "p2")]


def test_cost_above_limit_stops_with_exit_code_2(
    workspace: Callable[[int], list[str]], capsys: pytest.CaptureFixture[str]
) -> None:
    workspace(30)
    # 1,000,000 output tokens cost 0.50 USD each on haiku, so the 8th call crosses 3.50.
    client = FakeClient(lambda kw: message(output_tokens=1_000_000))
    assert run_all(client) == config.EXIT_STOP == 2
    assert 8 <= len(client.calls) <= 8 + config.WORKERS_PER_CELL - 1
    assert "halted by rule cost, exit code 2" in capsys.readouterr().out
    text = halt_file().read_text()
    assert "rule: cost\n" in text
    assert "exit_code: 2\n" in text
    assert re.search(r"detail: cost 3\.\d{4} USD is above 3\.50 USD\n", text)
    assert re.search(r"records: ok \d+, invalid 0, error 0, refusal 0, substituted 0\n", text)
    assert re.search(r"cost_usd: 3\.\d{4}\n", text)
    assert re.search(r"utc: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+00:00\n$", text)


def test_cost_of_earlier_runs_counts_toward_the_limit(
    workspace: Callable[[int], list[str]],
) -> None:
    workspace(30)
    assert run_all(FakeClient(lambda kw: message(output_tokens=1_000_000))) == 2
    again = FakeClient(lambda kw: message(output_tokens=1_000_000))
    assert run_all(again, ack_halt=True) == 2  # the cost stop is decided again by itself
    assert again.calls == []
    assert "rule: cost\n" in halt_file().read_text()


def test_halt_marker_is_written_when_the_stop_is_decided(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 2)
    second_started = threading.Event()
    marker_seen: list[bool] = []
    lock = threading.Lock()
    started = 0

    def handler(kwargs: dict) -> object:
        nonlocal started
        with lock:
            started += 1
            number = started
        if number == 1:  # in flight until the second call has started, then costs 4 USD
            assert second_started.wait(5)
            return message(output_tokens=8_000_000)
        second_started.set()  # the second call is still in flight when the stop is decided
        deadline = time.monotonic() + 5
        while not halt_file().exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        marker_seen.append(halt_file().exists())
        raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        run_all(FakeClient(handler))
    assert marker_seen == [True]
    assert "rule: cost\n" in halt_file().read_text()


def test_token_overrun_over_the_first_20_dishes_pauses_until_acknowledged(
    workspace: Callable[[int], list[str]],
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)

    # Only haiku/p1 overruns: it is estimated at 536 tokens per call, and 5000 is far above 1.5x.
    def handler(kwargs: dict) -> object:
        if kwargs["model"] == HAIKU and "total_kcal" in kwargs["messages"][0]["content"][1]["text"]:
            return message(input_tokens=5000)
        return reply_for(kwargs)

    client = FakeClient(handler)
    assert run_all(client) == config.EXIT_PAUSE == 3
    assert len(client.calls) == 20
    halted = halt_file()
    assert "rule: token_overrun\n" in halted.read_text()
    assert "exit_code: 3\n" in halted.read_text()
    assert "haiku/p1" in halted.read_text()
    assert "5020.0" in halted.read_text()
    capsys.readouterr()

    blocked = FakeClient()
    assert run_all(blocked) == 2  # refused to start
    out = capsys.readouterr().out
    assert str(halted) in out
    assert "--ack-halt" in out
    assert blocked.calls == []
    assert halted.exists()

    resumed = FakeClient(handler)
    assert run_all(resumed, ack_halt=True) == 0  # the first 20 calls were already checked
    assert not halted.exists()
    assert len(client.calls) + len(resumed.calls) == 120


def cell_of(kwargs: dict) -> tuple[str, str]:
    text = kwargs["messages"][0]["content"][1]["text"]
    return kwargs["model"], "p1" if "total_kcal" in text else "p2"


@pytest.mark.parametrize("target", config.CELLS)
def test_error_share_above_5_percent_stops_the_run_in_each_cell(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch, target: tuple
) -> None:
    key, model, prompt_id = target
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)

    def handler(kwargs: dict) -> object:
        if cell_of(kwargs) == (model, prompt_id):
            raise status_error(anthropic.BadRequestError, 400)
        return reply_for(kwargs)

    client = FakeClient(handler)
    assert run_all(client) == config.EXIT_STOP
    assert len(client.calls) == 30 * config.CELLS.index(target) + 20  # checked from the 20th call
    text = halt_file().read_text()
    assert "rule: error_share\n" in text
    assert (
        f"cell {key}/{prompt_id}: error 20, refusal 0 and substituted 0 in 20 completed calls"
        in text
    )
    blocked = FakeClient()
    assert run_all(blocked) == 2  # a stop persists like a pause
    assert blocked.calls == []


def test_error_share_counts_refusals_with_errors(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    calls = 0

    def handler(kwargs: dict) -> object:
        nonlocal calls
        calls += 1
        if calls in (3, 9):  # one error and one refusal in the first 20 calls: 10%
            if calls == 3:
                raise status_error(anthropic.BadRequestError, 400)
            return message("", stop_reason="refusal", model=kwargs["model"])
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == config.EXIT_STOP
    assert calls == 20
    assert "error 1, refusal 1 and substituted 0 in 20 completed calls" in halt_file().read_text()


def test_substituted_replies_count_toward_the_error_share(
    workspace: Callable[[int], list[str]],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    calls = 0

    def handler(kwargs: dict) -> object:
        nonlocal calls
        calls += 1
        if calls in (3, 9):  # another model answers 2 of the first 20 calls: 10%
            return message(model=SONNET)
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == config.EXIT_STOP
    assert calls == 20
    text = halt_file().read_text()
    assert "rule: error_share\n" in text
    assert "error 0, refusal 0 and substituted 2 in 20 completed calls" in text
    assert "records: ok 18, invalid 0, error 0, refusal 0, substituted 2\n" in text
    assert "halted by rule error_share, exit code 2" in capsys.readouterr().out
    third = sampler.read_ids(config.SAMPLE_FILE)[2]  # asked haiku, sonnet replied
    record = json.loads(runner.raw_path(HAIKU, "p1", third).read_text())
    assert (record["model"], record["response"]["model"]) == (HAIKU, SONNET)
    assert (classify(record).status, classify(record).reason) == ("substituted", "model_mismatch")


def test_one_substituted_reply_in_20_is_exactly_5_percent_and_does_not_stop(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    calls = 0

    def handler(kwargs: dict) -> object:
        nonlocal calls
        calls += 1
        if calls == 3:
            return message(model=SONNET)
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == 0
    assert calls == 120
    assert not halt_file().exists()


def test_invalid_replies_do_not_count_toward_the_error_share(
    workspace: Callable[[int], list[str]],
) -> None:
    workspace(30)
    client = FakeClient(lambda kw: message("not json", model=kw["model"]))
    assert run_all(client) == 0
    assert len(client.calls) == 120
    assert not halt_file().exists()


def test_retries_do_not_count_toward_the_error_share(
    workspace: Callable[[int], list[str]],
) -> None:
    workspace(30)
    tried: set[tuple] = set()

    def handler(kwargs: dict) -> object:
        key = (cell_of(kwargs), kwargs["messages"][0]["content"][0]["source"]["data"])
        if key not in tried:  # every call fails once with 429, then succeeds
            tried.add(key)
            raise status_error(anthropic.RateLimitError, 429)
        return reply_for(kwargs)

    client = FakeClient(handler)
    assert run_all(client) == 0
    assert len(client.calls) == 240
    assert not halt_file().exists()
    record = json.loads(
        runner.raw_path(HAIKU, "p1", sampler.read_ids(config.SAMPLE_FILE)[0]).read_text()
    )
    assert [a["status"] for a in record["attempts"]] == [429, 200]


def test_error_share_of_exactly_5_percent_does_not_stop(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    calls = 0

    def handler(kwargs: dict) -> object:
        nonlocal calls
        calls += 1
        if calls == 3:  # 1 error in the first 20 calls is exactly 5%
            raise status_error(anthropic.BadRequestError, 400)
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == 0
    assert calls == 120


def test_stop_leaves_recorded_calls_in_place(workspace: Callable[[int], list[str]]) -> None:
    workspace(30)
    client = FakeClient(lambda kw: message(output_tokens=1_000_000))
    run_all(client)
    files = list((config.RAW_DIR / HAIKU / "p1").glob("*.json"))
    assert len(files) == len(client.calls)
    assert not list(Path(config.RAW_DIR).rglob("*.tmp"))


def test_lock_held_by_another_run_refuses_to_start(
    workspace: Callable[[int], list[str]], capsys: pytest.CaptureFixture[str]
) -> None:
    workspace(3)
    config.RAW_DIR.mkdir()
    lock_path = config.RAW_DIR / config.LOCK_FILE_NAME
    client = FakeClient()
    with open(lock_path, "a") as other:
        fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert run_all(client) == 2
    assert client.calls == []
    assert str(lock_path) in capsys.readouterr().out
    assert not (config.RAW_DIR / "run.json").exists()
    assert run_all(client) == 0  # released


def test_a_raw_file_that_appears_before_the_call_is_not_overwritten(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(3)
    target = runner.raw_path(HAIKU, "p1", ids[1])
    loads = {i: 0 for i in ids}
    image_bytes = data.image_bytes

    def load(dish_id: str, sleep: Callable[[float], None]) -> bytes:
        loads[dish_id] += 1
        if dish_id == ids[1] and loads[dish_id] == 2:  # after the prefetch, before the call
            data.atomic_write(target, b"recorded by someone else\n")
        return image_bytes(dish_id, sleep)

    monkeypatch.setattr(data, "image_bytes", load)
    client = FakeClient()
    assert run_all(client) == 0
    assert len(client.calls) == 11
    assert target.read_bytes() == b"recorded by someone else\n"


@pytest.mark.parametrize("name", ["p1.txt", "sample_ids.txt", "evaluation-protocol.md"])
def test_restart_refuses_when_an_experiment_file_changed(
    workspace: Callable[[int], list[str]], capsys: pytest.CaptureFixture[str], name: str
) -> None:
    workspace(3)
    assert run_all(FakeClient()) == 0
    paths = {
        "p1.txt": config.PROMPTS_DIR / "p1.txt",
        "sample_ids.txt": config.SAMPLE_FILE,
        "evaluation-protocol.md": config.PROTOCOL_FILE,
    }
    with paths[name].open("a") as f:
        f.write("\n")  # the sample ids stay the same, only the hash changes
    capsys.readouterr()

    client = FakeClient()
    assert run_all(client) == 2
    assert client.calls == []
    assert f"{name} changed since" in capsys.readouterr().out


def test_sample_that_differs_from_the_draw_is_refused(
    workspace: Callable[[int], list[str]], capsys: pytest.CaptureFixture[str]
) -> None:
    ids = workspace(3)
    other = "dish_999"
    path = config.CACHE_DIR / data.image_cache_name(other)
    path.write_bytes(png(tag=other))
    sampler.write_ids(config.SAMPLE_FILE, [*ids[:-1], other])

    client = FakeClient()
    assert run_all(client) == 2
    assert client.calls == []
    out = capsys.readouterr().out
    assert "differs from the draw" in out
    assert "2 ids differ" in out
    assert not (config.RAW_DIR / "run.json").exists()


SENTINEL = "SENTINEL-TEXT"
LEAK = 4321.25  # an estimate that must never be shown


def b64(image: bytes) -> str:
    return base64.b64encode(image).decode()


def serve_images(
    monkeypatch: pytest.MonkeyPatch, failing: dict[str, list] | None = None, log: list | None = None
) -> list[str]:
    """The bucket serves each dish's PNG. failing[dish_id] lists what the first requests get
    instead: an exception to raise or bytes to return. log gets the dish id of every request."""
    log = [] if log is None else log
    failing = failing or {}

    def get(url: str) -> bytes:
        dish_id = url.split("/")[-2]
        log.append(dish_id)
        if failing.get(dish_id):
            outcome = failing[dish_id].pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        return png(tag=dish_id)

    monkeypatch.setattr(data, "http_get", get)
    return log


def uncache_images() -> None:
    shutil.rmtree(config.CACHE_DIR / "images")


def records_of(dish_id: str) -> list[dict]:
    return [json.loads(runner.raw_path(m, p, dish_id).read_text()) for _, m, p in config.CELLS]


def sent_images(client: FakeClient) -> list[str]:
    return [c["messages"][0]["content"][0]["source"]["data"] for c in client.calls]


def test_every_image_is_downloaded_once_before_the_first_call(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(5)
    uncache_images()
    events: list[str] = []
    serve_images(monkeypatch, log=events)
    client = FakeClient(lambda kw: events.append("call") or reply_for(kw))
    assert run_all(client) == 0
    first_call = events.index("call")
    assert sorted(events[:first_call]) == sorted(ids)
    assert events[first_call:] == ["call"] * 20  # no download after the first call


def test_image_download_retries_429_and_5xx_like_an_api_call(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(3)
    uncache_images()
    failing = {
        ids[0]: [
            http_error(429, {"retry-after": "7"}),
            http_error(503),
            http_error(500, {"retry-after": "900"}),
        ]
    }
    log = serve_images(monkeypatch, failing)
    sleeps: list[float] = []
    client = FakeClient()
    assert run_all(client, sleep=sleeps.append) == 0
    assert sleeps == [7, 4, 60]  # retry-after replaces the wait, capped at 60; else 2, 4, ...
    assert log.count(ids[0]) == 4
    assert len(client.calls) == 12
    assert all(r["error"] is None for r in records_of(ids[0]))


def test_a_failed_download_gives_the_dish_an_error_record_in_all_four_cells(
    workspace: Callable[[int], list[str]],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    ids = workspace(30)
    bad = ids[3]
    uncache_images()
    log = serve_images(monkeypatch, {bad: [http_error(503)] * 7})
    sleeps: list[float] = []
    client = FakeClient()
    assert run_all(client, sleep=sleeps.append) == 0  # 1 of 30 is below 5%
    assert sleeps == [2, 4, 8, 16, 32]
    assert log.count(bad) == 6  # the first try and five retries
    assert len(client.calls) == 4 * 29
    assert b64(png(tag=bad)) not in sent_images(client)
    for record in records_of(bad):
        assert record["error"] == {
            "type": "ImageUnavailable",
            "status": 503,
            "request_id": None,
            "message": "download failed: HTTP Error 503: status 503",
        }
        assert set(record) == set(RECORD_KEYS.split())
        assert record["response"] is None and record["request"] is None
        assert record["attempts"] == [] and record["image_sha256"] is None
        outcome = classify(record)
        assert (outcome.status, outcome.reason) == ("error", "ImageUnavailable")
    assert "images: 29 usable, 1 unavailable" in capsys.readouterr().out
    assert not halt_file().exists()


@pytest.mark.parametrize("case", ["404", "connection", "not_png"])
def test_other_download_problems_are_not_retried_and_are_truncated(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch, case: str
) -> None:
    ids = workspace(30)
    bad = ids[3]
    uncache_images()
    outcome = {
        "404": http_error(404),
        "connection": urllib.error.URLError("x" * 800),
        "not_png": b"<html>not an image</html>",
    }[case]
    log = serve_images(monkeypatch, {bad: [outcome, png(tag=bad)]})
    sleeps: list[float] = []
    client = FakeClient()
    assert run_all(client, sleep=sleeps.append) == 0
    assert sleeps == []
    assert log.count(bad) == 1
    assert b64(png(tag=bad)) not in sent_images(client)
    error = records_of(bad)[0]["error"]
    assert error["type"] == "ImageUnavailable"
    assert error["status"] == (404 if case == "404" else None)
    if case == "connection":
        assert error["message"].startswith("download failed with URLError: <urlopen error xxx")
        assert len(error["message"]) == 500
    if case == "not_png":
        assert error["message"].startswith("expected a PNG file")
        assert not (config.CACHE_DIR / data.image_cache_name(bad)).exists()
    assert all(r["error"] == error for r in records_of(bad))


def test_a_cached_file_that_is_not_a_png_is_deleted_and_gives_an_error_record(
    workspace: Callable[[int], list[str]],
) -> None:
    ids = workspace(30)
    bad = ids[3]
    path = config.CACHE_DIR / data.image_cache_name(bad)
    path.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 40)  # a JPEG; no download is possible
    client = FakeClient()
    assert run_all(client) == 0
    assert not path.exists()
    assert len(client.calls) == 4 * 29
    assert [r["error"]["type"] for r in records_of(bad)] == ["ImageUnavailable"] * 4


def test_a_png_of_another_size_is_sent_as_it_is_and_its_size_is_recorded(
    workspace: Callable[[int], list[str]],
) -> None:
    ids = workspace(3)
    odd = png(1024, 768, tag="odd")
    (config.CACHE_DIR / data.image_cache_name(ids[1])).write_bytes(odd)
    client = FakeClient()
    assert run_all(client) == 0
    assert sent_images(client).count(b64(odd)) == 4
    for record in records_of(ids[1]):
        assert record["error"] is None
        assert (record["image_width"], record["image_height"]) == (1024, 768)
        assert record["image_sha256"] == hashlib.sha256(odd).hexdigest()


def test_image_errors_count_in_the_error_share_and_make_no_api_call(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    uncache_images()
    serve_images(monkeypatch, {d: [http_error(404)] for d in ids[:2]})
    client = FakeClient()
    assert run_all(client) == config.EXIT_STOP
    assert len(client.calls) == 18  # 20 completed calls, 2 of them image errors: 10%
    text = halt_file().read_text()
    assert "rule: error_share\n" in text
    assert "cell haiku/p1: error 2, refusal 0 and substituted 0 in 20 completed calls" in text
    assert "records: ok 18, invalid 0, error 2, refusal 0, substituted 0\n" in text


def test_an_image_error_is_never_repeated_and_holds_in_all_four_cells(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    bad = ids[3]
    uncache_images()
    serve_images(monkeypatch, {bad: [http_error(503)] * 7})

    def handler(kwargs: dict) -> object:  # haiku p1 overruns: the run pauses after its 20th dish
        if cell_of(kwargs) == (HAIKU, "p1"):
            return message(input_tokens=5000, model=kwargs["model"])
        return reply_for(kwargs)

    first = FakeClient(handler)
    assert run_all(first) == config.EXIT_PAUSE
    assert runner.raw_path(HAIKU, "p1", bad).exists()
    assert not runner.raw_path(HAIKU, "p2", bad).exists()

    log = serve_images(monkeypatch)  # the bucket works again, the decision stands
    second = FakeClient(handler)
    assert run_all(second, ack_halt=True) == 0
    assert log == []
    for record in records_of(bad):
        assert (record["error"]["type"], record["error"]["status"]) == ("ImageUnavailable", 503)
    assert len(first.calls) + len(second.calls) == 4 * 29
    assert b64(png(tag=bad)) not in sent_images(first) + sent_images(second)


def overrun_reply(kwargs: dict) -> object:
    return message(f"{SENTINEL} {LEAK}", input_tokens=5000, model=kwargs["model"])


def error_reply(kwargs: dict) -> object:
    body = {"error": {"message": SENTINEL}}
    raise status_error(anthropic.BadRequestError, 400, message=f"{SENTINEL} {LEAK}", body=body)


def costly_reply(kwargs: dict) -> object:
    return message(f'{{"total_kcal": {LEAK}}}', output_tokens=1_000_000, model=kwargs["model"])


HALT_SCENARIOS = {
    "overrun": (overrun_reply, config.EXIT_PAUSE, "token_overrun"),
    "errors": (error_reply, config.EXIT_STOP, "error_share"),
    "cost": (costly_reply, config.EXIT_STOP, "cost"),
    "images": (reply_for, config.EXIT_STOP, "error_share"),
}


@pytest.mark.parametrize("scenario", HALT_SCENARIOS)
def test_halt_marker_and_output_show_only_counts_tokens_cost_rule_and_exit_code(
    workspace: Callable[[int], list[str]],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    scenario: str,
) -> None:
    ids = workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    handler, code, rule = HALT_SCENARIOS[scenario]
    if scenario == "images":  # two dishes whose download fails with texts that must stay hidden
        uncache_images()
        failing = {
            ids[0]: [urllib.error.URLError(SENTINEL)],
            ids[1]: [urllib.error.URLError(f"{SENTINEL} {LEAK}")],
        }
        serve_images(monkeypatch, failing)

    assert run_all(FakeClient(handler)) == code
    shown = capsys.readouterr()
    marker = halt_file().read_text()
    assert f"rule: {rule}\n" in marker and f"exit_code: {code}\n" in marker
    keys = {line.split(":")[0] for line in marker.splitlines()}
    assert keys == {"rule", "exit_code", "detail", "records", "cost_usd", "utc"}
    stored = " ".join(p.read_text() for p in config.RAW_DIR.rglob("*.json"))
    assert SENTINEL in stored or str(LEAK) in stored  # the raw records do keep it
    for text in (marker, shown.out, shown.err):
        assert SENTINEL not in text
        assert str(LEAK) not in text


def dish_log(ids: list[str]) -> tuple[Callable[[dict], object], list[tuple[str, str, str]]]:
    """A handler that logs (model, prompt, dish) of each call. Each cached image is unique."""
    dish_of = {b64(png(tag=i)): i for i in ids}
    calls: list[tuple[str, str, str]] = []

    def handler(kwargs: dict) -> object:
        image = kwargs["messages"][0]["content"][0]["source"]["data"]
        calls.append((*cell_of(kwargs), dish_of[image]))
        if cell_of(kwargs) == (HAIKU, "p1"):  # overruns, so the run pauses after the 20th dish
            return message(input_tokens=5000, model=kwargs["model"])
        return reply_for(kwargs)

    return handler, calls


def test_run_resumes_in_the_same_order_and_never_calls_a_recorded_dish(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    handler, calls = dish_log(ids)
    assert run_all(FakeClient(handler)) == config.EXIT_PAUSE
    assert calls == [(HAIKU, "p1", d) for d in ids[:20]]

    calls.clear()
    assert run_all(FakeClient(handler), ack_halt=True) == 0
    rest = [(m, p, d) for _, m, p in config.CELLS[1:] for d in ids]
    assert calls == [(HAIKU, "p1", d) for d in ids[20:]] + rest
    assert len(set(calls)) == len(calls) == 120 - 20  # no dish is called twice


def test_a_dish_with_a_record_is_skipped_wherever_it_lies_in_the_cell(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = workspace(6)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 1)
    assert run_all(FakeClient()) == 0
    for dish_id in (ids[1], ids[4]):  # lost records are the only ones called again
        runner.raw_path(SONNET, "p1", dish_id).unlink()
    handler, calls = dish_log(ids)
    assert run_all(FakeClient(handler)) == 0
    assert calls == [(SONNET, "p1", ids[1]), (SONNET, "p1", ids[4])]


def test_a_cell_finishes_before_the_next_one_starts_with_several_workers(
    workspace: Callable[[int], list[str]],
) -> None:
    workspace(30)
    order = {(model, prompt): i for i, (_, model, prompt) in enumerate(config.CELLS)}
    started: list[int] = []

    def handler(kwargs: dict) -> object:
        started.append(order[cell_of(kwargs)])
        return reply_for(kwargs)

    assert run_all(FakeClient(handler)) == 0
    assert started == sorted(started)
    assert [started.count(i) for i in range(4)] == [30] * 4


def test_cli_run_takes_ack_halt(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: list[bool] = []
    monkeypatch.setattr(anthropic, "Anthropic", lambda **kwargs: object())
    monkeypatch.setattr(runner, "run", lambda client, ack_halt: seen.append(ack_halt) or 0)
    assert cli.main(["run", "--ack-halt"]) == 0
    assert cli.main(["run"]) == 0
    assert seen == [True, False]
    with pytest.raises(SystemExit):
        cli.main(["run", "--ack-pause"])


def test_calls_in_flight_when_the_cost_stop_is_decided_finish_and_are_recorded(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    workspace(30)
    monkeypatch.setattr(config, "WORKERS_PER_CELL", 2)
    lock = threading.Lock()
    started = 0

    def handler(kwargs: dict) -> object:
        nonlocal started
        with lock:
            started += 1
            number = started
        if number == 1:  # in flight until the second call has decided the stop
            deadline = time.monotonic() + 5
            while not halt_file().exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            assert halt_file().exists()
            return message()
        return message(output_tokens=8_000_000)  # 4 USD on haiku

    client = FakeClient(handler)
    assert run_all(client) == config.EXIT_STOP
    assert len(client.calls) == 2  # nothing starts after the stop
    assert len(list((config.RAW_DIR / HAIKU / "p1").glob("*.json"))) == 2  # both recorded


def test_a_record_without_usage_costs_nothing_and_does_not_crash_the_run(
    workspace: Callable[[int], list[str]], capsys: pytest.CaptureFixture[str]
) -> None:
    ids = workspace(3)
    assert run_all(FakeClient()) == 0
    assert "total cost 0.0076 USD" in capsys.readouterr().out  # 6 x 6e-5 + 6 x 1.2e-3
    path = runner.raw_path(SONNET, "p1", ids[0])
    record = json.loads(path.read_text())
    del record["response"]["usage"]
    path.write_text(json.dumps(record))
    again = FakeClient()
    assert run_all(again) == 0
    assert again.calls == []
    assert "total cost 0.0064 USD" in capsys.readouterr().out  # 1.2e-3 less


def test_retry_after_on_a_5xx_replaces_the_scheduled_wait() -> None:
    client = scripted(
        [
            status_error(anthropic.InternalServerError, 503, {"retry-after": "3"}),
            status_error(anthropic.InternalServerError, 500, {"retry-after": "61"}),
            message(),
        ]
    )
    record, sleeps = record_for(client)
    assert sleeps == [3, 60]
    assert [a["retry_after"] for a in record["attempts"]] == [3.0, 61.0, None]


# The stop rules, on a Guard fed with records directly.

LABEL = "haiku/p1"
GUARD_IDS = [f"dish_{i:03d}" for i in range(40)]
STATUS_REPLY = {
    "ok": ('{"total_kcal": 100}', "end_turn"),
    "invalid": ("not json", "end_turn"),
    "refusal": ("", "refusal"),
    "substituted": ('{"total_kcal": 100}', "end_turn"),  # a valid reply, from the other model
}


def guard_record(
    dish_id: str, status: str = "ok", tokens: int = 520, usage: tuple[int, int] | None = None
) -> dict:
    """A record of the given status; tokens is input + output, usage overrides both."""
    record = runner.new_record(HAIKU, PROMPT, dish_id)
    if status == "error":
        record["error"] = {"type": "BadRequestError", "status": 400, "message": "x"}
        return record
    text, stop_reason = STATUS_REPLY[status]
    tokens_in, tokens_out = usage or (tokens - 20, 20)
    model = SONNET if status == "substituted" else HAIKU
    reply = message(
        text, stop_reason=stop_reason, input_tokens=tokens_in, output_tokens=tokens_out, model=model
    )
    record["response"] = reply.model_dump(mode="json")
    return record


def new_guard(tmp_path: Path) -> runner.Guard:
    return runner.Guard(tuple(GUARD_IDS[:20]), {LABEL: 536}, tmp_path / "HALTED.txt")


def add(
    guard: runner.Guard,
    dish_id: str,
    status: str = "ok",
    tokens: int = 520,
    usage: tuple[int, int] | None = None,
    live: bool = True,
) -> None:
    guard.add(LABEL, HAIKU, dish_id, guard_record(dish_id, status, tokens, usage), live=live)


def test_rule_2_looks_at_the_first_20_dishes_in_sample_order_not_the_first_completions(
    tmp_path: Path,
) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[20:]:  # later dishes finish first and are huge: they do not count
        add(guard, dish_id, tokens=9000)
    for dish_id in reversed(GUARD_IDS[:20]):  # the first 20, last to first, with normal tokens
        add(guard, dish_id)
    assert guard.stop is None

    guard = new_guard(tmp_path)
    shuffled = GUARD_IDS[:20][::3] + GUARD_IDS[:20][1::3] + GUARD_IDS[:20][2::3]
    for dish_id in GUARD_IDS[20:30]:  # ten later dishes are recorded before any of the first 20
        add(guard, dish_id)
    for dish_id in shuffled[:-1]:
        add(guard, dish_id, tokens=1000)
        assert guard.stop is None  # not before records exist for all 20
    add(guard, shuffled[-1], tokens=1000)
    stop = guard.stop
    assert (stop.rule, stop.exit_code) == ("token_overrun", config.EXIT_PAUSE)
    assert "mean 1000.0 tokens per call" in stop.detail and "above 804.0" in stop.detail


def test_rule_2_mean_is_over_the_dishes_of_the_first_20_that_have_a_response(
    tmp_path: Path,
) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[1:20]:
        add(guard, dish_id, tokens=820)
    add(guard, GUARD_IDS[0], "error")  # 1 of 20 is exactly 5%: no error share stop
    # 19 responses at 820 give 820 > 804; counting the error as 0 would give 779.
    assert guard.stop is not None and guard.stop.rule == "token_overrun"
    assert "mean 820.0 tokens" in guard.stop.detail


def test_rule_2_threshold_is_inclusive_and_records_of_earlier_invocations_count(
    tmp_path: Path,
) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:20]:
        add(guard, dish_id, tokens=804)  # exactly 1.5 x 536
    assert guard.stop is None

    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:12]:
        add(guard, dish_id, tokens=1000, live=False)
    assert guard.stop is None  # earlier records alone decide nothing
    for dish_id in GUARD_IDS[12:19]:
        add(guard, dish_id, tokens=1000)
    assert guard.stop is None
    add(guard, GUARD_IDS[19], tokens=1000)
    assert guard.stop is not None and guard.stop.rule == "token_overrun"


def test_rule_2_does_not_fire_again_when_the_first_20_were_recorded_by_an_earlier_invocation(
    tmp_path: Path,
) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:20]:
        add(guard, dish_id, tokens=5000, live=False)
    for dish_id in GUARD_IDS[20:]:
        add(guard, dish_id, tokens=5000)
    assert guard.stop is None


def test_rule_2_marker_is_written_with_the_pause(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:20]:
        add(guard, dish_id, tokens=1000)
    text = (tmp_path / "HALTED.txt").read_text()
    assert "rule: token_overrun\nexit_code: 3\n" in text
    assert "records: ok 20, invalid 0, error 0, refusal 0, substituted 0\n" in text


def test_rule_3_needs_20_completed_calls_in_the_cell(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:10]:
        add(guard, dish_id, "error")  # 100% of 10 completed calls
    assert guard.stop is None
    for dish_id in GUARD_IDS[10:19]:
        add(guard, dish_id)
    assert guard.stop is None  # 19 completed
    add(guard, GUARD_IDS[19])
    assert guard.stop is not None and guard.stop.rule == "error_share"
    assert guard.stop.exit_code == config.EXIT_STOP
    assert "error 10, refusal 0 and substituted 0 in 20 completed calls" in guard.stop.detail


def test_rule_3_is_above_5_percent_and_counts_errors_and_refusals_only(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    add(guard, GUARD_IDS[0], "error")
    for dish_id in GUARD_IDS[1:20]:
        add(guard, dish_id)
    assert guard.stop is None  # 1 of 20 is 5%, not above
    add(guard, GUARD_IDS[20], "refusal")  # 2 of 21
    assert guard.stop is not None and guard.stop.rule == "error_share"

    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:30]:
        add(guard, dish_id, "invalid")  # invalid does not count
    assert guard.stop is None


def test_rule_3_counts_substituted_with_errors_and_refusals(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    add(guard, GUARD_IDS[0], "substituted")
    for dish_id in GUARD_IDS[1:20]:
        add(guard, dish_id)
    assert guard.stop is None  # 1 of 20 is 5%, not above
    add(guard, GUARD_IDS[20], "substituted")  # 2 of 21
    assert guard.stop is not None and guard.stop.rule == "error_share"
    assert guard.stop.exit_code == config.EXIT_STOP
    assert "error 0, refusal 0 and substituted 2 in 21 completed calls" in guard.stop.detail

    guard = new_guard(tmp_path)
    statuses = ["error", "refusal", "substituted"] + ["ok"] * 17  # 3 of 20, one of each
    for dish_id, status in zip(GUARD_IDS[:20], statuses, strict=True):
        add(guard, dish_id, status)
    assert guard.stop is not None and guard.stop.rule == "error_share"
    assert "error 1, refusal 1 and substituted 1 in 20 completed calls" in guard.stop.detail
    assert (
        "records: ok 17, invalid 0, error 1, refusal 1, substituted 1\n"
        in (tmp_path / "HALTED.txt").read_text()
    )


def test_a_substituted_call_is_costed_and_counts_in_rule_2_like_any_call_with_a_response(
    tmp_path: Path,
) -> None:
    guard = new_guard(tmp_path)
    add(guard, GUARD_IDS[0], "substituted", usage=(1_000_000, 0))
    assert guard.cost == pytest.approx(0.10)  # priced from usage at the requested model's rate
    assert guard.cells[LABEL].status[GUARD_IDS[0]] == "substituted"
    assert guard.cells[LABEL].tokens[GUARD_IDS[0]] == 1_000_000

    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:19]:
        add(guard, dish_id, tokens=800)
    assert guard.stop is None
    add(guard, GUARD_IDS[19], "substituted", tokens=1200)  # mean 820 is above 804; 800 is not
    assert guard.stop is not None and guard.stop.rule == "token_overrun"
    assert "mean 820.0 tokens" in guard.stop.detail


def test_rule_3_counts_each_dish_once_and_includes_earlier_invocations(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:19]:
        add(guard, dish_id, "error", live=False)
    add(guard, GUARD_IDS[18], "error")  # the same dish again is not a 20th completed call
    assert guard.stop is None
    add(guard, GUARD_IDS[19], "error")
    assert guard.stop is not None and guard.stop.rule == "error_share"

    guard = new_guard(tmp_path)
    add(guard, GUARD_IDS[0], "error", live=False)
    for dish_id in GUARD_IDS[1:19]:
        add(guard, dish_id, live=False)
    add(guard, GUARD_IDS[19])  # 1 error of 20 completed, earlier ones included
    assert guard.stop is None
    guard = new_guard(tmp_path)
    for dish_id in GUARD_IDS[:2]:
        add(guard, dish_id, "error", live=False)
    for dish_id in GUARD_IDS[2:19]:
        add(guard, dish_id, live=False)
    add(guard, GUARD_IDS[19])  # 2 of 20
    assert guard.stop is not None and guard.stop.rule == "error_share"


def test_rule_3_is_per_cell(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    for label in ("haiku/p1", "haiku/p2"):
        for dish_id in GUARD_IDS[:10]:
            guard.add(label, HAIKU, dish_id, guard_record(dish_id, "error"))
    assert guard.stop is None  # 20 errors in all, but 10 completed calls in each cell


def test_cost_stops_above_3_50_and_a_record_without_usage_costs_nothing(tmp_path: Path) -> None:
    guard = new_guard(tmp_path)
    half_dollar = (0, 1_000_000)  # 1,000,000 output tokens are 0.50 USD on haiku
    for dish_id in GUARD_IDS[:4]:
        add(guard, dish_id, usage=half_dollar, live=False)  # earlier invocations count
    for dish_id in GUARD_IDS[4:7]:
        add(guard, dish_id, usage=half_dollar)
    assert guard.cost == 3.5 and guard.stop is None  # exactly 3.50 is not above
    bare = guard_record(GUARD_IDS[7])
    del bare["response"]["usage"]
    guard.add(LABEL, HAIKU, GUARD_IDS[7], bare)
    assert guard.cost == 3.5 and guard.stop is None
    add(guard, GUARD_IDS[8], usage=half_dollar)
    assert guard.stop is not None and guard.stop.rule == "cost"
    assert guard.stop.exit_code == config.EXIT_STOP
    text = (tmp_path / "HALTED.txt").read_text()
    assert "cost_usd: 4.0000\n" in text
    assert "records: ok 9, invalid 0, error 0, refusal 0, substituted 0\n" in text
