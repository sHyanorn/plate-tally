# Specification

The plan is in TASKS.md. The reasons behind choices are in DECISIONS.md (D001 to D010).

## Purpose

plate-tally is an iOS app for one person's daily use. It does two things.

1. It estimates the energy of a meal from a photo. A hosted model lists the foods, the user corrects the list, the app computes kcal.
2. It estimates daily energy expenditure and shows it next to the day's intake.

The app reports numbers only. It sets no weight goal, computes no deficit and gives no advice (D004).

## Scope

- Platform: iOS 26.0 or later, iPhone only, native SwiftUI (D010).
- Distribution: TestFlight, one user. Builds run on hosted macOS runners.
- Model: Claude Sonnet 5.5 (claude-sonnet-5-5), from Anthropic, with the item-list prompt the evaluation calls P2 (D001, D002, D009). The app calls one model and uses the measured prompt.
- Out of scope: weight goals, deficit, advice, accounts, a server of our own, analytics, other vendors' models, branded food data.

## Requirements

### Analysis of a meal

- R1. The user takes a photo or picks one from the photo library.
- R2. Before sending, the app resizes the photo to 1024 px on the long side and re-encodes it as JPEG. A photo whose long side is under 1024 px is not enlarged.
- R3. The sent image carries no metadata (location, time, device).
- R4. One analysis is one request: the image and a fixed prompt. The app never sends the profile or past records.
- R5. The response must be a JSON object with one key, `items`: a list of at most 20 objects with exactly the keys `name`, `grams`, `kcal`. `name` is a string of 1 to 100 characters after surrounding whitespace is removed. `grams` is a number from 1 to 2,000. `kcal` is a number from 0 to 5,000.
- R6. Validation rejects. Surrounding whitespace and one surrounding code fence are removed before parsing; nothing else is repaired, trimmed or guessed. A response that fails R5 is shown as an error with its reason code.
- R7. The app never retries on its own. A new call happens only when the user asks, and it is counted and costed like any call.
- R8. Each item is matched against the local food table. A matched item has kcal = kcal per 100 g times grams divided by 100.
- R9. An item with no match keeps the model's kcal. It is marked as an estimate on screen and in the stored record.
- R10. The user can rename an item, change its grams, delete it and add one. Every edit recomputes the item and the meal locally. An edit makes no call. A rename re-runs the match. Grams of an estimate item scale its kcal in proportion.
- R11. Saving stores the record: date, time, items (name, grams, kcal, matched or estimate) and the meal total. The photo is not stored.
- R12. The user can edit or delete a stored record. Totals follow.

### Expenditure and day view

- R13. The profile holds height (cm), weight (kg), sex (female or male) and age (years), plus one of four activity factors.
- R14. Estimated daily expenditure = REE times the activity factor, with REE from the Mifflin-St Jeor equation (see Energy).
- R15. The day view shows each meal, the day's intake and the estimated expenditure. It shows no difference between them and no target.
- R16. Expenditure is labelled as an estimate.

### Cost and limit

- R17. After each call the app shows its cost in USD, computed from the `usage` fields of the response and the price table.
- R18. The app shows cost totals per day and per month.
- R19. The daily call limit defaults to 30 and is adjustable in settings. At the limit the app refuses a new analysis and says the limit and the count. Browsing and editing stay available.
- R20. The user types the API key in settings. The app stores it in the keychain. Without a key the app refuses an analysis and says that a key is missing.

### Non-functional

- R21. Only the analysis of a new photo needs the network. Energy, browsing and editing records, recomputation after edits and cost totals work offline.
- R22. The only network destination the app contacts is the Anthropic API. There is no analytics and no account.
- R23. The key is stored only in the keychain and is sent only to the Anthropic API. It is never written to a record, a log, a file or a build.
- R24. The Swift package builds and its tests pass on Linux, without network and without a key. No test and no CI job calls a paid API.
- R25. Energy and FoodData are pure functions of their inputs. The same input gives the same output.
- R26. An error message states what happened, what was expected and what was seen.

## Flow

```
photo -> resize 1024 px long side -> JPEG -> request to the model
      -> items with grams and kcal -> validation (R5, R6)
      -> match against local table -> user edits (local, no call)
      -> store record
```

A failed validation ends the flow at an error. Edits and the stored record need no network.

## Energy

Mifflin et al. 1990 (Am J Clin Nutr 51:241-247), kcal per day, weight w in kg, height h in cm, age a in years. The coefficients are the rounded form given in the abstract:

```
REE male   = 10 w + 6.25 h - 5 a + 5
REE female = 10 w + 6.25 h - 5 a - 161
```

Activity factors (D003):

| Choice   | Factor |
|----------|--------|
| At home  | 1.40   |
| Light    | 1.55   |
| Moderate | 1.75   |
| Heavy    | 2.00   |

Test vector: male, 70 kg, 175 cm, 30 years, Light. REE 1648.75. Expenditure 2555.5625.

Energy rejects a height, weight or age of 0 or below with an error that names the field and the value.

## Food data

- Source: USDA FoodData Central, Foundation Foods and SR Legacy, kcal per 100 g. The data are public domain (CC0 1.0) (D005).
- A generator script (M1) reads the USDA download and writes the local table: name and kcal per 100 g.
- Name matching is deterministic. Where no entry matches, it returns no match. It does not return a weak match. The rule is fixed in M1 and recorded in DECISIONS.md before the code lands.

## Cost

Cost of a call = input_tokens times input price plus output_tokens times output price, each price per million tokens, from the response's `usage` fields.

| Model             | Input USD per million | Output USD per million |
|-------------------|-----------------------|------------------------|
| Claude Sonnet 5.5 | 2.00                  | 10.00                  |

Source: vendor pricing page, read 2026-11-22. The prices live in one table in the Cost module with the date they were read.

- A call whose response fails validation is costed from its `usage` fields.
- Day and month are local calendar day and month.

## Architecture

Logic lives in a Swift package with no UI code. A thin SwiftUI app target sits on top (M2).

| Module     | Content                                                                   |
|------------|---------------------------------------------------------------------------|
| Core       | Shared types: food item, meal, units, errors. No dependencies.            |
| Energy     | Mifflin-St Jeor, activity factors.                                        |
| Estimation | Request building, response parsing and validation (R5, R6).               |
| FoodData   | Local table, name matching, kcal per 100 g.                               |
| Ledger     | Meal records, daily totals, edit and recompute. Uses Core and FoodData.   |
| Cost       | Price table, per-call cost from usage, day and month totals, call limit.  |

Every other module uses Core.

The app target holds what needs the platform: screens (photo capture or pick, item list with editing, day view, settings for key, profile, activity factor and call limit), photo resizing and JPEG encoding, the HTTPS request, and the keychain.

Build and release:

- The project file is generated in CI from a text spec, App/project.yml. It is never committed (D008). The generator is XcodeGen, pinned by version and checksum (D010).
- CI on Linux runs the repository checks and the package tests.
- CI on a hosted macOS runner builds, signs and uploads to TestFlight.
- No model API key is ever in the repository, a workflow or a build (D007). Signing and upload in CI will use secrets.

## Privacy

Leaves the device, to the Anthropic API, once per analysis:

- the resized JPEG photo,
- the fixed prompt,
- the API key, as the credential of that request.

Does not leave the device: profile, activity factor, meal records, cost log, call limit, and the key in any other way.

What Anthropic does with the photo is governed by its terms for the API. This project has no control over it. Do not photograph anything you do not want sent.
