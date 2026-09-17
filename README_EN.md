<p align="center">
  <img src="codexBar/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" height="96" alt="codex-bar logo">
</p>

<h1 align="center">codex-bar</h1>

<p align="center">
  <strong>Your Codex workspace, at a glance.</strong><br>
  A native macOS menu bar companion for tasks, accounts, quotas, and token usage.
</p>

<p align="center">
  <a href="https://github.com/j-tide/codex-bar/releases/latest"><img src="https://img.shields.io/github/v/release/j-tide/codex-bar?style=flat-square&amp;label=release&amp;color=16866a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15.6%2B-24292f?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 15.6 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Built with Swift and SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-16866a?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/j-tide/codex-bar/releases/latest"><strong>Download</strong></a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#features">Features</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#development">Development</a> ·
  <a href="https://github.com/j-tide/codex-bar/issues">Report an issue</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/overview-en-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/overview-en-light.png">
    <img src="docs/assets/overview-en-light.png" width="900" alt="codex-bar two-column panel with task activity, account quotas, a model score matrix, and token usage history">
  </picture>
</p>

<p align="center">
  <sub>Native interface · Light and dark themes · English and Chinese<br>Preview images use sample accounts, tasks, usage, and scores.</sub>
</p>

## Fewer windows. More focus.

When several Codex tasks are running, you need to know which ones are working, which need your attention, and how much quota is left. codex-bar keeps that information in your menu bar. Open the panel to revisit a task, switch accounts, compare model scores, or review usage on this Mac. No separate server to set up.

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>Keep up with every task</h3>
      <p>See running, needs-attention, and completed-unread states with their counts. Browse tasks in Codex sidebar order and click to return to a conversation.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Know your available quota</h3>
      <p>Keep the current account in view and switch to a backup when needed. Check quota, reset times, subscription status, and available reset credits together.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Compare model scores</h3>
      <p>Explore Codex Radar scores by model and reasoning effort. The top three entries stand out; hover for precise values and ranking details.</p>
    </td>
    <td valign="top">
      <h3>Understand your usage</h3>
      <p>Review daily, weekly, and monthly token totals and session counts, with a 30-day curve and a 16-week heatmap of Codex activity on this Mac.</p>
    </td>
  </tr>
</table>

## Screenshots

Switch between English and Chinese, and between light and dark themes, directly in the app. Click any screenshot to view it at full size.

<table>
  <tr>
    <th width="50%">English · Light</th>
    <th width="50%">English · Dark</th>
  </tr>
  <tr>
    <td><a href="docs/assets/overview-en-light.png"><img src="docs/assets/overview-en-light.png" width="440" alt="English light theme with task activity, account quotas, model scores, and local usage"></a></td>
    <td><a href="docs/assets/overview-en-dark.png"><img src="docs/assets/overview-en-dark.png" width="440" alt="English dark theme with task activity, account quotas, model scores, and local usage"></a></td>
  </tr>
  <tr>
    <th>简体中文 · 浅色</th>
    <th>简体中文 · 深色</th>
  </tr>
  <tr>
    <td><a href="docs/assets/overview-zh-light.png"><img src="docs/assets/overview-zh-light.png" width="440" alt="Chinese light theme with task activity, account quotas, model scores, and local usage"></a></td>
    <td><a href="docs/assets/overview-zh-dark.png"><img src="docs/assets/overview-zh-dark.png" width="440" alt="Chinese dark theme with task activity, account quotas, model scores, and local usage"></a></td>
  </tr>
</table>

<p align="center"><sub>Captured from the native app with sample data. Accounts, tasks, usage, and model scores are for demonstration only.</sub></p>

## Features

