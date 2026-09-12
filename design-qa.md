# 模型质量矩阵 Design QA

## Evidence

- Source visual truth: `/var/folders/2w/0d5zh1115l11ghtm7jmy32mm0000gn/T/codex-clipboard-9e5a1812-372c-43e8-b9ee-94ccc7a8a622.png`
- First integrated app capture: `/var/folders/2w/0d5zh1115l11ghtm7jmy32mm0000gn/T/codex-clipboard-720a8263-0498-4b0a-bc5f-6fd53cf360fb.png`
- Selection-state feedback capture: `/var/folders/2w/0d5zh1115l11ghtm7jmy32mm0000gn/T/codex-clipboard-c4a59016-d776-4b27-93e3-fa7ab08b1598.png`
- Post-fix focused render: `/tmp/codexbar-matrix-rendered.png`
- Latest side-by-side comparison: `/tmp/codexbar-rank-comparison.png`
- Crown iteration comparison: `/tmp/codexbar-crown-comparison.png`
- Viewport: 300pt menu-bar popover; focused matrix render is 300pt wide at 2x scale.
- State: read-only matrix with no selection, CodexRadar ordering, top-three rank markers, all five standard effort columns visible, unavailable combinations disabled.

## Comparison history

### Pass 1

- P2: The integrated capture showed a thick purple keyboard-focus ring around `Terra max`, competing with the blue pinned-selection outline.
  - Fix: matrix cells are explicitly non-focusable; click and hover remain the only direct interactions.
- P2: Available values were not differentiated clearly enough by benchmark status.
  - Fix: score text and a restrained cell tint now use the existing success, warning, and danger semantic colors; selection continues to use only the blue outline.

### Pass 2

- The focused post-fix render has one unambiguous blue selection outline and no residual focus control.
- Normal values read green, warning values amber, and missing values remain neutral gray.
- Hover/click hit areas, five-column alignment, compact headers, row icons, and footer stay inside the 300pt width.

### Pass 3

- P2: User feedback rejected the remaining pinned-selection state and requested explicit first/second/third ranking.
  - Fix: removed click handling, pinned state, blue selection outline, and selected accessibility trait.
- P2: Ranking needed to follow CodexRadar's visible order when IQ scores tie.
  - Fix: rank by IQ descending, then the site's `Sol → Terra → Luna` family order and `max → xhigh → high → medium → low` effort order.
- P2: The first compact rank badge treatment collided with three-digit IQ values.
  - Fix: reserved a dedicated 12pt badge row inside each podium cell; the final comparison shows no overlap.
- Final render: first place `Sol medium`, second place `Luna max`, and third place `Sol max` are distinct, readable, and color-coded gold/silver/bronze.

### Pass 4

- P2: Numeric podium badges felt visually heavy and looked like generic notification counters.
  - Fix: replaced `1/2/3` circles with the native filled-crown symbol, colored gold, silver, and bronze by rank.
- Ranking remains available in the detail line and accessibility labels, so the icon-only treatment does not remove semantic information.
- Final comparison confirms the crowns remain distinct at 300pt width without colliding with three-digit IQ values.

### Pass 5

- P2: Crown color alone did not distinguish gold from bronze reliably at small size.
  - Fix: retained each colored crown and added its rank number as lightweight inline text, without restoring the circular notification-badge treatment.

### Pass 6

- User requested the horizontal effort scale to begin at the lowest reasoning level.
  - Fix: reversed the visible standard columns to `low → medium → high → xhigh → max`; podium tie-breaking remains aligned with CodexRadar's original ordering.

## Fidelity surfaces

- Typography: native system typography and monospaced digits match the app; hierarchy remains compact and legible.
- Spacing and layout: stable row labels, equal-width effort cells, and a single-line detail footer preserve the reference hierarchy at the narrower production width.
- Colors: semantic green/amber/red communicates benchmark status; gold/silver/bronze communicates rank without a selection color.
- Assets: native SF Symbols are used for family, refresh, and external-link icons; no raster or placeholder assets are introduced.
- Copy: localized relative time, full model/effort detail, IQ, pass count, empty state, help, and accessibility labels are present in Chinese and English.

## Result

final result: passed

## 2026-09-11：双栏账号与任务弹窗

- 按确认的 `many-accounts-bottom-radar.html` 实现 736pt 原生弹窗。上下两行共用 `(736 - 1) / 2` 列宽和 1pt 分隔线；左下为雷达，右下为用量。
- 任务和备用账号独立滚动，当前账号固定显示完整额度。1、12、100 个账号的原生视图测量高度一致。
- 菜单栏保留原有额度进度条，同时显示需处理、进行中、可继续数量；运行图标旋转，遵循系统减少动态效果设置。
- Hook 文件仍只保存原有状态字段。任务标题优先从本地 Codex 任务索引读取，缺失时从 SQLite 只读匹配，不写回 Hook；未匹配时显示项目与短标识。已匹配任务使用本机 Codex 支持的 `codex://threads/<UUID>` 打开。
- Plus 的 5h/7d 与 Pro 的仅 7d 规则不变。雷达加载、失败、缓存、深浅主题和多账号场景均保留。
- 验证：98 项完整回归通过；增加指定任务链接校验和三组菜单栏计数测试后，聚焦测试通过，并补充标题重命名与索引部分写入验证（合计 101 个测试用例）。最终 Debug 构建通过。
- 原生截图需使用 `NSHostingView`：`ImageRenderer` 无法完整捕获 AppKit 控件及滚动内容。多账号截图由 `CompactPopoverTests` 输出到 `/tmp/codexbar-compact-popover.png`。
- Debug 构建可用 `--show-popover` 启动即打开弹窗，方便核对真实数据；不影响 Release 行为。

- 真实数据核对：`/tmp/codexbar-final-live.png` 及对应 `-menubar.png` 由 Debug 进程自身导出，确认真实额度条、任务状态数量、账号与用量数据可见。截图命令参数：`--show-popover --snapshot-popover=/tmp/codexbar-final-live.png`。
- 本地运行构建沿用已安装版的 `MARKETING_VERSION=2026.09.07`、`CURRENT_PROJECT_VERSION=20260907.2`，避免工程默认开发版本号产生误导性的旧版本更新提示；未修改发布版本配置。


## Native interaction refinement and hook audit — 2026-09-11

