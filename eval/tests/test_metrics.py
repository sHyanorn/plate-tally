import numpy as np
import pytest

from plate_eval import config, data
from plate_eval.scorer import (
    CellData,
    bootstrap,
    common_differences,
    differences,
    draw_indices,
    fmt,
    fmt_interval,
    interval,
    point_metrics,
    undefined_counts,
    undefined_text,
)

NAN = float("nan")


def one_row(cell: CellData) -> dict[str, float]:
    return point_metrics(cell)


def test_hand_computed_metrics() -> None:
    # Dish 2 has ref 40 (below 50): only the kcal metrics use it. Dish 3 is invalid: unused.
    cell = CellData(
        valid=np.array([True, True, True, False, True]),
        pred=np.array([120.0, 170.0, 60.0, NAN, 390.0]),
        ref=np.array([100.0, 200.0, 40.0, 150.0, 300.0]),
    )
    got = one_row(cell)
    # errors +20, -30, +20, +90
    assert got["mae"] == pytest.approx(40.0)
    assert got["signed_mean_error"] == pytest.approx(25.0)
    assert got["median_abs_error"] == pytest.approx(25.0)  # abs errors 20, 20, 30, 90
    # relative errors on dishes 0, 1, 4: +0.20, -0.15, +0.30
    assert got["mape"] == pytest.approx(0.65 / 3)
    assert got["mean_relative_bias"] == pytest.approx(0.35 / 3)
    assert got["within_20"] == pytest.approx(2 / 3)  # 0.20 counts, 0.30 does not
    assert got["within_30"] == pytest.approx(1.0)  # 0.30 counts


def test_zero_kcal_dish_counts_in_kcal_metrics_and_not_in_ratio_metrics() -> None:
    cell = CellData(
        valid=np.array([True, True, True]),
        pred=np.array([30.0, 110.0, 180.0]),
        ref=np.array([0.0, 100.0, 200.0]),
    )
    got = one_row(cell)
    assert got["mae"] == pytest.approx(20.0)  # errors +30, +10, -20
    assert got["signed_mean_error"] == pytest.approx(20 / 3)
    assert got["median_abs_error"] == pytest.approx(20.0)  # abs errors 10, 20, 30
    assert got["mape"] == pytest.approx(0.1)  # only the dishes at 100 and 200: +0.10, -0.10
    assert got["mean_relative_bias"] == pytest.approx(0.0)
    assert got["within_20"] == pytest.approx(1.0)
    assert got["within_30"] == pytest.approx(1.0)
    assert not any(np.isinf(v) for v in got.values())


def test_ratio_bounds_are_inclusive_and_compared_as_parsed() -> None:
    # The reference of the first dish is read from CSV text, as the scorer reads it.
    reference = data.parse_reference(["dish_a,50.000000,1\ndish_b,49.999999,1\n"])
    refs = [reference["dish_a"], reference["dish_b"], 100.0, 100.0, 100.0, 100.0, 100.0]
    refs += [50.5, 51.9]
    preds = [50.0, 49.999999, 120.0, 130.0, 70.0, 120.01, 130.01, 60.6, 67.47]
    cell = CellData(np.ones(len(refs), dtype=bool), np.array(preds), np.array(refs))
    assert reference["dish_a"] == 50.0
    got = one_row(cell)
    # Dish b is below 50 and has no ratio. Eligible: 8 dishes.
    # Within 20%: dish a (0%), 120.0 (exactly 20%), 60.6 on 50.5.
    # Within 30%: also 130.0 and 70.0 (exactly 30%) and 120.01, not 130.01.
    assert got["within_20"] == pytest.approx(3 / 8)
    assert got["within_30"] == pytest.approx(6 / 8)
    assert got["mae"] == pytest.approx(np.mean(np.abs(np.array(preds) - np.array(refs))), rel=1e-12)


