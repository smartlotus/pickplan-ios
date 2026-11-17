import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Safe wrapper over `UNUserNotificationCenter` that short-circuits cleanly
/// when running inside an unbundled SwiftPM test host (`Bundle.main.bundleIdentifier == nil`).
public final class NotificationCoordinator: Sendable {
    public static let identifierPrefix = "pickplan.todo."

    public init() {}

    /// Returns true only when `UserNotifications` is available and the process has a valid app bundle identifier.
    public var isAvailableInCurrentProcess: Bool {
        #if canImport(UserNotifications)
        return Bundle.main.bundleIdentifier != nil
        #else
        return false
        #endif
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return false
        }
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Reconciles pending PickPlan local notifications against the current todo list.
    public func syncReminders(for todos: [TodoItem], language: AppLanguage = .zh) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let staleIds = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        let now = Date()
        let activeReminders = todos
            .filter { !$0.isCompleted }
            .compactMap { todo -> (TodoItem, Date)? in
                guard let fireDate = todo.reminderTime, fireDate > now else { return nil }
                return (todo, fireDate)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(60) // Stay under iOS 64-notification per-app pending cap

        for (todo, fireDate) in activeReminders {
            await scheduleNotification(todo: todo, fireDate: fireDate, language: language, center: center)
        }
        #endif
    }

    public func scheduleReminder(for todo: TodoItem, language: AppLanguage = .zh) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let identifier = "\(Self.identifierPrefix)\(todo.id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard !todo.isCompleted, let fireDate = todo.reminderTime, fireDate > Date() else {
            return
        }
        await scheduleNotification(todo: todo, fireDate: fireDate, language: language, center: center)
        #endif
    }

    public func cancelReminder(forTodoId id: String) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(Self.identifierPrefix)\(id)"])
        #endif
    }

    public func cancelAllReminders() async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        #endif
    }

    #if canImport(UserNotifications)
    private func scheduleNotification(
        todo: TodoItem,
        fireDate: Date,
        language: AppLanguage,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = AppLocalizer.t(zh: "PickPlan 任务提醒", en: "PickPlan Reminder", language: language)
        content.body = todo.title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)\(todo.id)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
    #endif
}