- Project names are the primary task labels; current account uses a blue outline, leading stripe and an explicit active badge.
- Status counts reserve NSTextField insets and use native symbols; the quota progress bar remains visible.
- Numeric counters, quota fills, heatmap cells and panel entrances animate on opening, then settle. Reduce Motion suppresses the effects. Native early/settled render comparison passed.
- Today/week/month segments have equal widths and a sliding selection indicator. Refresh buttons have no focus halo. Footer appearance toggle persists light/dark selection.
- Completed unread items use per-completion acknowledgements. Initial historical backlog is acknowledged once; opening a resolvable task acknowledges it. A new turn becomes unread again. Startup/resume, interruption and session end are excluded. External Codex read receipts are not available through this bridge.
- Notification bell activates the app and requests native authorization. A denied permission routes to system notification settings; macOS cannot display the original authorization prompt again after a recorded decision.
- Hook audit: UserPromptSubmit → processing; PreCompact → compacting; PostCompact and SessionStart compact → processing; Stop → completion; Interrupt/SessionEnd → idle without unread completion. PermissionRequest remains excluded because another hook or automatic approval can bypass user input. These hooks cannot prove every user-attention state; no unsupported Notification event is installed.
- Source: https://learn.chatgpt.com/docs/hooks (checked against local Codex 0.154.0-alpha.6.1). The bridge emits only `{}` for Stop, including persistence failures; all reporting exits successfully and never returns approval/control decisions.
- Validation: 104 XCTest cases, 16 Python bridge cases, Debug build and diff whitespace check passed. Installed script matches source; all 8 CodexBar entries (7 event types) have a 2-second timeout; unrelated hooks are unchanged.


## Glass, matrix and sidebar refinement — 2026-09-11

- Replace the top-six ranked tiles with a model-by-effort table. All valid model rows are retained; at most four rows are visible before vertical scrolling, preserving the 190-point insights region. Missing measurements use an em dash and the top score is highlighted.
- Hide the menu-bar attention icon and count when the count is zero; reclaim the entire group width and restore it when attention is needed.
- Read Codex's local sidebar preferences and read-only task recency metadata. Current project mode follows project order, pins and saved per-project task order, then recency. State changes no longer dictate list position. Refresh metadata every five seconds only while the task panel is visible. Malformed preference data falls back to recency.
- Restore the original numericText transition and 0.25-second ease-out from the pre-redesign TokenStatsView. Remove scalar interpolation and synthetic intermediate values. Heatmap entrance remains separate.
- Current account now has a restrained leading accent, light wash and text label; remove the solid badge and outline.
- Native macOS 26+ GlassEffectContainer, glassEffect and glass button styles provide the panel material and key controls. Remove opaque root/sidebar backgrounds. Older systems use regularMaterial; Reduce Transparency uses a solid accessible background. Data rows stay legible instead of each becoming a separate glass control.
- Official reference: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- 109 XCTest cases passed; final Debug build and diff checks passed. A sample of the running app identified menu-bar Core Animation replica redraws; the tiny spinner now draws a fixed-size arc at 20 Hz rather than rotating and relaying out a CALayer. A regression capture verifies that arc frames change while all count frames remain fixed.
- Native cacheDisplay cannot represent GPU-composited glass faithfully; do not use its transparent/malformed capture as a visual deliverable. Computer Use inspection timed out. The final application is running for direct review; full compositor-level visual validation remains unverified. Scoped inspection runtime cleanup returned result=clean; shared services used by other runtimes were preserved.

- Final menu refinement: reduce icon/count gap from 2 to 0 points, group gap from 7 to 3 points, and leading inset from 7 to 4 points. The native spinner regression passed; 110 distinct XCTest cases have passed across this refinement. CPU improvement is not claimed: the app still shows substantial native status-item replica rendering in sampling.


## Unread tasks and restored matrix podium — 2026-09-11

- Completed unread task checks and labels use the green status palette. Stale tasks are filtered from display records, the activity total and empty-state logic; the expired legend is removed. Raw stale records remain available for diagnostics and return to the list after fresh activity.
- Restored the earlier matrix presentation from b667389: model symbols, compact score cells and gold/silver/bronze crowns with ranks 1–3. Removed both scroll views and the four-row cap. Columns share the available width; the entire lower section grows with the model row count and preserves the common center divider.
- TaskCenterCoreTests passed, including stale-only empty state, unread visibility and fresh-activity recovery. Radar presentation and intelligence suites passed after replacing the obsolete fixed-height assertion with the complete-table height. Light and dark native table renders were inspected with animations disabled for stable scores.

## Balanced menu spacing and panel density — 2026-09-11

- Menu divider now has 8-point layout spacing on both sides, a subtler 10-point rule, 1-point icon/label frame gap and 6-point group gap. Native text insets remain included in count widths; the spinner keeps its fixed center. Animation and conditional-attention regression tests passed.
- Top section now follows task count with a bounded minimum for account content: four tasks and two accounts use 280 points instead of 372. Six or more tasks retain the capped list height. Two-account pools show both email and quota/reset details; larger pools retain compact backups. Hide the redundant backup-count footer for one or two accounts.
- Heatmap square size adapts to the available lower-right space and includes an explicit last-16-weeks caption and shared color legend. Preserve reveal and hover effects, quota semantics and the common column divider.
- CompactPopoverTests passed with 1, 2, 12 and 100 account fixtures. Native Liquid Glass compositor capture limitations from the prior section still apply to full-panel bitmap snapshots.

## Compact history curve and denser bottom glass — 2026-09-11

- Replaced the oversized lower-right calendar with a compact calendar above a daily token line/area curve. Both share the same Monday-aligned 16-week date window and daily data; the curve excludes future dates, fills missing days with zero and exposes date/value on hover. Date-range controls continue to govern the summary, while history explicitly labels its fixed window. Preserve the existing panel height and motion preferences.
- Added adaptive solid color backing at 48% opacity behind the insights row and 58% behind the bottom toolbar. Native glass and rounded outer edges remain in place.
- TokenUsageHistoryTests and CompactPopoverTests passed (11 cases); reran both history tests after correcting the area path closure. Inspected standalone light, dark and zero-usage renders, including compact-height layout. Full glass compositor appearance is for direct app review, not inferred from cacheDisplay.

## Unified glass and actionable notification authorization — 2026-09-11

- Removed separate 48%/58% bottom backing layers. The entire popup now shares one 62% backing surface inside native glass, with NSPopover appearance synchronized to the selected SwiftUI theme. Heatmap rows are shallower and both history charts use the full available width, leaving more height for the curve.
- Notification requests now retain NSError details and distinguish denied permission, request failure and incomplete authorization. First use requests system permission; already authorized users enable directly; denied users receive Settings access, while actual request failures show Retry with diagnostic hover details. Refresh system permission on reopening or returning to the app.
- Runtime evidence: before repair, user notification logs showed didGrant=0 and hasError=1; the linker-only signature had Identifier=codexAppBar and Info.plist not bound. A complete ad-hoc bundle signature now binds xmasdong.codexAppBar and its resources. The relaunched app returned enabled=true, status=2 (authorized), with no request error. No new prompt was needed because macOS already granted this bundle permission.
- Updated restart-local.sh to build with complete ad-hoc signing instead of CODE_SIGNING_ALLOWED=NO. Signed TaskCenterCoreTests and CompactPopoverTests passed (33 cases); history tests passed with revised proportions. Shell syntax and whitespace checks passed.

