import SwiftUI
import PickPlanCore

/// Faithful Liquid Glass port of Android Pickplan's `AIModeView`:
/// - Empty prompt: `试试：明天上午买菜，下午三点开会，周五前交报告。`
/// - Multi-task draft cards with per-draft `编辑` (`确认任务` sheet) + `加入` buttons,
///   plus full-width `全部加入计划` (`Add All`) and green `✓ 已加入计划` badge.
/// - Supports both BYOK Cloud AI and built-in offline bilingual `PlainWordsParser`.
public struct AIPlanBuilderView: View {
    @ObservedObject private var store: PlanStore
    private let onOpenSettings: () -> Void

    @State private var inputText: String = ""
    @State private var preferCloudAI: Bool = true
    @State private var editingDraftContext: DraftEditContext? = nil

    private struct DraftEditContext: Identifiable {
        let messageId: String
        let todo: TodoItem
        var id: String { "\(messageId)-\(todo.id)" }
    }

    public init(store: PlanStore, onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.onOpenSettings = onOpenSettings
    }

    private var hasConfiguredKey: Bool {
        let key = (store.aiSettings.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isCustom = store.aiSettings.providerName.caseInsensitiveCompare("Custom") == .orderedSame
            && !store.aiSettings.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.aiSettings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !key.isEmpty || isCustom
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        engineStatusPill

                        if store.chatHistory.isEmpty {
                            emptyPromptView
                        } else {
                            ForEach(store.chatHistory) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(14)
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
                .padding(.horizontal, 12)
                .padding(.bottom, 86)
        }
        .navigationTitle(AppLocalizer.t(zh: "AI 整理计划", en: "AI Plan Builder", language: store.language))
        .sheet(item: $editingDraftContext) { ctx in
            DraftConfirmEditorSheet(
                store: store,
                todo: ctx.todo,
                onSaveDraft: { updated in
                    Task {
                        await store.updateParsedTodoInChat(messageId: ctx.messageId, updatedTodo: updated)
                    }
                }
            )
        }
    }

    private var engineStatusPill: some View {
        HStack(spacing: 10) {
            Image(systemName: hasConfiguredKey && preferCloudAI ? "sparkles" : "cpu")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    hasConfiguredKey && preferCloudAI
                        ? "\(store.aiSettings.providerName) · \(store.aiSettings.modelName)"
                        : AppLocalizer.t(zh: "本机离线大白话解析引擎", en: "On-Device Plain Words Parser", language: store.language)
                )
                .font(.caption.bold())
                Text(
                    hasConfiguredKey
                        ? AppLocalizer.t(zh: "先整理成草稿，可逐条编辑或确认加入", en: "Parses into drafts — edit or confirm before adding", language: store.language)
                        : AppLocalizer.t(zh: "无需 API Key 即可离线拆分多任务；点击右侧可配置云端 AI", en: "Works offline without API Key; tap Settings for Cloud AI", language: store.language)
                )
                .font(.caption2)
                .foregroundStyle(PickPlanPalette.muted)
            }
            Spacer()
            if hasConfiguredKey {
                Button {
                    preferCloudAI.toggle()
                } label: {
                    Text(preferCloudAI
                         ? AppLocalizer.t(zh: "云端", en: "Cloud", language: store.language)
                         : AppLocalizer.t(zh: "离线", en: "Offline", language: store.language))
                        .font(.caption2.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .pickPlanGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            } else {
                Button(AppLocalizer.t(zh: "配置 Key", en: "API Key", language: store.language)) {
                    onOpenSettings()
                }
                .font(.caption2.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .pickPlanGlass(in: Capsule(), interactive: true)
            }
        }
        .padding(12)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyPromptView: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 52)
            Text(
                AppLocalizer.t(
                    zh: "试试：明天上午买菜，下午三点开会，周五前交报告。",
                    en: "Try: Buy groceries tomorrow morning, meet at 3 PM, submit report by Friday.",
                    language: store.language
                )
            )
            .font(.subheadline)
            .foregroundStyle(Color.gray.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineSpacing(5)

            HStack(spacing: 8) {
                sampleChip(
                    label: AppLocalizer.t(zh: "工作", en: "Work", language: store.language),
                    prompt: AppLocalizer.t(zh: "明天上午买菜，下午三点开会，周五前交报告。", en: "Buy groceries tomorrow morning, meet at 3 PM, submit report by Friday.", language: store.language)
                )
                sampleChip(
                    label: AppLocalizer.t(zh: "生活", en: "Life", language: store.language),
                    prompt: AppLocalizer.t(zh: "今晚八点取快递，明早九点去体检。", en: "Pick up parcel tonight 8 PM, health check tomorrow 9 AM.", language: store.language)
                )
                sampleChip(
                    label: AppLocalizer.t(zh: "学习", en: "Study", language: store.language),
                    prompt: AppLocalizer.t(zh: "下周一上午九点交实验报告。", en: "Submit lab report next Monday 9 AM.", language: store.language)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func sampleChip(label: String, prompt: String) -> some View {
        Button {
            inputText = prompt
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .pickPlanGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(PickPlanPressScaleStyle())
    }

    private func chatBubble(_ entry: ChatHistoryEntry) -> some View {
        VStack(alignment: entry.isUser ? .trailing : .leading, spacing: 10) {
            Text(entry.text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    entry.isUser ? Color.white.opacity(0.20) : Color(red: 0.118, green: 0.118, blue: 0.118).opacity(0.86),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(entry.isUser ? Color.white : Color.white.opacity(0.42), lineWidth: 1)
                )

            if !entry.isUser && !entry.parsedTodos.isEmpty && !entry.isAdded {
                VStack(spacing: 8) {
                    ForEach(entry.parsedTodos) { todo in
                        parsedTodoCard(messageId: entry.id, todo: todo)
                    }

                    Button {
                        HapticsBridge.success(store.preferences.hapticsEnabled)
                        Task { await store.addParsedTodosFromChat(messageId: entry.id) }
                    } label: {
                        Label(
                            AppLocalizer.t(zh: "全部加入计划", en: "Add All", language: store.language),
                            systemImage: "checklist.checked"
                        )
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(PickPlanPressScaleStyle())
                }
            }

            if !entry.isUser && entry.isAdded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(AppLocalizer.t(zh: "已加入计划", en: "Added to plan", language: store.language))
                        .font(.caption.bold())
                }
                .foregroundStyle(PickPlanPalette.successMint)
                .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isUser ? .trailing : .leading)
    }

    /// Faithful port of Android `_ParsedTodoCard`: title + reminder/deadline + `编辑` + `加入`.
    private func parsedTodoCard(messageId: String, todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(todo.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            if let rem = todo.reminderTime {
                Text("\(AppLocalizer.t(zh: "提醒", en: "Reminder", language: store.language)): \(PickPlanDateCodec.formatDisplayDateTime(rem))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.76))
            }
            if let dl = todo.deadline {
                Text("\(AppLocalizer.t(zh: "截止", en: "Deadline", language: store.language)): \(PickPlanDateCodec.formatDisplayDateTime(dl))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PickPlanPalette.deadlineCoral)
            }

            HStack {
                Spacer()
                Button {
                    editingDraftContext = DraftEditContext(messageId: messageId, todo: todo)
                } label: {
                    Label(AppLocalizer.t(zh: "编辑", en: "Edit", language: store.language), systemImage: "pencil")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .pickPlanGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PickPlanPressScaleStyle())

                Button {
                    HapticsBridge.success(store.preferences.hapticsEnabled)
                    Task { await store.addSingleParsedTodoFromChat(messageId: messageId, todoId: todo.id) }
                } label: {
                    Label(AppLocalizer.t(zh: "加入", en: "Add", language: store.language), systemImage: "plus")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PickPlanPressScaleStyle())
            }
        }
        .padding(12)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                AppLocalizer.t(zh: "用大白话说出你的安排...", en: "Describe your plan in plain words...", language: store.language),
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
                Task { await store.sendChatPrompt(text, preferAI: preferCloudAI) }
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
            .buttonStyle(PickPlanPressScaleStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoadingAI)
        }
    }
}

/// Faithful port of Android `_ParsedTodoEditor` (`确认任务` / `Confirm Task` -> `保存草稿` / `Save Draft`).
private struct DraftConfirmEditorSheet: View {
    @ObservedObject var store: PlanStore
    let todo: TodoItem
    let onSaveDraft: (TodoItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var reminderTime: Date?
    @State private var deadline: Date?
    @State private var showReminderPicker = false
    @State private var showDeadlinePicker = false

    init(store: PlanStore, todo: TodoItem, onSaveDraft: @escaping (TodoItem) -> Void) {
        self.store = store
        self.todo = todo
        self.onSaveDraft = onSaveDraft
        _title = State(initialValue: todo.title)
        _reminderTime = State(initialValue: todo.reminderTime)
        _deadline = State(initialValue: todo.deadline)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(
                        AppLocalizer.t(zh: "任务标题", en: "Task title", language: store.language),
                        text: $title
                    )
                    .padding(14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 10) {
                        draftTimeRow(
                            label: AppLocalizer.t(zh: "提醒", en: "Reminder", language: store.language),
                            value: reminderTime,
                            onToggle: {
                                if reminderTime == nil { reminderTime = QuickTimePreset.inOneHour.date() }
                                showReminderPicker.toggle()
                            },
                            onClear: {
                                reminderTime = nil
                                showReminderPicker = false
                            }
                        )
                        if showReminderPicker, let b = optBinding($reminderTime) {
                            DatePicker("", selection: b, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                        }
                        Divider().overlay(Color.white.opacity(0.14))
                        draftTimeRow(
                            label: AppLocalizer.t(zh: "截止", en: "Deadline", language: store.language),
                            value: deadline,
                            onToggle: {
                                if deadline == nil { deadline = QuickTimePreset.tomorrowAfternoon.date() }
                                showDeadlinePicker.toggle()
                            },
                            onClear: {
                                deadline = nil
                                showDeadlinePicker = false
                            }
                        )
                        if showDeadlinePicker, let b = optBinding($deadline) {
                            DatePicker("", selection: b, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                        }
                    }
                    .padding(14)
                    .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        var updated = todo
                        updated.title = clean
                        updated.reminderTime = reminderTime
                        updated.deadline = deadline
                        onSaveDraft(updated)
                        dismiss()
                    } label: {
                        Text(AppLocalizer.t(zh: "保存草稿", en: "Save Draft", language: store.language))
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(PickPlanPressScaleStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .background(AmbientMonochromeCanvas())
            .navigationTitle(AppLocalizer.t(zh: "确认任务", en: "Confirm Task", language: store.language))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.t(zh: "取消", en: "Cancel", language: store.language)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func draftTimeRow(label: String, value: Date?, onToggle: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        HStack {
            Text("\(label): \(value.map { PickPlanDateCodec.formatDisplayDateTime($0) } ?? AppLocalizer.t(zh: "未设置", en: "Not set", language: store.language))")
                .font(.subheadline)
            Spacer()
            Button(action: onToggle) { Image(systemName: "calendar").padding(6) }.buttonStyle(.plain)
            Button(action: onClear) { Image(systemName: "xmark").padding(6) }.buttonStyle(.plain).disabled(value == nil)
        }
    }

    private func optBinding(_ src: Binding<Date?>) -> Binding<Date>? {
        guard src.wrappedValue != nil else { return nil }
        return Binding(get: { src.wrappedValue ?? Date() }, set: { src.wrappedValue = $0 })
    }
}
