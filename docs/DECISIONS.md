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
