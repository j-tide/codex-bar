# RadarBench public API fixtures

Captured on 2026-10-07 (Asia/Shanghai) from CodexRadar's active website contract:

- `bench-binding.json`: `/data/radar-bench-binding.json`, retaining the fields consumed by the app.
- `bench-summary.json`: `/api/radar-bench-score?model=gpt-6.1-sol&effort=high&view=summary`, with a null score and zero task coverage.
- `bench-public-summaries.json`: all 34 catalog selections from `/api/radar-bench-score?...&view=summary`. Two initial HTTP 500 responses succeeded on retry.

The 2026-10-07 captured GPT 6.1 Sol results include low = 75 with 12/64 coverage, medium = 0 and xhigh = 0 with 1/64 coverage. Other captured selections have no current grades. These are source values, including valid zeroes; no scores were recalculated. That v1 public API did not provide grading timestamps.

Captured on 2026-10-20 (Asia/Shanghai) after the public contract migrated to a 150-point scale:

- `bench-binding-150.json`: `/data/radar-bench-binding.json`, retaining the app's consumed catalog fields, `score_version = radar-bench-v2-150`, `score_max = 150`, and all 34 model/effort selections.
- `bench-summary-150.json`: the complete `/api/radar-bench-score?model=gpt-6.1-sol&effort=high&view=summary&selection=user-selected-v1` response, including v6 statistics, detail metrics, and daily history. The raw high score is 97.90210570679321; source scores and historical scores can exceed 100. These values have not been converted to percentages or recalculated.

The current endpoint requires `selection=user-selected-v1` in the query or `X-Radar-Bench-Selection: user-selected-v1` in the request header when requesting a configuration other than the active display selection (`gpt-6.1-sol` / `low`). Without it, the endpoint returns HTTP 428. The current contract tests reproduce that rule with a local URLProtocol and change summary identity to match each requested configuration; they never make remote requests. Additional scores, boundary values, schema variants, and outage/recovery responses are derived in memory from the captured data.

Service and validation tests derive additional synthetic catalogs and scores in memory, so new versions, unknown model families, missing results, outages, and catalog changes remain deterministic.

Captured on 2026-10-30 (Asia/Shanghai) from the current homepage's four-task intelligence table:

- `four-task-results.json`: `/data/codex-four-task-results.json`, retaining the consumed protocol, round, catalog, weights, test interval, and all 46 rows' final task grades. The published round is `codex-four-261-10c-20261029`, tested 2026-10-29 16:08–20:00 Beijing time, with eight models including both Terra generations.
- `four-task-expected-scores.json`: the matching `data-mtr-payload` JSON embedded in the homepage, retaining its independent `score150` and `score150_display` projection for every selection. These expected totals are captured source values, rather than values calculated by the tests.

The homepage now reads this four-task dataset instead of the legacy RadarBench endpoints. Its `codex-four-weighted-150-v2` total uses the published task weights: combined final capped score / 100 × 60, Pompeii reward × 45, pelican score / 100 × 22.5, and candy correctness (0 or 1) × 22.5. The 46 totals and their two-decimal display strings are checked against the independent homepage projection, including floating-point rounding boundaries. Missing tasks or rows retain the catalog and make the affected total unavailable; real zeroes remain scores. Service tests intercept all requests locally and do not contact the website.
