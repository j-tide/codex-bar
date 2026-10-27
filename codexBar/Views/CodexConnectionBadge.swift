import SwiftUI

struct CodexConnectionBadge: View {
    @EnvironmentObject private var language: LanguageSettings
    let status: CodexConnectionStatus

    private var title: String {
        switch status.mode {
        case .subscription: return L.zh ? "Codex 订阅" : "Codex subscription"
        case .ccSwitchDirect: return L.zh ? "cc-switch 直连" : "cc-switch Direct"
        case .ccSwitchRouting: return L.zh ? "cc-switch 路由" : "cc-switch Routing"
        case .customAPI: return L.zh ? "自定义 API" : "Custom API"
        case .unknown: return L.zh ? "连接待确认" : "Connection unknown"
        }
    }

    private var color: Color {
        switch status.mode {
        case .subscription: return .green
        case .ccSwitchDirect: return .orange
        case .ccSwitchRouting: return .purple
        case .customAPI: return .blue
        case .unknown: return .secondary
        }
    }

    private var symbol: String {
        switch status.mode {
        case .subscription: return "person.crop.circle"
        case .ccSwitchDirect, .customAPI: return "arrow.up.right"
        case .ccSwitchRouting: return "arrow.triangle.branch"
        case .unknown: return "questionmark.circle"
        }
    }

    private var details: String {
        var lines = [L.zh ? "当前全局配置：\(title)" : "Current global configuration: \(title)"]
        if let provider = status.provider { lines.append((L.zh ? "供应商：" : "Provider: ") + provider) }
        if let endpoint = status.endpoint { lines.append((L.zh ? "入口：" : "Endpoint: ") + endpoint) }
        lines.append(L.zh
            ? "按本机配置识别；已运行会话或项目覆盖可能使用其他连接。"
            : "Based on local configuration; running sessions and project overrides may use another connection.")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        let _ = language.identity
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 0.5))
            .fixedSize()
            .help(details)
            .accessibilityLabel(details)
    }
}
