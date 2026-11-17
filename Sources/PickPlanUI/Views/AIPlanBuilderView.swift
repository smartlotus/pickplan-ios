import SwiftUI
import PickPlanCore

/// Conversational plain-words draft builder supporting both BYOK cloud AI and offline `PlainWordsParser`.
public struct AIPlanBuilderView: View {
    @ObservedObject private var store: PlanStore
    @State private var inputText: String = ""

    public init(store: PlanStore) {
        self.store = store
    }

    private var samplePrompts: [(labelZh: String, labelEn: String, textZh: String, textEn: String)] {
        [
            ("工作", "Work", "明天上午十点评审交互稿，下午三点回电客户，周五前交季度总结", "Review UI tomorrow morning, call client at 3 PM, submit report by Friday"),
            ("生活", "Life", "今晚买菜，明天早上九点取快递", "Buy groceries tonight, pick up package tomorrow at 9 AM"),
            ("学习", "Study", "今晚八点复习 SwiftUI Liquid Glass，下周一交算法作业", "Study SwiftUI Liquid Glass tonight 8 PM, submit assignment next Monday")
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        introHeaderCard

                        if store.chatHistory.isEmpty {
                            emptySamplesCard
                        } else {
                            ForEach(store.chatHistory) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }
                .onChange(of: store.chatHistory.count) { _, _ in
                    if let last = store.chatHistory.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composerBar
                .padding(.horizontal, 16)
                .padding(.bottom, 86)
        }
        .navigationTitle(AppLocalizer.t(zh: "AI 整理计划", en: "AI Plan Builder", language: store.language))
    }

    private var introHeaderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalizer.t(zh: "做计划，说大白话", en: "Plan in plain words", language: store.language))
                    .font(.subheadline.bold())
                let hasKey = !(store.aiSettings.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text(
                    hasKey
                        ? AppLocalizer.t(zh: "云端引擎已就绪：\(store.aiSettings.providerName) (\(store.aiSettings.modelName))", en: "Cloud AI ready: \(store.aiSettings.providerName) (\(store.aiSettings.modelName))", language: store.language)
                        : AppLocalizer.t(zh: "离线智能大白话引擎已就绪（也可在设置中填入 API Key）", en: "Offline Plain Words parser active (add API Key in Settings anytime)", language: store.language)
                )
                .font(.caption)
                .foregroundStyle(PickPlanPalette.muted)
            }
            Spacer()
        }
        .padding(14)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptySamplesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalizer.t(zh: "点按示例快速试试：", en: "Tap an example to try:", language: store.language))
                .font(.caption.bold())
                .foregroundStyle(PickPlanPalette.muted)
            ForEach(Array(samplePrompts.enumerated()), id: \.offset) { _, sample in
                let text = store.language == .zh ? sample.textZh : sample.textEn
                Button {
                    inputText = text
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.language == .zh ? sample.labelZh : sample.labelEn)
                            .font(.caption2.bold())
                            .foregroundStyle(PickPlanPalette.muted)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .pickPlanGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chatBubble(_ entry: ChatHistoryEntry) -> some View {
        VStack(alignment: entry.isUser ? .trailing : .leading, spacing: 10) {
            Text(entry.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(entry.isUser ? Color.white.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !entry.isUser && !entry.parsedTodos.isEmpty {
                VStack(spacing: 8) {
                    ForEach(entry.parsedTodos) { todo in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .font(.subheadline.bold())
                                HStack(spacing: 8) {
                                    if let rem = todo.reminderTime {
                                        Label(PickPlanDateCodec.formatDisplayDateTime(rem), systemImage: "bell")
                                            .font(.caption2)
                                            .foregroundStyle(PickPlanPalette.muted)
                                    }
                                    if let dl = todo.deadline {
                                        Label(PickPlanDateCodec.formatDisplayDateTime(dl), systemImage: "flag")
                                            .font(.caption2)
                                            .foregroundStyle(PickPlanPalette.deadlineCoral)
                                    }
                                }
                            }
                            Spacer()
                            if entry.isAdded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(PickPlanPalette.successMint)
                            }
                        }
                        .padding(12)
                        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !entry.isAdded {
                        Button {
                            HapticsBridge.success(store.preferences.hapticsEnabled)
                            Task { await store.addParsedTodosFromChat(messageId: entry.id) }
                        } label: {
                            Label(
                                AppLocalizer.t(zh: "全部加入计划 (\(entry.parsedTodos.count))", en: "Add All to Plan (\(entry.parsedTodos.count))", language: store.language),
                                systemImage: "checklist.checked"
                            )
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white, in: Capsule())
                            .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isUser ? .trailing : .leading)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                AppLocalizer.t(zh: "描述你想做的事情…", en: "Describe your plans in plain words…", language: store.language),
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !store.isLoadingAI else { return }
                inputText = ""
                HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                Task { await store.sendChatPrompt(text, preferAI: true) }
            } label: {
                Group {
                    if store.isLoadingAI {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoadingAI)
        }
    }
}
