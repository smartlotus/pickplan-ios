import SwiftUI
import PickPlanCore

/// Manual planning stream with 6 smart time sections, search, tag pills, swipe actions, and quick input.
public struct ManualPlanView: View {
    @ObservedObject private var store: PlanStore
    @Binding private var searchQuery: String
    @Binding private var tagFilter: TodoTag?
    @Binding private var sectionFilter: TimeSectionKind?
    @Binding private var selectedTodoId: String?

    private let onEditTodo: (TodoItem) -> Void
    private let onStartFocus: (TodoItem) -> Void

    @State private var quickText: String = ""

    public init(
        store: PlanStore,
        searchQuery: Binding<String>,
        tagFilter: Binding<TodoTag?>,
        sectionFilter: Binding<TimeSectionKind?>,
        selectedTodoId: Binding<String?>,
        onEditTodo: @escaping (TodoItem) -> Void,
        onStartFocus: @escaping (TodoItem) -> Void
    ) {
        self.store = store
        self._searchQuery = searchQuery
        self._tagFilter = tagFilter
        self._sectionFilter = sectionFilter
        self._selectedTodoId = selectedTodoId
        self.onEditTodo = onEditTodo
        self.onStartFocus = onStartFocus
    }

    public var body: some View {
        let sections = store.sections(
            query: searchQuery,
            tag: tagFilter,
            sectionFilter: sectionFilter
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerQuickAddBar
                tagFilterBar

                if sections.isEmpty {
                    emptyStateCard
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: section.kind.symbolName)
                                    .foregroundStyle(section.kind == .overdue ? PickPlanPalette.deadlineCoral : PickPlanPalette.muted)
                                Text(section.kind.title(language: store.language))
                                    .font(.caption.bold())
                                    .foregroundStyle(PickPlanPalette.muted)
                                Text("\(section.todos.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(PickPlanPalette.subtle)
                                Spacer()
                            }
                            .padding(.horizontal, 4)

                            ForEach(section.todos) { todo in
                                todoRow(todo)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .searchable(
            text: $searchQuery,
            prompt: AppLocalizer.t(zh: "搜索任务、备注或子任务…", en: "Search tasks, notes, or subtasks…", language: store.language)
        )
        .navigationTitle("Pickplan")
        .refreshable {
            await store.reload()
        }
    }

    private var headerQuickAddBar: some View {
        HStack(spacing: 10) {
            TextField(
                AppLocalizer.t(zh: "快捷录入：明天下午3点开会…", en: "Quick add: Call client tomorrow 3 PM…", language: store.language),
                text: $quickText
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pickPlanGlass(in: Capsule(), interactive: true)
            .onSubmit(submitQuickParse)

            Button(action: submitQuickParse) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagPill(
                    title: AppLocalizer.t(zh: "全部", en: "All", language: store.language),
                    selected: tagFilter == nil && sectionFilter == nil
                ) {
                    withAnimation(PickPlanPalette.quickSpring) {
                        tagFilter = nil
                        sectionFilter = nil
                    }
                }

                ForEach(TodoTag.allCases.filter { $0 != .none }) { tag in
                    tagPill(
                        title: tag.displayName(language: store.language),
                        selected: tagFilter == tag
                    ) {
                        withAnimation(PickPlanPalette.quickSpring) {
                            tagFilter = tagFilter == tag ? nil : tag
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tagPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? .black : .white)
                .background {
                    if selected {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(Color.clear).pickPlanGlass(in: Capsule(), interactive: true)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                Task { await store.toggleCompletion(id: todo.id) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 21))
                    .foregroundStyle(todo.isCompleted ? .white : PickPlanPalette.muted)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? PickPlanPalette.muted : .white)

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.caption)
                        .foregroundStyle(PickPlanPalette.muted)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let reminder = todo.reminderTime {
                        Label(PickPlanDateCodec.formatDisplayDateTime(reminder), systemImage: "bell.fill")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    if let deadline = todo.deadline {
                        Label(PickPlanDateCodec.formatDisplayDateTime(deadline), systemImage: "flag.fill")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PickPlanPalette.deadlineCoral)
                    }
                    if todo.tag != .none {
                        Text(todo.tag.displayName(language: store.language))
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    if !todo.subtasks.isEmpty {
                        let done = todo.subtasks.filter(\.isCompleted).count
                        Label("\(done)/\(todo.subtasks.count)", systemImage: "checklist")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PickPlanPalette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTodoId = todo.id
                onEditTodo(todo)
            }

            Menu {
                Button {
                    onEditTodo(todo)
                } label: {
                    Label(AppLocalizer.t(zh: "编辑", en: "Edit", language: store.language), systemImage: "pencil")
                }
                Button {
                    onStartFocus(todo)
                } label: {
                    Label(AppLocalizer.t(zh: "开启 25 分钟专注", en: "Focus 25 min", language: store.language), systemImage: "timer")
                }
                Divider()
                Button(role: .destructive) {
                    HapticsBridge.impact(store.preferences.hapticsEnabled, style: 1)
                    Task { await store.deleteTodo(id: todo.id) }
                } label: {
                    Label(AppLocalizer.t(zh: "删除", en: "Delete", language: store.language), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(PickPlanPalette.muted)
                    .padding(6)
            }
        }
        .padding(14)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if selectedTodoId == todo.id {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.4)
            }
        }
        .contextMenu {
            Button(AppLocalizer.t(zh: "编辑任务", en: "Edit", language: store.language)) {
                onEditTodo(todo)
            }
            Button(AppLocalizer.t(zh: "开始专注", en: "Start Focus", language: store.language)) {
                onStartFocus(todo)
            }
            Button(AppLocalizer.t(zh: "删除", en: "Delete", language: store.language), role: .destructive) {
                Task { await store.deleteTodo(id: todo.id) }
            }
        }
        .animation(PickPlanPalette.springAnimation, value: todo.isCompleted)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(PickPlanPalette.muted)
            Text(AppLocalizer.t(zh: "还没有待办任务", en: "No tasks yet", language: store.language))
                .font(.headline)
            Text(AppLocalizer.t(zh: "点击右下角 ＋ 写下下一件事，或在顶部用大白话快速拆解。", en: "Tap + to add a task, or describe your plan above in plain words.", language: store.language))
                .font(.caption)
                .foregroundStyle(PickPlanPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func submitQuickParse() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quickText = ""
        HapticsBridge.success(store.preferences.hapticsEnabled)
        Task { await store.quickParseAndAdd(text) }
    }
}
