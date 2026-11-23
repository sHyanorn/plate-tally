import base64
import json
import re
from collections.abc import Callable

import pytest
from fakes import FakeClient, message, png, reply_for

from plate_eval import config, runner, scorer

HAIKU = "claude-haiku-5-5"
SONNET = "claude-sonnet-5-5"

Handler = Callable[[dict], object]
# Called with (model, prompt id, dish id, all dish ids): True makes the reply invalid.
FailWhen = Callable[[str, str, str, list[str]], bool]


def replies_where(
    should_change: FailWhen, changed: Callable[[dict], object]
) -> Callable[[list[str]], Handler]:
    """A handler factory for prepare: valid replies, except where should_change says the reply
    is changed(kwargs) instead."""

    def factory(ids: list[str]) -> Handler:
        dish_of = {base64.b64encode(png(tag=i)).decode(): i for i in ids}

        def handler(kwargs: dict) -> object:
            image, text = kwargs["messages"][0]["content"]
            prompt_id = "p1" if "total_kcal" in text["text"] else "p2"
            if should_change(kwargs["model"], prompt_id, dish_of[image["source"]["data"]], ids):
                return changed(kwargs)
            return reply_for(kwargs)

        return handler

    return factory


def invalid_where(should_fail: FailWhen) -> Callable[[list[str]], Handler]:
    return replies_where(should_fail, lambda kw: message("not json", model=kw["model"]))


def substituted_where(should_substitute: FailWhen) -> Callable[[list[str]], Handler]:
    """The other model answers, with a reply that would parse."""
    other = {HAIKU: SONNET, SONNET: HAIKU}
    return replies_where(should_substitute, lambda kw: message(model=other[kw["model"]]))


ALL_SONNET_INVALID = invalid_where(lambda model, prompt_id, dish_id, ids: model == SONNET)


def prepare(
    workspace: Callable[[int], list[str]],
    n: int = 5,
    make_handler: Callable[[list[str]], Handler] = ALL_SONNET_INVALID,
) -> list[str]:
    """Run the 4 cells on n dishes with a fake client and write the reference CSVs to the cache.
    The references are 50, 150, 250, ... kcal in sample order."""
    ids = workspace(n)
    rows = "".join(f"{dish_id},{50 + 100 * i}.0,1,1,1,1\n" for i, dish_id in enumerate(ids))
    (config.CACHE_DIR / "dish_metadata_cafe1.csv").write_text(rows)
    (config.CACHE_DIR / "dish_metadata_cafe2.csv").write_text("")
    assert runner.run(FakeClient(make_handler(ids)), sleep=lambda s: None) == 0
    return ids


def read_table(name: str) -> list[dict[str, str]]:
    lines = (config.RESULTS_DIR / name).read_text().splitlines()
    header = lines[0].split("\t")
    return [dict(zip(header, line.split("\t"), strict=True)) for line in lines[1:]]


def cell_row(model: str, prompt_id: str) -> dict[str, str]:
    rows = read_table("cells.tsv")
    return next(r for r in rows if (r["model"], r["prompt"]) == (model, prompt_id))


