"""Scores the raw records: per-call table, per-cell metrics, paired bootstrap differences."""

import json
import warnings
from collections import Counter
from dataclasses import dataclass

import numpy as np

from plate_eval import config, data, runner, sampler
from plate_eval.parse import classify, usage_tokens

METRICS = (
    "mae",
    "signed_mean_error",
    "median_abs_error",
    "mape",
    "mean_relative_bias",
    "within_20",
    "within_30",
)
KCAL_METRICS = ("mae", "signed_mean_error", "median_abs_error")
TITLES = {
    "mae": "MAE (kcal)",
    "signed_mean_error": "Signed mean error (kcal)",
    "median_abs_error": "Median absolute error (kcal)",
    "mape": "MAPE",
    "mean_relative_bias": "Mean relative bias",
    "within_20": "Within 20%",
    "within_30": "Within 30%",
}

CALL_COLUMNS = (
    "model prompt dish_id status reason ref_kcal pred_kcal input_tokens output_tokens cost_usd"
).split()

Cell = tuple[str, str]  # model id, prompt id


@dataclass
class CellData:
    """One cell over the sampled dishes, in sample order. pred is NaN where valid is False."""

    valid: np.ndarray
    pred: np.ndarray
    ref: np.ndarray


def masked_mean(values: np.ndarray, mask: np.ndarray) -> np.ndarray:
    count = mask.sum(axis=1)
    total = np.where(mask, values, 0.0).sum(axis=1)
    return np.where(count > 0, total / np.maximum(count, 1), np.nan)


def cell_metrics(cell: CellData, idx: np.ndarray) -> dict[str, np.ndarray]:
    """Metrics for each row of idx, which holds dish indices (repeats allowed).

    Every metric uses the valid calls among the dishes. The ratio metrics also need ref >= 50.
    Values are compared as parsed, in float64, with inclusive bounds: a share counts a dish when
    abs(error) <= 0.20 * reference, not when the quotient is at most 0.20.
    """
    err = cell.pred - cell.ref
    abs_err = np.abs(err)
    with np.errstate(divide="ignore", invalid="ignore"):
        rel = err / cell.ref
    abs_rel = np.abs(rel)
    ok = cell.valid[idx]
    ok_ratio = (cell.valid & (cell.ref >= config.MIN_REF_KCAL))[idx]
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # a row without a valid dish gives NaN
        median = np.nanmedian(np.where(ok, abs_err[idx], np.nan), axis=1)
    return {
        "mae": masked_mean(abs_err[idx], ok),
        "signed_mean_error": masked_mean(err[idx], ok),
        "median_abs_error": median,
        "mape": masked_mean(abs_rel[idx], ok_ratio),
        "mean_relative_bias": masked_mean(rel[idx], ok_ratio),
        "within_20": masked_mean((abs_err <= 0.20 * cell.ref)[idx].astype(float), ok_ratio),
        "within_30": masked_mean((abs_err <= 0.30 * cell.ref)[idx].astype(float), ok_ratio),
    }


def draw_indices(n: int, seed: int, resamples: int) -> np.ndarray:
    """Dish indices of every resample. All cells and contrasts share them (paired)."""
    return np.random.default_rng(seed).integers(0, n, size=(resamples, n))


def point_metrics(cell: CellData) -> dict[str, float]:
    everything = np.arange(len(cell.ref))[None, :]
    return {m: float(v[0]) for m, v in cell_metrics(cell, everything).items()}


def bootstrap(
    cells: dict[Cell, CellData], draws: np.ndarray
) -> tuple[dict[Cell, dict[str, float]], dict[Cell, dict[str, np.ndarray]]]:
    """Point metrics and resampled metrics of every cell on the same draws."""
    point = {k: point_metrics(c) for k, c in cells.items()}
    samples = {k: cell_metrics(c, draws) for k, c in cells.items()}
    return point, samples