## Notification settings revocation and interaction — 2026-09-11

- Bell actions now read current system permission before choosing enable/disable, preventing a stale enabled icon from clearing the user's enable intent after macOS revoked permission. Serialize permission actions and ignore older refresh callbacks. Recheck while the popup is visible, on opening and on app activation.
- Replace the inline task-list warning and immediate Settings jump with a compact popover anchored to the bell. Denied permission explains the exact System Settings path and offers Notification Settings / Later; genuine request errors have expandable diagnostic details and retry. Opening Settings checks the workspace return value. Returning with permission granted restores the opted-in service, while an explicit app-level off preference remains off.
- Apple docs confirm subsequent requestAuthorization calls do not repeat the system authorization prompt: https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- Signed TaskCenterCoreTests and CompactPopoverTests passed (36 cases), including system revocation with a stale icon, permission restoration, out-of-order callbacks and overlapping taps. App signature and diff checks passed. Read-only runtime verification after restart returned enabled=false, status=1 (denied), matching the user's current System Settings state. No permission reset or system-setting modification was performed.

## Unified popup arrow and Settings handoff — 2026-09-11

- Replaced the outer NSPopover chrome with a transparent MenuBarGlassPanel. A single PopupGlassOutline includes the rounded body and top arrow, and supplies both the backing and native Liquid Glass shape. Window placement remains anchored to the menu item and clamps to the current screen; Escape, outside clicks and app activation dismiss the panel and release its hosted content.
- Signed MenuBarGlassPanelTests, CompactPopoverTests and TaskCenterCoreTests passed (39 cases). Verified bundle signature and diff whitespace. Actual WindowServer capture of the running 736 × 632 panel is saved at /tmp/codexbar-glass-arrow-live.png; inspected the continuous arrow/body edge, shared fill and intact layout. Unlike earlier cacheDisplay captures, this is a composited window capture.
- Notification Settings now launches through an application-level owner after closing the menu panel, uses an activating NSWorkspace configuration, and falls back to the Settings root if the launch fails or terminates during its initial two-second check. Final failure shows an actionable native alert. The URL is present in the installed System Settings sidebar metadata.
- Runtime handoff reported success at 17:58:13, but System Settings then performed a normal, approved termination at 17:58:14. This is not evidence of a crash and does not yet establish whether the user closed it or the original symptom remains. Do not claim the disappearing-window issue is fully verified.

## Projectless tasks, language controls, appearance and validated completions — 2026-09-11

- Resolve saved project names from Codex sidebar state, respecting explicit projectless membership, explicit project assignments (including worktrees), and root-directory boundaries. Projectless tasks use their actual title and a conversation icon. Verified kj-x is explicitly projectless.
- Completion rows now require matching live task metadata before entering the unread snapshot used by both the menu bar and popup. Two unmatched Stop records (prefixes 257527 and fa5087) have no corresponding task in the local Codex database and are no longer counted. Metadata refresh uses raw hook keys so delayed real tasks can appear without being acknowledged; a readable database takes precedence over archived/deleted titles retained in the append-only index. This is not a claim of complete synchronization with Codex's in-memory read state.
- Removed the 94% solid backing after the user supplied a Control Center glass reference. Preserve the native regular Liquid Glass surface, continuous arrow outline, thin edge highlight and custom contour shadow. The transparent host provides 24-point shadow room, compensates arrow placement, and no longer adds AppKit's host shadow. Screen-parameter changes reposition instead of dismissing the popup.
- Appearance transitions use a short native fade with a warm expanding wave for light mode and a cool contracting wave for dark mode. The wave originates at the appearance button's actual layout anchor and runs once for 0.6 seconds; Reduce Motion disables it. Captured runtime transition frames at /tmp/codexbar-theme-frame-{0,1,2}.png with the same window alive throughout.
- Language control is a compact two-segment glass capsule (中 / EN) beside Add and Import, with an animated selected background and direct selection. Explicitly invalidate leaf views when language changes, so task status, radar, history labels and numeric units update immediately. English date controls use Today / Week / Month to avoid truncation. User task titles remain as authored.
- Signed tests passed: 44 cases covering TaskCenterCore, CompactPopover, MenuBarGlassPanel and CodexSidebarOrder after unread filtering; final 17-case layout/placement/sidebar pass after language capsule changes. Earlier 14-case layout/history/glass pass covered theme and localization changes. Bundle signature and whitespace verified.

## All popup actions use Liquid Glass — 2026-09-11

- Centralized native regular/prominent glass button styles, using capsule borders for standalone controls and padding-preserving interactive glass for task rows and segmented controls. Migrated account refresh/delete/switch/reauthorize, radar info/refresh/source, all footer actions, notices, hook setup and update actions. Removed the update button's opaque custom rectangle and redundant glass behind the footer settings group.
- Keep semantic colors, Reduce Motion, disabled feedback, and disabled focus effects. System confirmation dialogs retain macOS-owned rendering and behavior. No raw plain/borderless button styles remain in popup views outside the shared compatibility helper.
- Signed CompactPopoverTests, CodexRadarPresentationTests and MenuBarGlassPanelTests passed (21 cases). Final build and signature verification passed. Inspected live Chinese and English captures at /tmp/codexbar-all-glass-buttons-{zh,en}.png, including account controls, footer and date segments; exercised language selection and restored Chinese.

## Roll back universal glass buttons — 2026-09-11

- At the user's request, reversed only the universal-button-glass pass. Restored plain task rows, compact account/radar/footer controls, previous grouped language/date controls, and the prior update button. Removed the new glass label style and capsule/prominent helper variants. Header refresh, notification bell, theme button, account switch glass and glass group surfaces remain as they were before that pass. Project names, unread filtering, localization, layout and theme transitions are preserved.

## Popup performance audit (2026-09-11)

