import Foundation

/// Quick-pick scheduling presets for task creation and rescheduling sheets.
public enum QuickTimePreset: String, CaseIterable, Identifiable, Sendable {
    case tonight
    case tomorrowMorning
    case tomorrowAfternoon
    case nextMondayMorning
    case inOneHour

    public var id: String { rawValue }

    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .inOneHour:
            return AppLocalizer.t(zh: "1 小时后", en: "+1h", language: language)
        case .tonight:
            return AppLocalizer.t(zh: "今晚", en: "Tonight", language: language)
        case .tomorrowMorning:
            return AppLocalizer.t(zh: "明早", en: "Tomorrow AM", language: language)
        case .tomorrowAfternoon:
            return AppLocalizer.t(zh: "明天下午", en: "Tomorrow PM", language: language)
        case .nextMondayMorning:
            return AppLocalizer.t(zh: "下周一", en: "Next Mon", language: language)
        }
    }

    public var symbolName: String {
        switch self {
        case .inOneHour: return "clock.arrow.circlepath"
        case .tonight: return "moon.stars.fill"
        case .tomorrowMorning: return "sunrise.fill"
        case .tomorrowAfternoon: return "sun.max.fill"
        case .nextMondayMorning: return "calendar.badge.clock"
        }
    }

    /// Computes the concrete future `Date` relative to `now` in `calendar`.
    public func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        SmartSectionEngine.presetDate(for: self, now: now, calendar: calendar)
    }
}

/// Pure domain engine for sorting, sectioning, filtering, and quick-scheduling todos.
public enum SmartSectionEngine {
    /// Sorts todos:
    /// - Incomplete before completed
    /// - Timed (`reminderTime ?? deadline`) before untimed
    /// - Timed incomplete sorted by earliest target time, then higher priority, then newest `createdAt`
    /// - Untimed incomplete sorted by higher priority, then newest `createdAt`
    /// - Completed sorted by `completedAt ?? updatedAt` descending
    public static func sortTodos(_ todos: [TodoItem]) -> [TodoItem] {
        todos.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }

            if lhs.isCompleted {
                let lhsDone = lhs.completedAt ?? lhs.updatedAt
                let rhsDone = rhs.completedAt ?? rhs.updatedAt
                if lhsDone != rhsDone {
                    return lhsDone > rhsDone
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id < rhs.id
            }

            let lhsTime = lhs.effectiveScheduleDate
            let rhsTime = rhs.effectiveScheduleDate

            switch (lhsTime, rhsTime) {
            case let (lTime?, rTime?):
                if lTime != rTime {
                    return lTime < rTime
                }
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    /// Determines which `TimeSectionKind` bucket a single todo belongs to.
    public static func sectionKind(
        for todo: TodoItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimeSectionKind {
        if todo.isCompleted {
            return .completed
        }
        guard let targetDate = todo.effectiveScheduleDate else {
            return .unscheduled
        }
        if targetDate < now {
            return .overdue
        }

        let startOfToday = calendar.startOfDay(for: now)
        if let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
           targetDate < startOfTomorrow {
            return .today
        }
        if let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
           targetDate < startOfDayAfterTomorrow {
            return .tomorrow
        }
        return .later
    }

    /// Groups todos into ordered, non-empty `TodoSection`s.
    public static func groupIntoSections(
        _ todos: [TodoItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoSection] {
        var buckets: [TimeSectionKind: [TodoItem]] = [:]
        for todo in todos {
            let kind = sectionKind(for: todo, now: now, calendar: calendar)
            buckets[kind, default: []].append(todo)
        }

        return TimeSectionKind.allCases.compactMap { kind in
            guard let items = buckets[kind], !items.isEmpty else { return nil }
            return TodoSection(kind: kind, todos: sortTodos(items))
        }
    }

    /// Filters todos by search query, optional tag, and optional section kind, returning sorted results.
    public static func filterTodos(
        _ todos: [TodoItem],
        query: String,
        tag: TodoTag?,
        sectionFilter: TimeSectionKind?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = todos.filter { todo in
            if let tag, todo.tag != tag {
                return false
            }
            if let sectionFilter, sectionKind(for: todo, now: now, calendar: calendar) != sectionFilter {
                return false
            }
            if !trimmedQuery.isEmpty {
                let matchesTitle = todo.title.lowercased().contains(trimmedQuery)
                let matchesNotes = todo.notes.lowercased().contains(trimmedQuery)
                let matchesSubtasks = todo.subtasks.contains { $0.title.lowercased().contains(trimmedQuery) }
                if !matchesTitle && !matchesNotes && !matchesSubtasks {
                    return false
                }
            }
            return true
        }

        return sortTodos(filtered)
    }

    /// Resolves a `QuickTimePreset` into a concrete `Date`.
    public static func presetDate(
        for preset: QuickTimePreset,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let startOfToday = calendar.startOfDay(for: now)

        switch preset {
        case .inOneHour:
            return calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)

        case .tonight:
            let tonightEight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: startOfToday)
                ?? now.addingTimeInterval(3600)
            if tonightEight > now {
                return tonightEight
            }
            if let endOfToday = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: startOfToday),
               now < endOfToday {
                let plusOne = now.addingTimeInterval(3600)
                return min(plusOne, endOfToday)
            }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        case .tomorrowAfternoon:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        case .nextMondayMorning:
            let weekday = calendar.component(.weekday, from: now) // Sun=1, Mon=2, ..., Sat=7
            let isoWeekday = ((weekday + 5) % 7) + 1 // Mon=1, ..., Sun=7
            let daysUntilNextMonday = 8 - isoWeekday
            let nextMonday = calendar.date(byAdding: .day, value: daysUntilNextMonday, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonday) ?? nextMonday
        }
    }
}
