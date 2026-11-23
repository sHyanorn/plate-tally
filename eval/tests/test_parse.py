import json

import pytest
from fakes import message

from plate_eval.parse import InvalidResponse, classify, parse_prediction, usage_tokens

ITEM = {"name": "rice", "grams": 100, "kcal": 130}
HAIKU = "claude-haiku-5-5"
SONNET = "claude-sonnet-5-5"


def p2(items: list) -> str:
    return json.dumps({"items": items})


def reason(prompt_id: str, text: str) -> str:
    with pytest.raises(InvalidResponse) as e:
        parse_prediction(prompt_id, text)
    return e.value.reason


def test_valid_p1_and_p2() -> None:
    assert parse_prediction("p1", '{"total_kcal": 412.5}') == 412.5
    assert parse_prediction("p1", '{"total_kcal": 0}') == 0.0
    assert parse_prediction("p1", '{"total_kcal": 5000}') == 5000.0
    two_items = p2([ITEM, {"name": " peas ", "grams": 50.5, "kcal": 40.25}])
    assert parse_prediction("p2", two_items) == 170.25
    assert parse_prediction("p2", p2([])) == 0.0
    assert parse_prediction("p2", p2([ITEM] * 20)) == 2600.0


@pytest.mark.parametrize("fence", ["```", "```json", "```JSON", "```python", "```json5"])
def test_one_surrounding_fence_is_accepted_with_or_without_a_language_word(fence: str) -> None:
    assert parse_prediction("p1", f'{fence}\n{{"total_kcal": 7}}\n```') == 7.0
    assert parse_prediction("p2", f"{fence}\n{p2([ITEM])}\n```") == 130.0
    padded = reply(f'\n  {fence}\n{{"total_kcal": 7}}\n``` \n\n')  # stripped before the fence test
    assert classify(record(padded)).pred_kcal == 7.0


@pytest.mark.parametrize(
    "text",
    [
        '``` json\n{"total_kcal": 7}\n```',  # a space is not a language word
        '````\n{"total_kcal": 7}\n```',
        '~~~\n{"total_kcal": 7}\n~~~',
        '```json\n{"total_kcal": 7}',
        '{"total_kcal": 7}\n```',
        '```json {"total_kcal": 7} ```',
        "```\n```",
    ],
)
def test_other_wrappers_are_not_removed(text: str) -> None:
    assert reason("p1", text) == "not_json"


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ('Here you go: {"total_kcal": 7}', "not_json"),
        ('{"total_kcal": 7} Hope this helps.', "not_json"),
        ('{"total_kcal": 7}\n{"total_kcal": 8}', "not_json"),
        ('```json\n{"total_kcal": 7}\n```\n```json\n{"total_kcal": 8}\n```', "not_json"),
        ("about 300 kcal", "not_json"),
        ('{"total_kcal": 7', "not_json"),
        ("", "empty_text"),
        ("[1, 2]", "not_object"),
        ('"text"', "not_object"),
        ("{}", "wrong_keys"),
        ('{"kcal": 7}', "wrong_keys"),
        ('{"total_kcal": 7, "note": "x"}', "wrong_keys"),
        ('{"total_kcal": true}', "bad_value"),
        ('{"total_kcal": "7"}', "bad_value"),
        ('{"total_kcal": null}', "bad_value"),
        ('{"total_kcal": NaN}', "not_json"),
        ('{"total_kcal": Infinity}', "not_json"),
        ('{"total_kcal": -Infinity}', "not_json"),
        ('{"total_kcal": 7, "total_kcal": 8}', "not_json"),
        ('{"total_kcal": 7, "total_kcal": 7}', "not_json"),
        ('```json\n{"total_kcal": 7, "total_kcal": 8}\n```', "not_json"),
        ('{"total_kcal": 1e999}', "bad_value"),
        ('{"total_kcal": -1}', "bad_value"),
        ('{"total_kcal": 5000.5}', "bad_value"),
    ],
)
def test_p1_rejections(text: str, expected: str) -> None:
    assert reason("p1", text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        (p2([ITEM] * 21), "too_many_items"),
        (json.dumps({"items": "rice"}), "bad_value"),
        (json.dumps({"items": [], "total": 1}), "wrong_keys"),
        (json.dumps({"item": []}), "wrong_keys"),
        (p2(["rice"]), "wrong_keys"),
        (p2([{"name": "rice", "grams": 100}]), "wrong_keys"),
        (p2([{**ITEM, "note": "x"}]), "wrong_keys"),
        (p2([{**ITEM, "name": ""}]), "bad_value"),
        (p2([{**ITEM, "name": "   "}]), "bad_value"),
        (p2([{**ITEM, "name": "x" * 101}]), "bad_value"),
        (p2([{**ITEM, "name": 5}]), "bad_value"),
        (p2([{**ITEM, "grams": 0.5}]), "bad_value"),
        (p2([{**ITEM, "grams": 2500}]), "bad_value"),
        (p2([{**ITEM, "grams": True}]), "bad_value"),
        (p2([{**ITEM, "kcal": -1}]), "bad_value"),
        (p2([{**ITEM, "kcal": 5001}]), "bad_value"),
        (p2([{**ITEM, "kcal": False}]), "bad_value"),
        ('{"items": [{"name": "a", "grams": 5, "kcal": NaN}]}', "not_json"),
        ('{"items": [{"name": "a", "grams": 5, "kcal": Infinity}]}', "not_json"),
        ('{"items": [{"name": "a", "grams": 5, "kcal": -Infinity}]}', "not_json"),
        ('{"items": [], "items": []}', "not_json"),
        ('{"items": [{"name": "a", "name": "b", "grams": 5, "kcal": 5}]}', "not_json"),
        ('{"items": [{"name": "a", "grams": 5, "kcal": 1e999}]}', "bad_value"),
        ('{"items": [{"name": "rice", "grams": 100, "kcal": 130}', "not_json"),
    ],
)
def test_p2_rejections(text: str, expected: str) -> None:
    assert reason("p2", text) == expected


