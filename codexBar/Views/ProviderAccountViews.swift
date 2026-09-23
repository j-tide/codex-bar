import SwiftUI
import AppKit

/// Codex 桌面端（独立 Codex App 或 ChatGPT App 内嵌 Codex）是否在运行。
/// 桌面端固定用登录的 ChatGPT 账号请求官方后端；provider 配置只对终端 codex CLI 生效。
enum CodexDesktopMonitor {
    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.openai.codex" || $0.bundleIdentifier == "com.openai.chat"
        }
    }
}

/// 右栏底部的第三方 API 通道区：录入/激活智谱 GLM 等 API Key 账号。
struct ProviderAccountsSection: View {
    @EnvironmentObject private var language: LanguageSettings
    @ObservedObject var store: ProviderAccountStore
    let onMessage: (String) -> Void
    let onError: (String) -> Void

    @State private var editingAccount: ProviderAccount?

    /// 面板整体高度需要提前算好，区块内部按同样的度量布局。
    /// 没有 API 账号且不在编辑时整块收起（高度 0），入口在底部工具栏的「API Key」按钮。
    static func height(accounts: Int, isEditing: Bool) -> CGFloat {
        guard isEditing || accounts > 0 else { return 0 }
        if isEditing { return 232 }
        let visible = min(accounts, 3)
        let cards = CGFloat(visible) * 47 + CGFloat(visible - 1) * 5
        return 8 + 22 + 7 + cards + 7 + 12 + 8
    }

    var body: some View {
        let _ = language.identity
        VStack(alignment: .leading, spacing: 7) {
            header
            if store.isEditingForm {
                ProviderAccountForm(initial: editingAccount) { account in
                    store.upsert(account)
                    store.isEditingForm = false
                    editingAccount = nil
                    onMessage(L.providerSaved)
                } onCancel: {
                    store.isEditingForm = false
                    editingAccount = nil
                }
            } else if store.accounts.count <= 3 {
                VStack(spacing: 5) {
                    ForEach(store.accounts) { card($0) }
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 5) {
                        ForEach(store.accounts) { card($0) }
                    }
                }
            }
            if !store.isEditingForm {
                desktopNote
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(L.providerSectionTitle).font(.system(size: 13, weight: .medium))
            Text(L.providerCLIBadge)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PopupLayout.plan)
                .padding(.horizontal, 5).frame(height: 16)
                .background(PopupLayout.plan.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
            Spacer()
            if store.activeProviderKey != nil {
                Button(L.providerRestoreOfficial, action: confirmRestoreOfficial).font(.system(size: 10))
                    .buttonStyle(.borderless).focusable(false)
                    .foregroundColor(.secondary)
                    .help(L.providerRestoreHelp)
            }
            Button {
                editingAccount = nil
                store.isEditingForm = true
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless).focusable(false)
            .disabled(store.isEditingForm)
            .help(L.providerAdd)
        }
        .frame(height: 22)
    }

    private func card(_ account: ProviderAccount) -> some View {
        ProviderAccountCard(
            account: account,
            isActive: store.activeProviderKey == account.providerKey
        ) {
            activate(account)
        } onEdit: {
            editingAccount = account
            store.isEditingForm = true
        } onDelete: {
            delete(account)
        }
    }

