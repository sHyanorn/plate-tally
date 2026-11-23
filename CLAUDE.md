# CLAUDE.md

plate-tally is specified as an iOS app (native SwiftUI) for one person's daily use. It will estimate the energy of a meal from a photo with a hosted model and show the estimated daily energy expenditure. It will be installed through TestFlight and built on hosted macOS runners.

The repository holds the specification, the accuracy evaluation of the hosted models (Python, in eval/), the repository checks (scripts/), the SwiftUI app with its project spec, unit tests and UI tests (App/) and a Swift package (Package.swift, Sources/, Tests/). Licence: MIT.

## Read first

1. docs/SPEC.md: what the app does and how it is built.
2. docs/TASKS.md: milestones and the next task.
3. docs/DECISIONS.md: why things are as they are.
4. docs/evaluation-protocol.md: the registered plan of the accuracy evaluation. It is never edited after it lands. A change is a dated amendment in docs/evaluation-amendments.md, approved by the owner first.

## Working practices

- Write a plan before each milestone.
- One commit per task. Conventional Commits, in English.
- Check the task off in docs/TASKS.md in the same commit.
- Record each decision in docs/DECISIONS.md.

## Repository rules

- Everything committed (code, comments, docs, commit messages) is in English and concise: say what changed and why, not the step-by-step process.
- No em dash and no en dash.
- The platform vendor's name never appears in any file, in any case, also inside other words. scripts/check_strings.py enforces it. scripts/string_allowlist.txt holds only lines that a tool forces into a file. Model replies recorded in eval/raw are data and stay as received: the check exempts that directory from the vendor-name and dash rules and keeps the key rule.
- Model names: the models the app calls and the evaluation measures, with their vendor. No other model is named.
- No model API key in files, workflows or builds. CI signing and upload will use secrets.
- Tests and CI never call a paid API.
- No photo and no dataset image is committed.

## Code style

- Short sentences. Numbers instead of adjectives.
- Comments say why, not what.
- Fail fast. An error says what happened, what was expected and what was seen.
- No dead code. No abstraction without a second use.
- Tests cover behaviour that matters.

## Commands

```
python3 scripts/check_strings.py
python3 -m unittest discover -s scripts -p "test_*.py"
uv run --project eval ruff check eval scripts
uv run --project eval ruff format --check eval scripts
uv run --project eval pytest eval/tests
swift build
swift test
uv run --project eval python -m plate_eval run --dry-run
```

Run all eight before each commit. The two Swift commands need Swift from swift.org (6.3.3 in CI, chosen to match Xcode 26.6) and no network. The last one makes no network call and needs no key. A real `run` needs a key in the environment and is part of M0 only.

The app builds and its tests run only on a hosted macOS runner (.github/workflows/ios-build.yml). No command here builds it; the Swift commands build the package. The generated project file is never committed (D008).
