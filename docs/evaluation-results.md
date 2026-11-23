# Evaluation results

Protocol: [evaluation-protocol.md](evaluation-protocol.md)

Reference energies are from Nutrition5k (Thames et al., CVPR 2021), released under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), data at https://github.com/google-research-datasets/Nutrition5k. `eval/results/per_call.tsv` repeats them for each dish. The selection of 300 dishes is the only change to the data.

## Headline

MAE in kcal on valid calls with its 95% percentile interval, the share of sampled dishes without a valid call, and the mean cost of a call. A cell with fewer records than sampled dishes is partial and has no failure share.

| Model | Prompt | MAE (kcal) | Failure share | Mean cost per call (USD) |
|---|---|---|---|---|
| claude-haiku-5-5 | p1 | 115.0 [103.8, 126.8] | 7.0% | 0.000061 |
| claude-haiku-5-5 | p2 | 121.4 [108.2, 135.3] | 0.0% | 0.000120 |
| claude-sonnet-5-5 | p1 | 106.9 [86.9, 129.2] | 70.3% | 0.001895 |
| claude-sonnet-5-5 | p2 | 92.3 [82.0, 103.1] | 1.7% | 0.002342 |

## Calls and cost

| Model | Prompt | Sampled | Recorded | Valid | Invalid | Error | Refusal | Substituted | Failure share | Input tokens | Output tokens | Cost (USD) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 | p1 | 300 | 300 | 279 | 21 | 0 | 0 | 0 | 7.0% | 153600 | 6114 | 0.0184 |
| claude-haiku-5-5 | p2 | 300 | 300 | 300 | 0 | 0 | 0 | 0 | 0.0% | 169800 | 38025 | 0.0360 |
| claude-sonnet-5-5 | p1 | 300 | 300 | 89 | 211 | 0 | 0 | 0 | 70.3% | 153600 | 26121 | 0.5684 |
| claude-sonnet-5-5 | p2 | 300 | 300 | 295 | 5 | 0 | 0 | 0 | 1.7% | 169800 | 36295 | 0.7026 |

## Metrics

Value and 95% percentile interval from 10,000 bootstrap resamples of the 300 dishes. Metrics use the valid calls; a dish without a record counts as not valid. MAPE, relative bias and the within-share metrics also need a reference of at least 50 kcal. Ratios are shown as percentages.

| Model | Prompt | MAE (kcal) | Signed mean error (kcal) | Median absolute error (kcal) | MAPE | Mean relative bias | Within 20% | Within 30% |
|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 | p1 | 115.0 [103.8, 126.8] | 63.1 [46.5, 78.9] | 83.1 [75.0, 103.9] | 58.2% [51.1%, 65.9%] | 46.1% [37.6%, 55.0%] | 26.1% [20.7%, 31.7%] | 39.4% [33.2%, 45.6%] |
| claude-haiku-5-5 | p2 | 121.4 [108.2, 135.3] | 52.4 [33.8, 70.8] | 79.3 [67.6, 99.6] | 56.8% [49.8%, 64.4%] | 36.1% [27.1%, 45.1%] | 26.3% [21.0%, 31.7%] | 37.8% [31.9%, 43.6%] |
| claude-sonnet-5-5 | p1 | 106.9 [86.9, 129.2] | 48.1 [16.8, 75.3] | 81.6 [64.8, 105.2] | 49.0% [38.5%, 61.5%] | 35.3% [22.0%, 49.9%] | 29.3% [19.4%, 39.3%] | 50.0% [39.1%, 61.0%] |
| claude-sonnet-5-5 | p2 | 92.3 [82.0, 103.1] | 2.6 [-12.6, 17.3] | 63.7 [53.0, 75.5] | 41.3% [36.3%, 46.8%] | 15.7% [9.0%, 22.8%] | 33.5% [27.8%, 39.3%] | 50.2% [44.1%, 56.3%] |

## Differences

Each cell uses its own valid dishes. Paired bootstrap on the same dish draws. The verdict is not distinguished when the interval contains 0.

