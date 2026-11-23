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

## D012: Request and reply handling

Date: 2026-11-23

Decision: The package builds one request and judges one reply.

Request: POST https://api.anthropic.com/v1/messages with the headers content-type and anthropic-version 2026-10-21. The app adds the key header (R23). The body holds the model claude-sonnet-5-5, max_tokens 600, thinking of type between_tools, and one user message: a base64 JPEG image block, then the text of the P2 prompt. There is no system prompt, no tool, no sampling parameter and no fallback. The prompt is a string constant in the Estimation module, and a test compares it with eval/prompts/p2.txt, the file the evaluation sent.

Image: Before the body is built the JPEG bytes are checked. Every APPn segment except the JFIF header and the ICC profile, and every comment, is dropped, and so is everything after the first end marker. The long side must be at most 1024 px. Bytes that are not a complete JPEG are an error. The Exif orientation goes with the rest, so the app must turn the pixels upright before it encodes them.

Reply: A status other than 200 is an error that gives the status and the type and message of the error body. A reply with the stop reason refusal or max_tokens is an error with that reason code and its text is not read. Otherwise the text blocks are joined and trimmed, one surrounding code fence is removed, and the text must be one JSON object that meets R5. The reason codes are http, bad_response, refusal, max_tokens, empty_text, not_json, not_object, wrong_keys, bad_value and too_many_items. A reply with prose before the object is not_json (D009). The usage of every reply that has one is returned with the result, so a failed call is costed.

Parser: The JSON text is read by a parser that follows RFC 8259 and adds nothing. It rejects a repeated key, as the evaluation did, and the values NaN and Infinity.

Toolchain: Package.swift uses tools version 6.0 and language mode 6, as App/project.yml does. The Linux CI job installs Swift 6.3.3 from swift.org and checks its SHA-256. The version was chosen to match Xcode 26.6; the macOS job prints the Swift version of Xcode.

Rationale: The request has the model, prompt and parameters of the evaluation (docs/evaluation-protocol.md); the image differs, as D009 says. Claude Sonnet 5.5 rejects thinking disabled, and between_tools turns off up-front thinking. Without a thinking parameter the model thinks by default, with an effect on output and cost that was not measured. A fallback would let another model answer, and the cost table has one model. The reason codes refusal, max_tokens, empty_text and not_json come from the registered handling of the evaluation, http and bad_response from the response itself, the others from R5. In the 300 recorded calls of this model and prompt output was 112.5 tokens at the median and 393 at most, so 600 has room.

The standard JSON readers are no basis for R6. On Linux the two of them disagree on a repeated key (one keeps the first, the other the last), and one reads a boolean as a number. Their behaviour on iOS cannot be tested here. One parser, built on the standard library's strings and numbers, does not depend on them.

R3 needs the segments gone from the bytes that are sent. The encoder of the app cannot be tested on Linux, and the package can.

The Linux runner image has its own Swift, which can be newer than that of Xcode 26.6 and accept code that Xcode rejects.

Alternatives: Leave thinking out. Request a fallback. Read the JSON with the standard readers. Hold the prompt as a package resource through a symbolic link into eval/, whose handling in Xcode cannot be tested here. Leave the metadata to the encoder of the app. Use the Swift of the runner image.

## D013: Record formats

Date: 2026-11-23

Decision: Meal records and the call log are JSON files that the package defines. The package turns a ledger or a log into bytes and reads bytes back. The app decides where the file lives and writes it whole. Each file is an object with "version": 1 and one list, "meals" or "calls". The version is read first. A file of another version is refused with the version expected and the one seen, and a file that is not in the format is refused with the same three parts, as is a file that holds a meal id twice or an item outside the bounds of R5. Dates are local calendar values without a time zone: a day is 2026-11-23 and a time is 2026-11-23T12:30. The package reads no clock and no system calendar. The app gives an instant and a time zone to LocalDateTime(_:in:) once, at its boundary, and the conversion uses a fixed Gregorian calendar. A meal has an id given by the caller. Its total is the sum of its items and is not stored. An item stores name, grams and kcal; its energy per 100 g is derived. An edit returns a new meal, and a refused edit changes nothing. Grams equal to the current ones leave the item as it is, and a scaled kcal above 5000 by at most 1e-9 is set to 5000. A name is stored as typed and only its length is judged, as in a reply (R5). Meals of one minute keep the order in which they were added. Money is a Decimal and is stored as a string. The cost of a call is worked out when the call is logged and is read back as stored. A call that returns no usage, such as an HTTP error, is not logged and does not count against the daily limit.

