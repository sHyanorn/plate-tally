# Decisions

Each entry has a number, a date, the decision, the rationale and the alternatives. Entries are not rewritten. A change is a new entry that names the one it replaces.

## D001: Hosted multimodal model instead of on-device

Date: 2026-11-22

Decision: A hosted multimodal model lists the foods in the photo with gram weights. The app does not run a model on the device.

Rationale: A hosted model reads the whole plate and names several foods with portions in one call. There is no model to train, convert or ship inside the app. The price is a payment per call and photos that leave the device (see Privacy in SPEC.md). Whether the accuracy is enough is decided from the M0 numbers.

Alternatives: An on-device classifier or regressor, which needs training data and a conversion pipeline. Lookup in a food database by manual search only.

## D002: Anthropic's cheap tier and Sonnet class only

Date: 2026-11-22

Decision: The app calls Claude Haiku 5.5 or Claude Sonnet 5.5. No other vendor is used or measured. The choice between the two is made from the M0 numbers.

Rationale: One existing credit balance and one API shape. The evaluation's cost is capped at 3.50 USD by its stop rule; the key's workspace has a monthly spend limit of 5 USD. The cheap tier and the Sonnet class are the two models the evaluation measures.

Alternatives: Models from other vendors. A larger set of Anthropic models.

## D003: Mifflin-St Jeor with four activity factors

Date: 2026-11-22

Decision: Resting energy expenditure from the Mifflin-St Jeor equation, times one of four activity factors: 1.40 at home, 1.55 light, 1.75 moderate, 2.00 heavy.

Rationale: The equation is from Mifflin et al., Am J Clin Nutr 1990, 51:241-247. In that study the Harris-Benedict equation overestimated measured resting energy expenditure by 5%. The factors are physical activity levels, which the FAO report defines against basal metabolic rate, so their product with a resting value is an approximation. FAO/WHO/UNU 2001, Human energy requirements, Table 5.3, gives these ranges: sedentary or light activity lifestyle 1.40 to 1.69, active or moderately active 1.70 to 1.99, vigorous or vigorously active 2.00 to 2.40. The four factors sit inside those ranges: 1.40 and 1.55 in the first, 1.75 in the second, 2.00 in the third. The labels "At home" and "Heavy" are this app's own names; the FAO table labels are those quoted above. 1.40 is the lowest value of the sedentary or light range and 2.00 the lowest value of the vigorous range.

Alternatives: Harris-Benedict. Measured expenditure from wearables.

## D004: No goal or deficit function

Date: 2026-11-22

Decision: The app shows intake and estimated expenditure. It has no weight goal, no deficit and no advice.

Rationale: Both numbers are estimates with individual error. A target built on them would turn that error into an instruction. The app is for reading numbers.

Alternatives: A weight goal with a daily deficit. Advice text based on the day's totals.

## D005: Food data from USDA FoodData Central

Date: 2026-11-22

Decision: kcal per 100 g come from USDA FoodData Central, Foundation Foods and SR Legacy. Where no entry matches, the model's own kcal value is used and marked as an estimate.

Rationale: The data are in the public domain and published under CC0 1.0, so the table can be built and shipped without licence terms. Foundation Foods and SR Legacy are the data types used for kcal per 100 g. A marked fallback keeps the number visible without hiding that it is the model's.

Alternatives: Branded data (label values, not analysed samples). National tables of other countries (licence unchecked).

## D006: Evaluation registered before it is run

Date: 2026-11-22

Decision: The evaluation protocol lands in the repository before any paid call. Results are published whatever they are. After it lands the protocol is not edited. Changes are dated amendments in docs/evaluation-amendments.md, approved by the owner first.

Rationale: A fixed plan stops the choice of sample, prompt, metric or stop rule from following the results. Publishing every result stops a bad number from being dropped.

Alternatives: Tune prompts on the sample, then report the best run.

## D007: The user's own API key in the keychain, no backend

Date: 2026-11-22

Decision: The user types an Anthropic API key in settings. It is stored in the keychain. The app calls the API directly. There is no server of our own.

Rationale: No server to run or secure. The cost of each call is the user's own. No model API key ever sits in the repository, a workflow or a build.

Alternatives: A proxy server that holds the key and forwards requests.

## D008: Project file generated in CI, not committed

Date: 2026-11-22

Decision: The project file is generated in CI from a text spec. It is never committed.

Rationale: A generated project file holds strings and paths that the repository rules forbid. It also merges badly. The text spec is short.

Alternatives: A committed project file.

## D009: Claude Sonnet 5.5 with the item list; go

Date: 2026-11-23

Decision: The app calls Claude Sonnet 5.5 and asks for the item list, the form the evaluation calls P2. The project goes on to the gate and M1. This decision was made after the evaluation results had been seen.

Rationale: In the registered evaluation (docs/evaluation-results.md) this cell has the lowest MAE, 92.3 kcal (95% interval 82.0 to 103.1). Claude Haiku 5.5 with the same prompt has 121.4 kcal, and the paired difference is -29.1 kcal (-39.6 to -18.8). Against the total-only cells the MAE difference is not distinguished. The signed mean error of the chosen cell is 2.6 kcal (-12.6 to 17.3); the other three cells overestimate by 48 to 63 kcal on average. 1.7% of its calls were invalid. A single estimate is rough: 50.2% of the valid estimates with a reference of at least 50 kcal are within 30% of the reference and 33.5% within 20%. The app therefore lets the user correct the items and grams (R10). The item list is also what the app needs to match foods against the food table (R8). The mean cost of a call in the evaluation was 0.0023 USD; the app's larger image adds about 0.0012 USD at the list price.

