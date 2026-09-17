#!/usr/bin/env python3
"""Regenerate the README wordmarks and download buttons from the existing app brand."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
asset=root/'docs/assets'
# Colors and mark match the existing app icon and OAuth page.
for lang in ['zh','en']:
  for theme in ['light','dark']:
    dark=theme=='dark'
    bg,fg,muted,border=('#0e161b','#eff6f5','#a4bbb6','#26383f') if dark else ('#edf4f1','#152e32','#486961','#dae8e2')
    subtitle='任务、额度、用量。抬眼就知道。' if lang=='zh' else 'Your Codex, at a glance.'
    svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="272" viewBox="0 0 1120 272" role="img" aria-labelledby="title desc">
<title id="title">codex-bar</title><desc id="desc">{subtitle}</desc>
<defs><linearGradient id="icon" x1="0" y1="1" x2="1" y2="0"><stop stop-color="#0e1c26"/><stop offset="1" stop-color="#253c4a"/></linearGradient></defs>
<rect x="1" y="1" width="1118" height="270" rx="24" fill="{bg}" stroke="{border}"/>
<g transform="translate(262 65)">
<rect width="96" height="96" rx="23" fill="url(#icon)" stroke="#50737c" stroke-width="0.8"/>
<g transform="translate(17 17) scale(3.875)" fill="none" stroke-width="1.65" stroke-linecap="round">
<path d="M11.1 3.4a6 6 0 1 0 0 9.2" stroke="#63e2c7"/>
<path d="M6.8 5.3h7.8M6.8 8h5.7M6.8 10.7h7.8" stroke="#f0fafc"/>
</g></g>
<text x="390" y="143" fill="{fg}" font-family="SF Pro Display, -apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif" font-size="88" font-weight="650" letter-spacing="-4">codex-bar</text>
<text x="560" y="217" text-anchor="middle" fill="{muted}" font-family="SF Pro Display, -apple-system, BlinkMacSystemFont, PingFang SC, sans-serif" font-size="28" font-weight="400" letter-spacing="0.4">{subtitle}</text>
</svg>'''
    (asset/f'brand-{lang}-{theme}.svg').write_text(svg+'\n')
for lang,label in [('zh','下载 macOS 版'),('en','Download for macOS')]:
  width=224 if lang=='zh' else 252
  svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="48" viewBox="0 0 {width} 48" role="img" aria-label="{label}"><rect width="{width}" height="48" rx="10" fill="#16705f"/><g transform="translate(20 14)" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10 0v12m-4-4 4 4 4-4M2 14v5h16v-5"/></g><text x="55" y="30" fill="#fff" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, PingFang SC, sans-serif" font-size="17" font-weight="600">{label}</text></svg>'''
  (asset/f'download-{lang}.svg').write_text(svg+'\n')
