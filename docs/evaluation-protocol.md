# Evaluation protocol: energy estimation from one overhead photo

Registered: 2026-11-23 (UTC), before any model call of this study.

This file is never edited after it lands. A change is a dated amendment appended to `docs/evaluation-amendments.md`, and the owner approves each amendment before it is written. No result has been seen when this text is registered.

## Question

How large are the energy errors of Claude Haiku 5.5 and Claude Sonnet 5.5 (Anthropic) when they estimate the food energy of a plate from one overhead photo, with two prompt forms: P1 asks for the total, P2 asks for every visible food with grams and kcal and the total is summed by code? The numbers feed the choice of model and of output form for the app. No pass or fail threshold is registered; the owner decides after the results are published.

## Data

Nutrition5k (Google Research, Thames et al., CVPR 2021, arXiv 2103.03375). Files are read one by one over HTTPS from the public bucket `https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/`, without an account.

Three reference files are pinned by SHA-256: `depth_test_ids.txt` `6e43a5334a72bd06fa9c0d4b3bc86e2f57e5342b0b260d3fa003a76f7e39eca2`, `dish_metadata_cafe1.csv` `881df31f27c2343d0ce219964527e0796f6ddadd60701ce6840fa801e8c2a960`, `dish_metadata_cafe2.csv` `ef9f800d7b9c2e7e9a9e7cda5cbb4cfe51c760a8c1af4c05786ccf051bf5d77d`. The scorer and the pool builder refuse other bytes.

Licence sentence, quoted from the dataset README at https://github.com/google-research-datasets/Nutrition5k: "We release all Nutrition5k data under the Creative Commons V4.0 license. You are free to share and adapt this data for any purpose, even commercially." The sentence names no variant. The link behind "Creative Commons V4.0" points to https://creativecommons.org/licenses/by/4.0/ (CC BY 4.0). This repository gives the source and does not redistribute any image. The per-call table repeats reference energies from Nutrition5k: Google Research, Nutrition5k, https://github.com/google-research-datasets/Nutrition5k, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). The selection of 300 dishes is the only change to the data.

## Pool

Dishes of `dish_ids/splits/depth_test_ids.txt` that have

- a total energy (second column, `total_calories`) in `metadata/dish_metadata_cafe1.csv` or `metadata/dish_metadata_cafe2.csv`, and
- an overhead image `imagery/realsense_overhead/<dish_id>/rgb.png` that answers a HEAD request with status 200.

Checked on 2026-11-22 with `python -m plate_eval build-pool`: the split lists 507 dishes; all 507 are in the pool; 0 are left out (`eval/pool_excluded.tsv` has only its header). All 507 are Cafe 1 dishes. One pool dish has a total energy of 0.0 kcal and 83 have less than 50 kcal; the pool median is 226 kcal. One image was downloaded to check its format: PNG, 640 x 480. The runner downloads each image once before its first call. A download that fails under the retry rule below, or a file that is not a PNG, gives that dish status `error` in all four cells; it counts in the failure share and in stop rule 3. `eval/pool_ids.txt` lists the pool.

## Sample

300 dishes drawn without replacement with `random.Random(20261122).sample(sorted_pool, 300)` on Python 3.13.18, where `sorted_pool` is the pool sorted as strings. The sorted ids are in `eval/sample_ids.txt`. `python -m plate_eval sample --check` redraws and compares.

## Calls

Each (image, model, prompt) is called once: 300 dishes x 2 models x 2 prompts = 1,200 calls. Models: `claude-haiku-5-5` and `claude-sonnet-5-5`. Prompts: `eval/prompts/p1.txt` (SHA-256 `100eabaf7d3a9ca66aaa342bc5acf5360958a5744ac3ef613bd49b6c15ec4185`) and `eval/prompts/p2.txt` (SHA-256 `ee8c04c67631bf377987f2821833d3f270523707010f804be3eba4216b9f2288`). The image is the 640 x 480 PNG exactly as downloaded, placed before the prompt text, sent as base64. It is below the models' image size limits and is not resized. A PNG of another size is sent as it is and its size is recorded. The prompt text sent is the file text with surrounding whitespace removed; the SHA-256 values above are of the file bytes. No system prompt, no tools.

Parameters, each checked against the vendor documentation on 2026-11-22:

| Parameter | Setting | Reason |
| --- | --- | --- |
| `max_tokens` | 600 | Allowed for both models. Twice the assumed P2 output of 300 tokens. |
| `temperature` | not sent | Both models reject non-default values; API version 2026-10-21 (the default of the SDK used here) rejects any value. Sampling therefore runs at the API default, and repeated calls would differ. |
| Thinking | Haiku: `{"type": "disabled"}`; Sonnet: `{"type": "between_tools"}` | Haiku accepts `disabled`. Sonnet rejects `disabled` with 400; the documentation describes `between_tools` as turning off up-front thinking. |
| `output_config.effort` | not sent | Defaults apply: medium for Haiku, high for Sonnet. |
| Fallbacks | none | Claude Haiku 5.5 has no server-side fallback. Claude Sonnet 5.5 has one, which would answer with another model; the run does not request it. A refusal is recorded as a failure. |
| SDK | `anthropic` 2.12.0 with `max_retries=0` | Retries are done by the runner so that the rule below holds. |

