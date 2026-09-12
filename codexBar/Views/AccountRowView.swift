import SwiftUI

/// Small account pools show full quotas; larger pools keep backups compact.
struct AccountRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var quotaRevealed = false
    private var quotaReveal: CGFloat { quotaRevealed || reduceMotion || !liveUpdates ? 1 : 0 }
    @EnvironmentObject var language: LanguageSettings
    @EnvironmentObject var quotaDisplay: QuotaDisplaySettings

    let account: TokenAccount
    let isActive: Bool
    let now: Date
    let isRefreshing: Bool
    var showsDetails = false
    var compactPool = false
    private var expanded: Bool { isActive || showsDetails }
    let onActivate: () -> Void
    let onRefresh: () -> Void
    let onReauth: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let _ = language.identity
        let fiveHourUsedPercent = account.hasFiveHourQuota
            ? account.fiveHourUsedPercent
            : nil
        let fiveHourDisplayPercent = fiveHourUsedPercent.map {
            quotaDisplay.amountMode.displayPercent(forUsedPercent: $0)
        }
        let fiveHourResetDescription = account.fiveHourResetDescription
        let weeklyDisplayPercent = quotaDisplay.amountMode.displayPercent(
            forUsedPercent: account.weeklyUsedPercent
        )
        let weeklyResetDescription = account.weeklyResetDescription
        let showWeeklyReset = !weeklyResetDescription.isEmpty

        VStack(alignment: .leading, spacing: 7) {
            // Line 1: org name + plan badge + active mark + switch button
            HStack(spacing: PopupSpacing.compact) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(displayName)

                accountBadge(color: planBadgeColor) { Text(planBadgeText) }

                if hasResetCredits { resetCreditsBadge }

                if isActive {
                    accountBadge(color: PopupLayout.accent) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(L.zh ? "当前账号" : "Current")
                    }
                }

                Spacer()

                if compactPool {
                    Menu {
                        Button(L.refreshUsage, action: onRefresh).disabled(isRefreshing || account.isBanned)
                        if account.tokenExpired { Button(L.reauth, action: onReauth) }
                        Divider()
                        Button(L.delete, role: .destructive, action: confirmDelete)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                            .frame(width: 20, height: 22)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .focusable(false).focusEffectDisabled()
                    .help(L.zh ? "账号操作" : "Account actions")
                    .accessibilityLabel("\(displayName) · \(L.zh ? "账号操作" : "Account actions")")
                    if account.tokenExpired {
                        Button(L.reauth, action: onReauth).font(.system(size: 10))
                            .popupGlassButton(tint: .orange, compact: true)
                    } else if !isActive && !account.isBanned {
                        Button(L.switchBtn, action: onActivate).font(.system(size: 11))
                            .popupGlassButton(tint: PopupLayout.accent, compact: true)
                    }
                } else {
                // 删除按钮（NSAlert 二次确认）
                Button {
                    let alert = NSAlert()
                    alert.messageText = L.confirmDelete(displayName)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L.delete)
                    alert.addButton(withTitle: L.cancel)
                    if PopupModalPresenter.run({ alert.runModal() }) == .alertFirstButtonReturn {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .foregroundColor(.secondary)
                .help(L.delete)
                .accessibilityLabel(L.confirmDelete(displayName))

                if account.tokenExpired {
                    Button(L.reauth, action: onReauth)
                        .popupGlassButton(tint: .orange, compact: true)
                        .font(.system(size: 10, weight: .medium))
                        .tint(.orange)
                } else if !account.isBanned {
                    Button(action: onRefresh) {
                        RefreshIconView(
                            isRefreshing: isRefreshing,
                            size: 14,
                            fontSize: 10,
                            weight: .medium
                        )
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .foregroundColor(.secondary)
                    .disabled(isRefreshing)
                    .help(L.refreshUsage)

                    if !isActive {
                        Button(action: onActivate) {
                            Text(L.switchBtn).font(.system(size: 11))
                        }.popupGlassButton(tint: PopupLayout.accent, compact: true)
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if expanded {
                HStack(spacing: 8) {
                    Text(account.email).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(account.email)
                    Spacer(minLength: 0)
                    subscriptionValidity
                }
            } else {
                subscriptionValidity
            }

            if shouldShowResetCreditsExpiration && !compactPool {
                resetCreditsExpirationInfo
            }

            // Line 2: usage info
            if account.tokenExpired {
                HStack(spacing: PopupSpacing.compact) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(L.tokenExpiredHint)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Spacer()
                }
            } else if account.isBanned {
                HStack(spacing: PopupSpacing.compact) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text(L.accountSuspended)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Spacer()
                }
            } else {
                if let fiveHourUsedPercent, let fiveHourDisplayPercent {
                    HStack(alignment: .top, spacing: PopupSpacing.regular) {
                        quotaColumn(
                            label: "5h",
                            displayPercent: fiveHourDisplayPercent,
                            usedPercent: fiveHourUsedPercent,
                            resetDescription: fiveHourResetDescription,
                            showReset: !compactPool && !fiveHourResetDescription.isEmpty
                        )
                        quotaColumn(
                            label: "7d",
                            displayPercent: weeklyDisplayPercent,
                            usedPercent: account.weeklyUsedPercent,
                            resetDescription: weeklyResetDescription,
                            showReset: !compactPool && showWeeklyReset
                        )
                    }
                } else {
                    quotaColumn(
                        label: "7d",
                        displayPercent: weeklyDisplayPercent,
                        usedPercent: account.weeklyUsedPercent,
                        resetDescription: weeklyResetDescription,
                        showReset: !compactPool && showWeeklyReset
                    )
                }
            }
        }
        .padding(.vertical, PopupSpacing.regular)
        .padding(.horizontal, expanded || compactPool ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? PopupLayout.accent.opacity(0.09) : Color.primary.opacity(compactPool ? 0.025 : 0))
        )
        .overlay(alignment: .leading) {
            if isActive {
                Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 7)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isActive)
        .task {
            guard liveUpdates, !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.7)) { quotaRevealed = true }
        }
        .onDisappear { quotaRevealed = false }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(account.email)
    }

    @ViewBuilder
    private var subscriptionValidity: some View {
        if account.planType.lowercased() != "free" {
            if let billing = account.subscriptionBilling, let date = billing.activeUntil {
                let stale = account.subscriptionRefreshFailed || now.timeIntervalSince(billing.checkedAt) >= 3600 || date <= now
                let label = billing.willRenew == true
                    ? (L.zh ? "下次续订" : "Renews")
                    : (L.zh ? "有效期至" : "Valid until")
                let dateText = date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
                Text("\(label) \(dateText)\(stale ? (L.zh ? " · 缓存" : " · Cached") : "")")
                    .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                    .help("\(label): \(date.formatted(date: .complete, time: .shortened))\n\(L.zh ? "来源：订阅接口 active_until；更新时间" : "Source: subscriptions active_until; checked"): \(billing.checkedAt.formatted(date: .abbreviated, time: .shortened))\(stale ? (L.zh ? "\n当前显示上次查询结果，等待重新验证" : "\nShowing the last result, awaiting verification") : "")")
            } else {
                Text(L.zh ? "有效期未获取" : "Validity unavailable")
                    .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                    .help(L.zh ? "尚未从订阅接口获取有效期；不会使用登录凭证里的历史日期。" : "Subscription validity has not been retrieved. Historical sign-in credential dates are not used.")
            }
        }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = L.confirmDelete(displayName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.delete)
        alert.addButton(withTitle: L.cancel)
        if PopupModalPresenter.run({ alert.runModal() }) == .alertFirstButtonReturn { onDelete() }
    }

    private var displayName: String {
        account.displayName
    }

    private var statusColor: Color {
        if account.tokenExpired { return CodexStatusPalette.warning }
        return CodexStatusPalette.color(for: account.usageStatus)
    }

    private var planBadgeColor: Color {
        switch normalizedPlanType {
        case "free": return .secondary
        case "prolite", "pro5x", "codexpro5x": return .blue
        case "pro", "promax", "pro20x", "codexpro20x": return CodexStatusPalette.warning
        case "team", "business": return .teal
        case "enterprise": return .indigo
        case "plus": return .purple
        default: return .gray
        }
    }

    private var planBadgeText: String {
        switch normalizedPlanType {
        case "prolite", "pro5x", "codexpro5x": return "PRO 5X"
        case "pro", "promax", "pro20x", "codexpro20x": return "PRO 20X"
        default: return account.planType.uppercased()
        }
    }

    private var normalizedPlanType: String {
        account.planType
            .lowercased()
            .replacingOccurrences(of: "[_\\-\\s]", with: "", options: .regularExpression)
    }

    private func accountBadge<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 3, content: content)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.18), lineWidth: 0.5) }
            .fixedSize()
    }

    private var resetCreditsBadge: some View {
        accountBadge(color: resetCreditsColor) {
            Image(systemName: "gift.fill")
            Text(resetCreditsText)
        }
        .help(shouldShowResetCreditsExpiration ? "\(L.resetCreditsHelp)\n\(resetCreditsExpirationText)" : L.resetCreditsHelp)
        .accessibilityLabel(L.resetCreditsAvailable)
        .accessibilityValue(resetCreditsText)
    }

    private var resetCreditsText: String {
        guard let count = account.rateLimitResetCreditsAvailableCount else { return L.resetCreditsUnknown }
        return L.resetCreditsCount(count)
    }

    private var hasResetCredits: Bool {
        guard let count = account.rateLimitResetCreditsAvailableCount else { return false }
        return count > 0
    }

    private var resetCreditsColor: Color {
        guard let count = account.rateLimitResetCreditsAvailableCount, count > 0 else {
            return .secondary
        }
        return CodexStatusPalette.ok
    }

    private var shouldShowResetCreditsExpiration: Bool {
        guard let count = account.rateLimitResetCreditsAvailableCount,
              count > 0,
              let expiresAt = account.rateLimitResetCreditsExpiresAt else {
            return false
        }
        return isWithinResetCreditsReminderWindow(expiresAt)
    }

    private var resetCreditsExpirationInfo: some View {
        HStack(spacing: PopupSpacing.compact) {
            Image(systemName: resetCreditsExpirationIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(resetCreditsExpirationText)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: PopupSpacing.compact)
        }
        .foregroundColor(resetCreditsExpirationColor)
        .padding(.horizontal, PopupSpacing.regular)
        .padding(.vertical, PopupSpacing.compact)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(resetCreditsExpirationColor.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(resetCreditsExpirationColor.opacity(0.42), lineWidth: 1)
        )
        .help(L.resetCreditsExpiresAtHelp)
    }

    private func isWithinResetCreditsReminderWindow(_ expiresAt: Date) -> Bool {
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 && remaining <= 3 * 24 * 60 * 60
    }

    private var resetCreditsExpirationColor: Color {
        CodexStatusPalette.brightWarning
    }

    private var resetCreditsExpirationIcon: String {
        "calendar.badge.clock"
    }

    private var resetCreditsExpirationText: String {
        guard let expiresAt = account.rateLimitResetCreditsExpiresAt else { return "" }
        return L.resetCreditsExpiresAt(formattedResetCreditsExpirationDate(expiresAt))
    }

    private func formattedResetCreditsExpirationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.zh ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func usageColor(_ percent: Double) -> Color {
        CodexStatusPalette.color(forUsedPercent: percent)
    }

    private func quotaColumn(
        label: String,
        displayPercent: Double,
        usedPercent: Double,
        resetDescription: String,
        showReset: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PopupSpacing.compact) {
            HStack(spacing: PopupSpacing.compact) {
                Text("\(quotaDisplay.amountMode.shortLabel) \(label)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                AnimatedMetric(value: displayPercent, format: .percent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(usageColor(usedPercent))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(usageColor(usedPercent))
                        .frame(width: geometry.size.width * min(max(displayPercent, 0), 100) / 100 * quotaReveal)
                }
            }
            .frame(height: 5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: displayPercent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(quotaDisplay.amountMode.shortLabel) \(label)")
            .accessibilityValue("\(Int(displayPercent))%")

            if showReset {
                Text("\(label): \(resetDescription)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .help(resetDescription.isEmpty ? label : "\(label): \(resetDescription)")
    }
}