Rationale: A version field turns a format change into a clear error, and reading it before anything else means that a newer file reports its version and not a missing field. Local calendar values keep a record on its day when the time zone changes. A fixed Gregorian calendar keeps the regional settings of the user, such as another year numbering or a 13th month, out of the stored day. The caller gives the id so that the package stays free of random numbers. A stored total or density could disagree with the items after an edit. Scaling can end one ulp off, so a restore at 5000 kcal would be refused and an unchanged weight would change the kcal. A file edited by hand meets the bounds of an edit. Decimal sums are exact. As a JSON number a Decimal would be read back by other readers as a binary fraction, so it is stored as a string. The reader accepts only ASCII digits with at most one decimal point that has a digit on each side, because Decimal(string:) reads a prefix and ignores the rest. A stored cost is not worked out again, so a later change of the price table cannot rewrite what a past call cost. A call without usage costs nothing, and the limit exists to bound spending.

Alternatives: Store instants (a change of time zone moves records between days). Store the total. Store the energy per 100 g with each item. Count every attempt against the limit. Work out the cost again on every read.

## D014: Depth limit and line ends of the reply parser

Date: 2026-11-23

Decision: The reply parser rejects nesting deeper than 16 levels as not_json (StrictJSON.maxDepth). The lines of a fenced reply end at the scalar U+000A only, as in the evaluation. The depth limit is a rule beyond RFC 8259, to which D012 said the parser adds nothing. The line ends bring the fence rule in line with the evaluation, which D012 follows.

Rationale: The parser is recursive, so the nesting of a reply is the depth of the stack. A reply of enough open brackets can overflow the stack, and the process then dies instead of giving a reason code. RFC 8259 section 9 lets a parser limit the depth of nesting. A valid reply nests 3 levels: an object, a list, an object. 16 leaves a reply of the wrong shape room to reach the checks of R5 and get its reason code and place; a limit of 3 would give such a reply not_json. Swift reads the pair CR LF as one Character, so a split of the reply on Characters misses a line that ends with it. A fenced reply whose opening fence is followed by LF and whose closing fence follows a CR LF is valid in the evaluation, and was not_json here. The 300 recorded replies are judged as the evaluation judged them.

The parser and the evaluation still differ on four kinds of input, found by running both on generated replies. At the edge of a reply or a name, U+001C to U+001F are removed by the evaluation's str.strip() and kept by Foundation's whitespace set, so such a reply is not_json here and valid there, and a name that is one of them has length 1 here and 0 there. U+200B is the reverse: the evaluation keeps it and Foundation trims it. In the language word after an opening fence, the evaluation tests code points against \w and Swift tests Characters. A letter followed by a combining mark or a joiner (a with U+0301, x with U+200D), a circled letter (U+24B6) and a letter that Unicode 15.1, the data of Python 3.13, does not assign are part of the word here and the reply is valid, and there the first line is not a fence and the reply is not_json. An escape of a lone surrogate (U+D800 to U+DFFF) in a string is not_json here and accepted there. Nesting deeper than 16 levels is not_json here, and there it gets the reason code of R5 (not_object, wrong_keys, bad_value), or an uncaught RecursionError at 100,000 levels. None of the 1,200 recorded replies has any of these inputs.

Alternatives: No limit. A limit of 3. A parser with a stack of its own instead of recursion, which is more code for a reply the model does not produce. The whitespace set of the evaluation, which needs five scalars kept by hand for a difference that no recorded reply shows.

## D015: App state, files, the transport seam and the languages

Date: 2026-11-23

Decision: A sixth module of the package, Tally, holds the state and the flow of the app: the settings (UserSettings), one analysis (Analysis.run) and the object that holds the meals, the call log and the settings (AppModel, observable, on the main actor). The app target holds what needs the platform: the screens, the photo encoder, the camera picker, the keychain and the URLSession transport.

The three files are meals.json, calls.json and settings.json in Application Support/PlateTally, in the format of D013. The settings file extends D013: version 1 and one object, "settings", in place of a list. A change to the meals or the settings is written whole, through a temporary file that replaces the old one, before the screens see it, and a failed write changes nothing. A ledger is checked with the rules of the reader before it is written, and one that fails is not written. The call log is the exception: a billed call is counted in memory first and written after. If that write fails, the screen says so once. The call stays in the count in memory and is stored by the next successful write of the log; if the app restarts first, it is lost from the count. A file that exists and cannot be read stops the start with the three-part error and is never overwritten. This narrows D013: the package reads no clock and draws no random number, except Tally, which draws the meal id (AppModel.draft) and reads the clock that the app supplies. Where D013 has the app write the files, the app now gives the folder, and Tally writes each file through FileStore in Core.

The key never enters the package. Tally defines Transport, a function from a request to a status and a body, and is told only whether a key exists (R20, R23). The app builds the transport on URLSession with the ephemeral configuration (no cache, no cookies) and a timeout of 60 s. It reads the key from the keychain, adds it as the x-api-key header just before the request leaves, and never retries (R7). The key is stored with the attribute for this device only (kSecAttrAccessibleWhenUnlockedThisDeviceOnly), so it is not synced and does not move to another device. Closing the analysis screen cancels the request. A request that times out, or is cancelled after it left the device, returns no usage, so the app neither costs nor counts it. A request that reached the API may still be billed; the app cannot see it.

