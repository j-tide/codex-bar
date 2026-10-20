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