- Coalesce hosting-size invalidations and ignore unchanged intrinsic sizes. Retain AppKit minimum and intrinsic sizing constraints for stable native glass layout; skip only the unused maximum-size proposal. Initialize the arrow position with the shadow inset to avoid an extra first-open environment update.
- Keep the one-second quota polling schedule, but update minute-only relative labels once per minute. Auth file monitoring and the hook service already run at app level, so opening no longer repeats their synchronous file reads.
- Reuse ISO date formatters and decoded task records when file bytes are identical. Revalidate retention and corruption on every load; changed timestamps alone are not the cache key. Publish task metadata/snapshots and usage datasets only on change.
- Reuse token statistics for 15 seconds on repeated opens; explicit refresh/range changes still force refresh. Start visible refresh after the initial 200 ms layout window.
- Render heatmap cells on a single animated Canvas, preserving staggered reveal, colors, future-day exclusion, hover outline and tooltip. NumericText digit animation and glass styling remain in place.
- Same local Debug build configuration, six opens, measured synchronously from show through layout/display: mean 143.8 ms before, 105.4 ms after (26.7% reduction). This is not end-to-end frame latency or a Release benchmark. First open: 207.8 → 162.4 ms.
- Benchmark flag: `--benchmark-popover` (DEBUG only), writes six samples to `/tmp/codexbar-popup-benchmark.json`. Baseline and final copies: `/tmp/codexbar-popup-benchmark-before.json`, `/tmp/codexbar-popup-benchmark-after.json`.
- Targeted task/notification/cache, popup geometry/lifecycle, menu animation, unread handling and history-render tests passed (43 cases; after Canvas changes, the 15 affected view tests were rerun and passed). New regressions cover unchanged-size invalidations, real height changes, same-mtime file replacement, corrupt replacements and expiry of cached records.
- Signing and `git diff --check` verified. Live sample files: `/tmp/codexbar-popup-before.sample`, `/tmp/codexbar-popup-after.sample`. Menu-bar replica snapshot work remains a separate ongoing animation cost; no claim that every rendering cost has been eliminated.

- Final host geometry tests rerun: 4 passed. Actual settled window inspected at `/tmp/codexbar-performance-minsize.png`; columns, arrow, heatmap and curve are contained within the popup.

## Completion notification delivery (2026-09-11)

- Live authorization was already enabled: app opt-in true, system authorization authorized, alerts/sound enabled, banner style. The delivery path previously selected only needsAttention records and never scheduled ready/Stop completions.
- Include the task center's filtered unread Stop completions; complete immediately, keep the existing attention grace period. SessionStart, Interrupt and SessionEnd are not completion notifications.
- Keep persistent dedupe before scheduling, but remove the key on a definite system rejection, log the failure, and retry while the same event remains actionable (three attempts maximum, 2/4 second retry delays). Reading the completion, resuming the task or disabling notifications cancels pending retries. Successful requests stay deduplicated across restarts.
- Tests cover completed unread delivery, non-completion lifecycle events, retry success and persistent dedupe, read cancellation, bounded failures, and persistence while system submission is still pending. Core plus compact popup regression run: 42 passed.
- Actual signed-app diagnostic (`--notification-status --test-task-notification`) sent one explicitly labeled test notification without adding a synthetic task or changing read state. System reported `Diagnostic notification delivered: true` at 19:32:51. This verifies real system delivery; completion event selection is separately covered by the regression tests.
# App and menu bar identity (2026-09-11)

- Replaced the app icon with an open mint quota ring and three parallel task strokes on a dark blue base. The ring also forms a C.
- Added `CodexBrandMark` as shared vector geometry. The normal menu icon uses a cached, resolution-independent 16-point monochrome image; quota warning symbols retain their existing behavior.
- Added `scripts/generate-app-icon.swift` to reproducibly export all seven macOS icon sizes with transparent corners.
- Signed Debug build and strict signature verification passed. Inspected the new icon in the actual menu bar after relaunch and checked the 16/1024-pixel asset dimensions and alpha.
# Popup button and menu audit (2026-09-11)

| Control | Expected action / verification |
| --- | --- |
| Menu bar left click | Toggle the panel. Native down/up events verified open → closed; the outside-click monitor excludes the anchor, so it cannot close on down and reopen on up. |
| Menu bar right click | Native context menu with Open Panel, Open Codex, Refresh Usage, Show Task Status, and Quit. Menu display and Open Panel/Quit routes exercised. Control-click uses the same route. |
| Footer / context-menu Quit | Shared native confirmation, Cancel is the default. Cancel keeps the app running; confirming Quit was exercised and the process disappeared. The latest build was then relaunched. |
| Delete / switch account | Native confirmation appears above the popup; Cancel exercised without removing accounts or changing active auth. |
| Import | Native file picker opens; Cancel returns to the same panel. Clicking the status item during the modal brings the dialog forward instead of closing its parent. No files imported. |
| Chinese / English, theme | Both directions exercised and restored to Chinese/light. |
| Quota metric / task status visibility | Both directions exercised and restored to remaining/shown. |
| Refresh interval | 10s → 30s → 1m → 2m → 10s exercised. |
| Today / Week / Month | All three native buttons exercised and restored to Today. |
| Radar info | Explanation control exercised; refresh/source/reset-window source handlers reviewed. |
| Header/account refresh, task links, notifications | Dispatch reviewed: refresh services, open-task then mark-read, authorization toggle/settings callback respectively. Existing task-navigation/read regression tests pass. |
| OAuth add/reauthorize, hook install, update install | Dispatch and confirmation paths reviewed. No account authorization, hook mutation, or update installation performed in the audit. |

- Native dialogs now use `PopupModalPresenter` to temporarily lower the floating panel, preserve hosted state, and restore its level after dismissal. The outside-click and activation observers do not tear down a modal's parent.
- Seven panel/quit tests pass, plus nine existing compact-popup tests. The initial anchor fixture over-released its test NSWindow on close; corrected the fixture's `isReleasedWhenClosed` ownership and reran the panel suite successfully.
- Final signed Debug build, strict codesign verification and whitespace check passed. Native UI actions were performed through short-lived AX/CoreGraphics CLI helpers; no persistent Computer Use runtime was started.
# Codex read/unread synchronization (2026-09-11)

- Root cause: `TaskReadState` only acknowledged clicks made in CodexAppBar. Opening the same task in Codex never updated that local acknowledgement store.
- Added a read-only adapter for Codex's `electron-thread-read-state-v1` in `.codex-global-state.json`. Verified the current installed desktop source's identity hash (`I5`), access-token principal selection (`cj`), and execution-host hash (`NY`). Identity is SHA256 of `["chatgpt", accountId, userId]`; only the local stdio execution-host bucket is selected. Other accounts, SSH/alternate hosts and the legacy migration backlog are not merged.
- `CodexReadStateMonitor` reads on a utility task every second, skips JSON decoding for unchanged bytes, survives atomic file replacement, and continues while the popup is closed. Partial writes retain the last good snapshot for the same identity; an unavailable/changed identity cannot inherit the previous account's state.
- TaskCenter uses Codex's unread membership for completed Stop records, filtered to known tasks. Its list, count and completion-notification candidates come from the same resulting snapshot. No inferred unread completions appear during initial loading. Existing running/attention behavior remains unchanged.
- App clicks open the exact Codex task using the existing deep link. Codex owns the acknowledgement; the subsequent state update removes the row/count here. Local acknowledgement history cannot override Codex's later unread changes. Codex files are never rewritten by this integration.
- 47 read-state, task-center/notification and compact-popup tests passed. Tests cover identity/host isolation, malformed state, first-launch unread preservation, external read/unread changes without hook events, partial writes and account changes.
- Live parser resolved the current identity and parsed its local bucket successfully. The active completed record absent from that bucket was removed; native UI inspection after relaunch showed `4 进行中` and `0 待查看`. Strict signature verification and whitespace check passed.
- Compatibility boundary: this adapter targets the installed desktop's version-1 local stdio state schema; it is not a public OpenAI API.

