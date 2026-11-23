"""Strict validation of model replies, and the one place that derives a call's status."""

import json
import re
from dataclasses import dataclass

ITEM_KEYS = {"name", "grams", "kcal"}
FENCE_OPEN = re.compile(r"```\w*")  # three backticks and an optional language word
MAX_ITEMS = 20


class InvalidResponse(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def response_text(content: list[dict]) -> str:
    return "".join(b["text"] for b in content if b["type"] == "text").strip()


def unfence(text: str) -> str:
    """Remove exactly one surrounding Markdown code fence, nothing else."""
    lines = text.split("\n")
    if len(lines) >= 3 and FENCE_OPEN.fullmatch(lines[0]) and lines[-1] == "```":
        return "\n".join(lines[1:-1])
    return text


def reject_constant(name: str) -> float:
    raise ValueError(f"JSON constant {name} is not allowed")


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    obj = dict(pairs)
    if len(obj) != len(pairs):
        raise ValueError("duplicate key in a JSON object")
    return obj


def number(value: object, low: float, high: float) -> float:
    # 1e999 is a valid literal that parses to infinity; the range test rejects it.
    if isinstance(value, bool) or not isinstance(value, int | float) or not low <= value <= high:
        raise InvalidResponse("bad_value")
    return float(value)


def parse_p1(obj: dict) -> float:
    if set(obj) != {"total_kcal"}:
        raise InvalidResponse("wrong_keys")
    return number(obj["total_kcal"], 0, 5000)


def parse_p2(obj: dict) -> float:
    if set(obj) != {"items"}:
        raise InvalidResponse("wrong_keys")
    items = obj["items"]
    if not isinstance(items, list):
        raise InvalidResponse("bad_value")
    if len(items) > MAX_ITEMS:
        raise InvalidResponse("too_many_items")
    total = 0.0
    for item in items:
        if not isinstance(item, dict) or set(item) != ITEM_KEYS:
            raise InvalidResponse("wrong_keys")
        name = item["name"]
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
            raise InvalidResponse("bad_value")
        number(item["grams"], 1, 2000)
        total += number(item["kcal"], 0, 5000)
    return total


PARSERS = {"p1": parse_p1, "p2": parse_p2}


def parse_prediction(prompt_id: str, text: str) -> float:
    """Return the predicted total kcal, or raise InvalidResponse with a reason code."""
    if not text:
        raise InvalidResponse("empty_text")
    try:
        obj = json.loads(
            unfence(text), object_pairs_hook=reject_duplicate_keys, parse_constant=reject_constant
        )
    except ValueError as e:  # includes JSONDecodeError and oversized integer literals
        raise InvalidResponse("not_json") from e
    if not isinstance(obj, dict):
        raise InvalidResponse("not_object")
    return PARSERS[prompt_id](obj)


@dataclass(frozen=True)
class Outcome:
    status: str  # ok, invalid, error, refusal, substituted
    reason: str  # empty for ok
    pred_kcal: float | None


def classify(record: dict) -> Outcome:
    """Derive the status of one raw call record. Runner and scorer both use this."""
    if record["error"] is not None:
        return Outcome("error", record["error"]["type"], None)
    response = record["response"]
    # The run requests no fallback, so another model's answer is not a measurement of this one.
    # A response may carry the same id followed by a hyphen and eight digits.
    if re.sub(r"-\d{8}$", "", response["model"]) != record["model"]:
        return Outcome("substituted", "model_mismatch", None)
    if response["stop_reason"] == "refusal":
        return Outcome("refusal", "refusal", None)
    if response["stop_reason"] == "max_tokens":
        return Outcome("invalid", "max_tokens", None)
    try:
        pred = parse_prediction(record["prompt_id"], response_text(response["content"]))
    except InvalidResponse as e:
        return Outcome("invalid", e.reason, None)
    return Outcome("ok", "", pred)


def usage_tokens(record: dict) -> tuple[int, int]:
    """Input and output tokens billed for the call; (0, 0) without a response or a usage field."""
    usage = (record["response"] or {}).get("usage") or {}
    return usage.get("input_tokens") or 0, usage.get("output_tokens") or 0