def test_score_writes_tables_and_markdown(workspace: Callable[[int], list[str]]) -> None:
    ids = prepare(workspace)
    assert scorer.score() == 0
    assert sorted(p.name for p in config.RESULTS_DIR.iterdir()) == [
        "cells.tsv",
        "differences.tsv",
        "differences_common.tsv",
        "per_call.tsv",
    ]

    per_call = (config.RESULTS_DIR / "per_call.tsv").read_text().splitlines()
    columns = "model prompt dish_id status reason ref_kcal pred_kcal input_tokens output_tokens"
    assert per_call[0].split("\t") == [*columns.split(), "cost_usd"]
    assert len(per_call) == 1 + 4 * len(ids)
    first = per_call[1].split("\t")
    assert first[:7] == ["claude-haiku-5-5", "p1", ids[0], "ok", "", "50.0", "100.0"]
    assert per_call[-1].split("\t")[3:5] == ["invalid", "not_json"]

    cells = (config.RESULTS_DIR / "cells.tsv").read_text().splitlines()[0].split("\t")
    assert (
        cells[:16]
        == (
            "model prompt n_sampled n_recorded partial n_valid n_invalid n_error n_refusal "
            "n_substituted failure_share cost_usd mean_cost_per_call input_tokens output_tokens "
            "reasons"
        ).split()
    )
    assert cells[-1] == "undefined_resamples"
    haiku_p1 = cell_row(HAIKU, "p1")
    sonnet_p1 = cell_row(SONNET, "p1")
    assert haiku_p1["n_valid"] == "5" and haiku_p1["failure_share"] == "0.0"
    assert haiku_p1["partial"] == "false" and haiku_p1["n_recorded"] == "5"
    assert haiku_p1["n_substituted"] == "0" and sonnet_p1["n_substituted"] == "0"
    assert sonnet_p1["n_valid"] == "0" and sonnet_p1["n_invalid"] == "5"
    assert sonnet_p1["failure_share"] == "1.0"
    assert sonnet_p1["reasons"] == "not_json:5"
    assert sonnet_p1["mae"] == "nan" and sonnet_p1["mae_low"] == "nan"
    # predictions 100 for refs 50, 150, 250, 350, 450: errors 50, 50, 150, 250, 350
    assert float(haiku_p1["mae"]) == pytest.approx(170.0)
    # The tsv keeps fractions at full precision, not percentages.
    assert float(haiku_p1["mape"]) == pytest.approx((1 + 1 / 3 + 3 / 5 + 5 / 7 + 7 / 9) / 5)
    assert float(haiku_p1["mean_relative_bias"]) == pytest.approx(
        (50 / 50 - 50 / 150 - 150 / 250 - 250 / 350 - 350 / 450) / 5
    )
    assert float(haiku_p1["within_20"]) == 0.0
    assert len(haiku_p1["mape"].split(".")[1]) > 10 and "%" not in haiku_p1["mape"]
    # 5 calls of 500 input and 20 output tokens on haiku: 6e-5 USD each
    assert float(haiku_p1["mean_cost_per_call"]) == pytest.approx(6e-5)
    assert float(haiku_p1["cost_usd"]) == pytest.approx(5 * 6e-5)
    assert haiku_p1["undefined_resamples"] == ""
    assert sonnet_p1["undefined_resamples"] == ";".join(
        f"{m}:{config.BOOTSTRAP_RESAMPLES}" for m in scorer.METRICS
    )

    for name in ("differences.tsv", "differences_common.tsv"):
        header = (config.RESULTS_DIR / name).read_text().splitlines()[0]
        assert (
            header.split("\t")
            == ("comparison metric difference low high verdict partial undefined_resamples").split()
        )
        assert len(read_table(name)) == 4 * 7

    markdown = config.RESULTS_MD.read_text()
    assert markdown.startswith("# Evaluation results\n")
    assert "170.0 [" in markdown
    assert "n/a" in markdown
    assert markdown.rstrip().endswith("sample size 5.")
    assert re.search(r"Run date \d{4}-\d{2}-\d{2}, ", markdown)
    assert not re.search(r"[\u2013\u2014]", markdown)
    assert "Nutrition5k" in markdown and "CC BY 4.0" in markdown
    assert (
        "`eval/results/per_call.tsv` repeats them for each dish. "
        f"The selection of {len(ids)} dishes is the only change to the data."
    ) in markdown


def test_markdown_starts_with_the_headline_table_and_shows_percentages(
    workspace: Callable[[int], list[str]],
) -> None:
    prepare(workspace)
    scorer.score()
    lines = config.RESULTS_MD.read_text().splitlines()
    assert [line for line in lines if line.startswith("##")] == [
        "## Headline",
        "## Calls and cost",
        "## Metrics",
        "## Differences",
        "## Differences on common dishes",
    ]
    table = [line for line in lines[lines.index("## Headline") :] if line.startswith("|")][:6]
    assert table[0] == "| Model | Prompt | MAE (kcal) | Failure share | Mean cost per call (USD) |"
    haiku_p1 = table[2].split(" | ")
    assert haiku_p1[:2] == ["| claude-haiku-5-5", "p1"]
    assert re.fullmatch(r"170\.0 \[\d+\.\d, \d+\.\d\]", haiku_p1[2])
    assert haiku_p1[3:] == ["0.0%", "0.000060 |"]
    sonnet_p1 = table[4].split(" | ")
    assert sonnet_p1[2:4] == ["n/a", "100.0%"]
    # kcal metrics have one decimal; ratio metrics are percentages with one decimal.
    metrics = lines[lines.index("## Metrics") :]
    row = next(line for line in metrics if line.startswith("| claude-haiku-5-5 | p1"))
    cols = [c.strip() for c in row.strip("|").split("|")]
    assert re.fullmatch(r"170\.0 \[\d+\.\d, \d+\.\d\]", cols[2])  # MAE
    assert re.fullmatch(r"68\.5% \[\d+\.\d%, \d+\.\d%\]", cols[5])  # MAPE
    assert re.fullmatch(r"-28\.5% \[-\d+\.\d%, -?\d+\.\d%\]", cols[6])  # relative bias
    assert cols[7] == "0.0% [0.0%, 0.0%]"  # within 20%
    calls = lines[lines.index("## Calls and cost") :]
    assert any(
        line.startswith("| claude-sonnet-5-5 | p1 | 5 | 5 | 0 | 5 | 0 | 0 | 0 | 100.0% |")
        for line in calls
    )


