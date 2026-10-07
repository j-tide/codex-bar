# RadarBench public API fixtures

Captured on 2026-10-07 (Asia/Shanghai) from CodexRadar's active website contract:

- `bench-binding.json`: `/data/radar-bench-binding.json`, retaining the fields consumed by the app.
- `bench-summary.json`: `/api/radar-bench-score?model=gpt-6.1-sol&effort=high&view=summary`, with a null score and zero task coverage.
- `bench-public-summaries.json`: all 34 catalog selections from `/api/radar-bench-score?...&view=summary`. Two initial HTTP 500 responses succeeded on retry.

The captured GPT 6.1 Sol results include low = 75 with 12/64 coverage, medium = 0 and xhigh = 0 with 1/64 coverage. Other captured selections have no current grades. These are source values, including valid zeroes; no scores were recalculated. The public API does not provide grading timestamps.

Service and validation tests derive additional synthetic catalogs and scores in memory, so new versions, unknown model families, missing results, outages, and catalog changes remain deterministic.
