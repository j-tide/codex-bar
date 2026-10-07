# Dynamic Radar Models Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Execution is already authorized in this conversation.

**Goal:** Follow CodexRadar's current model/effort catalog automatically, including models with no scores yet.

**Architecture:** Read `/data/radar-bench-binding.json` on every refresh, then request each catalog selection from `/api/radar-bench-score?model=...&effort=...&view=summary`. Validate summary identity against the binding and display the authoritative 0–100 score without calculating legacy IQ. Build table rows and extra effort columns from the catalog, preserving missing scores as unavailable cells.

**Tech Stack:** Swift, URLSession, SwiftUI, XCTest, Xcode, macOS DMG packaging.

**Spec:** This document, Specification below, records the user's instructions in this conversation.

## Specification

- The model list must follow data source changes without shipping a new app for every GPT release.
- Investigate why GPT 6.1 was absent, repair the active path, add and run appropriate tests, and produce an updated local test package.
- Retain the already implemented Pro 5X / 10X / 25X colors and weekly quota behavior.

## Global Constraints

- No model version or family allowlist determines table membership.
- Keep every catalog model in the matrix. Missing scores remain `—`; a valid score of zero remains zero. The user's final choice restores the table after a brief ranked-list trial, recorded below.
- Do not mix old 0–150 IQ with current RadarBench 0–100 scores.
- Public summaries contain no grading timestamp; do not invent one.
- The user subsequently authorized functional commits, pushing the changes, and publishing a new version on 2026-10-07. The release follows the repository's `scripts/release.sh` workflow.

## Review Focus

- New catalog entries and unknown efforts must be fetched and displayed after refresh.
- A removed catalog entry must disappear, without reusing a score from another catalog.
- Null scores must retain model rows and must never enter rankings as zero.
- Mismatched catalog, task digest, model, effort, or coverage must not produce scores.
- A partial request failure must retain other results; a complete failure must retain the previous successful snapshot.

## Task 1: Current API and dynamic presentation

**Files:** Modify `codexBar/Services/CodexRadarService.swift`, `codexBar/Support/CodexRadarPresentation.swift`, `codexBar/Views/CodexRadarView.swift`, `codexBar/Views/MenuBarView.swift`, `codexBar/Localization.swift`, and Radar XCTest files. Add compact public API fixtures under `codexBarTests/Fixtures/Radar`.

**Interfaces:** Service publishes `CodexRadarIntelligenceReport` from the current catalog and validated public summaries; report provides `modelIQ` and partial failure state; presentation consumes all catalog entries, with optional scores.

- [x] Add `testServiceDiscoversModelsAndEffortsFromChangingCatalogWithoutAppUpdate`: assert GPT 6.1 plus an unknown future model/effort appear; a second catalog replaces the future model without retaining removed entries.
- [x] Run that test and confirm failure against the legacy endpoint implementation.
- [x] Implement dynamic catalog fetch, concurrent summary reads, contract validation, and score preservation.
- [x] Preserve rows without scores and derive extra columns from every catalog effort.
- [x] Replace legacy IQ copy, tooltips, and panel sizing with RadarBench score and coverage copy.
- [x] Test zero/null scores, partial and total failures, contract mismatches, and light/dark rendering at menu width.
- [x] Run focused Radar tests and the full test suite; confirm zero failures in the result bundle.

**Verification:** The final suite passed all 186 tests with no failures or skips in `/tmp/codexbar-dynamic-radar-delivery-tests.xcresult`. Review also covered a 40-model catalog on a compact screen, collision-safe model/effort identifiers, and native score help that stays available after scrolling.

## Task 2: Reviewable test build

**Files:** Local outputs under ignored `dist/`.

**Interfaces:** Uses the completed app sources and passing Xcode tests from Task 1.

- [x] Build the Debug app, sign the app and helper, and verify the nested signature.
- [x] Package a new DMG; verify its checksum and mounted application signature.
- [x] Launch that app and provide the DMG plus a clearly identified live-data preview.

**Package verification:** `dist/codexAppBar-pro-tiers-dynamic-radar-test-2026-10-07.dmg` passed checksum validation and mounted application signature verification. All 13 regular app bundle files match the final Debug build. SHA-256: `0ae05ae70d8a9db86d47ef50aea1beec010e29cf2d3760ba24b116bc0ddd23e0`.