| Feature | What you can do |
| :--- | :--- |
| **Menu bar status** | See quota bars and task counts together. Zero-count task states hide automatically; right-click for panel, Codex, and refresh shortcuts. |
| **Task activity** | Follow running, compacting, waiting-for-input, and completed-unread states, reconciled with local task metadata and Codex unread state. |
| **System notifications** | Opt in to completion, attention, and app update notifications. Notification content excludes conversation titles and messages. |
| **Multiple accounts** | Add accounts through browser OAuth or import account JSON. View identity, organization, and plan; refresh, reauthorize, or remove accounts. |
| **Quotas and subscriptions** | The current implementation shows 5-hour / 7-day windows for Plus and a 7-day window for Pro. Toggle used / remaining values and inspect reset credits and expiry. Subscription dates come from the subscription endpoint, with stale results labeled. |
| **Account switching** | Update local credentials alone, or switch and restart Codex. Account changes also synchronize with the local authentication file. |
| **Model score matrix** | Compare Codex Radar scores weighted across software and visual-spatial evaluations. Refreshes every 15 minutes; failures retain the last successful result from the current app session. |
| **Local usage statistics** | Count timestamped token increments by local date, including cached input, with distinct session counts, a 30-day curve, and a 16-week heatmap. |
| **Native appearance** | A two-column panel with light / dark themes and instant English / Chinese switching. Uses Liquid Glass on macOS 26 and system material fallbacks on earlier versions. |
| **In-app updates** | Check GitHub Releases, download, verify, and install an update from the panel, with download progress and completion status. |

## Quick start

### 1. Install

Requires **macOS 15.6 or later**. Designed to work with the Codex desktop app on this Mac. Account quotas and model scores require an internet connection.

