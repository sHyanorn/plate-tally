# plate-tally

plate-tally is specified as an iOS app for one person's daily use. It will estimate the energy of a meal from a photo and show the estimated daily energy expenditure next to it. It will report numbers only: no weight goal, no deficit, no advice.

## How it will work

1. Photograph a meal. The app will resize the photo to 1024 px on the long side and send it to a hosted model, Claude Sonnet 5.5 (Anthropic).
2. The model will list the visible foods with gram weights.
3. You correct the list. Energy will be recomputed on the device from a local table built from USDA FoodData Central (CC0). Where no table entry matches, the model's own kcal value will be used and marked as an estimate.
4. Expenditure will come from the Mifflin-St Jeor equation times one of four activity factors.

Model calls will be paid by you, per call, with your own API key. The app will show the cost of each call and enforce a daily call limit (default 30). The key will be stored only in the keychain and will be sent only to the Anthropic API as the request credential. There will be no server and no account. Requirements are in [docs/SPEC.md](docs/SPEC.md).

## State

M0, the accuracy evaluation, is complete. The protocol was registered before any call, and the run is scored in [docs/evaluation-results.md](docs/evaluation-results.md). The lowest mean absolute error is 92.3 kcal (95% interval 82.0 to 103.1), from Claude Sonnet 5.5 with the prompt that lists every food, with 1.7% of calls invalid. D009 chose that model and prompt and decided to go on. The plates are from California cafeterias under a fixed overhead camera, so the number does not carry over to phone photos or home cooking.

The app is one screen that shows its name, version and build number. CI builds and archives it without signing on a hosted macOS runner (App/, .github/workflows/ios-build.yml). Signing and upload to TestFlight follow the enrolment in the paid developer programme. M1, the Swift package, does not wait for it. The plan is in [docs/TASKS.md](docs/TASKS.md), the reasons are in [docs/DECISIONS.md](docs/DECISIONS.md).

## Evaluation

Which model the app calls was decided from measured accuracy and cost (D009). The evaluation ran 2 models and 2 prompts on 300 dishes of the Nutrition5k dataset, 1,200 calls. The protocol was written before any call was made and is in [docs/evaluation-protocol.md](docs/evaluation-protocol.md). The results are in [docs/evaluation-results.md](docs/evaluation-results.md).

## Checks

Python 3 and uv are required. No check calls a paid API. The last command below prints the planned requests and the estimated cost, with no network call and no key.

```
python3 scripts/check_strings.py
python3 -m unittest discover -s scripts -p "test_*.py"
uv run --project eval ruff check eval scripts
uv run --project eval ruff format --check eval scripts
uv run --project eval pytest eval/tests
uv run --project eval python -m plate_eval run --dry-run
```

The app is not built by these commands. It builds in CI on a hosted macOS runner.

## Limits

- The hosted model can misname foods and misjudge portions. You will correct the list.
- The evaluation uses plates from a few select cafeterias in California, USA (the dataset README's words). It says nothing about Chinese home cooking.
- The evaluation sends 640 x 480 PNG images (414 image tokens). The app will send JPEGs with a 1024 px long side (about 1,036 tokens at 4:3). The image part of the app's input is about 2.5 times the evaluation's, so its cost per call is higher and its accuracy may differ.
- Expenditure will be an estimate from a population equation (R2 = 0.71 in the sample of 498 adults that derived it; Mifflin et al. 1990, cited in docs/SPEC.md). A person's own value can differ.
- Photos will leave the device and go to Anthropic. See the privacy section of [docs/SPEC.md](docs/SPEC.md).

## Licence

MIT. See [LICENSE](LICENSE).