def interval(samples: np.ndarray) -> tuple[float, float]:
    """95% percentile interval of the resamples that have a value; NaN when none has."""
    if np.isnan(samples).all():
        return float("nan"), float("nan")
    low, high = np.nanpercentile(samples, [2.5, 97.5])
    return float(low), float(high)


def undefined_counts(samples: dict[str, np.ndarray]) -> dict[str, int]:
    """Resamples without a value, by metric."""
    return {m: int(np.isnan(v).sum()) for m, v in samples.items()}


def undefined_text(counts: dict[str, int]) -> str:
    return ";".join(f"{m}:{counts[m]}" for m in METRICS if counts.get(m))


def verdict(low: float, high: float) -> str:
    if np.isnan(low):
        return "n/a"
    if low > 0:
        return "positive"
    if high < 0:
        return "negative"
    return "not distinguished"


def contrasts() -> list[tuple[Cell, Cell, str]]:
    """P2 minus P1 within each model, then the second model minus the first within each prompt."""
    (_, first), (_, second) = config.MODELS
    p1, p2 = config.PROMPTS
    within_model = [((m, p2), (m, p1), f"{p2} minus {p1} ({m})") for _, m in config.MODELS]
    within_prompt = [
        ((second, p), (first, p), f"{second} minus {first} ({p})") for p in config.PROMPTS
    ]
    return within_model + within_prompt


Metrics = tuple[dict[str, float], dict[str, np.ndarray]]  # point and resampled values of a cell


def difference_rows(name: str, a: Metrics, b: Metrics, partial: bool) -> list[dict]:
    """One row per metric: a minus b, with the interval of the paired resamples."""
    rows = []
    for metric in METRICS:
        paired = a[1][metric] - b[1][metric]
        low, high = interval(paired)
        rows.append(
            {
                "comparison": name,
                "metric": metric,
                "difference": a[0][metric] - b[0][metric],
                "low": low,
                "high": high,
                "verdict": verdict(low, high),
                "partial": partial,
                "undefined": int(np.isnan(paired).sum()),
            }
        )
    return rows


def differences(
    point: dict[Cell, dict[str, float]],
    samples: dict[Cell, dict[str, np.ndarray]],
    partial: frozenset[Cell] = frozenset(),
) -> list[dict]:
    """Differences with each cell's own valid dishes."""
    rows = []
    for a, b, name in contrasts():
        rows += difference_rows(
            name, (point[a], samples[a]), (point[b], samples[b]), a in partial or b in partial
        )
    return rows


def common_differences(
    cells: dict[Cell, CellData], draws: np.ndarray, partial: frozenset[Cell] = frozenset()
) -> list[dict]:
    """The same differences with both cells restricted to the dishes valid in both."""
    rows = []
    for a, b, name in contrasts():
        both = cells[a].valid & cells[b].valid
        pair = [CellData(both, cells[k].pred, cells[k].ref) for k in (a, b)]
        first, second = ((point_metrics(c), cell_metrics(c, draws)) for c in pair)
        rows += difference_rows(name, first, second, a in partial or b in partial)
    return rows


def load_records(ids: list[str]) -> dict[tuple[str, str, str], dict]:
    """The raw records that exist, by (model, prompt, dish). Refuses records of another
    experiment or another cell. A dish without a record is simply absent."""
    run_info = config.RAW_DIR / "run.json"
    if run_info.exists():
        changed = runner.changed_files(json.loads(run_info.read_text())["sha256"])
        if changed:
            raise ValueError(
                f"expected the files hashed in {run_info} to be unchanged, "
                f"{', '.join(changed)} changed since the run"
            )
    prompt_sha256 = {p.id: p.sha256 for p in runner.load_prompts().values()}
    records = {}
    for _, model, prompt_id in config.CELLS:
        for dish_id in ids:
            path = runner.raw_path(model, prompt_id, dish_id)
            if not path.exists():
                continue
            record = json.loads(path.read_text())
            expected = {
                "dish_id": dish_id,
                "model": model,
                "prompt_id": prompt_id,
                "prompt_sha256": prompt_sha256[prompt_id],
            }
            for key, value in expected.items():
                if record.get(key) != value:
                    raise ValueError(f"{path}: expected {key} {value!r}, got {record.get(key)!r}")
            records[model, prompt_id, dish_id] = record
    return records


