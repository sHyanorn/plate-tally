# Tasks

## Working practices

- Write a plan before each milestone.
- One commit per task. Conventional Commits, in English.
- Check the task off here in the same commit.
- Record each decision in DECISIONS.md.
- A task is done when the checks in CLAUDE.md pass and the behaviour matches SPEC.md.

## M0 Accuracy evaluation

Question: which hosted model, if any, is accurate and cheap enough for daily use. The plan is in evaluation-protocol.md.

Registered before any paid call:

- [x] M0.1 Licence (MIT), repository rules, string check script and its tests.
- [x] M0.2 Specification, tasks, decisions.
- [x] M0.3 Evaluation protocol registered, with the evaluation code and its tests.

Run and decide:

- [x] M0.4 Run the evaluation. The evaluation's cost is capped at 3.50 USD by its stop rule; the key's workspace has a monthly spend limit of 5 USD.
- [x] M0.5 Score the raw records and publish the results.
- [x] M0.6 Decide the model and go or no-go. Record it in DECISIONS.md with its date, stating that the results had been seen.

## Gate

The half of G2 that needs no paid account comes first, so the build route is known to work early. M1 does not depend on the account. Signing and upload (G2.3) come after G1.

- [ ] G1 Enrol in the platform's paid developer programme.
- [ ] G2 Smoke test of the upload route: a minimal app built on a hosted macOS runner and uploaded to TestFlight.
  - [x] G2.1 Minimal app and its project spec.
  - [x] G2.2 Unsigned build and archive on a hosted macOS runner.
  - [ ] G2.3 Signing and upload to TestFlight (needs G1).

## M1 Logic as a Swift package, tested on Linux

No UI code. Each module has tests that run on Linux without network. M1.4 (FoodData) and M1.7 (table generator) moved to M4 by D011.

- [ ] M1.1 Core: food item, meal, units, errors.
- [ ] M1.2 Energy: Mifflin-St Jeor, activity factors, the test vector in SPEC.md.
- [ ] M1.3 Estimation: request building, response parsing and validation (R5, R6).
- [ ] M1.5 Ledger: meal records, daily totals, edit and recompute.
- [ ] M1.6 Cost: price table, per-call cost from usage, day and month totals, call limit.
- [ ] M1.8 CI on Linux: repository checks and package tests.

## M2 Interface and CI

- [ ] M2.1 Screen: capture or pick a photo, turn it upright, resize, JPEG, request.
- [ ] M2.2 Screen: item list with editing.
- [ ] M2.3 Screen: day view with intake and expenditure.
- [ ] M2.4 Screen: settings for key, profile, activity factor and call limit.
- [ ] M2.5 Extend App/project.yml with the Swift package and the screens.
- [ ] M2.6 Extend the hosted macOS build in CI to build the screens.

## M3 First installable build

- [ ] M3.1 Signing of the full app, reusing G2.3.
- [ ] M3.2 Upload of the full app to TestFlight from CI, reusing G2.3.
- [ ] M3.3 Beta test group.
- [ ] M3.4 Install on the author's device.
- [ ] M3.5 First week of use: notes on errors, cost and corrections.

## M4 Later ideas

Not commitments.

- Chinese food composition data. Check the licence first.
- A reference object in the photo for scale.
- Compare the model's list with weighed meals.
- An on-device model, once one meets the accuracy bar.
- Export of daily totals.
- A food table from USDA FoodData Central (Foundation Foods and SR Legacy, public domain) with name matching that returns no weak match, as postponed in D011. Checked on 2026-11-23 in the downloads of 2026-10-29 and 2018-04: SR Legacy has kcal in nutrient id 1008 for all 7,793 foods. Foundation Foods has it in id 2048 (Atwater specific factors) for 313 of 498 foods, in id 2047 (Atwater general factors) for 399, and in id 1008 for 135, of which 31 have only that one; 68 have none. Take 2048, else 2047, else 1008.
