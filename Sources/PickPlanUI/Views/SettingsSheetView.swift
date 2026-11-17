import SwiftUI
import PickPlanCore

/// Settings sheet covering all 7 OpenAI-compatible AI presets, connection testing, language, and haptics.
public struct SettingsSheetView: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderName: String = "DeepSeek"
    @State private var baseUrl: String = ""
    @State private var modelName: String = ""
    @State private var apiKey: String = ""
    @State private var testResultMessage: String = ""
    @State private var testSucceeded: Bool? = nil

    public init(store: PlanStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalizer.t(zh: "语言与触感", en: "Language & Tactile Feedback", language: store.language)) {
                    Picker(
                        AppLocalizer.t(zh: "界面语言", en: "Language", language: store.language),
                        selection: Binding(
                            get: { store.language },
                            set: { newLang in Task { await store.setLanguage(newLang) } }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Toggle(
                        AppLocalizer.t(zh: "Liquid Glass 触感反馈", en: "Tactile Haptics", language: store.language),
                        isOn: Binding(
                            get: { store.preferences.hapticsEnabled },
                            set: { enabled in Task { await store.setHapticsEnabled(enabled) } }
                        )
                    )
                }

                Section(AppLocalizer.t(zh: "AI 大模型接口 (BYOK)", en: "AI Engine (OpenAI-Compatible)", language: store.language)) {
                    Picker(
                        AppLocalizer.t(zh: "平台预设", en: "Provider Preset", language: store.language),
                        selection: $selectedProviderName
                    ) {
                        ForEach(AIProviderPreset.presets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    .onChange(of: selectedProviderName) { _, newValue in
                        if let preset = AIProviderPreset.preset(named: newValue), preset.name != "Custom" {
                            baseUrl = preset.baseUrl
                            modelName = preset.defaultModel
                        }
                    }

                    TextField("Base URL", text: $baseUrl)
                        .autocorrectionDisabled()
                    TextField(AppLocalizer.t(zh: "模型名称", en: "Model Name", language: store.language), text: $modelName)
                        .autocorrectionDisabled()
                    SecureField("API Key (sk-...)", text: $apiKey)

                    Button {
                        Task {
                            await store.updateAISettings(
                                AISettingsRecord(
                                    providerName: selectedProviderName,
                                    baseUrl: baseUrl,
                                    modelName: modelName,
                                    apiKey: apiKey.isEmpty ? nil : apiKey
                                )
                            )
                            let res = await store.testAIConnection()
                            switch res {
                            case .success(let msg):
                                testSucceeded = true
                                testResultMessage = "OK: \(msg)"
                            case .failure(let err):
                                testSucceeded = false
                                testResultMessage = err.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Label(
                                AppLocalizer.t(zh: "保存并测试连接", en: "Save & Test Connection", language: store.language),
                                systemImage: "network"
                            )
                            if store.isLoadingAI {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }

                    if !testResultMessage.isEmpty {
                        Text(testResultMessage)
                            .font(.caption)
                            .foregroundStyle(testSucceeded == true ? PickPlanPalette.successMint : PickPlanPalette.deadlineCoral)
                    }
                }

                Section(AppLocalizer.t(zh: "零费用使用说明", en: "Zero-Cost Sideloading", language: store.language)) {
                    Text(
                        AppLocalizer.t(
                            zh: "本应用未启用 iCloud 或付费 Push Entitlements。定时本地备份文件可在系统「文件」App → Pickplan → Backups 中直接访问。",
                            en: "Uses zero paid entitlements. Scheduled local backups are accessible directly in the iOS Files app under Pickplan/Backups.",
                            language: store.language
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(PickPlanPalette.muted)
                }
            }
            .navigationTitle(AppLocalizer.t(zh: "设置", en: "Settings", language: store.language))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.t(zh: "完成", en: "Done", language: store.language)) {
                        Task {
                            await store.updateAISettings(
                                AISettingsRecord(
                                    providerName: selectedProviderName,
                                    baseUrl: baseUrl,
                                    modelName: modelName,
                                    apiKey: apiKey.isEmpty ? nil : apiKey
                                )
                            )
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                selectedProviderName = store.aiSettings.providerName
                baseUrl = store.aiSettings.baseUrl
                modelName = store.aiSettings.modelName
                apiKey = store.aiSettings.apiKey ?? ""
            }
        }
        .preferredColorScheme(.dark)
    }
}
