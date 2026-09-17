# README visual assets

The READMEs use the app's existing mint mark and native macOS interface. All accounts, task titles, quotas, subscription dates, token totals, and model scores in the screenshots are demonstration data. They are not live account information or published benchmark results.

## Native screenshots

| Prefix | Captured content |
| --- | --- |
| `overview` | Complete native `MenuBarView` |
| `tasks` | Native `TaskActivityListView` |
| `accounts` | `MenuBarView`'s account section and `AccountRowView` |
| `insights` | Native `CodexRadarView` and `TokenStatsView` |

Each prefix has four variants: `zh-light`, `zh-dark`, `en-light`, and `en-dark`. The feature images render the real components in an isolated preview window with live refresh disabled. They are fresh window captures, not cropped or AI-generated interfaces. The overview's version label identifies the documentation render, not a published release.

When updating screenshots, use sample data and capture the native window compositor so AppKit controls and glass render correctly. Check both languages and themes. Keep credentials and private task content out of every image.

## Brand assets

`brand-*.svg` and `download-*.svg` provide scalable wordmarks and download links. Their mark and mint/graphite palette follow the existing app icon and OAuth page. Regenerate them from the repository root:

```sh
python3 scripts/generate-readme-brand.py
```

The original app icon is also shown in the README footer directly from `codexBar/Assets.xcassets/AppIcon.appiconset/icon_64.png`.

## Presentation

`<picture>` selects the appropriate language and light/dark image. Feature captures are paired with concise descriptions; full overview variants remain available in the screenshot disclosure. The root READMEs link to `docs/guide.zh-CN.md` and `docs/guide.en.md` for installation details, privacy, troubleshooting, and development.