## 2026-09-11 — popup hit regions, conditional status counts, account identity and badges

- Kept the native glass outline/arrow and added a 1% contour backing fill plus an explicit SwiftUI interaction shape. `FirstMouseHostingView` now falls back to receiving otherwise-unclaimed hits only inside that same outline; transparent shadow, arrow cutouts and rounded corners are excluded. Radar refresh/source controls use their full 20-point rectangular interaction region, including inert handling while refresh is disabled.
- Status-bar attention/running/unread groups each require a positive count. Zero groups clear their frames, drawing and animation; the empty strip has zero width, no separator and no reserved gap. Regression coverage cycles all combinations, including running disappearing while unread remains.
- Subscription, reset credits and current-account badges share one renderer (18-point height, 4-point radius, 9-point semibold type, 5-point horizontal inset). Purple/green/blue distinguish their meanings. Task summary uses three aligned compact status blocks with icons, numeric transitions and subdued zero counts; these are informational, not filters.
- Verified Codex's installed profile reader uses GET `/backend-api/wham/profiles/me` and reads `profile.username` / `profile.display_name`. Added account-scoped persisted profile data and credential-generation-checked commits. Optional profile reads run alongside quota refresh without blocking quota publication; one-hour success cache / five-minute failure backoff. Display prioritizes the real @username, then profile display name, meaningful organization name, then email/ID. No usernames inferred from email. Live profile requests timed out on this host (URLSession -1001 and proxy probe); actual usernames remain unverified and the live UI currently shows email fallback.
- Validation: 56 focused tests passed in `/tmp/codexbar-profile-hit-tests.log`, including quota race/reauthorization, profile caching/failure, legacy decoding, popup hit geometry and status layout/motion. Signed Debug bundle verified and relaunched. Existing unrelated compiler warnings remain unchanged.
- Native click-through check used a disposable floating underlay window below the popup, with a file-backed mouseDown counter. With popup closed, two posted physical clicks produced counter 2. With popup open, 12 clicks across radar refresh, radar whitespace, task whitespace and quota whitespace left counter at 2. Four more dark-mode clicks also left it at 2. Physical theme-button clicks changed appearance successfully. Temporary probe processes were terminated; Chinese/light preferences restored.
- Screenshots inspected: `/tmp/codexbar-labels-hit-final.png` (Chinese/light) and `/tmp/codexbar-labels-english-dark.png` (English/dark). Labels fit; long email fallbacks truncate on the heading while the email remains on its own line.

## 2026-09-11 — consistent custom glass controls

- Replaced the remaining native glass/filled button bezels with `PopupGlassControlStyle`, using the same `PopupGlassOutline` surface as adjacent controls. Covers header refresh, theme, notification bell, account switch/reauthorization and notification-settings action. Borderless icon/text actions remain borderless.
- Centralized regular (10 pt), compact (7 pt) and segmented-selection (6 pt) radii. Language and usage-period groups now share the regular outer radius. Preserved the refresh/theme hit-area dimensions, account switch dimensions, semantic tints, disabled appearance, native interactive glass hover and reduced-motion-aware press feedback.
- The initial native `.buttonBorderShape` approach still rendered the old tight bezel on this host; replaced it with the shared custom contour after screenshot inspection.
- Validation: 18 existing popup geometry/layout/motion tests passed (`/tmp/codexbar-custom-controls-test.log`), signed Debug build verified and relaunched. Physical mouse clicks toggled dark → light → dark successfully, with theme hit-area size remaining 42×28 pt. Inspected `/tmp/codexbar-custom-controls-light.png`; restored the user's dark appearance.

## 2026-09-11 — compact controls, refresh motion, podium and header logo

- Supersedes the earlier retained icon dimensions: header refresh, theme and notification controls now measure 30×26 pt; language inner segments are 32×20 plus 3 pt group insets, aligning the footer at 26 pt. Usage-period controls retain their separate content size.
- Header refresh animates a clipped cyan/indigo surface with a moving bright contour and white refresh glyph. Idle, hidden preview and Reduce Motion states pause scheduled motion; refreshing stays disabled to repeated clicks without dimming its progress artwork.
- Radar podium cells have distinct gold, silver-blue and copper gradients/borders and matching crowns, with appearance-aware contrast. Ranking and tie ordering remain unchanged. Nineteen radar/compact tests passed; inspected the renderer output `/tmp/codexbar-leaderboard-rendered.png` and live flowing refresh `/tmp/codexbar-refresh-flow-final.png`.
- Task loading rings now have a faint track and a tapered-opacity arc, shared visually between popup and menu bar. Native rendering retains fixed bounds and uses short overlapping arcs; ten compact tests passed, including changing spinner frames without shifting counts (`/tmp/codexbar-comet-spinner-tests.log`).
- Added the bundled application icon before the header title at 28×28 pt with a 7 pt gap; header height stays 48 pt. Final signed Debug build and strict signature verification passed, and app was restarted. AX confirms the updated panel hierarchy. The final logo screenshot attempt returned a blank offscreen window, so the logo's live screenshot appearance was not verified in this pass.

## 2026-09-11 — loading arc seam correction

- Fixed the popup spinner's detached bright dot: a round cap at angular-gradient position zero sampled the opaque color from position one. Moved the arc to 0.10–0.88 so the gradient seam falls inside its gap, and increased tail contrast slightly.
- Signed Debug build and strict signature/whitespace verification passed; app relaunched. Inspected live `/tmp/codexbar-spinner-seam-fixed.png`: continuous tails without the detached highlight, aligned task rows. This screenshot also verifies the previously unverified header logo and live gold/silver-blue/copper podium cells.

## 2026-09-11 — refresh effect on the header divider

- Moved the animated cyan/indigo/purple highlight from the button surface onto the divider below the header. A 1.5 pt bright beam and restrained halo sweep horizontally while the existing real refresh flag is active; the overlay reserves no space and never receives input.
- The 30×26 pt button retains only a blue rotating glyph. Divider motion pauses when idle, in static previews, and under Reduce Motion; active state fades out in 250 ms. No determinate progress or success result is invented.
- Signed Debug build, strict signature verification and whitespace check passed; relaunched and activated header refresh via AX. Inspected `/tmp/codexbar-refresh-sweep-final.png`, showing the beam centered on the requested divider with unchanged content layout.

## 2026-09-11 — full-width flowing refresh divider

