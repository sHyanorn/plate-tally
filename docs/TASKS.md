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
- [ ] M0.3 Evaluation protocol registered, with the evaluation code and its tests.

Run and decide:

- [ ] M0.4 Run the evaluation. The evaluation's cost is capped at 3.50 USD by its stop rule; the key's workspace has a monthly spend limit of 5 USD.
- [ ] M0.5 Score the raw records and publish the results.
- [ ] M0.6 Decide the model and go or no-go. Record it in DECISIONS.md with its date, stating that the results had been seen.

## Gate

After a go and before M1, so the build route is known to work early.

- [ ] G1 Enrol in the platform's paid developer programme.
- [ ] G2 Smoke test of the upload route: a minimal app built on a hosted macOS runner and uploaded to TestFlight.

## M1 Logic as a Swift package, tested on Linux

No UI code. Each module has tests that run on Linux without network.

- [ ] M1.1 Core: food item, meal, units, errors.
- [ ] M1.2 Energy: Mifflin-St Jeor, activity factors, the test vector in SPEC.md.
- [ ] M1.3 Estimation: request building, response parsing and validation (R5, R6).
- [ ] M1.4 FoodData: local table, name matching, kcal per 100 g. Record the matching rule in DECISIONS.md first.
- [ ] M1.5 Ledger: meal records, daily totals, edit and recompute.
- [ ] M1.6 Cost: price table, per-call cost from usage, day and month totals, call limit.
- [ ] M1.7 FoodData table generator from USDA data. The generated table is not committed. Foundation Foods energy is in the Atwater fields (nutrient id 2047 and 2048); the SR Legacy field is checked in M1.
- [ ] M1.8 CI on Linux: repository checks and package tests.

## M2 Interface and CI

- [ ] M2.1 Screen: capture or pick a photo, resize, JPEG, request.
- [ ] M2.2 Screen: item list with editing.
- [ ] M2.3 Screen: day view with intake and expenditure.
- [ ] M2.4 Screen: settings for key, profile, activity factor and call limit.
- [ ] M2.5 Project file generated from a text spec. Not committed.
- [ ] M2.6 Hosted macOS build in CI.

## M3 First installable build

- [ ] M3.1 Signing.
- [ ] M3.2 Upload to TestFlight from CI.
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