def percent(value: float) -> str:
    return f"{100 * value:.1f}%"


def fmt(value: float, metric: str) -> str:
    """Display only: kcal metrics to one decimal, ratios as percentages with one decimal."""
    if np.isnan(value):
        return "n/a"
    return f"{value:.1f}" if metric in KCAL_METRICS else percent(value)


def fmt_interval(low: float, high: float, metric: str) -> str:
    return "n/a" if np.isnan(low) else f"[{fmt(low, metric)}, {fmt(high, metric)}]"


def with_interval(value: float, low: float, high: float, metric: str) -> str:
    """The value and its interval; a single n/a when the metric has no value."""
    text = fmt(value, metric)
    return text if np.isnan(low) else f"{text} {fmt_interval(low, high, metric)}"


def label(model: str, partial: bool) -> str:
    return f"{model} (partial)" if partial else model


def footnote(entries: list[tuple[str, int]]) -> list[str]:
    """The line under a table that lists resamples without a value; nothing when none."""
    parts = [f"{name} {n}" for name, n in entries if n]
    if not parts:
        return []
    return ["", "Resamples without a value, left out of the interval: " + "; ".join(parts) + "."]


def difference_table(diffs: list[dict]) -> list[str]:
    out = [
        "| Comparison | Metric | Difference | 95% interval | Verdict |",
        "|---|---|---|---|---|",
    ]
    for d in diffs:
        m = d["metric"]
        name = f"{d['comparison']} (partial)" if d["partial"] else d["comparison"]
        out.append(
            f"| {name} | {TITLES[m]} | {fmt(d['difference'], m)} "
            f"| {fmt_interval(d['low'], d['high'], m)} | {d['verdict']} |"
        )
    return out + footnote([(f"{d['comparison']} {d['metric']}", d["undefined"]) for d in diffs])


