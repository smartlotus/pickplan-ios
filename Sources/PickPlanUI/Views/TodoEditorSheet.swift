import SwiftUI
import PickPlanCore

/// Faithful Liquid Glass port of Android Pickplan's `_TodoForm` bottom sheet:
/// - Title (`新建任务` / `编辑任务`)
/// - Required title input (`任务标题（必填）`)
/// - Quick reminder chips (`今晚`, `明早`, `明天下午`, `下周一`, `1 小时后`)
/// - Explicit `提醒: 未设置 / yyyy-MM-dd HH:mm` row with picker toggle & clear button
/// - Explicit `截止: 未设置 / yyyy-MM-dd HH:mm` row with picker toggle & clear button
/// - Collapsible optional extras (`备注 / 标签 / 优先级 / 子任务`)
/// - Full-width primary `添加任务` / `保存修改` button
public struct TodoEditorSheet: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss

    private let initialTodo: TodoItem?

    @State private var title: String
    @State private var notes: String
    @State private var tag: TodoTag
    @State private var priority: TodoPriority
    @State private var reminderTime: Date?
    @State private var deadline: Date?
    @State private var showReminderPicker: Bool = false
    @State private var showDeadlinePicker: Bool = false
    @State private var showAdvancedOptions: Bool = false
    @State private var subtasks: [SubtaskItem]
    @State private var newSubtaskTitle: String = ""

    public init(store: PlanStore, initialTodo: TodoItem?) {
        self.store = store
        self.initialTodo = initialTodo
        _title = State(initialValue: initialTodo?.title ?? "")
        _notes = State(initialValue: initialTodo?.notes ?? "")
        _tag = State(initialValue: initialTodo?.tag ?? .none)
        _priority = State(initialValue: initialTodo?.priority ?? .normal)
        _reminderTime = State(initialValue: initialTodo?.reminderTime)
        _deadline = State(initialValue: initialTodo?.deadline)
        _subtasks = State(initialValue: initialTodo?.subtasks ?? [])
        _showAdvancedOptions = State(initialValue:
            !(initialTodo?.notes.isEmpty ?? true)
            || (initialTodo?.tag ?? .none) != .none
            || (initialTodo?.priority ?? .normal) != .normal
            || !(initialTodo?.subtasks.isEmpty ?? true)
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(
                        AppLocalizer.t(zh: "任务标题（必填）", en: "Task title (required)", language: store.language),
                        text: $title
                    )
                    .font(.body)
                    .padding(14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onSubmit(save)

                    // Quick Chips matching Android `_TodoForm`
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QuickTimePreset.allCases) { preset in
                                Button {
                                    reminderTime = preset.date()
                                    HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                                } label: {
                                    Text(preset.displayName(language: store.language))
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .pickPlanGlass(in: Capsule(), interactive: true)
                                }
                                .buttonStyle(PickPlanPressScaleStyle())
                            }
                        }
                    }

                    // Explicit Reminder & Deadline rows matching Android `_timeRow`
                    VStack(spacing: 10) {
                        timeRow(
                            label: AppLocalizer.t(zh: "提醒", en: "Reminder", language: store.language),
                            value: reminderTime,
                            isPickerOpen: $showReminderPicker,
                            onPickDefault: {
                                if reminderTime == nil { reminderTime = QuickTimePreset.inOneHour.date() }
                                showReminderPicker.toggle()
                            },
                            onClear: {
                                reminderTime = nil
                                showReminderPicker = false
                            }
                        )
                        if showReminderPicker, let binding = optionalDateBinding($reminderTime) {
                            DatePicker(
                                "",
                                selection: binding,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            #if os(iOS)
                            .datePickerStyle(.graphical)
                            #endif
                            .labelsHidden()
                        }

                        Divider().overlay(Color.white.opacity(0.14))

                        timeRow(
                            label: AppLocalizer.t(zh: "截止", en: "Deadline", language: store.language),
                            value: deadline,
                            isPickerOpen: $showDeadlinePicker,
                            onPickDefault: {
                                if deadline == nil { deadline = QuickTimePreset.tomorrowAfternoon.date() }
                                showDeadlinePicker.toggle()
                            },
                            onClear: {
                                deadline = nil
                                showDeadlinePicker = false
                            }
                        )
                        if showDeadlinePicker, let binding = optionalDateBinding($deadline) {
                            DatePicker(
                                "",
                                selection: binding,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            #if os(iOS)
                            .datePickerStyle(.graphical)
                            #endif
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Collapsible iOS enhancements (Notes, Tag, Priority, Subtasks)
                    advancedOptionsSection

                    Button(action: save) {
                        Text(
                            initialTodo == nil
                                ? AppLocalizer.t(zh: "添加任务", en: "Add Task", language: store.language)
                                : AppLocalizer.t(zh: "保存修改", en: "Save Changes", language: store.language)
                        )
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.white.opacity(0.28)
                                : Color.white,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(PickPlanPressScaleStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .background(AmbientMonochromeCanvas())
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
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var advancedOptionsSection: some View {
        DisclosureGroup(
            AppLocalizer.t(zh: "更多选项（备注、标签、优先级、子任务）", en: "More options (Notes, Tag, Priority, Subtasks)", language: store.language),
            isExpanded: $showAdvancedOptions
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    AppLocalizer.t(zh: "备注（可选）", en: "Notes (optional)", language: store.language),
                    text: $notes,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker(AppLocalizer.t(zh: "标签", en: "Tag", language: store.language), selection: $tag) {
                    ForEach(TodoTag.allCases) { item in
                        Text(item.displayName(language: store.language)).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker(AppLocalizer.t(zh: "优先级", en: "Priority", language: store.language), selection: $priority) {
                    ForEach(TodoPriority.allCases) { level in
                        Text(level.displayName(language: store.language)).tag(level)
                    }
                }
                .pickerStyle(.segmented)

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
            .padding(.top, 10)
        }
        .padding(14)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func timeRow(
        label: String,
        value: Date?,
        isPickerOpen: Binding<Bool>,
        onPickDefault: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(
                "\(label): \(value.map { PickPlanDateCodec.formatDisplayDateTime($0) } ?? AppLocalizer.t(zh: "未设置", en: "Not set", language: store.language))"
            )
            .font(.subheadline)
            .foregroundStyle(value == nil ? PickPlanPalette.muted : .white)
            Spacer()
            Button(action: onPickDefault) {
                Image(systemName: "calendar")
                    .padding(6)
            }
            .buttonStyle(.plain)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .padding(6)
                    .foregroundStyle(value == nil ? PickPlanPalette.subtle : .white)
            }
            .buttonStyle(.plain)
            .disabled(value == nil)
        }
    }

    private func optionalDateBinding(_ source: Binding<Date?>) -> Binding<Date>? {
        guard source.wrappedValue != nil else { return nil }
        return Binding(
            get: { source.wrappedValue ?? Date() },
            set: { source.wrappedValue = $0 }
        )
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
                existing.reminderTime = reminderTime
                existing.deadline = deadline
                existing.subtasks = subtasks
                await store.updateTodo(existing)
            } else {
                await store.addTodo(
                    title: trimmed,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    subtasks: subtasks,
                    tag: tag,
                    priority: priority,
                    reminderTime: reminderTime,
                    deadline: deadline
                )
            }
            dismiss()
        }
    }
}