def test_within_shares_use_the_multiplication_form() -> None:
    # 60.6 is 20% above 50.5 in decimal. In float64 the error is 10.100000000000001, equal to
    # 0.20 * 50.5, so the multiplication form counts it; the quotient 0.2000000000000000..2
    # would not. 67.47 is 30% above 51.9 in decimal; its error 15.57 is a bit above
    # 0.30 * 51.9, so the multiplication form does not count it; the quotient would.
    cell = CellData(np.array([True, True]), np.array([60.6, 67.47]), np.array([50.5, 51.9]))
    err = np.abs(cell.pred - cell.ref)
    assert err[0] / cell.ref[0] > 0.20 and err[0] <= 0.20 * cell.ref[0]
    assert err[1] / cell.ref[1] <= 0.30 and err[1] > 0.30 * cell.ref[1]
    got = one_row(cell)
    assert got["within_20"] == pytest.approx(0.5)  # 60.6 on 50.5
    assert got["within_30"] == pytest.approx(0.5)  # 60.6 only


def test_dish_at_exactly_50_kcal_is_in_the_ratio_metrics() -> None:
    cell = CellData(np.array([True, True]), np.array([60.0, 40.0]), np.array([50.0, 49.999999]))
    got = one_row(cell)
    assert got["mape"] == pytest.approx(0.2)  # only the dish at 50.0
    assert got["mean_relative_bias"] == pytest.approx(0.2)
    assert got["within_20"] == pytest.approx(1.0)  # |10| <= 0.20 * 50 exactly
    assert got["mae"] == pytest.approx((10.0 + 9.999999) / 2)


def test_cell_without_valid_calls_is_undefined() -> None:
    cell = CellData(np.array([False, False]), np.array([NAN, NAN]), np.array([100.0, 200.0]))
    got = one_row(cell)
    assert all(np.isnan(v) for v in got.values())
    assert all(np.isnan(x) for x in interval(np.array([NAN, NAN])))


def test_interval_uses_the_resamples_that_have_a_value() -> None:
    values = np.array([NAN, 1.0, 2.0, 3.0, NAN, 4.0, 5.0])
    low, high = interval(values)
    assert (low, high) == tuple(np.nanpercentile(values, [2.5, 97.5]))
    assert (low, high) == tuple(np.percentile([1.0, 2.0, 3.0, 4.0, 5.0], [2.5, 97.5]))
    assert interval(np.array([NAN, 1.0])) == (1.0, 1.0)


def synthetic(shift: float = 0.0, n: int = 80) -> CellData:
    rng = np.random.default_rng(1)
    ref = rng.uniform(30, 600, n)
    pred = ref + rng.normal(0, 40, n) + shift
    valid = rng.random(n) > 0.1
    return CellData(valid, np.where(valid, pred, NAN), ref)


def all_cells(shifted_model: str | None = None) -> dict:
    """The four cells hold the same calls; the shifted model predicts 50 kcal higher."""
    cells = {}
    for _, model, prompt_id in config.CELLS:
        shift = 50.0 if model == shifted_model else 0.0
        cells[model, prompt_id] = synthetic(shift)
    return cells


def draws(n: int, seed: int = 7, resamples: int = 200) -> np.ndarray:
    return draw_indices(n, seed, resamples)


def test_draws_are_the_registered_call() -> None:
    expected = np.random.default_rng(config.BOOTSTRAP_SEED).integers(0, 300, size=(10000, 300))
    got = draw_indices(300, config.BOOTSTRAP_SEED, config.BOOTSTRAP_RESAMPLES)
    np.testing.assert_array_equal(got, expected)


def test_bootstrap_is_reproducible_for_a_seed() -> None:
    cells = {("m", "p"): synthetic()}
    point, first = bootstrap(cells, draws(80))
    _, second = bootstrap(cells, draws(80))
    _, other = bootstrap(cells, draws(80, seed=8))
    for metric in first[("m", "p")]:
        np.testing.assert_array_equal(first[("m", "p")][metric], second[("m", "p")][metric])
    assert not np.array_equal(first[("m", "p")]["mae"], other[("m", "p")]["mae"])
    assert point[("m", "p")]["mae"] == pytest.approx(one_row(cells[("m", "p")])["mae"])