def render_markdown(
    counts: dict[Cell, dict],
    point: dict[Cell, dict[str, float]],
    samples: dict[Cell, dict[str, np.ndarray]],
    diffs: list[dict],
    common: list[dict],
    run_date: str,
    n: int,
) -> str:
    def share(c: dict) -> str:  # n/a for a partial cell
        value = c["failure_share"]
        return value if isinstance(value, str) else percent(value)

    def cost(c: dict) -> str:  # n/a for a cell without records
        value = c["mean_cost_per_call"]
        return value if isinstance(value, str) else f"{value:.6f}"

    out = [
        "# Evaluation results",
        "",
        "Protocol: [evaluation-protocol.md](evaluation-protocol.md)",
        "",
        "Reference energies are from Nutrition5k (Thames et al., CVPR 2021), released under "
        "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), data at "
        "https://github.com/google-research-datasets/Nutrition5k. "
        "`eval/results/per_call.tsv` repeats them for each dish. "
        f"The selection of {n} dishes is the only change to the data.",
        "",
        "## Headline",
        "",
        "MAE in kcal on valid calls with its 95% percentile interval, the share of sampled "
        "dishes without a valid call, and the mean cost of a call. A cell with fewer records "
        "than sampled dishes is partial and has no failure share.",
        "",
        "| Model | Prompt | MAE (kcal) | Failure share | Mean cost per call (USD) |",
        "|---|---|---|---|---|",
    ]
    for (model, prompt_id), c in counts.items():
        low, high = interval(samples[model, prompt_id]["mae"])
        mae = with_interval(point[model, prompt_id]["mae"], low, high, "mae")
        out.append(
            f"| {label(model, c['partial'])} | {prompt_id} | {mae} | {share(c)} | {cost(c)} |"
        )
    out += footnote(
        [
            (f"{model} {prompt_id} mae", undefined_counts(samples[model, prompt_id])["mae"])
            for model, prompt_id in counts
        ]
    )
    out += [
        "",
        "## Calls and cost",
        "",
        "| Model | Prompt | Sampled | Recorded | Valid | Invalid | Error | Refusal | Substituted "
        "| Failure share | Input tokens | Output tokens | Cost (USD) |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for (model, prompt_id), c in counts.items():
        out.append(
            f"| {label(model, c['partial'])} | {prompt_id} | {c['n_sampled']} | {c['n_recorded']} "
            f"| {c['n_valid']} | {c['n_invalid']} | {c['n_error']} | {c['n_refusal']} "
            f"| {c['n_substituted']} "
            f"| {share(c)} | {c['input_tokens']} | {c['output_tokens']} | {c['cost_usd']:.4f} |"
        )
    out += [
        "",
        "## Metrics",
        "",
        f"Value and 95% percentile interval from {config.BOOTSTRAP_RESAMPLES:,} bootstrap "
        f"resamples of the {n} dishes. Metrics use the valid calls; a dish without a record "
        f"counts as not valid. MAPE, relative bias and the within-share metrics also need a "
        f"reference of at least {config.MIN_REF_KCAL} kcal. Ratios are shown as percentages.",
        "",
        "| Model | Prompt | " + " | ".join(TITLES[m] for m in METRICS) + " |",
        "|---|---|" + "---|" * len(METRICS),
    ]
    undefined = []
    for (model, prompt_id), values in point.items():
        cols = []
        for m in METRICS:
            low, high = interval(samples[model, prompt_id][m])
            cols.append(with_interval(values[m], low, high, m))
        name = label(model, counts[model, prompt_id]["partial"])
        out.append(f"| {name} | {prompt_id} | " + " | ".join(cols) + " |")
        for m, k in undefined_counts(samples[model, prompt_id]).items():
            undefined.append((f"{model} {prompt_id} {m}", k))
    out += footnote(undefined)
    out += [
        "",
        "## Differences",
        "",
        "Each cell uses its own valid dishes. Paired bootstrap on the same dish draws. The "
        "verdict is not distinguished when the interval contains 0.",
        "",
        *difference_table(diffs),
        "",
        "## Differences on common dishes",
        "",
        "The same differences with both cells restricted to the dishes that are valid in both, "
        "on the same dish draws.",
        "",
        *difference_table(common),
        "",
        f"Run date {run_date}, sample size {n}.",
        "",
    ]
    return "\n".join(out)


def tsv(rows: list[list]) -> str:
    def text(v: object) -> str:
        if v is None:
            return ""
        return str(v).lower() if isinstance(v, bool) else str(v)

    return "".join("\t".join(text(v) for v in row) + "\n" for row in rows)


def summarise_cell(
    model: str, prompt_id: str, ids: list[str], ref: np.ndarray, records: dict
) -> tuple[list[list], CellData, dict]:
    """Per-call rows, the data for the metrics and the counts of one cell. A dish without a
    record has no row and counts as not valid."""
    recorded = {
        i: records[model, prompt_id, d]
        for i, d in enumerate(ids)
        if (model, prompt_id, d) in records
    }
    outcomes = {i: classify(r) for i, r in recorded.items()}
    usage = {i: usage_tokens(r) for i, r in recorded.items()}
    costs = {i: config.cost_usd(model, *usage[i]) for i in recorded}
    rows = [
        [model, prompt_id, ids[i], o.status, o.reason, ref[i], o.pred_kcal, *usage[i], costs[i]]
        for i, o in outcomes.items()
    ]
    ok = {i: o.pred_kcal for i, o in outcomes.items() if o.status == "ok"}
    cell = CellData(
        valid=np.array([i in ok for i in range(len(ids))]),
        pred=np.array([ok.get(i, np.nan) for i in range(len(ids))]),
        ref=ref,
    )
    status = Counter(o.status for o in outcomes.values())
    reasons = Counter(o.reason for o in outcomes.values() if o.status != "ok")
    partial = len(recorded) < len(ids)
    total_cost = sum(costs.values())
    counts = {
        "n_sampled": len(ids),
        "n_recorded": len(recorded),
        "partial": partial,
        "n_valid": status["ok"],
        "n_invalid": status["invalid"],
        "n_error": status["error"],
        "n_refusal": status["refusal"],
        "n_substituted": status["substituted"],
        "failure_share": "n/a" if partial else 1 - status["ok"] / len(ids),
        "cost_usd": total_cost,
        "mean_cost_per_call": total_cost / len(recorded) if recorded else "n/a",
        "input_tokens": sum(a for a, _ in usage.values()),
        "output_tokens": sum(b for _, b in usage.values()),
        "reasons": ";".join(f"{r}:{n}" for r, n in sorted(reasons.items())),
    }
    return rows, cell, counts


DIFFERENCE_COLUMNS = "comparison metric difference low high verdict partial".split()


def difference_tsv(diffs: list[dict]) -> str:
    rows = [[*DIFFERENCE_COLUMNS, "undefined_resamples"]]
    for d in diffs:
        rows.append(
            [d[k] for k in DIFFERENCE_COLUMNS] + [undefined_text({d["metric"]: d["undefined"]})]
        )
    return tsv(rows)


def score() -> int:
    ids = sampler.read_ids(config.SAMPLE_FILE)
    reference = data.load_reference()
    no_reference = [i for i in ids if i not in reference]
    if no_reference:
        raise ValueError(f"expected a reference energy for every dish, missing {no_reference}")
    records = load_records(ids)
    ref = np.array([reference[i] for i in ids])

    call_rows = [CALL_COLUMNS]
    cells: dict[Cell, CellData] = {}
    counts: dict[Cell, dict] = {}
    for _, model, prompt_id in config.CELLS:
        rows, cells[model, prompt_id], counts[model, prompt_id] = summarise_cell(
            model, prompt_id, ids, ref, records
        )
        call_rows += rows

    draws = draw_indices(len(ids), config.BOOTSTRAP_SEED, config.BOOTSTRAP_RESAMPLES)
    point, samples = bootstrap(cells, draws)
    partial = frozenset(k for k, c in counts.items() if c["partial"])
    diffs = differences(point, samples, partial)
    common = common_differences(cells, draws, partial)

    metric_columns = [f"{m}{suffix}" for m in METRICS for suffix in ("", "_low", "_high")]
    cell_rows = [
        ["model", "prompt", *next(iter(counts.values())), *metric_columns, "undefined_resamples"]
    ]
    for (model, prompt_id), c in counts.items():
        metric_values = []
        for m in METRICS:
            low, high = interval(samples[model, prompt_id][m])
            metric_values += [point[model, prompt_id][m], low, high]
        undefined = undefined_text(undefined_counts(samples[model, prompt_id]))
        cell_rows.append([model, prompt_id, *c.values(), *metric_values, undefined])

    run_date = json.loads((config.RAW_DIR / "run.json").read_text())["utc"][:10]
    config.RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    (config.RESULTS_DIR / "per_call.tsv").write_text(tsv(call_rows))
    (config.RESULTS_DIR / "cells.tsv").write_text(tsv(cell_rows))
    (config.RESULTS_DIR / "differences.tsv").write_text(difference_tsv(diffs))
    (config.RESULTS_DIR / "differences_common.tsv").write_text(difference_tsv(common))
    config.RESULTS_MD.write_text(
        render_markdown(counts, point, samples, diffs, common, run_date, len(ids))
    )
    for (model, prompt_id), c in counts.items():
        note = f", partial ({c['n_recorded']}/{c['n_sampled']} records)" if c["partial"] else ""
        print(
            f"{model} {prompt_id}: valid {c['n_valid']}/{c['n_sampled']}, invalid "
            f"{c['n_invalid']}, error {c['n_error']}, refusal {c['n_refusal']}, "
            f"substituted {c['n_substituted']}, "
            f"cost {c['cost_usd']:.4f} USD, reasons {c['reasons'] or 'none'}{note}"
        )
    return 0
