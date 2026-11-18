import SwiftUI
import PickPlanCore

/// Faithful Liquid Glass port of Android Pickplan's `SettingsDialog`:
/// - `AI 引擎设置` (`AI Engine Settings`)
/// - 7 platform presets (`DeepSeek`, `Kimi (Moonshot)`, `Tongyi Qwen`, `GLM`, `SiliconFlow`, `OpenAI`, `Custom`)
/// - Locks Base URL & Model fields when preset != `Custom` (matching Android behavior)
/// - `测试连接` (`Test Connection`) showing HTTP 200 status + Language/Haptics + Official Site link
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

    private var isCustomProvider: Bool {
        selectedProviderName == "Custom"
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text(AppLocalizer.t(zh: "AI 引擎设置", en: "AI Engine Settings", language: store.language)),
                    footer: Text(AppLocalizer.t(zh: "可快速选择平台，或自定义接口与模型。", en: "Pick a provider quickly, or use custom endpoint/model.", language: store.language))
                ) {
                    Picker(
                        AppLocalizer.t(zh: "平台", en: "Provider", language: store.language),
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
                            testResultMessage = ""
                        }
                    }

                    TextField("Base URL", text: $baseUrl)
                        .disabled(!isCustomProvider)
                        .foregroundStyle(isCustomProvider ? .white : Color.gray)
                        .autocorrectionDisabled()

                    TextField(AppLocalizer.t(zh: "模型", en: "Model", language: store.language), text: $modelName)
                        .disabled(!isCustomProvider)
                        .foregroundStyle(isCustomProvider ? .white : Color.gray)
                        .autocorrectionDisabled()

                    SecureField("API Key", text: $apiKey)

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
                            case .success:
                                testSucceeded = true
                                testResultMessage = AppLocalizer.t(
                                    zh: "连接成功（200）。",
                                    en: "Connection OK (200).",
                                    language: store.language
                                )
                            case .failure(let err):
                                testSucceeded = false
                                testResultMessage = "\(AppLocalizer.t(zh: "连接失败", en: "Connection failed", language: store.language)): \(err.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Label(
                                AppLocalizer.t(zh: "测试连接", en: "Test Connection", language: store.language),
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

                Section(AppLocalizer.t(zh: "关于 Pickplan iOS", en: "About Pickplan iOS", language: store.language)) {
                    if let url = URL(string: "https://pickplan-ios.pages.dev/") {
                        Link(
                            AppLocalizer.t(
                                zh: "官方网站：https://pickplan-ios.pages.dev/",
                                en: "Official Website: https://pickplan-ios.pages.dev/",
                                language: store.language
                            ),
                            destination: url
                        )
                    }
                    Text(
                        AppLocalizer.t(
                            zh: "零付费权限：所有待办、AI 设置与定时自动快照均保存在本机，并可通过系统「文件」App 访问 Pickplan/Backups。",
                            en: "Zero paid entitlements: tasks, AI settings, and scheduled snapshots stay locally on-device and are accessible in the iOS Files app under Pickplan/Backups.",
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
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.t(zh: "取消", en: "Cancel", language: store.language)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.t(zh: "保存", en: "Save", language: store.language)) {
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
