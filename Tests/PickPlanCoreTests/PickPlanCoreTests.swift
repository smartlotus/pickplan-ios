import Foundation
import Testing
@testable import PickPlanCore

@Suite("PickPlanCore Suite")
struct PickPlanCoreTests {
    private func withTempVault(_ body: (LocalVaultStore) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickPlanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = LocalVaultStore(baseDirectory: dir)
        try body(vault)
    }

    @MainActor
    private func withTempVaultAsync(_ body: @MainActor (LocalVaultStore) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickPlanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = LocalVaultStore(baseDirectory: dir)
        try await body(vault)
    }

    private func makeReferenceCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        return cal
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 9,
        minute: Int = 0,
        second: Int = 0,
        calendar: Calendar
    ) -> Date {
        let comps = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return calendar.date(from: comps)!
    }

    // MARK: - 1. Android v1 JSON Array Import & Dart Timestamps

    @Test("Android v1 legacy JSON array decodes cleanly with Dart microsecond timestamps")
    func androidV1LegacyArrayDecodingWithDartTimestamps() throws {
        let legacyJSON = """
        [
          {
            "id": "v1-task-1",
            "title": "迁移旧版待办",
            "reminder_time": "2026-09-10T12:30:00.123456",
            "deadline": "2026-09-11T18:00:00",
            "isCompleted": false
          },
          {
            "id": "v1-task-2",
            "title": "已完成旧任务",
            "completed_at": "2026-09-09T08:15:30Z",
            "isCompleted": true
          }
        ]
        """.data(using: .utf8)!

        let inspected = try BackupCodec.decodeAndInspect(legacyJSON)
        #expect(inspected.isLegacyV1 == true)
        #expect(inspected.checksumValid == nil)
        #expect(inspected.envelope.payload.todos.count == 2)

        let first = inspected.envelope.payload.todos[0]
        #expect(first.id == "v1-task-1")
        #expect(first.title == "迁移旧版待办")
        #expect(first.notes == "")
        #expect(first.subtasks.isEmpty)
        #expect(first.tag == .none)
        #expect(first.priority == .normal)
        #expect(first.isCompleted == false)
        #expect(first.focusMinutesLogged == 0)

        let localCal = Calendar.current
        let reminder = try #require(first.reminderTime)
        let rComps = localCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder)
        #expect(rComps.year == 2026)
        #expect(rComps.month == 9)
        #expect(rComps.day == 10)
        #expect(rComps.hour == 12)
        #expect(rComps.minute == 30)
        #expect(rComps.second == 0)

        let deadline = try #require(first.deadline)
        let dComps = localCal.dateComponents([.year, .month, .day, .hour, .minute], from: deadline)
        #expect(dComps.year == 2026)
        #expect(dComps.month == 9)
        #expect(dComps.day == 11)
        #expect(dComps.hour == 18)
        #expect(dComps.minute == 0)

        let second = inspected.envelope.payload.todos[1]
        #expect(second.isCompleted == true)
        #expect(second.completedAt != nil)
    }

    // MARK: - 2. v2 Export -> Import Round-Trip Fidelity & API Key Control

    @Test("v2 Export -> Import preserves tasks, preferences, and API key privacy control")
    func v2ExportImportRoundTripAndApiKeyPrivacyControl() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_795_000_000)

        try withTempVault { storeA in
            let task = TodoItem(
                id: "roundtrip-1",
                title: "Design Liquid Glass Sheet",
                notes: "Verify contrast & accessibility",
                subtasks: [
                    SubtaskItem(id: "sub-1", title: "Header spacing", isCompleted: true),
                    SubtaskItem(id: "sub-2", title: "Blur material", isCompleted: false)
                ],
                tag: .work,
                priority: .high,
                reminderTime: fixedNow.addingTimeInterval(3600),
                deadline: fixedNow.addingTimeInterval(7200),
                createdAt: fixedNow,
                updatedAt: fixedNow,
                completedAt: nil,
                isCompleted: false,
                focusMinutesLogged: 50
            )
            storeA.upsertTodo(task)
            storeA.updateAISettings(AISettingsRecord(
                providerName: "DeepSeek",
                baseUrl: "https://api.deepseek.com/v1",
                modelName: "deepseek-chat",
                apiKey: "sk-super-secret-123"
            ))
            var prefs = storeA.getPreferences()
            prefs.languageCode = "en"
            prefs.hapticsEnabled = false
            prefs.backupPolicy.maxSnapshots = 9
            storeA.updatePreferences(prefs)

            // Default export strips API key
            let redactedArchive = try storeA.exportArchive(exportedAt: fixedNow)
            try withTempVault { storeB in
                let redactedPreview = try storeB.previewImport(data: redactedArchive)
                #expect(redactedPreview.isV1Legacy == false)
                #expect(redactedPreview.checksumValid == true)
                #expect(redactedPreview.includesAISettings == true)
                #expect(redactedPreview.includesApiKey == false)

                _ = try storeB.applyImport(data: redactedArchive, strategy: .replaceAll, now: fixedNow)
                #expect(storeB.getAISettings().apiKey == nil)
                #expect(storeB.getAISettings().modelName == "deepseek-chat")
                #expect(storeB.getPreferences().languageCode == "en")
                #expect(storeB.getPreferences().hapticsEnabled == false)
                #expect(storeB.getPreferences().backupPolicy.maxSnapshots == 9)

                let imported = try #require(storeB.getTodos().first)
                #expect(imported.id == task.id)
                #expect(imported.title == task.title)
                #expect(imported.notes == task.notes)
                #expect(imported.subtasks == task.subtasks)
                #expect(imported.tag == .work)
                #expect(imported.priority == .high)
                #expect(imported.focusMinutesLogged == 50)
                #expect(abs((imported.reminderTime?.timeIntervalSince1970 ?? 0) - (task.reminderTime?.timeIntervalSince1970 ?? -100)) < 1.0)
                #expect(abs((imported.deadline?.timeIntervalSince1970 ?? 0) - (task.deadline?.timeIntervalSince1970 ?? -100)) < 1.0)
            }

            // Explicit opt-in includes API key
            let fullArchive = try storeA.exportArchive(includeApiKey: true, exportedAt: fixedNow)
            try withTempVault { storeC in
                let fullPreview = try storeC.previewImport(data: fullArchive)
                #expect(fullPreview.includesApiKey == true)
                _ = try storeC.applyImport(data: fullArchive, strategy: .replaceAll, now: fixedNow)
                #expect(storeC.getAISettings().apiKey == "sk-super-secret-123")
            }
        }
    }

    // MARK: - 3. SHA256 Checksum Tamper Detection

    @Test("SHA256 checksum detects tampered payload vs valid envelope")
    func checksumDetectsTamperedPayload() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_795_000_000)
        let payload = PickPlanBackupPayload(
            todos: [
                TodoItem(
                    id: "chk-1",
                    title: "Original Title",
                    createdAt: fixedNow,
                    updatedAt: fixedNow
                )
            ]
        )
        let validData = try BackupCodec.encodeEnvelope(payload, exportedAt: fixedNow)
        let validInspect = try BackupCodec.decodeAndInspect(validData)
        #expect(validInspect.checksumValid == true)

        let jsonString = try #require(String(data: validData, encoding: .utf8))
        let tamperedString = jsonString.replacingOccurrences(of: "Original Title", with: "Tampered Title")
        let tamperedData = try #require(tamperedString.data(using: .utf8))

        let tamperedInspect = try BackupCodec.decodeAndInspect(tamperedData)
        #expect(tamperedInspect.isLegacyV1 == false)
        #expect(tamperedInspect.checksumValid == false)
        #expect(tamperedInspect.envelope.payload.todos.first?.title == "Tampered Title")
    }

    // MARK: - 4. Import Strategies: smartMerge, appendCopy, replaceAll

    @Test("Import strategies smartMerge, appendCopy, and replaceAll behave accurately")
    func importStrategiesSmartMergeAppendCopyAndReplaceAll() throws {
        let t0 = Date(timeIntervalSince1970: 1_795_000_000)
        let t1 = t0.addingTimeInterval(600)
        let tOld = t0.addingTimeInterval(-600)

        let incomingPayload = PickPlanBackupPayload(
            todos: [
                TodoItem(id: "same-newer", title: "Newer Version", createdAt: t0, updatedAt: t1),
                TodoItem(id: "same-older", title: "Stale Version", createdAt: t0, updatedAt: tOld),
                TodoItem(id: "brand-new", title: "Incoming Brand New", createdAt: t0, updatedAt: t0)
            ]
        )
        let archiveData = try BackupCodec.encodeEnvelope(incomingPayload, exportedAt: t1)

        // .smartMerge
        try withTempVault { mergeStore in
            mergeStore.addTodos([
                TodoItem(id: "same-newer", title: "Old Local", createdAt: t0, updatedAt: t0),
                TodoItem(id: "same-older", title: "Newer Local", createdAt: t0, updatedAt: t0),
                TodoItem(id: "local-only", title: "Local Only", createdAt: t0, updatedAt: t0)
            ])

            let preview = try mergeStore.previewImport(data: archiveData)
            #expect(preview.incomingTaskCount == 3)
            #expect(preview.conflictingIdCount == 2)
            #expect(preview.newTaskCount == 1)

            let mergeResult = try mergeStore.applyImport(data: archiveData, strategy: .smartMerge, now: t1)
            #expect(mergeResult.addedCount == 1)
            #expect(mergeResult.updatedCount == 1)
            #expect(mergeResult.totalCountAfter == 4)
            #expect(mergeResult.safetySnapshotId == nil)
            #expect(mergeStore.getTodos().first(where: { $0.id == "same-newer" })?.title == "Newer Version")
            #expect(mergeStore.getTodos().first(where: { $0.id == "same-older" })?.title == "Newer Local")
        }

        // .appendCopy
        try withTempVault { appendStore in
            appendStore.upsertTodo(TodoItem(id: "same-newer", title: "Existing Local", createdAt: t0, updatedAt: t0))
            let appendResult = try appendStore.applyImport(data: archiveData, strategy: .appendCopy, now: t1)
            #expect(appendResult.addedCount == 3)
            #expect(appendResult.updatedCount == 0)
            #expect(appendResult.totalCountAfter == 4)
            #expect(Set(appendStore.getTodos().map(\.id)).count == 4)
        }

        // .replaceAll creates .safetyPreRestore snapshot automatically
        try withTempVault { replaceStore in
            replaceStore.upsertTodo(TodoItem(id: "before-replace", title: "Before Replace", createdAt: t0, updatedAt: t0))
            let replaceResult = try replaceStore.applyImport(data: archiveData, strategy: .replaceAll, now: t1)
            #expect(replaceResult.addedCount == 3)
            #expect(replaceResult.totalCountAfter == 3)
            let safetyId = try #require(replaceResult.safetySnapshotId)

            let snapshots = replaceStore.listSnapshots()
            #expect(snapshots.count == 1)
            #expect(snapshots.first?.id == safetyId)
            #expect(snapshots.first?.trigger == .safetyPreRestore)
            let safetyEnvelope = try replaceStore.loadSnapshotPayload(id: safetyId)
            #expect(safetyEnvelope.payload.todos.map(\.id) == ["before-replace"])
        }
    }

    // MARK: - 5. Scheduled Backup Evaluator

    @Test("Scheduled backup evaluator handles disabled, background-dirty, and interval gates")
    func scheduledBackupEvaluator() throws {
        try withTempVault { store in
            let baseTime = Date(timeIntervalSince1970: 1_795_000_000)
            store.upsertTodo(TodoItem(id: "sched-1", title: "Important task", createdAt: baseTime, updatedAt: baseTime))

            // Disabled -> skips
            var prefs = store.getPreferences()
            prefs.backupPolicy.isEnabled = false
            prefs.backupPolicy.intervalHours = 6
            store.updatePreferences(prefs)
            #expect(try store.evaluateScheduledBackup(now: baseTime, isBackgroundTransition: true) == nil)

            // Enabled + background transition while dirty -> triggers
            prefs.backupPolicy.isEnabled = true
            prefs.backupPolicy.backupOnBackgroundAfterChanges = true
            store.updatePreferences(prefs)
            let bgSnap = try store.evaluateScheduledBackup(now: baseTime, isBackgroundTransition: true)
            #expect(bgSnap != nil)
            #expect(bgSnap?.trigger == .scheduled)

            // Interval NOT elapsed (2 hours < 6 hours) -> skips
            let twoHoursLater = baseTime.addingTimeInterval(2 * 3600)
            #expect(try store.evaluateScheduledBackup(now: twoHoursLater, isBackgroundTransition: false) == nil)

            // Interval elapsed (6 hours >= 6 hours) -> creates snapshot
            let sixHoursLater = baseTime.addingTimeInterval(6 * 3600)
            let intervalSnap = try store.evaluateScheduledBackup(now: sixHoursLater, isBackgroundTransition: false)
            #expect(intervalSnap != nil)
            #expect(intervalSnap?.trigger == .scheduled)
            #expect(store.listSnapshots().count == 2)
        }
    }

    // MARK: - 6. Snapshot Retention Pruning Preserves Pinned Snapshots

    @Test("Retention pruning keeps pinned snapshots and evicts oldest unpinned snapshots")
    func snapshotRetentionPruningPreservesPinnedSnapshots() throws {
        try withTempVault { store in
            var prefs = store.getPreferences()
            prefs.backupPolicy.maxSnapshots = 3
            store.updatePreferences(prefs)

            let base = Date(timeIntervalSince1970: 1_795_000_000)
            store.upsertTodo(TodoItem(title: "Seed task", createdAt: base, updatedAt: base))

            let snap1 = try store.createSnapshot(trigger: .manual, note: "S1", now: base.addingTimeInterval(10))
            _ = try store.togglePinSnapshot(id: snap1.id) // Oldest, pinned!

            let snap2 = try store.createSnapshot(trigger: .manual, note: "S2", now: base.addingTimeInterval(20)) // Unpinned
            let snap3 = try store.createSnapshot(trigger: .manual, note: "S3", now: base.addingTimeInterval(30))
            _ = try store.togglePinSnapshot(id: snap3.id) // Pinned!

            // Total 4 > maxSnapshots 3 -> snap2 (oldest unpinned) should be pruned!
            let snap4 = try store.createSnapshot(trigger: .manual, note: "S4", now: base.addingTimeInterval(40))
            var remainingIds = Set(store.listSnapshots().map(\.id))
            #expect(remainingIds.count == 3)
            #expect(remainingIds.contains(snap1.id))
            #expect(!remainingIds.contains(snap2.id))
            #expect(remainingIds.contains(snap3.id))
            #expect(remainingIds.contains(snap4.id))

            // Creating snap5 -> snap4 pruned; snap1 & snap3 remain pinned!
            let snap5 = try store.createSnapshot(trigger: .manual, note: "S5", now: base.addingTimeInterval(50))
            remainingIds = Set(store.listSnapshots().map(\.id))
            #expect(remainingIds.count == 3)
            #expect(remainingIds.contains(snap1.id))
            #expect(remainingIds.contains(snap3.id))
            #expect(!remainingIds.contains(snap4.id))
            #expect(remainingIds.contains(snap5.id))

            // When all snapshots are pinned, none are ever deleted
            _ = try store.togglePinSnapshot(id: snap5.id)
            let snap6 = try store.createSnapshot(trigger: .manual, note: "S6", now: base.addingTimeInterval(60))
            _ = try store.togglePinSnapshot(id: snap6.id)
            #expect(store.listSnapshots().count == 4)
            #expect(store.pruneSnapshotsIfNeeded() == 0)
        }
    }

    // MARK: - 7. Snapshot Restore & Automatic Safety Snapshot

    @Test("Snapshot restore recovers previous todos and creates pre-restore safety snapshot")
    func snapshotRestoreRecoversPreviousStateAndCreatesSafetySnapshot() throws {
        try withTempVault { store in
            let t0 = Date(timeIntervalSince1970: 1_795_000_000)

            store.upsertTodo(TodoItem(id: "orig-1", title: "Original One", createdAt: t0, updatedAt: t0))
            let originalSnap = try store.createSnapshot(trigger: .manual, note: "Before big edit", now: t0)

            store.upsertTodo(TodoItem(id: "new-2", title: "Added Later", createdAt: t0, updatedAt: t0))
            _ = store.deleteTodo(id: "orig-1")
            #expect(store.getTodos().map(\.id) == ["new-2"])

            let restoreResult = try store.restoreSnapshot(id: originalSnap.id, now: t0.addingTimeInterval(60))
            #expect(store.getTodos().map(\.id) == ["orig-1"])
            #expect(store.getTodos().first?.title == "Original One")

            let safetyId = try #require(restoreResult.safetySnapshotId)
            let safetyEnvelope = try store.loadSnapshotPayload(id: safetyId)
            #expect(safetyEnvelope.payload.todos.map(\.id) == ["new-2"])
        }
    }

    // MARK: - 8. SmartSectionEngine Categorization & Sorting

    @Test("SmartSectionEngine categorizes overdue, today, tomorrow, later, unscheduled, completed and sorts")
    func smartSectionEngineCategorizationAndSorting() {
        let cal = makeReferenceCalendar()
        let now = makeDate(year: 2026, month: 11, day: 17, hour: 12, minute: 0, calendar: cal)

        let overdue = TodoItem(
            id: "overdue",
            title: "Overdue Task",
            priority: .normal,
            reminderTime: makeDate(year: 2026, month: 11, day: 17, hour: 9, minute: 0, calendar: cal),
            createdAt: now
        )
        let todayLate = TodoItem(
            id: "today-late",
            title: "Today 18:00",
            priority: .high,
            reminderTime: makeDate(year: 2026, month: 11, day: 17, hour: 18, minute: 0, calendar: cal),
            createdAt: now
        )
        let todayEarly = TodoItem(
            id: "today-early",
            title: "Today 14:00",
            priority: .low,
            reminderTime: makeDate(year: 2026, month: 11, day: 17, hour: 14, minute: 0, calendar: cal),
            createdAt: now
        )
        let tomorrow = TodoItem(
            id: "tomorrow",
            title: "Tomorrow Deadline",
            deadline: makeDate(year: 2026, month: 11, day: 18, hour: 17, minute: 0, calendar: cal),
            createdAt: now
        )
        let later = TodoItem(
            id: "later",
            title: "Next Week",
            reminderTime: makeDate(year: 2026, month: 11, day: 25, hour: 10, minute: 0, calendar: cal),
            createdAt: now
        )
        let unscheduledLow = TodoItem(
            id: "unsched-low",
            title: "Someday Low",
            priority: .low,
            createdAt: now.addingTimeInterval(10)
        )
        let unscheduledHigh = TodoItem(
            id: "unsched-high",
            title: "Backlog High",
            priority: .high,
            createdAt: now
        )
        let completedOld = TodoItem(
            id: "done-old",
            title: "Done Earlier",
            createdAt: now,
            updatedAt: now.addingTimeInterval(-3600),
            completedAt: now.addingTimeInterval(-3600),
            isCompleted: true
        )
        let completedRecent = TodoItem(
            id: "done-new",
            title: "Done Recently",
            createdAt: now,
            updatedAt: now.addingTimeInterval(-60),
            completedAt: now.addingTimeInterval(-60),
            isCompleted: true
        )

        let all = [completedOld, unscheduledLow, later, todayLate, overdue, completedRecent, tomorrow, unscheduledHigh, todayEarly]
        let sections = SmartSectionEngine.groupIntoSections(all, now: now, calendar: cal)

        #expect(sections.map(\.kind) == [.overdue, .today, .tomorrow, .later, .unscheduled, .completed])
        #expect(sections[0].todos.map(\.id) == ["overdue"])
        #expect(sections[1].todos.map(\.id) == ["today-early", "today-late"])
        #expect(sections[2].todos.map(\.id) == ["tomorrow"])
        #expect(sections[3].todos.map(\.id) == ["later"])
        #expect(sections[4].todos.map(\.id) == ["unsched-high", "unsched-low"])
        #expect(sections[5].todos.map(\.id) == ["done-new", "done-old"])

        let filtered = SmartSectionEngine.filterTodos(all, query: "Backlog", tag: nil, sectionFilter: .unscheduled, now: now, calendar: cal)
        #expect(filtered.map(\.id) == ["unsched-high"])
    }

    // MARK: - 9. PlainWordsParser Chinese Multi-Task Input

    @Test("PlainWordsParser splits Chinese multi-task sentence with reminder & deadline dates")
    func plainWordsParserChineseMultiTaskSentence() throws {
        let cal = makeReferenceCalendar()
        // Tuesday, 2026-11-17 08:30
        let refDate = makeDate(year: 2026, month: 11, day: 17, hour: 8, minute: 30, calendar: cal)

        let parsed = PlainWordsParser.parse(
            "明天上午买菜，下午三点开会，周五前交报告",
            referenceDate: refDate,
            calendar: cal
        )

        #expect(parsed.count == 3)

        // 1. 买菜 -> 明天上午 (2026-11-18 09:00)
        #expect(parsed[0].title == "买菜")
        #expect(parsed[0].tag == .life)
        #expect(parsed[0].deadline == nil)
        let r0 = try #require(parsed[0].reminderTime)
        let c0 = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r0)
        #expect(c0.year == 2026 && c0.month == 11 && c0.day == 18 && c0.hour == 9 && c0.minute == 0)

        // 2. 开会 -> inherits 明天, 下午三点 (2026-11-18 15:00)
        #expect(parsed[1].title == "开会")
        #expect(parsed[1].tag == .work)
        #expect(parsed[1].deadline == nil)
        let r1 = try #require(parsed[1].reminderTime)
        let c1 = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r1)
        #expect(c1.year == 2026 && c1.month == 11 && c1.day == 18 && c1.hour == 15 && c1.minute == 0)

        // 3. 交报告 -> 周五前 (deadline on Friday 2026-11-20)
        #expect(parsed[2].title == "交报告")
        #expect(parsed[2].tag == .work)
        #expect(parsed[2].reminderTime == nil)
        let d2 = try #require(parsed[2].deadline)
        let c2 = cal.dateComponents([.year, .month, .day], from: d2)
        #expect(c2.year == 2026 && c2.month == 11 && c2.day == 20)
    }

    // MARK: - 10. PlainWordsParser English Multi-Task Input

    @Test("PlainWordsParser splits English multi-task input with reminder & deadline dates")
    func plainWordsParserEnglishMultiTaskSentence() throws {
        let cal = makeReferenceCalendar()
        // Tuesday, 2026-11-17 10:00
        let refDate = makeDate(year: 2026, month: 11, day: 17, hour: 10, minute: 0, calendar: cal)

        let parsed = PlainWordsParser.parse(
            "Call client tomorrow at 3 PM; submit report by Friday",
            referenceDate: refDate,
            calendar: cal
        )

        #expect(parsed.count == 2)

        #expect(parsed[0].title == "Call client")
        #expect(parsed[0].deadline == nil)
        let r0 = try #require(parsed[0].reminderTime)
        let c0 = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r0)
        #expect(c0.year == 2026 && c0.month == 11 && c0.day == 18 && c0.hour == 15 && c0.minute == 0)

        #expect(parsed[1].title == "Submit report")
        #expect(parsed[1].reminderTime == nil)
        let d1 = try #require(parsed[1].deadline)
        let c1 = cal.dateComponents([.year, .month, .day], from: d1)
        #expect(c1.year == 2026 && c1.month == 11 && c1.day == 20)
    }

    // MARK: - 11. Data Hygiene & Storage Breakdown

    @Test("Data hygiene clears completed, deduplicates, reports breakdown, and resets vault")
    func dataHygieneClearCompletedDeduplicateAndFactoryReset() throws {
        try withTempVault { store in
            let t0 = Date(timeIntervalSince1970: 1_795_000_000)

            let dup1 = TodoItem(id: "d1", title: "Buy Milk", notes: "", createdAt: t0, updatedAt: t0)
            let dup2 = TodoItem(id: "d2", title: "  buy milk ", notes: "Organic", createdAt: t0, updatedAt: t0.addingTimeInterval(60))
            let done = TodoItem(id: "done-1", title: "Completed Task", createdAt: t0, updatedAt: t0, completedAt: t0, isCompleted: true)
            let active = TodoItem(id: "act-1", title: "Active Task", createdAt: t0, updatedAt: t0)

            store.addTodos([dup1, dup2, done, active])
            store.appendChatMessage(ChatHistoryEntry(text: "Hello", isUser: true, createdAt: t0))
            _ = try store.createSnapshot(trigger: .manual, note: "Snap", now: t0)

            let initialBreakdown = store.computeStorageBreakdown()
            #expect(initialBreakdown.totalTodos == 4)
            #expect(initialBreakdown.activeTodos == 3)
            #expect(initialBreakdown.completedTodos == 1)
            #expect(initialBreakdown.chatMessageCount == 1)
            #expect(initialBreakdown.snapshotCount == 1)
            #expect(initialBreakdown.liveDatabaseBytes > 0)
            #expect(initialBreakdown.snapshotsTotalBytes > 0)

            let dedupRemoved = store.deduplicateTodos()
            #expect(dedupRemoved == 1)
            #expect(store.getTodos().count == 3)
            #expect(store.getTodos().first(where: { $0.title.lowercased().contains("milk") })?.notes == "Organic")

            let completedRemoved = store.clearCompletedTodos()
            #expect(completedRemoved == 1)
            #expect(store.getTodos().count == 2)

            store.factoryReset()
            let afterReset = store.computeStorageBreakdown()
            #expect(afterReset.totalTodos == 0)
            #expect(afterReset.snapshotCount == 0)
            #expect(afterReset.chatMessageCount == 0)
            #expect(afterReset.liveDatabaseBytes == 0)
            #expect(afterReset.snapshotsTotalBytes == 0)
        }
    }

    // MARK: - 12. Markdown Export Formatting

    @Test("Markdown export groups tasks by section with metadata, notes, and subtasks")
    func markdownExportFormatting() {
        let cal = makeReferenceCalendar()
        let now = makeDate(year: 2026, month: 11, day: 17, hour: 10, minute: 0, calendar: cal)

        let todos = [
            TodoItem(
                id: "md-1",
                title: "Prepare Keynote",
                notes: "Include demo video",
                subtasks: [
                    SubtaskItem(title: "Record clip", isCompleted: true),
                    SubtaskItem(title: "Export slides", isCompleted: false)
                ],
                tag: .work,
                priority: .high,
                reminderTime: makeDate(year: 2026, month: 11, day: 17, hour: 15, minute: 0, calendar: cal),
                createdAt: now,
                updatedAt: now,
                focusMinutesLogged: 25
            ),
            TodoItem(
                id: "md-2",
                title: "Morning Run",
                tag: .life,
                createdAt: now,
                updatedAt: now,
                completedAt: now,
                isCompleted: true
            )
        ]

        let markdownEn = BackupCodec.exportMarkdown(todos: todos, language: .en, now: now, calendar: cal)
        #expect(markdownEn.contains("# PickPlan Task List"))
        #expect(markdownEn.contains("## Today (1)"))
        #expect(markdownEn.contains("## Completed (1)"))
        #expect(markdownEn.contains("- [ ] **Prepare Keynote**"))
        #expect(markdownEn.contains("[High]"))
        #expect(markdownEn.contains("#Work"))
        #expect(markdownEn.contains("🍅 25m"))
        #expect(markdownEn.contains("Include demo video"))
        #expect(markdownEn.contains("  - [x] Record clip"))
        #expect(markdownEn.contains("  - [ ] Export slides"))
        #expect(markdownEn.contains("- [x] **Morning Run**"))

        let markdownZh = BackupCodec.exportMarkdown(todos: todos, language: .zh, now: now, calendar: cal)
        #expect(markdownZh.contains("# PickPlan 任务清单"))
        #expect(markdownZh.contains("## 今天 (1)"))
        #expect(markdownZh.contains("## 已完成 (1)"))
    }

    // MARK: - 13. Date Codec ISO8601 Variants & Quick Time Presets

    @Test("PickPlanDateCodec parses ISO8601 variants and QuickTimePreset computes future dates")
    func dateCodecVariantsAndQuickTimePresets() {
        #expect(PickPlanDateCodec.parseISO8601("2026-11-17T18:00:00Z") != nil)
        #expect(PickPlanDateCodec.parseISO8601("2026-11-17T18:00:00.123Z") != nil)
        #expect(PickPlanDateCodec.parseISO8601("2026-11-17T18:00:00.123456+08:00") != nil)
        #expect(PickPlanDateCodec.parseISO8601("2026-09-10T12:30:00.123456") != nil)
        #expect(PickPlanDateCodec.parseISO8601("2026-09-10T12:30:00") != nil)
        #expect(PickPlanDateCodec.parseISO8601("2026-02-30T12:00:00Z") == nil)
        #expect(PickPlanDateCodec.parseISO8601("not-a-date") == nil)

        let cal = makeReferenceCalendar()
        let tuesday = makeDate(year: 2026, month: 11, day: 17, hour: 10, minute: 0, calendar: cal)
        let nextMon = QuickTimePreset.nextMondayMorning.date(from: tuesday, calendar: cal)
        let nextMonComps = cal.dateComponents([.year, .month, .day, .hour], from: nextMon)
        #expect(nextMonComps.year == 2026)
        #expect(nextMonComps.month == 11)
        #expect(nextMonComps.day == 23)
        #expect(nextMonComps.hour == 9)
    }

    // MARK: - 14. NotificationCoordinator Unbundled Safety & AIService JSON Parsing

    @Test("NotificationCoordinator does not crash in unbundled process and AIService parses fenced JSON")
    func notificationCoordinatorSafeInTestProcessAndAIServiceParsing() async throws {
        let coordinator = NotificationCoordinator()
        let authorized = await coordinator.requestAuthorization()
        #expect(authorized == false)
        await coordinator.syncReminders(for: [TodoItem(title: "Test", reminderTime: Date().addingTimeInterval(600))])
        await coordinator.cancelAllReminders()

        let fencedResponse = """
        ```json
        {
          "todos": [
            {
              "title": "Submit quarterly OKRs",
              "tag": "work",
              "priority": "high",
              "deadline": "2026-11-20T18:00:00Z"
            }
          ]
        }
        ```
        """
        let aiItems = try AIService.parseAIResponseContent(fencedResponse)
        #expect(aiItems.count == 1)
        #expect(aiItems.first?.title == "Submit quarterly OKRs")
        #expect(aiItems.first?.tag == .work)
        #expect(aiItems.first?.priority == .high)
        #expect(aiItems.first?.deadline != nil)
        #expect(AIProviderPreset.presets.count == 7)
    }

    // MARK: - 15. PlanStore Async Operations & Undo

    @Test("PlanStore supports async CRUD, undo delete, quick parse, and offline chat extraction")
    @MainActor
    func planStoreCrudUndoAndQuickParse() async throws {
        try await withTempVaultAsync { vault in
            let store = PlanStore(vault: vault)

            let added = await store.addTodo(title: "Write Swift 6 Core", tag: .work, priority: .high)
            #expect(store.todos.count == 1)

            await store.deleteTodo(id: added.id)
            #expect(store.todos.isEmpty)
            #expect(store.lastDeletedTodo?.id == added.id)

            await store.undoLastDelete()
            #expect(store.todos.count == 1)
            #expect(store.lastDeletedTodo == nil)

            let quick = await store.quickParseAndAdd("明天上午买咖啡；周五前写总结")
            #expect(quick.count == 2)
            #expect(store.todos.count == 3)

            await store.sendChatPrompt("明天下午三点代码评审", preferAI: false)
            #expect(store.chatHistory.count == 2)
            let aiMsg = try #require(store.chatHistory.last)
            #expect(aiMsg.isUser == false)
            #expect(aiMsg.parsedTodos.count == 1)
            await store.addParsedTodosFromChat(messageId: aiMsg.id)
            #expect(store.todos.count == 4)
            #expect(store.chatHistory.last?.isAdded == true)
        }
    }
}
