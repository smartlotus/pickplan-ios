import Foundation

/// High-level life/work category tag for a todo item.
public enum TodoTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case work
    case life
    case study
    case idea
    case none

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        let raw = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = TodoTag(rawValue: raw) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Localized label for display in UI or Markdown exports.
    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .work: return AppLocalizer.t(zh: "工作", en: "Work", language: language)
        case .life: return AppLocalizer.t(zh: "生活", en: "Life", language: language)
        case .study: return AppLocalizer.t(zh: "学习", en: "Study", language: language)
        case .idea: return AppLocalizer.t(zh: "灵感", en: "Idea", language: language)
        case .none: return AppLocalizer.t(zh: "无标签", en: "None", language: language)
        }
    }

    /// SF Symbol name representing this tag.
    public var symbolName: String {
        switch self {
        case .work: return "briefcase.fill"
        case .life: return "house.fill"
        case .study: return "book.fill"
        case .idea: return "lightbulb.fill"
        case .none: return "tag"
        }
    }
}

/// Priority level for a todo item.
public enum TodoPriority: String, Codable, CaseIterable, Sendable, Identifiable {
    case low
    case normal
    case high

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .normal
            return
        }
        if let raw = try? container.decode(String.self) {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self = TodoPriority(rawValue: normalized) ?? .normal
            return
        }
        if let numeric = try? container.decode(Int.self) {
            switch numeric {
            case ...0: self = .low
            case 1: self = .normal
            default: self = .high
            }
            return
        }
        self = .normal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Lower rank sorts earlier (high priority first).
    public var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    /// Localized display label.
    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .low: return AppLocalizer.t(zh: "低", en: "Low", language: language)
        case .normal: return AppLocalizer.t(zh: "普通", en: "Normal", language: language)
        case .high: return AppLocalizer.t(zh: "高", en: "High", language: language)
        }
    }
}

/// Checklist sub-item belonging to a `TodoItem`.
public struct SubtaskItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isCompleted: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case isCompletedSnake = "is_completed"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.title = try container.decode(String.self, forKey: .title)
        if let completed = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) {
            self.isCompleted = completed
        } else if let completedSnake = try container.decodeIfPresent(Bool.self, forKey: .isCompletedSnake) {
            self.isCompleted = completedSnake
        } else {
            self.isCompleted = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
}