- Replaced the short traveling beam with a full-width illuminated gradient. Three repeated color periods translate seamlessly at a 3.2-second cycle, keeping both divider ends lit throughout; existing completion fade, Reduce Motion and noninteractive overlay behavior remain.
- Signed Debug build and signature verification passed; restarted and exercised refresh. Inspected `/tmp/codexbar-full-refresh-flow.png`, confirming the full divider carries cyan/blue/purple highlights without a short-beam gap.

## 2026-09-11 — restrained silver reflection for refresh

- Replaced the rainbow cycle with a continuous 1 pt ice-blue divider and a traveling silver-white reflection with a cyan tail. Reduced glow to a narrow 1.2 pt blur; the whole divider remains illuminated while refreshing.
- A single 450 ms brightness decay acknowledges activation, followed by a 2.6 s reflection cycle. Completion fades in 450 ms. Reduce Motion keeps a stationary reflection and removes ignition/fade animation.
- Signed Debug build, strict signature and whitespace verification passed. Relaunched and exercised refresh; inspected `/tmp/codexbar-silver-refresh-a.png` while active and `/tmp/codexbar-silver-refresh-b.png` after completion. Full-width line is visible during refresh and restores to the ordinary divider afterward.

## 2026-09-11 — layered refresh highlight and abandoned OAuth recovery

- Strengthened the silver refresh highlight with cyan/lavender trailing color, a narrow 2 pt halo and gentle 80–100% brightness modulation. The full-width ice-blue line remains visible; Reduce Motion stays static. Inspected `/tmp/codexbar-layered-flow-oauth-fixed.png` after relaunch.
- Closing an external browser tab provides no cancellation event. Previously OAuthManager kept its completion forever, and LocalCallbackServer.stop only set a Boolean while accept remained blocked. Restarting authorization therefore failed with “already in progress” and could retain port 1455.
- New attempts cancel the previous attempt and generate fresh PKCE/state. Published pending state exposes Restart sign-in and Cancel sign-in controls. Cancellation is silent; a three-minute expiry, browser-open failure and socket binding failure all release state. Main-actor attempt IDs guard token responses/retries and timeout callbacks so obsolete work cannot complete a newer flow.
- Replaced the blocking listener with loopback-only nonblocking sockets: bounded accept checks every 100 ms only while authorizing, incremental read sources with five-second client expiry, and synchronous listener-port release on cancel. Invalid paths/stale states do not consume the active callback. The initial Dispatch cancellation approach deferred descriptor release and failed the immediate-rebind regression; corrected the ownership and reran successfully.
- 45 OAuth lifecycle/account refresh tests passed (`/tmp/codexbar-oauth-lifecycle-tests.log`), including immediate port reuse, restart with a new state, timeout isolation, browser/bind failures and stale callbacks. Tests use ephemeral local ports and an injected browser opener; no real account authorization or credential exchange was performed. Signed Debug bundle verified and restarted, clearing the user's abandoned listener; port 1455 no longer had a listening process afterward.

## 2026-09-12 — callback page and compact account pool

- Replaced the old bilingual callback card with a responsive, localized page, inline brand artwork, light/dark appearances, reduced-motion support and a return action. Receipt copy does not claim token verification succeeded. Response is no-store/no-referrer and clears callback query from page history. Desktop light and mobile dark previews inspected.
- Three-account pools now show complete quota bars without a cropped third row; current account stays prominent, secondary rows use compact consistent cards and a More menu for maintenance actions. Larger pools retain bounded scrolling with reserved scrollbar space.
- Subscription badges share an 18 pt outline: Free neutral, Plus purple, Pro 5X blue, Pro 20X amber, Team/Business teal, Enterprise indigo. Removed unwanted focus appearance from compact More controls. Live screenshot inspected: /tmp/codexbar-subscription-colors.png.
- Nineteen OAuth/compact tests passed in /tmp/codexbar-account-colors-final-tests.log. Final signed build, strict signature and whitespace verification passed. Native return route delivered to the explicit Debug app successfully opens the panel after switching to NSApplicationDelegateAdaptor. Unqualified codexappbar://open is still not resolved by LaunchServices with the temporary Debug bundle and existing installed copy; browser-to-installed-app handoff remains unverified.

## 2026-09-12 — account availability and scroll discovery

- Replaced the weak available/total text with separate icon/count/label chips: available is green, nonzero unavailable is red, and zero counts are neutral. Availability still uses TokenAccount.isAvailable, including authorization, restrictions and quota exhaustion.
- Added a dedicated account scrolling surface with an always-visible position rail when content overflows, a localized scroll hint and up/down controls. Current account remains outside the scroll view. Geometry determines arrow enablement and bottom status; page steps use 80% of actual viewport height and respect Reduce Motion. No cue or footer appears when content fits.
- Live four-account verification: down reveals the fourth account, current account remains fixed, bottom shows End of list and disables down; up restores the initial rows. Inspected /tmp/codexbar-account-scroll-top.png and /tmp/codexbar-account-scroll-bottom.png.
- Language-switch QA caught stale child badge labels; added direct environment observation to both new components, rebuilt, and verified English labels fit and update immediately. Also inspected dark mode; restored Chinese/light afterward. Final screenshots: /tmp/codexbar-account-scroll-english-final.png and /tmp/codexbar-account-scroll-dark.png. Signed Debug build, strict signature and whitespace checks passed. No account state or credentials modified by QA.

## 2026-09-12 — correct calendar token usage, 30-day curve, uninterrupted status spinner

- Confirmed the old today query summed lifetime tokens_used for threads updated today (621,180,643 across seven rows), incorrectly charging earlier days to today and moving historical heatmap values when a thread updated.
- Added a read-only rollout usage index over sessions and archived_sessions. It uses timestamped cumulative-counter deltas, first-request usage for inherited/reset baselines, deduplicates copied events, excludes future events and groups by local calendar date. Only sessions with positive usage count. Cached input is already included in total tokens, not added again. An incremental disk cache contains usage metadata only; incomplete tails, append, truncate/replacement and restart are handled.
- Independent Python and Swift scans at 2026-09-12 11:31:07 +08:00 both produced exactly 52,189,961 tokens across six sessions. Usage continues growing. Full historical indexing read about 9 GB off the main thread in 27.7 s; the subsequent process/cache scan completed in 0.83 s. Current cache size about 10 MB.
- Curve now uses exactly 30 local days including today, zero-fills missing days and excludes future dates. Heatmap remains 16 weeks; each has a visible range label. Inspected native corrected popup /tmp/codexbar-corrected-today-30days.png (captured during numeric entrance).
- Popup construction baseline measured 93–176 ms. The old status spinner required main-thread Timer drawing at 20 FPS; replaced with a persistent linear Core Animation rotation. A stationary host owns layout, while the rotating child uses bounds/position instead of transformed frame, avoiding earlier wobble. Rotation stops when idle/hidden/reduced motion and does not restart on unchanged updates.
- The initial test attempted to inspect a presentation layer while blocking its client run loop; values are synchronized at run-loop commits, so this assertion was invalid and failed. Revised phase/layout/lifecycle regression passes. Independently paused only the live app process briefly with SIGSTOP and guaranteed SIGCONT in finally: screen captures changed solely inside the 22×22 physical-pixel ring region, proving compositor motion continues independently (/tmp/codexbar-spinner-blocked-a.png and -b.png). Process resumed normally.
- Fourteen targeted compact, usage-index and curve tests passed in /tmp/codexbar-usage-spinner-final-tests.log, covering midnight, duplicate logs, inherited/reset counters, partial writes, cache reload, truncation and future exclusion. Signed Debug build and strict signature verification passed, app restarted. No Codex log/database or account data was modified.


