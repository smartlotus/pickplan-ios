import SwiftUI
import PickPlanCore

/// Sheet for creating or editing a `TodoItem` with quick-time chips, subtasks, tags, and priority.
public struct TodoEditorSheet: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss

    private let initialTodo: TodoItem?

    @State private var title: String
    @State private var notes: String
    @State private var tag: TodoTag
    @State private var priority: TodoPriority
    @State private var hasReminder: Bool
    @State private var reminderTime: Date
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var subtasks: [SubtaskItem]
    @State private var newSubtaskTitle: String = ""

    public init(store: PlanStore, initialTodo: TodoItem?) {
        self.store = store
        self.initialTodo = initialTodo
        _title = State(initialValue: initialTodo?.title ?? "")
        _notes = State(initialValue: initialTodo?.notes ?? "")
        _tag = State(initialValue: initialTodo?.tag ?? .none)
        _priority = State(initialValue: initialTodo?.priority ?? .normal)
        _hasReminder = State(initialValue: initialTodo?.reminderTime != nil)
        _reminderTime = State(initialValue: initialTodo?.reminderTime ?? QuickTimePreset.inOneHour.date())
        _hasDeadline = State(initialValue: initialTodo?.deadline != nil)
        _deadline = State(initialValue: initialTodo?.deadline ?? QuickTimePreset.tomorrowAfternoon.date())
        _subtasks = State(initialValue: initialTodo?.subtasks ?? [])
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalizer.t(zh: "任务详情", en: "Task Details", language: store.language)) {
                    TextField(
                        AppLocalizer.t(zh: "输入任务标题…", en: "Task title…", language: store.language),
                        text: $title
                    )
                    TextField(
                        AppLocalizer.t(zh: "备注（可选）", en: "Notes (optional)", language: store.language),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section(AppLocalizer.t(zh: "快捷设定提醒时间", en: "Quick Reminder Presets", language: store.language)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QuickTimePreset.allCases) { preset in
                                Button {
                                    hasReminder = true
                                    reminderTime = preset.date()
                                    HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                                } label: {
                                    Label(preset.displayName(language: store.language), systemImage: preset.symbolName)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .pickPlanGlass(in: Capsule(), interactive: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(AppLocalizer.t(zh: "提醒与截止时间", en: "Schedule", language: store.language)) {
                    Toggle(AppLocalizer.t(zh: "开启提醒", en: "Reminder", language: store.language), isOn: $hasReminder)
                    if hasReminder {
                        DatePicker(
                            AppLocalizer.t(zh: "提醒时间", en: "Remind At", language: store.language),
                            selection: $reminderTime,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle(AppLocalizer.t(zh: "设置截止时间", en: "Deadline", language: store.language), isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            AppLocalizer.t(zh: "截止时间", en: "Due At", language: store.language),
                            selection: $deadline,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                Section(AppLocalizer.t(zh: "分类与优先级", en: "Tag & Priority", language: store.language)) {
                    Picker(AppLocalizer.t(zh: "标签", en: "Tag", language: store.language), selection: $tag) {
                        ForEach(TodoTag.allCases) { item in
                            Label(item.displayName(language: store.language), systemImage: item.symbolName).tag(item)
                        }
                    }
                    Picker(AppLocalizer.t(zh: "优先级", en: "Priority", language: store.language), selection: $priority) {
                        ForEach(TodoPriority.allCases) { level in
                            Text(level.displayName(language: store.language)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(AppLocalizer.t(zh: "子任务清单", en: "Subtasks", language: store.language)) {
                    ForEach($subtasks) { $sub in
                        HStack {
                            Button {
                                sub.isCompleted.toggle()
                            } label: {
                                Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)
                            TextField("", text: $sub.title)
                        }
                    }
                    .onDelete { offsets in
                        subtasks.remove(atOffsets: offsets)
                    }

                    HStack {
                        TextField(
                            AppLocalizer.t(zh: "添加一步子任务…", en: "Add subtask step…", language: store.language),
                            text: $newSubtaskTitle
                        )
                        .onSubmit(appendSubtask)
                        Button(AppLocalizer.t(zh: "添加", en: "Add", language: store.language), action: appendSubtask)
                            .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(
                initialTodo == nil
                    ? AppLocalizer.t(zh: "新建任务", en: "New Task", language: store.language)
                    : AppLocalizer.t(zh: "编辑任务", en: "Edit Task", language: store.language)
            )
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
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func appendSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtasks.append(SubtaskItem(title: trimmed))
        newSubtaskTitle = ""
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticsBridge.success(store.preferences.hapticsEnabled)

        Task {
            if var existing = initialTodo {
                existing.title = trimmed
                existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.tag = tag
                existing.priority = priority
                existing.reminderTime = hasReminder ? reminderTime : nil
                existing.deadline = hasDeadline ? deadline : nil
                existing.subtasks = subtasks
                await store.updateTodo(existing)
            } else {
                await store.addTodo(
                    title: trimmed,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    subtasks: subtasks,
                    tag: tag,
                    priority: priority,
                    reminderTime: hasReminder ? reminderTime : nil,
                    deadline: hasDeadline ? deadline : nil
                )
            }
            dismiss()
        }
    }
}