def test_substituted_calls_are_counted_costed_and_not_scored(
    workspace: Callable[[int], list[str]],
) -> None:
    # Sonnet p1 is answered by haiku for the dishes with 250 and 450 kcal. The text would parse.
    ids = prepare(
        workspace,
        make_handler=substituted_where(
            lambda model, prompt_id, dish_id, ids: (
                (model, prompt_id) == (SONNET, "p1") and dish_id in (ids[2], ids[4])
            )
        ),
    )
    assert scorer.score() == 0

    row = cell_row(SONNET, "p1")
    counts = [row[k] for k in ("n_valid", "n_invalid", "n_error", "n_refusal", "n_substituted")]
    assert counts == ["3", "0", "0", "0", "2"]
    assert row["failure_share"] == "0.4"
    assert row["reasons"] == "model_mismatch:2"
    # The other dishes predict 100 for refs 50, 150, 350: errors 50, 50, 250.
    assert float(row["mae"]) == pytest.approx((50 + 50 + 250) / 3)
    assert float(row["cost_usd"]) == pytest.approx(5 * 1.2e-3)  # 500 in, 20 out on sonnet
    for other in (cell_row(HAIKU, "p1"), cell_row(SONNET, "p2")):
        assert other["n_substituted"] == "0"

    calls = [r for r in read_table("per_call.tsv") if (r["model"], r["prompt"]) == (SONNET, "p1")]
    substituted = [r for r in calls if r["status"] == "substituted"]
    assert [r["dish_id"] for r in substituted] == [ids[2], ids[4]]
    for r in substituted:
        assert (r["reason"], r["pred_kcal"], r["input_tokens"], r["output_tokens"]) == (
            "model_mismatch",
            "",
            "500",
            "20",
        )
        assert float(r["cost_usd"]) == pytest.approx(1.2e-3)
    assert [r["status"] for r in calls].count("ok") == 3

    markdown = config.RESULTS_MD.read_text()
    assert "| Refusal | Substituted | Failure share |" in markdown
    assert "| claude-sonnet-5-5 | p1 | 5 | 5 | 3 | 0 | 0 | 0 | 2 | 40.0% |" in markdown


def test_score_reports_undefined_resamples_in_the_tsv_files_and_a_footnote(
    workspace: Callable[[int], list[str]],
) -> None:
    # Sonnet p1 has one valid call (dish 0, ref 50): the resamples without that dish have no value.
    only_first = invalid_where(
        lambda model, prompt_id, dish_id, ids: (
            (model, prompt_id) == (SONNET, "p1") and dish_id != ids[0]
        )
    )
    prepare(workspace, make_handler=only_first)
    scorer.score()

    row = cell_row(SONNET, "p1")
    assert row["n_valid"] == "1" and row["failure_share"] == "0.8"
    counts = dict(pair.split(":") for pair in row["undefined_resamples"].split(";"))
    assert set(counts) == set(scorer.METRICS)
    assert 0 < int(counts["mae"]) < config.BOOTSTRAP_RESAMPLES  # not every draw holds dish 0
    assert row["mae_low"] != "nan" and row["mae_high"] != "nan"  # an interval from the rest
    key = f"{SONNET} minus {HAIKU} (p1)"
    for name in ("differences.tsv", "differences_common.tsv"):
        diff = next(r for r in read_table(name) if (r["comparison"], r["metric"]) == (key, "mae"))
        assert diff["undefined_resamples"] == f"mae:{counts['mae']}"
        assert diff["low"] != "nan"
    rows = read_table("differences.tsv")
    untouched = next(r for r in rows if r["comparison"] == f"p2 minus p1 ({HAIKU})")
    assert untouched["undefined_resamples"] == ""

    markdown = config.RESULTS_MD.read_text()
    note = "Resamples without a value, left out of the interval: "
    assert markdown.count(note) == 4  # headline, metrics, both difference tables
    assert f"{SONNET} p1 mae {counts['mae']}" in markdown
    assert f"{key} mae {counts['mae']}" in markdown