def test_p2_name_of_100_characters_after_stripping_is_valid() -> None:
    assert parse_prediction("p2", p2([{**ITEM, "name": " " + "x" * 100 + " "}])) == 130.0


def record(
    response: dict | None,
    error: dict | None = None,
    prompt_id: str = "p1",
    model: str = HAIKU,
) -> dict:
    return {"model": model, "prompt_id": prompt_id, "response": response, "error": error}


def reply(text: str = '{"total_kcal": 100}', **kwargs: object) -> dict:
    return message(text, **kwargs).model_dump(mode="json")


def test_classify_statuses() -> None:
    ok = classify(record(reply()))
    assert (ok.status, ok.reason, ok.pred_kcal) == ("ok", "", 100.0)

    bad = classify(record(reply("sure, about 100")))
    assert (bad.status, bad.reason, bad.pred_kcal) == ("invalid", "not_json", None)

    wrong = classify(record(reply('{"items": []}'), prompt_id="p1"))
    assert (wrong.status, wrong.reason) == ("invalid", "wrong_keys")

    refusal = classify(record(reply("", stop_reason="refusal")))
    assert (refusal.status, refusal.reason) == ("refusal", "refusal")

    error = classify(record(None, {"type": "BadRequestError", "status": 400, "message": "x"}))
    assert (error.status, error.reason) == ("error", "BadRequestError")


def test_classify_substituted_when_the_response_names_another_model() -> None:
    assert classify(record(reply(), model=HAIKU)).status == "ok"
    out = classify(record(reply(model=SONNET)))  # the text is a valid reply, and still not scored
    assert (out.status, out.reason, out.pred_kcal) == ("substituted", "model_mismatch", None)
    assert classify(record(reply(model=HAIKU), model=SONNET)).status == "substituted"
    # Only a date suffix is ignored: another case or padding is another string.
    for named in ("Claude-Haiku-5-5", " claude-haiku-5-5", "claude-haiku-5-5 "):
        assert classify(record(reply(model=named))).status == "substituted"


