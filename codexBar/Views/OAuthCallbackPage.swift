import Foundation

/// Self-contained callback document. Never interpolate callback codes or tokens.
enum OAuthCallbackPage {
    static let returnURL = "codexappbar://open"

    static func isReturnURL(_ url: URL) -> Bool {
        url.scheme == "codexappbar" && url.host == "open"
            && (url.path.isEmpty || url.path == "/") && url.query == nil
            && url.fragment == nil && url.user == nil && url.password == nil && url.port == nil
    }

    static func html(chinese: Bool) -> String {
        let title = chinese ? "授权已接收" : "Authorization received"
        let description = chinese ? "正在由 CodexAppBar 完成账号验证。<br>返回应用即可查看结果。" : "CodexAppBar is finishing account verification.<br>Return to the app to see the result."
        let action = chinese ? "返回 CodexAppBar" : "Return to CodexAppBar"
        let hint = chinese ? "也可以点击菜单栏中的应用图标" : "You can also use the app icon in your menu bar"
        let footer = chinese ? "你可以安全关闭此标签页" : "You can safely close this tab"
        return """
        <!doctype html>
        <html lang="\(chinese ? "zh-CN" : "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="no-referrer">
          <meta name="color-scheme" content="light dark">
          <link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHJlY3Qgd2lkdGg9IjI0IiBoZWlnaHQ9IjI0IiByeD0iNiIgZmlsbD0iIzIxM2Q0OSIvPjxnIHRyYW5zZm9ybT0idHJhbnNsYXRlKDMgMykgc2NhbGUoMS4xMjUpIiBmaWxsPSJub25lIiBzdHJva2U9IiM3NWUwZDIiIHN0cm9rZS13aWR0aD0iMS42NSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMTEuMSAzLjRhNiA2IDAgMSAwIDAgOS4yTTYuOCA1LjNoNy44TTYuOCA4aDUuN002LjggMTAuN2g3LjgiLz48L2c+PC9zdmc+">
          <title>\(title) · CodexAppBar</title>
          <style>
            *{box-sizing:border-box}html{min-height:100%;background:#f5f7f8}
            body{margin:0;min-height:100svh;display:grid;grid-template-rows:auto 1fr auto;color:#202d36;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased;background:radial-gradient(ellipse at 50% 42%,#ffffff 0,transparent 56%),radial-gradient(ellipse at 82% 0%,#dff4f3 0,transparent 42%),#f5f7f8}
            header{display:flex;align-items:center;justify-content:space-between;gap:24px;padding:32px 44px}
            .brand{font-size:17px;font-weight:650;letter-spacing:-.5px;display:flex;align-items:center;gap:10px}
            .brand svg{width:25px;height:25px;color:#178d91}.context{font-size:12px;color:#69767e}
            main{width:min(100%,600px);margin:auto;text-align:center;padding:48px 24px 70px;animation:enter .6s both}
            .emblem{position:relative;width:132px;height:132px;display:grid;place-items:center;margin:0 auto 32px}
            .emblem:before{content:"";position:absolute;inset:-24px;border-radius:50%;background:radial-gradient(circle,#72d4cf30,transparent 68%);pointer-events:none}
            .app-icon{width:104px;height:104px;filter:drop-shadow(0 12px 17px #1538441c)}
            .seal{position:absolute;right:3px;bottom:5px;width:35px;height:35px;display:grid;place-items:center;border-radius:50%;background:#f4fffc;box-shadow:0 0 0 5px #f8fbfb,0 3px 10px #244e4c16;color:#138969}
            .seal svg{width:19px;height:19px}.seal path{stroke-dasharray:24;stroke-dashoffset:0;animation:check .55s .2s both}
            h1{font-size:34px;line-height:1.25;letter-spacing:-1.1px;font-weight:650;margin:0 0 17px}
            .description{font-size:15px;line-height:1.85;color:#637079;margin:0}
            .action{margin-top:32px;min-height:48px;padding:0 24px;display:inline-flex;align-items:center;justify-content:center;gap:16px;border-radius:15px;background:linear-gradient(#2e4552,#1c303c);border:1px solid #ffffff45;box-shadow:inset 0 1px #ffffff20,0 5px 13px #19333c16;color:#fff;font-size:14px;font-weight:600;text-decoration:none;transition:transform .18s,box-shadow .18s}
            .action svg{height:16px;width:16px;color:#89e0d6;transition:transform .18s}.action:hover{transform:translateY(-2px);box-shadow:inset 0 1px #ffffff30,0 8px 20px #19333c26}.action:hover svg{transform:translateX(3px)}.action:active{transform:translateY(0)}.action:focus-visible{outline:3px solid #55bdbb;outline-offset:4px}
            .hint{font-size:12px;line-height:1.6;color:#75818a;margin:17px 0 0}
            footer{text-align:center;padding:24px;font-size:12px;color:#7a858c;display:flex;gap:7px;justify-content:center;align-items:center}footer svg{width:13px;height:13px}
            @keyframes enter{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}@keyframes check{from{stroke-dashoffset:24}to{stroke-dashoffset:0}}
            @media(prefers-color-scheme:dark){html{background:#11191f}body{color:#eff4f6;background:radial-gradient(ellipse at 50% 38%,#23383c 0,transparent 53%),radial-gradient(ellipse at 85% 0,#17343b 0,transparent 42%),#11191f}.brand svg{color:#75d8d0}.context,.hint,footer{color:#9dabb3}.description{color:#b0bec5}.seal{background:#213e38;box-shadow:0 0 0 5px #1c2e32,0 3px 10px #0002;color:#8be4c5}.action{background:linear-gradient(#e6f8f4,#c6e8e2);color:#1d393b;border-color:#fff7;box-shadow:inset 0 1px #fff8,0 5px 18px #0002}.action svg{color:#287c77}}
            @media(max-width:480px){header{padding:24px}.context{display:none}main{padding:40px 24px}h1{font-size:29px}.description{font-size:14px}.action{width:100%;max-width:300px}footer{padding:22px}}
            @media(prefers-reduced-motion:reduce){*,*:before{animation:none!important;transition:none!important}}
          </style>
        </head>
        <body>
          <header><div class="brand"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" aria-hidden="true"><path d="M11.1 3.4a6 6 0 1 0 0 9.2M6.8 5.3h7.8M6.8 8h5.7M6.8 10.7h7.8"/></svg>CodexAppBar</div><span class="context">\(chinese ? "账号授权" : "Account authorization")</span></header>
          <main>
            <div class="emblem" aria-hidden="true">
              <svg class="app-icon" viewBox="0 0 104 104" fill="none"><defs><linearGradient id="glass" x1="12" y1="0" x2="89" y2="104" gradientUnits="userSpaceOnUse"><stop stop-color="#345460"/><stop offset="1" stop-color="#10232e"/></linearGradient><linearGradient id="rim" x1="0" y1="0" x2="100" y2="104"><stop stop-color="#b9f6ec" stop-opacity=".6"/><stop offset=".55" stop-color="#72c5c8" stop-opacity=".06"/><stop offset="1" stop-color="#a9f4ef" stop-opacity=".2"/></linearGradient></defs><rect x="1" y="1" width="102" height="102" rx="25" fill="url(#glass)" stroke="url(#rim)"/><g transform="translate(18 18) scale(4.25)" stroke-width="1.65" stroke-linecap="round"><path d="M11.1 3.4a6 6 0 1 0 0 9.2" stroke="#75e0d2"/><path d="M6.8 5.3h7.8M6.8 8h5.7M6.8 10.7h7.8" stroke="#e6f4f7"/></g></svg>
              <span class="seal"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 4.5 4.5L19 7"/></svg></span>
            </div>
            <h1>\(title)</h1><p class="description">\(description)</p>
            <a class="action" href="\(returnURL)">\(action)<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m-5-5 5 5-5 5"/></svg></a>
            <p class="hint">\(hint)</p>
          </main>
          <footer><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.3" aria-hidden="true"><rect x="4.5" y="8" width="11" height="8" rx="2"/><path d="M7 8V6a3 3 0 0 1 6 0v2"/></svg>\(footer)</footer>
          <script>try { history.replaceState(null, '', location.pathname); } catch (_) {}</script>
        </body></html>
        """
    }
}