**Local launch:** Confirmed PID 61775 runs the final Debug app at `/private/tmp/codexbar-dynamic-radar-debug/Build/Products/Debug/codexAppBar.app/Contents/MacOS/codexAppBar`. `dist/radar-dynamic-preview.png` renders this session's captured public API data, rather than a screenshot of the live menu.

## Follow-up: scored selections as a ranked list

The user explicitly selected “只保留新 RadarBench，改成逐行排行”. This supersedes the earlier matrix display while retaining the dynamic catalog and public score contract.

- Display one row per scored model/effort selection, sorted by unrounded score descending. Keep real zeroes; omit ungraded selections from the list.
- Display full effort names, ranked positions, source score scale, and the graded-selection count relative to the catalog.
- Use a compact no-grades message when no selection has a score. Retain partial-fetch warnings in that state and count only successfully loaded selections as awaiting grades.
- Preserve native score help, coverage metadata, scrolling, and the actual screen height budget. Menu sizing now counts scored selections rather than model families.
- Regression tests failed against the matrix implementation in `/tmp/codexbar-radar-ranking-red.xcresult`. The no-grades partial warning also failed before its fix in `/tmp/codexbar-radar-ranking-empty-partial-red.xcresult`.
- Final suite: **189/189 passed**, no failures or skips, in `/tmp/codexbar-radar-ranking-final-tests.xcresult`. Debug build succeeded in `/tmp/codexbar-radar-ranking-final-build.log`.
- Independent read-only review found no remaining defects. `dist/radar-ranking-preview.png` is a render of this session's captured public API data, not a live menu screenshot.
- Updated package: `dist/codexAppBar-pro-tiers-radar-ranking-test-2026-10-07.dmg`. The DMG checksum and mounted nested app signature passed. All 13 regular app bundle files match the final Debug build. SHA-256: `a7ddceadc59e470343dacb868693f4fc4fd0c37572393c673b25f3730c579baa`.
- Relaunched the updated Debug app and confirmed executable path and PID 68468. The earlier launch record above belongs to the matrix package.

## Final follow-up: restore the model/effort matrix

The user explicitly changed the display preference back to a table. This supersedes the ranked-list presentation above.

- Restored model rows and effort columns from the dynamic RadarBench catalog, including ungraded models. The service and score contract remain unchanged.
- Missing grades show `—`, valid zeroes remain zero, and native help retains precise scores, coverage and rank.
- Kept the graded/catalog count and added a visible `—` legend. Partial-fetch warnings stay visible even when all loaded scores are missing.
- Table and menu heights count model rows again; tall tables retain scrolling and the actual screen height budget.
- The two restored-matrix regression cases first failed against the ranked list in `/tmp/codexbar-radar-matrix-restore-red.xcresult`.
- Final suite: **189/189 passed**, no failures or skips, in `/tmp/codexbar-radar-matrix-final-tests.xcresult`. Debug build succeeded in `/tmp/codexbar-radar-matrix-final-build.log`.
- Independent read-only review passed. `dist/radar-matrix-preview.png` renders this session's captured public API data.
- Final matrix package: `dist/codexAppBar-pro-tiers-radar-matrix-test-2026-10-07.dmg`. Checksum and mounted nested signature passed; all 13 regular bundle files match the build. SHA-256: `e4c0f23124d32afbdc08c920aa4d380db523765a09e5b8419738f7ebce7bc22f`.

## Release follow-up: functional commits and publication

The user requested separate functional commits, a push, and a new release. The intended release is `v2026.10.07`, using the client's Asia/Shanghai date.

- Commit boundaries: Pro tier names, colors and weekly quota regression tests; dynamic RadarBench integration and matrix presentation; screen-aware menu sizing and its regression test; development and verification records.
- Refreshed `origin` and confirmed `main` and the feature branch share the original base `caaaa4402409bd2f54671cf1e90aaa59d7b4c005`, allowing a fast-forward integration.
- Fresh pre-release verification: **189/189 passed**, zero failures or skips, in `/tmp/codexbar-release-20261007.APMWwi/tests.xcresult`. `git diff --check` passed.
- Release procedure: push the functional commits, fast-forward `main`, verify remote synchronization, run the repository release dry-run, then publish and verify the Release archive, signed ZIP and DMG, GitHub asset digests, and tag target.