The photo is redrawn at a scale of 1 with its orientation applied, at most 1024 px on the long side, and encoded as JPEG at quality 0.8, which the evaluation did not measure (it sent PNG); the package then drops the metadata (R2, R3). The photo is kept in memory only while its analysis or draft meal is on screen, and is never stored (R11).

The daily limit is 1 to 100, default 30. The profile has no default: it exists once sex is picked and height, weight and age are numbers above 0 (an age with a fraction counts as not set). The activity factor defaults to Light. A typed number is ASCII digits with at most one point or comma after the first digit; surrounding whitespace is ignored and nothing else is read. The expenditure and the energy of a day, a meal and an item in a list carry the sign ≈ (R9, R16), except a figure that is exactly 0, such as an empty day, which shows 0 kcal. A result of a conversion carries = (D018). The sign is the only mark of an estimate; no screen carries a sentence that says so.

The screens are in Chinese (Simplified) or English, from two string catalogs, Localizable and InfoPlist. The app starts in Chinese whatever the language of the device is. The choice is kept in the settings file and applies at once, without a restart: the screens take their locale from it, system alerts and dialogs included. The three-part error texts come from the package and stay in English. The camera permission text follows the language of the device; the camera and photo pickers are the system's and are not tested. Amounts and the grouping of numbers follow the region of the device.

Rationale: What the package holds is tested on Linux without a network or a key (R24). With the key out of the package, the code that handles it is in the app target: the keychain store, the settings screen and the transport. The order of the writes follows what the user would otherwise lose: a meal that was not written is not shown, and a call that was paid for is counted. A file that cannot be read is not overwritten, because writing the empty value would delete the records. The limit counts what returns usage (D013), so a call billed without a response is not counted, and the API may bill more calls in a day than the limit. A default sex would change the estimate without being seen. A number without a sign, an exponent or grouping has one meaning in every region. The error texts carry names and values from the package, which has no catalog.

Alternatives: The model in the app target, which Linux cannot test. The key in the package behind a keychain protocol. UserDefaults or SwiftData for the records, which would leave D013 unused. Writing the call log before counting the call. A default profile. The default URLSession configuration, which keeps a cache on disk. JPEG quality 1.0. The language of the device. Translated error texts.

## D016: Tests of the app without a Mac

Date: 2026-11-23

Decision: Only the macOS job of CI (.github/workflows/ios-build.yml, D010) builds and runs the app. There is no local run. The job runs on a push to main that changes App/, Sources/, Package.swift or the workflow, and when started by hand. A change to Tests/ alone does not start it. It generates the project, builds the app and its two test targets once for an iPhone simulator on iOS 26 and archives the app for a device without signing. On the simulator it then runs the unit tests and the UI tests of the app, and the package tests. The package tests also run on Linux in the other job (.github/workflows/ci.yml).

The unit tests cover the photo (long side, pixels against points, upright orientation), the transport against a stub protocol inside the process, and the keychain store against the keychain of the simulator. The UI tests start the app with the argument -ui-test, which only debug builds read (App/Sources/UITestHarness.swift). The app then runs on a fresh folder, a clock fixed at 2026-11-23 12:30 in the time zone UTC, an in-memory key and a canned model reply after 2 s: an item list, a reply that is not JSON, or no network. A generated picture stands in for the library; the simulator has no camera, so the app offers none. The texts are English unless a test asks for Chinese. A launch argument (-ui-appearance) sets the colour scheme, because the appearance set through XCUIDevice did not reach the app.

The UI tests check the numbers and texts on each screen and keep a screenshot of each state in light and dark: the empty day, the day with meals and with a profile, the refusals without a key and at the limit, the choice of source, the analysis running, failed with its reason code and failed without network, the draft meal, the item form (opened, after a change of grams, in kJ), the stored meal and its delete confirmation, settings empty and filled, and the converter per serving and per 100 g. The day with meals is also kept at an accessibility text size, in light only. In Chinese they keep the day with meals, a stored meal, the refusal without a key, the delete confirmation, settings, and the converter per 100 g in light only. One test opens settings in Chinese, keeps it, switches the language to English, keeps the screen again in light and dark, and checks that the key field, the title of settings and the title of the day change at once. The screenshots, the test logs and the result bundle of the app tests are kept with the run for 7, 3 and 3 days.

Not covered: the app has never run on a device and has never called the model; every test answers with the canned reply or the stub. No test opens the camera or the real photo library, uses the keychain of a device or shows the layout on a device. The Release build is archived and never launched. No test reaches the screen that reports an unreadable file at the start. The language of the system pickers and of the camera permission is not tested.