def test_interval_contains_the_point_estimate() -> None:
    cells = {("m", "p"): synthetic()}
    point, samples = bootstrap(cells, draws(80, resamples=1000))
    for metric, values in samples[("m", "p")].items():
        low, high = interval(values)
        assert low <= point[("m", "p")][metric] <= high, metric


def diff_row(rows: list[dict], comparison: str, metric: str) -> dict:
    return next(r for r in rows if r["comparison"] == comparison and r["metric"] == metric)


def test_identical_cells_have_exactly_zero_difference() -> None:
    cells = all_cells()
    point, samples = bootstrap(cells, draws(80, 3, 300))
    rows = differences(point, samples)
    assert len(rows) == 4 * 7
    for row in rows:
        assert row["difference"] == 0.0
        assert (row["low"], row["high"]) == (0.0, 0.0)
        assert row["verdict"] == "not distinguished"
        assert row["undefined"] == 0
        assert row["partial"] is False


def test_a_shifted_cell_gets_a_positive_verdict() -> None:
    cells = all_cells(shifted_model="claude-sonnet-5-5")
    point, samples = bootstrap(cells, draws(80, 3, 500))
    rows = differences(point, samples)
    mae = diff_row(rows, "claude-sonnet-5-5 minus claude-haiku-5-5 (p1)", "mae")
    assert mae["verdict"] == "positive"
    assert mae["low"] > 0
    bias = diff_row(rows, "claude-sonnet-5-5 minus claude-haiku-5-5 (p2)", "signed_mean_error")
    assert bias["verdict"] == "positive"
    same_model = diff_row(rows, "p2 minus p1 (claude-sonnet-5-5)", "signed_mean_error")
    assert same_model["verdict"] == "not distinguished"


def test_a_partial_cell_marks_its_differences() -> None:
    cells = all_cells()
    point, samples = bootstrap(cells, draws(80, 3, 100))
    partial = frozenset({("claude-haiku-5-5", "p2")})
    rows = differences(point, samples, partial)
    flagged = {r["comparison"] for r in rows if r["partial"]}
    assert flagged == {
        "p2 minus p1 (claude-haiku-5-5)",
        "claude-sonnet-5-5 minus claude-haiku-5-5 (p2)",
    }
    common = common_differences(cells, draws(80, 3, 100), partial)
    assert {r["comparison"] for r in common if r["partial"]} == flagged


REF = np.linspace(100, 400, 60)
HAIKU_P1 = ("claude-haiku-5-5", "p1")


def errs(errors: np.ndarray, valid: np.ndarray | None = None) -> CellData:
    """A cell over REF whose valid dishes err by the given amounts."""
    valid = np.ones(len(REF), dtype=bool) if valid is None else valid
    return CellData(valid, np.where(valid, REF + errors, NAN), REF)


def four_cells(haiku_p1: CellData, haiku_p2: CellData) -> dict:
    other = errs(np.full(60, 20.0))
    return {
        HAIKU_P1: haiku_p1,
        ("claude-haiku-5-5", "p2"): haiku_p2,
        ("claude-sonnet-5-5", "p1"): other,
        ("claude-sonnet-5-5", "p2"): other,
    }


def test_common_differences_equal_the_own_ones_when_no_dish_fails() -> None:
    cells = four_cells(errs(np.full(60, 10.0)), errs(np.arange(60.0)))
    idx = draw_indices(60, 5, 300)
    point, samples = bootstrap(cells, idx)
    assert differences(point, samples) == common_differences(cells, idx)


def test_common_differences_differ_when_a_dish_fails() -> None:
    # Haiku p1 fails on the last 30 dishes. Haiku p2 errs by 20 on the first 30 and by 60 on
    # the last 30, so its own MAE is 40 and its MAE on the dishes both cells have is 20.
    valid = np.arange(60) < 30
    cells = four_cells(errs(np.full(60, 10.0), valid), errs(np.where(valid, 20.0, 60.0)))
    idx = draw_indices(60, 5, 300)
    point, samples = bootstrap(cells, idx)
    own = differences(point, samples)
    common = common_differences(cells, idx)
    name = "p2 minus p1 (claude-haiku-5-5)"
    assert diff_row(own, name, "mae")["difference"] == pytest.approx(30.0)  # 40 minus 10
    assert diff_row(common, name, "mae")["difference"] == pytest.approx(10.0)  # 20 minus 10
    assert own != common
    # The contrasts that do not involve haiku p1 are the same in both tables.
    for untouched in (
        "p2 minus p1 (claude-sonnet-5-5)",
        "claude-sonnet-5-5 minus claude-haiku-5-5 (p2)",
    ):
        assert [r for r in own if r["comparison"] == untouched] == [
            r for r in common if r["comparison"] == untouched
        ]