    private var desktopNote: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.8))
            Text(L.providerDesktopNote)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func activate(_ account: ProviderAccount) {
        if CodexDesktopMonitor.isRunning {
            let alert = NSAlert()
            alert.messageText = L.providerDesktopAlertTitle
            alert.informativeText = L.providerDesktopAlertInfo
            alert.addButton(withTitle: L.providerActivateAnyway)
            alert.addButton(withTitle: L.cancel)
            guard PopupModalPresenter.run { alert.runModal() } == .alertFirstButtonReturn else { return }
        }
        do {
            try store.activate(account)
            onMessage(L.providerActivated(account.model))
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func delete(_ account: ProviderAccount) {
        let alert = NSAlert()
        alert.messageText = L.confirmDelete(account.name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.delete)
        alert.addButton(withTitle: L.cancel)
        guard PopupModalPresenter.run { alert.runModal() } == .alertFirstButtonReturn else { return }
        // 删除的是当前生效通道时，同时移除 config.toml 覆盖，避免 CLI 指向不存在的段落。
        if store.activeProviderKey == account.providerKey {
            do {
                try store.deactivateProvider()
            } catch {
                onError(error.localizedDescription)
                return
            }
        }
        store.remove(account)
    }

    private func confirmRestoreOfficial() {
        let alert = NSAlert()
        alert.messageText = L.providerRestoreTitle
        alert.informativeText = L.providerRestoreInfo
        alert.addButton(withTitle: L.providerRestoreOfficial)
        alert.addButton(withTitle: L.cancel)
        guard PopupModalPresenter.run { alert.runModal() } == .alertFirstButtonReturn else { return }
        do {
            try store.deactivateProvider()
            onMessage(L.providerRestored)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

/// 单个 API 账号卡片：名称 + 协议徽标 + 模型/密钥摘要 + 激活/编辑/删除。
private struct ProviderAccountCard: View {
    @EnvironmentObject private var language: LanguageSettings

    let account: ProviderAccount
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let _ = language.identity
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: PopupSpacing.compact) {
                Circle()
                    .fill(isActive ? CodexStatusPalette.ok : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(account.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1).truncationMode(.middle)
                badge(text: "API KEY", color: PopupLayout.accent)
                badge(text: account.resolvedWireAPI == "chat" ? "CHAT" : "RESPONSES", color: .secondary)
                if isActive {
                    badge(text: L.providerCurrentBadge, color: PopupLayout.accent)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 10))
                }
                .buttonStyle(.borderless).focusable(false)
                .foregroundColor(.secondary)
                .help(L.providerEdit)

                Button(action: confirmDelete) {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.borderless).focusable(false)
                .foregroundColor(.secondary)
                .help(L.delete)

                if !isActive {
                    Button(action: onActivate) {
                        Text(L.switchBtn).font(.system(size: 11))
                    }
                    .popupGlassButton(tint: PopupLayout.accent, compact: true)
                }
            }
            HStack(spacing: 6) {
                Text(account.model)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(account.maskedKey)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.leading, 13)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? PopupLayout.accent.opacity(0.09) : Color.primary.opacity(0.025))
        )
        .overlay(alignment: .leading) {
            if isActive {
                Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name) · \(account.model)")
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).frame(height: 16)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = L.confirmDelete(account.name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.delete)
        alert.addButton(withTitle: L.cancel)
        if PopupModalPresenter.run { alert.runModal() } == .alertFirstButtonReturn {
            onDelete()
        }
    }
}

/// 内联录入表单：预设一键填充 + 连接验证（顺带拉取模型列表）。
private struct ProviderAccountForm: View {
    @EnvironmentObject private var language: LanguageSettings

    let initial: ProviderAccount?
    let onSave: (ProviderAccount) -> Void
    let onCancel: () -> Void

    @State private var presetID = ProviderPreset.zhipuCN.id
    @State private var name = ""
    @State private var providerKey = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var wireAPI = "responses"
    @State private var isVerifying = false
    @State private var verifySuccess: String?
    @State private var verifyError: String?
    @State private var availableModels: [String] = []