def test_classify_accepts_the_dated_form_of_the_requested_id() -> None:
    out = classify(record(reply(model="claude-haiku-5-5-20261001")))
    assert (out.status, out.pred_kcal) == ("ok", 100.0)
    dated = classify(record(reply(model="claude-sonnet-5-5-20260101"), model=SONNET))
    assert dated.status == "ok"


def test_classify_dated_form_does_not_make_another_id_the_same() -> None:
    # sonnet-5 is not sonnet-5-5, dated or not.
    for named in ("claude-sonnet-5", "claude-sonnet-5-20260101"):
        out = classify(record(reply(model=named), model=SONNET))
        assert (out.status, out.reason) == ("substituted", "model_mismatch")
    # The suffix is exactly eight digits.
    for suffix in ("2026100", "202610011", "2026"):
        assert classify(record(reply(model=f"{HAIKU}-{suffix}"))).status == "substituted"
    twice = classify(record(reply(model=f"{HAIKU}-20261001-20261001")))
    assert twice.status == "substituted"  # only one trailing suffix is removed


def test_classify_substituted_comes_before_the_refusal_and_parse_checks() -> None:
    for kwargs in ({"stop_reason": "refusal"}, {"stop_reason": "max_tokens"}):
        assert classify(record(reply("", model=SONNET, **kwargs))).status == "substituted"
    assert classify(record(reply("sure, about 100", model=SONNET))).status == "substituted"
    assert classify(record(reply("", model=SONNET))).status == "substituted"
    error = {"type": "BadRequestError", "status": 400, "message": "x"}
    assert classify(record(None, error)).status == "error"  # an error has no response to compare


def test_classify_max_tokens_is_invalid_even_if_the_text_parses() -> None:
    out = classify(record(reply(stop_reason="max_tokens")))
    assert (out.status, out.reason) == ("invalid", "max_tokens")
    fenced = reply('```json\n{"total_kcal": 100}\n```', stop_reason="max_tokens")
    assert classify(record(fenced)).status == "invalid"


def test_classify_empty_items_list_is_ok_with_total_zero() -> None:
    out = classify(record(reply('{"items": []}'), prompt_id="p2"))
    assert (out.status, out.reason, out.pred_kcal) == ("ok", "", 0.0)
    fenced = classify(record(reply('```json\n{"items": []}\n```'), prompt_id="p2"))
    assert (fenced.status, fenced.pred_kcal) == ("ok", 0.0)


def test_classify_response_without_text_block_is_empty_text() -> None:
    out = classify(record(reply("")))
    assert (out.status, out.reason) == ("invalid", "empty_text")


def blocks(*texts: str) -> dict:
    response = reply()
    response["content"] = [
        {"type": "thinking", "thinking": "hmm", "signature": "s"},
        *({"type": "text", "text": t} for t in texts),
    ]
    return response


def test_classify_ignores_non_text_blocks_and_joins_text_blocks() -> None:
    out = classify(record(blocks('{"total_kcal":', " 55}")))
    assert (out.status, out.pred_kcal) == ("ok", 55.0)


def test_text_blocks_are_joined_with_no_separator() -> None:
    assert classify(record(blocks('{"total_kcal": 5', "5}"))).pred_kcal == 55.0  # not "5 5"
    split_fence = classify(record(blocks("```json\n", '{"total_kcal": 7}', "\n```")))
    assert split_fence.pred_kcal == 7.0
    # A separator would have turned the key into two words and the number into two tokens.
    assert classify(record(blocks('{"total_', 'kcal": 8}'))).pred_kcal == 8.0
    cut_number = classify(record(blocks('{"total_kcal": 1', " 2}")))
    assert (cut_number.status, cut_number.reason) == ("invalid", "not_json")


@pytest.mark.parametrize(
    "usage", [{}, None, {"input_tokens": 7}, {"input_tokens": None, "output_tokens": None}]
)
def test_usage_tokens_without_usage_are_zero(usage: dict | None) -> None:
    response = reply()
    if usage is None:
        del response["usage"]
    else:
        response["usage"] = usage
    expected = (7, 0) if usage == {"input_tokens": 7} else (0, 0)
    assert usage_tokens(record(response)) == expected
    assert usage_tokens(record(None)) == (0, 0)