Choose a package from [Releases](https://github.com/j-tide/codex-bar/releases/latest):

| Package | Installation |
| :--- | :--- |
| **DMG** · Recommended | Download `codexAppBar-*-setup.dmg`, open it, and drag the app into **Applications**. |
| **ZIP** | Download `codexAppBar-*-release.zip`, unzip it, and move `codexAppBar.app` into **Applications**. |

Launch the app, then click its menu bar icon to open the panel. Future updates are available in the app.

<details>
<summary>macOS blocked the first launch?</summary>

The release script currently uses ad-hoc signing without Apple notarization. After verifying that the package came from this repository's Releases, choose **Open Anyway** in **System Settings → Privacy & Security**. Release notes include SHA-256 hashes for checking your download.

</details>

<details>
<summary>Why are the packages still named codexAppBar?</summary>

The project and app display name are now **codex-bar**. The `codexAppBar.app` bundle filename, release asset prefix, bundle identifiers, and local data paths retain their existing names for installation and updater compatibility. Older releases may still display CodexAppBar.

</details>

### 2. Add an account

Click **Add** in the footer, complete OAuth sign-in in your browser, and return to the app. You can also **Import** compatible account JSON. If you close the browser page early, cancel the pending attempt or restart sign-in from the panel.

When switching accounts:

- **Switch only** updates the local authentication file. A running Codex instance uses the new account when it next reads its credentials.
- **Switch and restart Codex** updates credentials and restarts Codex to apply them immediately. This interrupts running tasks.

### 3. Connect task activity

Follow the **Install hooks** prompt in the task activity section. The installer backs up `~/.codex/hooks.json`, merges the required entries, and preserves other hooks. The status script uses `/usr/bin/python3`.

For alerts, click the section's notification control and allow macOS notifications. See the [notification reference](docs/notification-prompts.md) for trigger details (Chinese).

### 4. Make it yours

Use the footer to switch **English / Chinese**, **light / dark appearance**, **used / remaining quota**, and **task status visibility**. Choose a refresh interval of **10 seconds, 30 seconds, 1 minute, or 2 minutes**. The top-right refresh button refreshes accounts, quotas, model scores, and local statistics, and checks for updates.

## Data and privacy

codex-bar runs on your Mac without a separate backend. It reads local Codex state and connects directly to account endpoints, Codex Radar, and GitHub Releases.

| Data | Source and purpose |
| :--- | :--- |
| Account pool and active account | `~/.codex/token_pool.json` and `~/.codex/auth.json`; may be written when adding, refreshing, or switching accounts. |
| Quotas and subscriptions | ChatGPT / Codex endpoints for quotas, account identity, subscription dates, and available reset credits. |
| Task activity | Hook state in `~/.codex/codexbar/sessions/`, combined with local SQLite, the task index, and `.codex-global-state.json` for titles, ordering, and unread state. |
| Token statistics | Local SQLite locates session logs; timestamped JSONL usage increments drive the totals. The index cache in `~/Library/Caches/codexAppBar/` does not store prompts, replies, or credentials. |
| Model scores and reset-window hints | Public data from [Codex Radar](https://codexradar.com/). Scores are third-party evaluations; reset-window hints do not replace your account's actual quota. |
| App updates | This repository's [GitHub Releases](https://github.com/j-tide/codex-bar/releases). |

**Treat account files like passwords.** The account pool and exported JSON contain login credentials. Do not commit them, attach them to issues, or expose them in screenshots. Task notifications exclude conversation content; the local usage index caches only the data needed for statistics.

This is a community project, unaffiliated with OpenAI. Some features depend on private endpoints and internal Codex file formats, so upstream changes can affect compatibility.

## FAQ

<details>
<summary>Why are task status or unread counts missing?</summary>

Check that hooks are installed, then start a new task in Codex. Activity depends on local events and readable Codex data. Completed-unread tasks must also match the current account's Codex unread list. Missing events, stale states, or unmatched records are not invented as unread tasks.

</details>

<details>
<summary>Why do token totals differ from quota percentages?</summary>

They come from different sources. Quotas are reported by the server; token usage counts local session input and output, including cached input. It is neither a billing amount nor a conversion of quota percentages. Other devices are not automatically included. Today begins at local midnight, the week on Monday, and the month on its first day.

</details>

<details>
<summary>Why are subscription dates or model scores marked as cached?</summary>

When the network or an upstream endpoint is unavailable, the interface may keep a previous result and label its status. Subscription dates use the subscription endpoint's validity date, never the login token's expiry. You can retry model scores using that section's refresh button.

</details>

## Development

Use **Xcode 26 or later with the macOS 26 SDK**. The app's deployment target remains macOS 15.6. The interface uses SwiftUI / AppKit, with system SQLite for local metadata.

```sh
git clone https://github.com/j-tide/codex-bar.git
cd codex-bar
open codexBar.xcodeproj
```

Build and run the `codexBar` scheme, or use the helper script:

```sh
# Build and launch the local development app
./scripts/restart-local.sh

# Build without launching or replacing a running instance
./scripts/restart-local.sh --build-only
```

Run the tests:

```sh
xcodebuild test \
  -project codexBar.xcodeproj \
  -scheme codexBar \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

<details>
<summary>Code map and releases</summary>

| Directory | Responsibility |
| :--- | :--- |
| `codexBar/Views/` | The panel, account list, model matrix, usage charts, and update components. |
| `codexBar/Services/` | OAuth, account storage, quotas, task synchronization, notifications, and updates. |
| `codexBar/Models/` | Account, task state, and metadata models. |
| `codexBar/Support/` | Native menu bar artwork, panel behavior, and the Python hook. |
| `NotificationHelper/` | The macOS notification helper app. |
| `codexBarTests/` | Quota, concurrent account refresh, task state, statistics, and interface regression tests. |
| `scripts/` | Local builds, icon generation, DMG packaging, and releases. |

Before publishing, sign in to GitHub CLI and check the working tree and target commit:

```sh
./scripts/release.sh --dry-run
./scripts/release.sh
```

The script creates `vYYYY.MM.DD[.N]` versions, builds, signs, and validates ZIP / DMG packages, then uploads them through GitHub CLI and verifies their SHA-256 digests. See `./scripts/release.sh --help` for options.

</details>

## Contributing

[Issues](https://github.com/j-tide/codex-bar/issues), suggestions, and pull requests are welcome.

- Include your macOS, Codex, and codex-bar versions, reproduction steps, and sanitized screenshots or logs when reporting a bug.
- Keep each change focused. Run relevant tests for behavior changes; check both languages and appearances for interface changes.
- Update both READMEs when features or installation steps change.

## Acknowledgments and license

Built on [xmasdong/codexbar](https://github.com/xmasdong/codexbar). Thanks to the original author and all contributors. Model scores and reset-window data are provided by [Codex Radar](https://codexradar.com/).

Released under the [MIT License](LICENSE).
