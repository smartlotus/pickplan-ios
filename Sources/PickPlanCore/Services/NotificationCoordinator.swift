import Foundation
#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

#if canImport(UserNotifications)
private final class PickPlanForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
#endif

/// Safe wrapper over `UNUserNotificationCenter` that short-circuits cleanly
/// when running inside an unbundled SwiftPM test host (`Bundle.main.bundleIdentifier == nil`).
/// Schedules both reminder and deadline local notifications for each task, matching Android Pickplan.
public final class NotificationCoordinator: @unchecked Sendable {
    public static let identifierPrefix = "pickplan.todo."

    #if canImport(UserNotifications)
    private let foregroundDelegate = PickPlanForegroundNotificationDelegate()
    #endif

    public init() {}

    /// Installs foreground presentation delegate so reminders and test notifications appear as banners while open.
    public func installForegroundDelegate() {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = foregroundDelegate
        #endif
    }

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
        installForegroundDelegate()
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

    /// Sends an instant local test notification (1 second trigger) matching Android's notification test button.
    @discardableResult
    public func sendInstantTestNotification(language: AppLanguage = .zh) async -> Bool {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return false
        }
        let granted = await requestAuthorization()
        guard granted else { return false }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = AppLocalizer.t(zh: "Pickplan 通知测试", en: "Pickplan notification test", language: language)
        content.body = AppLocalizer.t(
            zh: "看到这条消息就说明 iOS 通知正常。",
            en: "If you can see this, iOS notification is working.",
            language: language
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.8, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)test.instant",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Reconciles pending PickPlan local notifications (both reminderTime and deadline) against current todos.
    public func syncReminders(for todos: [TodoItem], language: AppLanguage = .zh) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        installForegroundDelegate()
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let staleIds = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !$0.hasSuffix("test.instant") }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        let now = Date()
        var pendingEvents: [(identifier: String, title: String, body: String, fireDate: Date)] = []

        for todo in todos where !todo.isCompleted {
            if let reminder = todo.reminderTime, reminder > now {
                pendingEvents.append((
                    identifier: "\(Self.identifierPrefix)\(todo.id).reminder",
                    title: AppLocalizer.t(zh: "提醒: \(todo.title)", en: "Reminder: \(todo.title)", language: language),
                    body: AppLocalizer.t(zh: "提醒时间到了。", en: "Your reminder time has arrived.", language: language),
                    fireDate: reminder
                ))
            }
            if let deadline = todo.deadline, deadline > now {
                pendingEvents.append((
                    identifier: "\(Self.identifierPrefix)\(todo.id).deadline",
                    title: AppLocalizer.t(zh: "截止: \(todo.title)", en: "Deadline: \(todo.title)", language: language),
                    body: AppLocalizer.t(zh: "该任务已到达截止时间。", en: "This task has reached its deadline.", language: language),
                    fireDate: deadline
                ))
            }
        }

        pendingEvents.sort { $0.fireDate < $1.fireDate }
        for event in pendingEvents.prefix(60) {
            await scheduleNotification(
                identifier: event.identifier,
                title: event.title,
                body: event.body,
                fireDate: event.fireDate,
                center: center
            )
        }
        #endif
    }

    public func scheduleReminder(for todo: TodoItem, language: AppLanguage = .zh) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        installForegroundDelegate()
        let center = UNUserNotificationCenter.current()
        let remId = "\(Self.identifierPrefix)\(todo.id).reminder"
        let dlId = "\(Self.identifierPrefix)\(todo.id).deadline"
        center.removePendingNotificationRequests(withIdentifiers: [remId, dlId, "\(Self.identifierPrefix)\(todo.id)"])

        guard !todo.isCompleted else { return }
        let now = Date()

        if let fireDate = todo.reminderTime, fireDate > now {
            await scheduleNotification(
                identifier: remId,
                title: AppLocalizer.t(zh: "提醒: \(todo.title)", en: "Reminder: \(todo.title)", language: language),
                body: AppLocalizer.t(zh: "提醒时间到了。", en: "Your reminder time has arrived.", language: language),
                fireDate: fireDate,
                center: center
            )
        }
        if let deadlineDate = todo.deadline, deadlineDate > now {
            await scheduleNotification(
                identifier: dlId,
                title: AppLocalizer.t(zh: "截止: \(todo.title)", en: "Deadline: \(todo.title)", language: language),
                body: AppLocalizer.t(zh: "该任务已到达截止时间。", en: "This task has reached its deadline.", language: language),
                fireDate: deadlineDate,
                center: center
            )
        }
        #endif
    }

    public func cancelReminder(forTodoId id: String) async {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(Self.identifierPrefix)\(id)",
            "\(Self.identifierPrefix)\(id).reminder",
            "\(Self.identifierPrefix)\(id).deadline"
        ])
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
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
    #endif
}