    var body: some View {
        let _ = language.identity
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(
                get: { presetID },
                set: { applyPreset($0) }
            )) {
                ForEach(ProviderPreset.all, id: \.id) { preset in
                    Text(preset.displayName).tag(preset.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            fieldRow(L.providerFieldName) {
                TextField(L.providerFieldNamePlaceholder, text: $name)
                    .textFieldStyle(.plain).font(.system(size: 11))
            }
            if presetID == ProviderPreset.custom.id {
                fieldRow(L.providerFieldID) {
                    TextField("my_provider", text: $providerKey)
                        .textFieldStyle(.plain).font(.system(size: 11))
                }
            }
            fieldRow("Base URL") {
                TextField("https://open.bigmodel.cn/api/v1", text: $baseURL)
                    .textFieldStyle(.plain).font(.system(size: 11))
            }
            fieldRow(L.providerFieldKey) {
                SecureField("xxxxxxxx.xxxxxxxx", text: $apiKey)
                    .textFieldStyle(.plain).font(.system(size: 11))
            }
            HStack(spacing: 8) {
                fieldRow(L.providerFieldModel) {
                    HStack(spacing: 3) {
                        TextField("glm-5.3", text: $model)
                            .textFieldStyle(.plain).font(.system(size: 11))
                        if !availableModels.isEmpty {
                            Menu {
                                ForEach(availableModels, id: \.self) { slug in
                                    Button(slug) { model = slug }
                                }
                            } label: {
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help(L.providerModelSuggestions)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Picker("", selection: $wireAPI) {
                    Text("Responses").tag("responses")
                    Text("Chat").tag("chat").disabled(true)
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize()
                .help(L.providerProtocolHelp)
            }

            HStack(spacing: 8) {
                Button(action: verify) {
                    HStack(spacing: 4) {
                        if isVerifying {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10))
                        }
                        Text(isVerifying ? L.providerVerifying : L.providerVerify)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(height: 18)
                }
                .buttonStyle(.borderless).focusable(false)
                .disabled(isVerifying || baseURL.isEmpty || apiKey.isEmpty)

                if let verifySuccess {
                    Text(verifySuccess).font(.system(size: 10)).foregroundColor(.green).lineLimit(1)
                }
                if let verifyError {
                    Text(verifyError).font(.system(size: 10)).foregroundColor(.orange)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(L.cancel, action: onCancel).font(.system(size: 10))
                    .buttonStyle(.borderless).focusable(false)
                Button(L.providerSave, action: save).font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.borderless).focusable(false)
                    .disabled(!canSave)
                    .foregroundColor(canSave ? .accentColor : .secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.025)))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .onAppear(perform: prefill)
    }

    private var canSave: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && wireAPI == "responses"
            && (presetID != ProviderPreset.custom.id
                || ProviderAccount.isValidProviderKey(providerKey.trimmingCharacters(in: .whitespaces)))
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            content()
        }
    }

    private func prefill() {
        guard let initial else {
            applyPreset(ProviderPreset.zhipuCN.id)
            return
        }
        name = initial.name
        providerKey = initial.providerKey
        baseURL = initial.baseURL
        apiKey = initial.apiKey
        model = initial.model
        wireAPI = initial.resolvedWireAPI
        presetID = ProviderPreset.match(baseURL: initial.baseURL)?.id ?? ProviderPreset.custom.id
    }

    private func applyPreset(_ id: String) {
        presetID = id
        guard let preset = ProviderPreset.all.first(where: { $0.id == id }) else { return }
        if preset.id == ProviderPreset.custom.id {
            providerKey = initial?.providerKey ?? ""
            return
        }
        providerKey = preset.providerKey
        baseURL = preset.baseURL
        model = preset.defaultModel
        wireAPI = preset.wireAPI
        name = preset.displayName
        availableModels = []
        verifySuccess = nil
        verifyError = nil
    }

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true
        verifySuccess = nil
        verifyError = nil
        let url = baseURL.trimmingCharacters(in: .whitespaces)
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            do {
                let slugs = try await CodexProviderConfigService.fetchModelSlugs(baseURL: url, apiKey: key)
                availableModels = slugs
                if !slugs.contains(model), let first = slugs.first {
                    model = first
                }
                isVerifying = false
                verifySuccess = L.providerVerifyOK(slugs.count)
            } catch {
                isVerifying = false
                verifyError = L.providerVerifyFailed(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let fallbackName = ProviderPreset.all.first(where: { $0.id == presetID })?.displayName
            ?? baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let account = ProviderAccount(
            id: initial?.id ?? UUID(),
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            providerKey: providerKey.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            wireAPI: wireAPI,
            createdAt: initial?.createdAt ?? Date()
        )
        onSave(account)
    }
}