/// Core task entity compatible with both Android PickPlan v1 JSON and iOS v2 backups.
public struct TodoItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    public var subtasks: [SubtaskItem]
    public var tag: TodoTag
    public var priority: TodoPriority
    public var reminderTime: Date?
    public var deadline: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var isCompleted: Bool
    public var focusMinutesLogged: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        subtasks: [SubtaskItem] = [],
        tag: TodoTag = .none,
        priority: TodoPriority = .normal,
        reminderTime: Date? = nil,
        deadline: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        isCompleted: Bool = false,
        focusMinutesLogged: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.subtasks = subtasks
        self.tag = tag
        self.priority = priority
        self.reminderTime = reminderTime
        self.deadline = deadline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isCompleted = isCompleted
        self.focusMinutesLogged = focusMinutesLogged
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case subtasks
        case tag
        case priority
        case reminderTime = "reminder_time"
        case deadline
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case isCompleted
        case focusMinutesLogged
    }

    private enum LegacyFallbackKeys: String, CodingKey {
        case reminderTimeCamel = "reminderTime"
        case createdAtCamel = "createdAt"
        case updatedAtCamel = "updatedAt"
        case completedAtCamel = "completedAt"
        case isCompletedSnake = "is_completed"
        case focusMinutesSnake = "focus_minutes_logged"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = try decoder.container(keyedBy: LegacyFallbackKeys.self)
        let now = Date()

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.title = try container.decode(String.self, forKey: .title)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.subtasks = try container.decodeIfPresent([SubtaskItem].self, forKey: .subtasks) ?? []
        self.tag = try container.decodeIfPresent(TodoTag.self, forKey: .tag) ?? .none
        self.priority = try container.decodeIfPresent(TodoPriority.self, forKey: .priority) ?? .normal

        if let reminder = try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .reminderTime) {
            self.reminderTime = reminder
        } else {
            self.reminderTime = try PickPlanDateCodec.decodeDateIfPresent(from: fallback, forKey: .reminderTimeCamel)
        }

        self.deadline = try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .deadline)

        let decodedCreatedAt =
            try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .createdAt)
            ?? (try PickPlanDateCodec.decodeDateIfPresent(from: fallback, forKey: .createdAtCamel))
            ?? now
        self.createdAt = decodedCreatedAt

        self.updatedAt =
            try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .updatedAt)
            ?? (try PickPlanDateCodec.decodeDateIfPresent(from: fallback, forKey: .updatedAtCamel))
            ?? decodedCreatedAt

        if let completedDate = try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .completedAt) {
            self.completedAt = completedDate
        } else {
            self.completedAt = try PickPlanDateCodec.decodeDateIfPresent(from: fallback, forKey: .completedAtCamel)
        }

        if let completed = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) {
            self.isCompleted = completed
        } else if let completedSnake = try fallback.decodeIfPresent(Bool.self, forKey: .isCompletedSnake) {
            self.isCompleted = completedSnake
        } else {
            self.isCompleted = false
        }

        if let focus = try container.decodeIfPresent(Int.self, forKey: .focusMinutesLogged) {
            self.focusMinutesLogged = max(0, focus)
        } else if let focusSnake = try fallback.decodeIfPresent(Int.self, forKey: .focusMinutesSnake) {
            self.focusMinutesLogged = max(0, focusSnake)
        } else {
            self.focusMinutesLogged = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encode(tag, forKey: .tag)
        try container.encode(priority, forKey: .priority)
        if let reminderTime {
            try container.encode(PickPlanDateCodec.formatISO8601(reminderTime), forKey: .reminderTime)
        }
        if let deadline {
            try container.encode(PickPlanDateCodec.formatISO8601(deadline), forKey: .deadline)
        }
        try container.encode(PickPlanDateCodec.formatISO8601(createdAt), forKey: .createdAt)
        try container.encode(PickPlanDateCodec.formatISO8601(updatedAt), forKey: .updatedAt)
        if let completedAt {
            try container.encode(PickPlanDateCodec.formatISO8601(completedAt), forKey: .completedAt)
        }
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(focusMinutesLogged, forKey: .focusMinutesLogged)
    }

    /// Primary scheduling timestamp (`reminderTime ?? deadline`).
    public var effectiveScheduleDate: Date? {
        reminderTime ?? deadline
    }
}

/// Smart time-bucket sections for organizing todos.
public enum TimeSectionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case overdue
    case today
    case tomorrow
    case later
    case unscheduled
    case completed

    public var id: String { rawValue }

    /// Localized title for section headers and Markdown exports.
    public func title(language: AppLanguage) -> String {
        switch self {
        case .overdue: return AppLocalizer.t(zh: "已逾期", en: "Overdue", language: language)
        case .today: return AppLocalizer.t(zh: "今天", en: "Today", language: language)
        case .tomorrow: return AppLocalizer.t(zh: "明天", en: "Tomorrow", language: language)
        case .later: return AppLocalizer.t(zh: "之后", en: "Later", language: language)
        case .unscheduled: return AppLocalizer.t(zh: "无时间", en: "No time", language: language)
        case .completed: return AppLocalizer.t(zh: "已完成", en: "Completed", language: language)
        }
    }

    /// SF Symbol name representing this time section.
    public var symbolName: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        case .later: return "calendar"
        case .unscheduled: return "tray.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// Grouped list of todos for a single `TimeSectionKind`.
public struct TodoSection: Identifiable, Equatable, Sendable {
    public let kind: TimeSectionKind
    public let todos: [TodoItem]

    public var id: String { kind.rawValue }

    public init(kind: TimeSectionKind, todos: [TodoItem]) {
        self.kind = kind
        self.todos = todos
    }
}