The limits of the evaluation stay: cafeteria plates from California under a fixed overhead camera, 300 dishes, one call per dish with sampling at the API default, a reference computed from ingredient weights. The evaluation sent 640 x 480 PNG images (414 image tokens); the app sends 1024 px JPEGs (about 1,036 tokens), so cost and accuracy may differ. The evaluation scored the model's kcal values; the app computes matched items from the food table (R8). The numbers are not carried over to phone photos or home cooking.

Post hoc finding, not a registered result: 236 of the 237 invalid replies hold a valid JSON object after some prose, 211 of them from Claude Sonnet 5.5 with the total-only prompt and 21 from Claude Haiku 5.5 with it. The registered handling repairs nothing, so these replies count as invalid and the scores stand as registered. No rescoring was done. With the item prompt 4 of the 300 replies of Claude Sonnet 5.5 had this shape. The app keeps R6: such a reply is shown as an error, and a new call happens only when the user asks (R7).

Alternatives: Claude Haiku 5.5 with the item list, at about a twentieth of the cost per call (0.00012 USD against 0.0023 USD), with an MAE 29 kcal higher and an overestimate of 52 kcal on average. Claude Sonnet 5.5 with the total-only prompt: 70.3% failure share, so its MAE of 106.9 kcal rests on 89 dishes. An amendment that reads the object out of a reply with prose and publishes both scores; it would mainly change the total-only cells, which the app does not use. Stopping the project: no-go.

## D010: XcodeGen 2.48.0 on macos-26 with Xcode 26.6, iOS 26.0, iPhone only

Date: 2026-11-23

Decision: XcodeGen 2.48.0 (MIT licence) generates the project file from App/project.yml. The workflow downloads the release archive and checks its SHA-256 before it runs the tool. The macOS job uses the macos-26 runner and selects /Applications/Xcode_26.6.app. The deployment target is iOS 26.0 and the device family is iPhone. The build number is the run number of the workflow (github.run_number). The workflow passes it to xcodebuild as CURRENT_PROJECT_VERSION; the spec holds 1 as the default.

Rationale: The spec is 37 lines of YAML and meets D008. A checksum pins the bytes of the generator. The Homebrew formula has no versioned form, so a version there would float. The label macos-latest moves to a new macOS version over 1 to 2 months (runner-images README), so the job names macos-26. The image keeps one major Xcode per macOS version and replaces a patch release by the next, so the job names the minor version. Consequence: when the image drops Xcode 26.6, the Select Xcode step fails with the expected path and the installed list, and the fix is the XCODE_APP line in .github/workflows/ios-build.yml. Uploads since 2026-04-28 must be built with Xcode 26 or later and an iOS 26 SDK. The image has Xcode 26.6 with the iOS 26.5 SDK. Xcode 27 is a preview on its own runner label and is not used. 26.0 is the first iOS 26 release and the app needs no older system. A target of 27.0 needs the iOS 27 SDK, which only the Xcode 27 preview has. Signing and upload (G2.3) must stay in the same workflow file, because a new workflow file counts its runs from 1. A re-run of one run keeps its number.

Alternatives: Tuist, a larger tool than one target needs. XcodeGen from Homebrew, whose version follows the formula. The macos-latest label. The default Xcode of the image, which changes with the image. A committed project file (D008). A deployment target of 27.0 or of an older iOS.

## D011: Food table postponed, items keep the energy of the model

Date: 2026-11-23

Decision: The app has no food table in M1. Every item keeps the kcal that the model gave for its grams, or the number the user typed, and the screen marks them as estimates. A change of the grams scales the kcal of the item in proportion. R8 to R11 and the Food data section of the SPEC say this. The matching rule, the table generator and the FoodData module are not built and move to M4. D005 stays as the choice of the data source (USDA Foundation Foods and SR Legacy, public domain) for a later table, and its decision to use a table is suspended. The sentences of D009 that match items against the food table (R8) no longer apply.

Rationale: A trial on the recorded replies of the chosen cell (docs/evaluation-results.md, D009) measured what a table would do. A table of 8,223 entries (USDA Foundation Foods of 2026-10-29 and SR Legacy of 2018-04) and a rule that matches equal word sets (plural endings folded; a second pass drops a few cut words such as sliced; no match when the candidate entries differ by more than 10% of their median) found an entry for 250 of the 1,062 items in the 295 valid replies (23.5%). For these items the kcal per 100 g of the model divided by the kcal per 100 g of the table has a median of 1.01, and a 10th to 90th percentile of 0.93 to 1.09. If the table values replace the model's, the total of a dish changes by 1.2 kcal on average (median 0.6, largest 7.9) on the 133 dishes with a match, and the matched items hold 5.1% of the kcal that the model reported. The registered mean absolute error is 92.3 kcal. On the items it matches the table agrees with the model, and no dish moves by more than 8 kcal.

Three limits. The numbers come from an analysis made after the results were seen; they are not a registered result, and the scripts of the analysis are not in the repository. The rule and its word lists were fitted on these replies, so 23.5% holds for this sample only. The comparison is between the table and the model's own numbers, not between either and the reference; the distance to the reference was not measured.

The sample is cafeteria plates, and the numbers are not carried over to phone photos or home cooking (D009). An English table cannot match names in other languages. Without a table the app has no data file to build and ship, and the numbers it shows are the ones the evaluation scored.

Alternatives: Build the table and the matching rule as in the trial. A looser rule, where every word of the name, cut words aside, occurs in the entry: 52.1% of the items matched, but for 80% of those the candidate entries differ by more than 10% of their median, so choosing one is a guess. A curated list from names to entries.