def test_undefined_resamples_are_left_out_of_the_interval_and_counted() -> None:
    # Only dish 0 has a valid call with ref >= 50: the ratio metrics have no value in the
    # resamples that do not draw it.
    n = 10
    valid = np.zeros(n, dtype=bool)
    valid[0] = True
    pred = np.full(n, NAN)
    pred[0] = 110.0
    cell = CellData(valid, pred, np.full(n, 100.0))
    idx = draw_indices(n, 11, 2000)
    point, samples = bootstrap({("m", "p"): cell}, idx)
    values = samples[("m", "p")]["mape"]
    missing = int(np.isnan(values).sum())
    assert missing == int((~(idx == 0).any(axis=1)).sum())
    assert 0.2 * 2000 < missing < 0.5 * 2000  # (9/10)^10 is about 0.35
    assert undefined_counts(samples[("m", "p")])["mape"] == missing
    assert undefined_counts(samples[("m", "p")])["mae"] == missing
    low, high = interval(values)
    assert (low, high) == tuple(np.nanpercentile(values, [2.5, 97.5]))
    assert (low, high) == (pytest.approx(0.1), pytest.approx(0.1))
    assert point[("m", "p")]["mape"] == pytest.approx(0.1)


def test_differences_keep_the_verdict_rule_with_undefined_resamples() -> None:
    # Haiku p1 has one valid dish, so most metrics are undefined in some resamples. Haiku p2
    # has none: every resample is undefined, the interval and verdict are n/a.
    one = np.zeros(60, dtype=bool)
    one[0] = True
    cells = four_cells(errs(np.full(60, 10.0), one), errs(np.full(60, 0.0), np.zeros(60, bool)))
    idx = draw_indices(60, 5, 400)
    point, samples = bootstrap(cells, idx)
    rows = differences(point, samples)
    name = "claude-sonnet-5-5 minus claude-haiku-5-5 (p1)"
    some = diff_row(rows, name, "mae")
    assert some["undefined"] == int((~(idx == 0).any(axis=1)).sum()) > 0
    assert not np.isnan(some["low"])
    assert some["verdict"] == "positive"  # sonnet errs by 20, haiku by 10 on its one dish
    none = diff_row(rows, "p2 minus p1 (claude-haiku-5-5)", "mae")
    assert none["undefined"] == 400
    assert np.isnan(none["low"]) and np.isnan(none["high"]) and np.isnan(none["difference"])
    assert none["verdict"] == "n/a"


def test_undefined_text_lists_the_metrics_with_a_count_in_metric_order() -> None:
    counts = {"within_20": 4, "mae": 3, "mape": 0}
    assert undefined_text(counts) == "mae:3;within_20:4"
    assert undefined_text({"mae": 0}) == ""


def test_display_rounding() -> None:
    assert fmt(123.456, "mae") == "123.5"
    assert fmt(-0.04, "signed_mean_error") == "-0.0"
    assert fmt(12.25, "median_abs_error") == "12.2"
    assert fmt(0.4666, "mape") == "46.7%"
    assert fmt(-0.0123, "mean_relative_bias") == "-1.2%"
    assert fmt(0.5, "within_20") == "50.0%"
    assert fmt(1.0, "within_30") == "100.0%"
    assert fmt(NAN, "mape") == "n/a"
    assert fmt_interval(0.25, 0.5, "within_20") == "[25.0%, 50.0%]"
    assert fmt_interval(10.04, 20.06, "mae") == "[10.0, 20.1]"
    assert fmt_interval(NAN, NAN, "mae") == "n/a"