| Comparison | Metric | Difference | 95% interval | Verdict |
|---|---|---|---|---|
| p2 minus p1 (claude-haiku-5-5) | MAE (kcal) | 6.4 | [-4.3, 17.0] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Signed mean error (kcal) | -10.8 | [-24.5, 3.1] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Median absolute error (kcal) | -3.8 | [-22.7, 10.0] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | MAPE | -1.4% | [-7.0%, 4.3%] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Mean relative bias | -10.1% | [-16.4%, -3.6%] | negative |
| p2 minus p1 (claude-haiku-5-5) | Within 20% | 0.2% | [-6.0%, 6.3%] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Within 30% | -1.6% | [-7.9%, 4.6%] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | MAE (kcal) | -14.6 | [-32.9, 2.2] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | Signed mean error (kcal) | -45.5 | [-69.4, -20.1] | negative |
| p2 minus p1 (claude-sonnet-5-5) | Median absolute error (kcal) | -17.9 | [-40.4, -4.6] | negative |
| p2 minus p1 (claude-sonnet-5-5) | MAPE | -7.7% | [-17.7%, 1.1%] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | Mean relative bias | -19.6% | [-31.3%, -8.6%] | negative |
| p2 minus p1 (claude-sonnet-5-5) | Within 20% | 4.2% | [-6.0%, 14.2%] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | Within 30% | 0.2% | [-10.3%, 10.8%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | MAE (kcal) | -8.1 | [-25.4, 11.0] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Signed mean error (kcal) | -15.0 | [-40.3, 8.8] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Median absolute error (kcal) | -1.4 | [-23.6, 20.1] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | MAPE | -9.2% | [-19.3%, 1.3%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Mean relative bias | -10.8% | [-22.7%, 1.7%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Within 20% | 3.1% | [-6.6%, 13.2%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Within 30% | 10.6% | [-0.1%, 21.3%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | MAE (kcal) | -29.1 | [-39.6, -18.8] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Signed mean error (kcal) | -49.8 | [-61.5, -38.3] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Median absolute error (kcal) | -15.6 | [-33.7, -2.5] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | MAPE | -15.5% | [-21.8%, -9.4%] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Mean relative bias | -20.4% | [-27.4%, -13.4%] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Within 20% | 7.1% | [0.6%, 13.8%] | positive |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Within 30% | 12.4% | [5.3%, 19.5%] | positive |

## Differences on common dishes

The same differences with both cells restricted to the dishes that are valid in both, on the same dish draws.

| Comparison | Metric | Difference | 95% interval | Verdict |
|---|---|---|---|---|
| p2 minus p1 (claude-haiku-5-5) | MAE (kcal) | 0.8 | [-8.9, 10.3] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Signed mean error (kcal) | -5.8 | [-17.5, 6.4] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Median absolute error (kcal) | -6.1 | [-23.8, 8.8] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | MAPE | -0.8% | [-6.5%, 5.0%] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Mean relative bias | -8.0% | [-14.3%, -1.6%] | negative |
| p2 minus p1 (claude-haiku-5-5) | Within 20% | 0.4% | [-5.8%, 6.6%] | not distinguished |
| p2 minus p1 (claude-haiku-5-5) | Within 30% | -1.2% | [-7.5%, 5.1%] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | MAE (kcal) | -11.0 | [-21.0, -1.3] | negative |
| p2 minus p1 (claude-sonnet-5-5) | Signed mean error (kcal) | -24.1 | [-34.6, -13.8] | negative |
| p2 minus p1 (claude-sonnet-5-5) | Median absolute error (kcal) | -24.9 | [-43.1, -7.0] | negative |
| p2 minus p1 (claude-sonnet-5-5) | MAPE | -4.9% | [-11.6%, 1.8%] | not distinguished |
| p2 minus p1 (claude-sonnet-5-5) | Mean relative bias | -10.2% | [-17.0%, -3.3%] | negative |
| p2 minus p1 (claude-sonnet-5-5) | Within 20% | 13.6% | [2.5%, 25.0%] | positive |
| p2 minus p1 (claude-sonnet-5-5) | Within 30% | 7.4% | [-2.2%, 17.5%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | MAE (kcal) | -16.8 | [-28.6, -5.3] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Signed mean error (kcal) | -25.9 | [-37.5, -14.4] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Median absolute error (kcal) | -33.2 | [-55.0, 5.1] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | MAPE | -5.2% | [-10.9%, 0.4%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Mean relative bias | -7.2% | [-13.3%, -1.1%] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Within 20% | 6.1% | [-3.7%, 16.0%] | not distinguished |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p1) | Within 30% | 14.6% | [5.0%, 24.7%] | positive |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | MAE (kcal) | -29.1 | [-39.6, -18.9] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Signed mean error (kcal) | -51.3 | [-63.0, -39.9] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Median absolute error (kcal) | -16.7 | [-34.8, -2.4] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | MAPE | -16.0% | [-22.4%, -9.8%] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Mean relative bias | -21.0% | [-28.0%, -13.9%] | negative |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Within 20% | 7.0% | [0.4%, 13.7%] | positive |
| claude-sonnet-5-5 minus claude-haiku-5-5 (p2) | Within 30% | 12.5% | [5.4%, 19.5%] | positive |

Run date 2026-11-23, sample size 300.