Retries: only on HTTP 429 and on HTTP 5xx, at most 5 retries, waiting 2, 4, 8, 16 and 32 seconds. If `retry-after` is present, its value capped at 60 seconds replaces the scheduled wait. The request timeout is 120 seconds. Any other failure (connection error, timeout, 4xx) is recorded as an API error and is not repeated. A call that has a raw record is never repeated.

## Order and resumption

Order: Haiku with P1, Haiku with P2, Sonnet with P1, Sonnet with P2, each over the sorted sample, up to 4 calls at a time inside a cell.

After a pause or stop the run resumes in the same order. Dishes without a raw record are called and dishes with one never again. A cell is finished before the next starts. No cell is skipped, reordered or dropped except by an amendment.

## Response handling

The text blocks of the response are joined with no separator and stripped. One surrounding Markdown code fence is accepted and removed; a fence is a first line of three backticks with an optional language word and a last line of three backticks, after stripping. Nothing else is repaired. The text must then be one JSON object (NaN, Infinity and duplicate keys are rejected).

- P1: exactly the key `total_kcal`, a finite number (not a boolean) from 0 to 5,000.
- P2: exactly the key `items`, a list of at most 20 objects. Each has exactly the keys `name` (string of 1 to 100 characters after surrounding whitespace is removed), `grams` (finite number from 1 to 2,000) and `kcal` (finite number from 0 to 5,000). The predicted total is the sum of the item `kcal` values, computed by the code. An empty `items` list is `ok` and its predicted total is 0 kcal. `grams` and `name` are validated and stored, and are not scored.

Every call gets one status. `ok`: parsed and valid. `invalid`: no text, not parseable, or failed validation. A reply with stop reason `max_tokens` is `invalid` even if its text parses. `error`: API error after retries. `refusal`: stop reason `refusal`. `substituted`: another model answered. A trailing hyphen and eight digits (a date suffix) are removed from the `model` field of the response before it is compared with the requested model id; if they then differ, the call is costed and not scored. Only `ok` calls enter the error metrics. Each cell reports its counts of `invalid`, `error`, `refusal` and `substituted` in separate columns and its failure share, 1 - (ok calls / 300).

A change to response handling after any call is an amendment that applies to all four cells, and the scores under the registered handling are published beside the scores under the amended handling.

## Metrics

The headline result is MAE in kcal on `ok` calls, per cell, shown with the failure share and the mean cost per call. Other metrics are secondary. The decision (model, prompt form, go or no-go) is recorded in DECISIONS.md with its date and states that the results had been seen.

Per cell (model and prompt, four cells). Error = predicted total minus reference total energy, in kcal.

On all `ok` calls of the cell: MAE (mean absolute error), signed mean error (mean error), median absolute error.

On `ok` calls whose reference energy is at least 50 kcal (relative errors are unstable on tiny denominators; this cut is fixed here, before any output is seen): MAPE (mean of |error| / reference), mean relative bias (mean of error / reference), share within 20% (|error| / reference at most 0.20) and share within 30% (at most 0.30).

All comparisons use the values as parsed, in 64-bit floats, with no rounding; the bounds 50, 0.20 and 0.30 are inclusive, tested as `abs(error) <= 0.20 * reference`. Rounding is for display only: kcal values to one decimal, ratios and shares as percentages to one decimal.

No dish is dropped after the sample is drawn. The dish with reference 0.0 kcal (dish_1557861216) counts in MAE, mean error and median absolute error, and not in the ratio metrics.

The reported value of a metric is computed on the full sample.

Intervals: a bootstrap over dishes. Indices are `rng.integers(0, 300, size=(10000, 300))` with `rng = numpy.random.default_rng(20261123)`, over the dishes in the order of `eval/sample_ids.txt`, with numpy 2.5.5 and Python 3.13.18: 10,000 resamples, each of 300 dish indices drawn with replacement. The same draws are used for all cells, so differences are paired. In each resample, each metric is computed on the resampled dishes that are `ok` in that cell (and, for the ratio metrics, have a reference of at least 50 kcal). A resample with no eligible dish for a metric gives no value, and the number of such resamples is reported. The 95% interval is the 2.5th to the 97.5th percentile of the values (`numpy.nanpercentile` over the resamples that gave a value, with linear interpolation).

Differences: P2 minus P1 within each model, and Sonnet minus Haiku within each prompt, for every metric. Differences use each cell's own `ok` dishes. The same differences on dishes that are `ok` in both cells are reported in a second table. The difference is computed per resample from the two cell values; the interval is taken the same way. A difference whose interval includes 0 is reported as "not distinguished". There are no significance stars and no claim beyond the intervals.

## Literature context

Background only. The samples, prompts and metric definitions differ, so these numbers are not comparable with this study.