Rationale: A canned reply, a fixed clock and a fixed time zone take the network, the date and the zone out of what a screenshot shows, and no test calls a paid API (R24). The screenshots are the only view of the screens before an install, so each state is kept in both colour schemes. A UI test runs in another process, so a harness inside the app binary is the direct way to replace the network and the key. Leaving it out of the Release build keeps R22 and R23 true for the build that is installed. The package tests run on the simulator as well as on Linux, because the Foundation of the platform can differ from that of Linux (D012).

Alternatives: Rendering the views to images in unit tests. A second app target for the tests. No UI tests, which leaves the screens unchecked until the first install. UI tests against the real API with a key, which R24 forbids.

## D017: One accent colour and the price tag

Date: 2026-11-23

Decision: The base is neutral: canvas #F4F1EA, surfaces #FFFFFF and #E9E5DC, ink #14110F and #5E584F; in dark mode #0F0E0D, #1D1B19, #2B2825, #F7F4EE and #B0AAA0. One colour, moss #2F4F3E (#44705A in dark mode), marks the results of a screen: the intake of the day, the total of a meal and the results of a conversion. It also colours the text cursor, except in the result field of the converter, which is moss itself. The intake and the total are drawn as a price tag with a punched hole. The expenditure stands beside the intake on an outlined neutral block. Controls are ink on the neutral base. Errors are ink with an icon: the design has no alarm colour. Text is the rounded system font at a fixed size for each role (TextRole in App/Sources/Theme.swift), which scales with Dynamic Type; the reason code of a failed analysis is monospaced. At accessibility text sizes the intake and the expenditure stack. Cards have 28 pt corners, tags 32 pt, and buttons are fully round. A number rolls its digits when it changes and fades instead with Reduce Motion. The colours are defined in code, each with a light and a dark value. The app has no asset catalog, no image or font file and no third-party package. The day, meal, item, converter and settings screens draw their own title.

Rationale: Moss marks results and nothing else, so on the day screen the intake is the only coloured block. The expenditure stays neutral: it is an estimate from the profile, and nothing on the screen compares the two (R15, D004). Errors in ink leave the colour to results alone; an error is told by its icon and its three parts (R26). Colours in code keep each value next to its name in one file, App/Sources/Theme.swift, and need no generated asset symbols. Their values follow the traits of the view, so the colour scheme that a UI test sets reaches them (D016). A title drawn by the screen takes the rounded type of the design, and the UI tests find each screen by the identifier of its title.

Alternatives: The system's stock list and form. Several accent colours, one for each kind of number. A saturated accent. Photos of the meals on the cards of the day, which would need the photo stored (R11). Colour sets in an asset catalog.

## D018: Energy converter and the factor 4.18

Date: 2026-11-23

Decision: A converter turns the energy on a food label into one item. Per serving it takes the energy of a serving and its grams; per 100 g it takes the energy per 100 g and the grams eaten. The energy can be typed in kJ or in kcal, and the other field shows it converted. The item joins the latest meal of today unless the user picks a new meal, which starts at the current time. The item form also takes its energy in kcal or kJ. The factor is 4.18 kJ per kcal, one constant in Core (EnergyUnit.kilojoulesPerKilocalorie). An item stores its kcal without rounding. The results of a conversion carry "=", and the item carries "≈" in every list, as every item does (R9, D015). A field that shows a computed number shows at most one decimal, a point and no grouping; a tag shows a whole number with the grouping of the region. The arithmetic and the rules of both forms are in the package (Core, Ledger) and tested on Linux.

Rationale: Standard 1.2.8 of the Australia New Zealand Food Standards Code requires the energy on a label in kJ; kcal are optional beside it. Schedule 11, section S11-2(4), of the same Code sets the equation from kJ to kcal for labels, and its factor is 4.18. With 4.184 kJ per kcal, 1000 kJ would be 239.0 kcal instead of 239.2, 0.1% less. "=" marks the defined conversion of a typed number; "≈" marks that the energy of an item stays an estimate. A kcal stored without rounding gives the typed number back: 1000 kJ are stored as 1000 / 4.18 kcal (239.2344...) and shown in kJ as 1000. A grouped number in an editable field would be read back wrongly, because the parser takes a comma as the decimal sign: "1,250" would be 1.25. An item above 5,000 kcal (R5) is refused with the existing error in kcal. In kJ that is above 20,900 kJ per item or per serving, and per 100 g it depends on the grams eaten. The forms need no error of their own.

Alternatives: 4.184 kJ per kcal. Storing kJ beside kcal. Rounding the stored kcal. A kJ field in the item form only, without a converter. Adding the item to a meal of the day that the day screen shows.