## 2026-09-12 — native glass reset-window strip and physical menu toggle

- Replaced the oversized blue reset-window banner with a compact 34 pt strip using the shared native Liquid Glass modifier, a light accent tint, a fine edge highlight and the existing control radius. Kept the localized open badge, expected reset date and source action. Inspected the running app in /tmp/codexbar-reset-window-native-glass.png.
- Physical second clicks were intercepted by the popup panel's transparent top shadow margin, which overlapped the status item. A nil view hit-test cannot forward a click through an NSWindow. Removed only the top margin, retained horizontal/bottom shadow space and aligned the panel top with the menu anchor. Status-item left clicks now toggle on mouse-down; right-click remains on mouse-up.
- Eight panel regression tests passed in /tmp/codexbar-glass-toggle-final-tests.log, including anchor geometry and shadow hit testing. Four physical mouse clicks produced open, closed, open, closed (window IDs 13764 and 13765). Signed Debug build and strict signature verification passed; app restarted with the changes.


## 2026-09-12 — coordinated status surfaces

- Reset-window strip now uses orange title/lightning and a pale amber native-glass tint; removed the left accent rail. Refined the lightning with a 24 pt translucent circular backing and grouped the expected reset label/date in a quiet inset. Strip remains compact at 36 pt.
- Task processing text, spinner and running summary share NSColor.systemYellow with the menu-bar running indicator. Quota warning colors remain unchanged. Replaced the three independent activity tiles with one native-glass status strip and fine dividers; zero counts are subdued.
- Account summary displays All available with total count in the normal state, separate available/unavailable counts with exception emphasis when needed, and No accounts for an empty pool. Chinese/English labels and accessibility grouping remain supported.
- Signed Debug builds, strict signature and whitespace checks passed. Restarted and inspected the live two-account Chinese popup in /tmp/codexbar-unified-status.png, showing the amber banner, unified yellow activity strip and All available summary. No account availability or task state was changed for validation.

- Follow-up preference: restored the reset-window accent and native-glass tint to blue, retaining the compact circular icon, grouped reset time and rail-free layout. Rebuilt, verified signature and restarted the Debug app.


## 2026-09-12 — activity summary beside title

- Moved the activity summary into the title row, replacing the standalone total count and removing its separate full-width row. The compact native-glass strip is 22 pt high and includes only positive state counts; all-zero state omits the whole surface. Dividers appear only between visible states.
- Full labels fit first; constrained widths use icon/count with localized help and accessibility labels. Added direct language observation and kept the section title from wrapping.
- Signed Debug build and strict signature/whitespace checks passed. Restarted and inspected /tmp/codexbar-inline-activity.png: the live header displays only 2 Running next to the title, with zero attention/unread states absent and the task list immediately below.

- Account availability summary now uses the shared native glass surface with the compact 7 pt contour and semantic green/red/neutral tint, replacing its flat fill. Existing counts, localization and 25 pt sizing remain. Signed Debug build, signature and whitespace checks passed; app restarted.

- Running-state contrast refinement: popup light appearance uses a deeper golden yellow (0.55, 0.40, 0.02), while dark appearance and menu-bar yellow retain systemYellow. Small text has 4.87:1 contrast against a pale (0.96, 0.97, 0.98) reference background; actual translucent-glass contrast varies with the background. Raised spinner tail/track opacity for visibility. Signed Debug build, signature and whitespace checks passed; restarted the app.


## 2026-09-12 — continuous token switching, smooth curve and popup transitions

- Removed the nil assignment during period switching. The usage index now includes daily unique thread sets in its in-memory snapshot, allowing today/week/month totals and distinct session counts to update synchronously from the same 119-day data. Refresh results apply to the currently selected period; switching no longer starts redundant scans. Initial metric rendering falls back to its known target value; no-cache state uses localized loading/unavailable copy instead of dashes.
- The 30-day curve and its area fill share monotone cubic interpolation. Original daily points/local extrema remain unchanged; controls are bounded inside each segment's endpoint range. Hover values still use actual daily observations.
- Panel opening now fades in over 200 ms with a small content translation; closing fades out over 140 ms and releases content after completion. Window geometry stays fixed to avoid menu-bar overlap. Closing is immediately reflected by isShown, repeated closes are ignored, and Reduce Motion skips transitions.
- Fifteen targeted index, curve and panel tests passed in /tmp/codexbar-motion-final-tests.log, including calendar-window deduplication, no-overshoot controls, delayed close cleanup, geometry and click handling. Signed Debug bundle verified and restarted. Physical clicks produced open/closed/open/closed (14500/14501); selected Week and inspected /tmp/codexbar-smooth-week.png with 18.4亿, 55 sessions and the smoothed curve. No account or Codex source data modified.

- Reset-window follow-up: replaced the full-width banner with a content-sized, left-aligned 30 pt blue native-glass strip. Removed the icon disc and nested state/time fills; used a fine separator between status and expected reset time. Source action and open-window logic unchanged. Signed build/signature/whitespace checks passed; restarted and inspected /tmp/codexbar-compact-reset-strip.png.

- Moved the reset-window strip into the header between the title spacer and freshness/refresh controls. Reduced height to 26 pt to match refresh, shortened the English title and retained visible Open/estimated-date semantics with full expected-reset help/accessibility text. Removed the separate banner row. Signed Debug build and strict signature/whitespace checks passed. Inspected Chinese and English live headers (/tmp/codexbar-header-reset-strip.png, /tmp/codexbar-header-reset-english.png); both fit without truncation. Restored Chinese afterward.

## 2026-09-12 — Independent columns and content readability