- Tanabe and Yanai, Nutrients 2025, 17(7), 1128 (doi 10.3390/nu17071128), Table 1: one multimodal large language model in a zero-shot setting, MAE 82.7 kcal and MAPE 46.7%, on a test split of 506 samples, the samples left after 2,759 training samples. The paper names no split file and gives no formula for MAPE.
- Thames et al., arXiv 2103.03375, Table 3: the monocular model ("2D Direct Prediction") has a calorie MAE of 70.6 kcal; the percentage next to it, 26.1%, is the "mean absolute error as a percent of the respective mean", which is MAE divided by the mean reference and differs from MAPE. The test set is the paper's own, 10% of the dishes.

## Budget and stop rules

Prices (https://platform.claude.com/docs/en/about-claude/pricing, read 2026-11-22), per million tokens, input and output: Claude Haiku 5.5 $0.10 and $0.50 for prompts up to 100,000 tokens ($0.50 and $2.50 above); Claude Sonnet 5.5 $2 and $10. The evaluation's cost is capped at 3.50 USD by stop rule 1; the key's workspace has a monthly spend limit of 5 USD.

Image tokens (https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-11-22): ceil(width / 28) x ceil(height / 28) = 23 x 18 = 414 for 640 x 480.

Prompt text is estimated as ceil(number of characters of the stripped prompt text / 3) tokens: 82 for P1 and 132 for P2. The vendor states that the current tokenizer produces about 30% more tokens than the previous one; 3 characters per token is an assumption. Expected output of 40 tokens for P1 and 300 for P2 is an assumption.

| Cell | Input tokens (image + prompt) | Expected output tokens | Estimated cost (USD) |
| --- | --- | --- | --- |
| Haiku, P1 | 496 (414 + 82) | 40 | 0.0209 |
| Haiku, P2 | 546 (414 + 132) | 300 | 0.0614 |
| Sonnet, P1 | 496 (414 + 82) | 40 | 0.4176 |
| Sonnet, P2 | 546 (414 + 132) | 300 | 1.2276 |
| Total, 1,200 calls | | | 1.7275 |

If every call used all 600 output tokens, the total would be 4.4365 USD.

Stop rules:

1. The sum is over all raw records of the study, from `usage` and the prices in this file. The run stops when the sum is above 3.50 USD; calls in flight finish and are recorded. A response without `usage` costs 0.
2. The first 20 dishes of the cell in the order of `eval/sample_ids.txt`; the mean of `input_tokens + output_tokens` over those of the 20 calls that returned a response is compared with 804 tokens per call (P1) or 1,269 (P2), which is 150% of the estimate in the table; a mean above the threshold pauses the run.
3. After each completed call, once the cell has at least 20 completed calls, compute (`error` + `refusal` + `substituted`) / completed calls of that cell, each dish once, retries not counted, `invalid` not counted. A value above 0.05 stops the whole run.

A cell with fewer than 300 calls is marked incomplete: its counts are reported, its failure share is not, and its metrics are labelled partial.

The runner writes raw responses to files. A pause or stop report contains counts per status, tokens and cost only. No estimate, error value or raw reply text is read or shown before the run is complete. The runner writes a marker file at the moment it stops or pauses and refuses to start while that file exists, so a run continues only after the owner decides and the decision is passed to it explicitly. Any change of the protocol is an amendment.

## Limits

- Plates from a few select cafeterias in California, USA (the dataset README's words), photographed by a fixed overhead camera. A phone photo at another angle and distance is a different task.
- No Chinese home cooking.
- The evaluation sends 640 x 480 PNG images (414 image tokens). The app will send JPEGs with a 1024 px long side (ceil(1024 / 28) x ceil(768 / 28) = 37 x 28 = 1,036 tokens at 4:3). The image part of the app's input is about 2.5 times the evaluation's, so its cost per call is higher and its accuracy may differ.
- One call per cell and dish with sampling at the API default: part of the variation between dishes is sampling noise.
- 300 dishes of the 507 in the split. The intervals describe this sample.
- The reference energy is computed from the weight of each ingredient, measured as it was added to the plate, and per-gram values from the USDA Food and Nutrient Database (Thames et al.). It is a computed value, not a direct measurement.
- The result describes this sample and is not carried over to the owner's meals.

## What is published

This protocol, `eval/sample_ids.txt`, both prompt files, every raw response (`eval/raw/`), the per-call table and the result tables with intervals (`eval/results/`, `docs/evaluation-results.md`, generated by `python -m plate_eval score`), whatever the result is. The per-call table repeats reference energies from Nutrition5k: Google Research, Nutrition5k, https://github.com/google-research-datasets/Nutrition5k, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).

## Reproduction

```
uv run --project eval python -m plate_eval build-pool
uv run --project eval python -m plate_eval sample --check
uv run --project eval python -m plate_eval run --dry-run
uv run --project eval python -m plate_eval run
uv run --project eval python -m plate_eval score
```

`run` needs an Anthropic API key in the environment; the other commands need none.