def test_score_has_no_footnote_when_every_resample_has_a_value(
    workspace: Callable[[int], list[str]],
) -> None:
    prepare(workspace, make_handler=invalid_where(lambda model, p, d, ids: False))
    scorer.score()
    assert "Resamples without a value" not in config.RESULTS_MD.read_text()
    assert all(r["undefined_resamples"] == "" for r in read_table("cells.tsv"))


def test_score_marks_an_incomplete_run_as_partial(workspace: Callable[[int], list[str]]) -> None:
    ids = prepare(workspace)
    for dish_id in ids[3:]:  # haiku p2 keeps 3 of 5 records
        runner.raw_path(HAIKU, "p2", dish_id).unlink()
    assert scorer.score() == 0

    partial = cell_row(HAIKU, "p2")
    assert partial["partial"] == "true"
    assert (partial["n_sampled"], partial["n_recorded"], partial["n_valid"]) == ("5", "3", "3")
    assert partial["failure_share"] == "n/a"
    assert float(partial["mean_cost_per_call"]) == pytest.approx(6e-5)  # over its 3 calls
    assert float(partial["mae"]) == pytest.approx((80 + 20 + 120) / 3)  # p2 predicts 130 kcal
    assert cell_row(HAIKU, "p1")["partial"] == "false"
    assert cell_row(HAIKU, "p1")["failure_share"] == "0.0"

    assert len((config.RESULTS_DIR / "per_call.tsv").read_text().splitlines()) == 1 + 4 * 5 - 2
    flagged = f"p2 minus p1 ({HAIKU})", f"{SONNET} minus {HAIKU} (p2)"
    for name in ("differences.tsv", "differences_common.tsv"):
        rows = read_table(name)
        assert {r["comparison"] for r in rows if r["partial"] == "true"} == set(flagged)
        assert [r["partial"] for r in rows].count("true") == 2 * 7

    markdown = config.RESULTS_MD.read_text()
    assert f"| {HAIKU} (partial) | p2 |" in markdown
    assert f"| {HAIKU} | p1 |" in markdown
    assert f"| p2 minus p1 ({HAIKU}) (partial) |" in markdown
    assert f"| {SONNET} minus {HAIKU} (p2) (partial) |" in markdown
    assert f"p2 minus p1 ({SONNET}) (partial)" not in markdown
    assert f"| {SONNET} minus {HAIKU} (p2) (partial) |" in markdown.split("common dishes")[1]


def test_missing_dishes_count_as_not_ok_in_the_bootstrap(
    workspace: Callable[[int], list[str]],
) -> None:
    ids = prepare(workspace, make_handler=invalid_where(lambda m, p, d, ids: False))
    saved = {d: runner.raw_path(HAIKU, "p1", d).read_text() for d in ids[1:]}
    for dish_id in ids[1:]:
        runner.raw_path(HAIKU, "p1", dish_id).unlink()
    scorer.score()
    missing = cell_row(HAIKU, "p1")
    assert missing["partial"] == "true" and missing["n_recorded"] == "1"

    for dish_id, text in saved.items():  # the same dishes as invalid calls instead
        record = json.loads(text)
        record["response"]["content"][0]["text"] = "not json"
        runner.raw_path(HAIKU, "p1", dish_id).write_text(json.dumps(record))
    scorer.score()
    invalid = cell_row(HAIKU, "p1")
    assert invalid["partial"] == "false" and invalid["n_invalid"] == "4"
    metric_columns = [f"{m}{s}" for m in scorer.METRICS for s in ("", "_low", "_high")]
    assert [missing[c] for c in metric_columns] == [invalid[c] for c in metric_columns]
    assert missing["undefined_resamples"] == invalid["undefined_resamples"] != ""


def test_score_with_a_cell_without_any_record(workspace: Callable[[int], list[str]]) -> None:
    ids = prepare(workspace)
    for dish_id in ids:
        runner.raw_path(SONNET, "p2", dish_id).unlink()
    scorer.score()
    row = cell_row(SONNET, "p2")
    assert (row["n_recorded"], row["partial"], row["failure_share"]) == ("0", "true", "n/a")
    assert row["mean_cost_per_call"] == "n/a"
    assert row["mae"] == "nan"
    assert f"| {SONNET} (partial) | p2 | n/a | n/a | n/a |" in config.RESULTS_MD.read_text()


def difference_rows(markdown: str) -> list[str]:
    return [line for line in markdown.splitlines() if line.startswith("| ") and " minus " in line]