- Task/radar and account/usage sections now flow independently. Task height follows visible rows (with room for setup/read-error notices); account pool retains its bounded scrolling behavior. Preserved two-account detail height after visual QA found header misalignment at 252 pt.
- Added a translucent neutral backing only under the content columns (72% light / 64% dark), preserving existing glass for the outer panel, header, footer and controls.
- Period totals identify their selected date range; a separate Usage history section distinguishes the fixed 16-week heatmap and 30-day curve. Token calculations and chart samples are unchanged.
- Speedrun date explicitly says Expected reset in Chinese and English. Radar exposes precise two-decimal scores to accessibility/hover and explains rounded display versus raw-score ranking.
- Debug build succeeded: /tmp/codexbar-content-polish-build.log. Strict bundle signature validation and git diff --check passed.
- Live captures: /tmp/codexbar-polish-final-light-zh.png and /tmp/codexbar-polish-final-dark-en.png. Checked header fit, aligned section headings, account controls, radar and graph bounds. Restored Chinese/light appearance. Running the rebuilt debug app; no commit or release performed.

## 2026-09-12 — Subscription validity and continuous popup backing

- Paid accounts show credential-reported subscription validity beside the email, or an explicit unavailable label when absent; Free does not get a subscription deadline. Full date and data-source/refresh caveat are in help. No auto-renewal inference or quota/JWT-exp substitution.
- Corrected stale subscription metadata: loading the pool prefers the current ID-token subscription claim; token refresh and active auth-file synchronization also update the stored date. Live Pro validity now reads Sep 19 and Plus Sep 25.
- Moved the neutral backing to the entire popup contour, eliminating the contrasting header/footer strips created by the previous content-only backing.
- Heatmap tooltip now uses a local semantic color surface with a border and shadow instead of transient regularMaterial; it no longer adds a separate backdrop effect to the surrounding glass hierarchy.
- AccountRefreshRaceTests passed, including new reload/refresh regression coverage and the existing distinction between subscription expiry and token expiry. Log: /tmp/codexbar-subscription-tests.log. Strict signature verification and git diff --check passed.
- Live dark hover screenshots: /tmp/codexbar-hover-before.png and /tmp/codexbar-hover-during.png. Footer ROI (60,1195)-(1510,1270) and lower-left ROI (65,1050)-(750,1180) were pixel-identical before/during hover. Light hover footer ROI also pixel-identical. Light English account/header fit checked in /tmp/codexbar-subscription-light-en.png. Restored Chinese/dark appearance used at the start of this follow-up.

## 2026-09-12 — Bottom-aligned radar and unverified subscription dates

- Anchored the full radar section above the footer, including the score explanation in its reserved height. The activity list takes remaining space; removed the unused area below radar. Live loaded-state screenshot: /tmp/codexbar-radar-bottom-final.png.
- Corrected the previous validity claim: first account's ID token was issued Sep 7 but its subscription_last_checked is Aug 21; second account's check is Aug 25. These are credential snapshots, not live billing confirmation. A read-only account-check request returned HTTP 403. Neither date can be claimed as current verified billing truth.
- Visible labels now say Validity unverified, with the credential-recorded date and explicit historical-source caveat in help. Actual current expiry remains unconfirmed; no invented date or renewal inference.
- Debug build, strict signature verification and git diff --check passed. Build log: /tmp/codexbar-radar-bottom-build.log. Rebuilt app launched; live loaded layout checked.

## 2026-09-12 — Equal insight panels and immediate radar score details

- Both lower panels share one computed height; their top dividers align. Radar content uses top alignment, including the empty/loading state, so its title does not sink toward the footer while loading.
- Replaced score cells' delayed native help with an immediate hover overlay showing model/effort, rank, two-decimal raw IQ, rounding/ranking explanation and the composite weighting method. Overlay uses a local semantic color surface, stays within the table width, and does not intercept pointer events.
- Debug build succeeded in /tmp/codexbar-radar-hover-build.log. Strict bundle signature validation and git diff --check passed. Running rebuilt debug app.
- Live captures /tmp/codexbar-radar-loading-top.png and /tmp/codexbar-score-hover.png confirm stable loading placement and an actual Astra medium tooltip with raw IQ 116.06 and rank 1.
- User's web billing screenshot reports automatic renewal on October 7, 2026. App OAuth billing request remains denied (403); connected Chrome tab inventory timed out. Automatic verified billing synchronization is not implemented; no screenshot date hardcoded into an account.

## 2026-09-12 — Subscription endpoint as billing date source

- Added a separately persisted subscription billing snapshot from GET /backend-api/subscriptions?account_id=<workspace>. UI reads only active_until and will_renew, never the legacy JWT expiry snapshot or accounts/check expires_at. Renewal and validity labels follow the returned renewal flag.
- Optional requests run alongside quota/profile refresh, cache success for one hour and back off failures for five minutes. Manual refresh bypasses the cache. Failed/invalid/401/403 responses do not invalidate credentials or replace previously verified dates; retained results are visibly marked Cached. Without verified data, show Validity unavailable.
- Billing commits require the current credential revision; workspace changes clear the old workspace snapshot. Credential rotations and JSON reload cannot overwrite billing dates with JWT claims.
- All 46 AccountRefreshRaceTests passed, including six added billing tests for request account scope, parsing, expiry-field separation, errors/cache, stale credential responses, persistence and workspace changes. Log: /tmp/codexbar-billing-source-tests.log. Strict code signature and git diff --check passed.
- Restarted the rebuilt debug app. Real URLSession requests succeeded for both saved accounts: active Pro active_until=2026-10-07T03:51:24Z, will_renew=true; Plus active_until=2026-09-25T02:15:06Z, will_renew=false. Both saved with checkedAt=2026-09-12T08:26:21Z and subscription_refresh_failed=false. Account authorization/availability flags remain healthy. Unlike the earlier curl replay, the native app requests succeeded; no manual date insertion or browser credential import was performed.

## 2026-09-12 — Restore saturated menu bar quota colors

- Root cause: dark appearance variants added for the popup shared the same AppKit color helper as the menu bar; its green changed to pale mint on a dark menu bar.
- Menu bar quota fills now use their own fixed, fully opaque palette with the original green/amber/red RGB values. Popup adaptive colors and quota thresholds are unchanged.
- Debug build succeeded in /tmp/codexbar-menu-color-build.log; strict signature verification and whitespace checks passed. Restarted the rebuilt debug app.

## 2026-09-12 — Release validation

- Full signed Debug suite: 163 Swift tests passed in /tmp/codexbar-release-tests.log. All 16 Python hook tests passed in /tmp/codexbar-release-python-tests.log.
- Full-suite rendering exposed an outdated radar height assertion and a small shortfall in reserved layout height after adding score explanations. Both lower sections now reserve table height plus 96 pt (minimum 252 pt), covering the measured 265 pt radar content. Light/dark/loading/error/cached render checks pass.
- Changes split into functional commits for branding, glass/motion, usage indexing, task state/notifications, OAuth, subscription/account presentation, radar, usage charts and dashboard integration. Release archive and publishing use scripts/release.sh.