def test_common_differences_equal_the_first_table_when_no_dish_fails(
    workspace: Callable[[int], list[str]],
) -> None:
    prepare(workspace, make_handler=invalid_where(lambda m, p, d, ids: False))
    scorer.score()
    own = (config.RESULTS_DIR / "differences.tsv").read_text()
    assert own == (config.RESULTS_DIR / "differences_common.tsv").read_text()
    first, second = config.RESULTS_MD.read_text().split("## Differences on common dishes")
    assert len(difference_rows(first)) == 4 * 7
    assert difference_rows(first) == difference_rows(second)


def test_common_differences_differ_when_a_dish_fails(workspace: Callable[[int], list[str]]) -> None:
    # Sonnet p1 fails on the dish with 450 kcal. Every p1 reply says 100 kcal, every p2 reply 130.
    last_dish = invalid_where(
        lambda model, prompt_id, dish_id, ids: (
            (model, prompt_id) == (SONNET, "p1") and dish_id == ids[4]
        )
    )
    prepare(workspace, make_handler=last_dish)
    scorer.score()

    own = {(r["comparison"], r["metric"]): r for r in read_table("differences.tsv")}
    common = {(r["comparison"], r["metric"]): r for r in read_table("differences_common.tsv")}
    key = (f"{SONNET} minus {HAIKU} (p1)", "mae")
    # Own dishes: sonnet's MAE over 4 dishes is 125, haiku's over 5 is 170. On the 4 common
    # dishes both are 125.
    assert float(own[key]["difference"]) == pytest.approx(125 - 170)
    assert float(common[key]["difference"]) == 0.0
    assert own != common
    first, second = config.RESULTS_MD.read_text().split("## Differences on common dishes")
    assert difference_rows(first) != difference_rows(second)
    untouched = (f"{SONNET} minus {HAIKU} (p2)", "mae")
    assert own[untouched] == common[untouched]  # no dish failed in either p2 cell


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("prompt_sha256", "0" * 64),
        ("dish_id", "dish_999"),
        ("model", "claude-sonnet-5-5"),
        ("prompt_id", "p2"),
    ],
)
def test_score_refuses_a_record_that_does_not_belong_to_its_cell(
    workspace: Callable[[int], list[str]], key: str, value: str
) -> None:
    ids = prepare(workspace)
    path = runner.raw_path("claude-haiku-5-5", "p1", ids[2])
    record = json.loads(path.read_text())
    record[key] = value
    path.write_text(json.dumps(record))
    with pytest.raises(ValueError, match=f"expected {key} .* got '{value}'"):
        scorer.score()


def test_score_refuses_when_a_hashed_file_changed_since_the_run(
    workspace: Callable[[int], list[str]],
) -> None:
    prepare(workspace)
    with config.PROTOCOL_FILE.open("a") as f:
        f.write("amended\n")
    with pytest.raises(ValueError, match="evaluation-protocol.md changed since the run"):
        scorer.score()


def test_score_refuses_reference_files_with_other_bytes(
    workspace: Callable[[int], list[str]], monkeypatch: pytest.MonkeyPatch
) -> None:
    prepare(workspace)
    monkeypatch.setattr(config, "EXPECTED_SHA256", {"dish_metadata_cafe1.csv": "0" * 64})
    match = "expected dish_metadata_cafe1.csv to have sha256 0{64}, got [0-9a-f]{64}"
    with pytest.raises(ValueError, match=match):
        scorer.score()


def test_score_reads_a_record_without_usage_and_an_image_error_record(
    workspace: Callable[[int], list[str]],
) -> None:
    ids = prepare(workspace)
    path = runner.raw_path(HAIKU, "p1", ids[0])
    record = json.loads(path.read_text())
    del record["response"]["usage"]
    path.write_text(json.dumps(record))
    problem = runner.ImageProblem(503, "download failed")
    image_error = runner.image_error_record(HAIKU, runner.load_prompts()["p1"], ids[1], problem)
    runner.raw_path(HAIKU, "p1", ids[1]).write_text(json.dumps(image_error))
    assert scorer.score() == 0
    rows = (config.RESULTS_DIR / "per_call.tsv").read_text().splitlines()
    assert rows[1].split("\t")[7:9] == ["0", "0"]  # no usage: no tokens, no cost
    assert rows[1].split("\t")[9] == "0.0"
    assert rows[2].split("\t")[3:5] == ["error", "ImageUnavailable"]
    assert cell_row(HAIKU, "p1")["n_error"] == "1"
    assert float(cell_row(HAIKU, "p1")["failure_share"]) == pytest.approx(0.2)
