import Foundation

/// Offline deterministic natural-language parser supporting Chinese and English multi-task sentences,
/// relative dates, clock times, durations, deadline vs reminder cues, and priority/tag hints.
public enum PlainWordsParser {
    private struct ExtractedTimeInfo {
        var explicitDay: Date?
        var resolvedDay: Date?
        var hour: Int?
        var minute: Int?
        var periodDefaultHour: Int?
        var isPMBias: Bool = false
        var isAMBias: Bool = false
        var offsetDate: Date?
        var isDeadline: Bool = false
        var hasAnyTimeSignal: Bool {
            explicitDay != nil || hour != nil || periodDefaultHour != nil || offsetDate != nil
        }
        var strippedRanges: [NSRange] = []
    }

    private static let chineseActionPrefixes: [String] = [
        "买", "开", "交", "去", "写", "做", "发", "查", "看", "约", "学", "读",
        "整理", "准备", "确认", "提交", "完成", "回复", "联系", "打", "吃", "拿",
        "取", "修", "洗", "订", "还", "寄", "参加", "讨论", "沟通", "复习", "背",
        "练", "跑", "游", "打卡", "清理", "备份", "更新", "部署", "测试", "提醒"
    ]

    private static let englishActionPrefixes: Set<String> = [
        "call", "submit", "buy", "email", "send", "write", "read", "review", "check",
        "meet", "schedule", "book", "pay", "clean", "fix", "deploy", "test", "prepare",
        "finish", "complete", "update", "pick", "take", "order", "reply", "ask", "remind",
        "study", "practice", "backup", "export", "import", "visit", "workout", "run"
    ]

    /// Parses freeform Chinese or English text into structured `TodoItem` objects.
    public static func parse(
        _ input: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoItem] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let clauses = splitClauses(trimmed, referenceDate: referenceDate, calendar: calendar)
        var results: [TodoItem] = []
        var inheritedDay: Date?

        for clause in clauses {
            let trimmedClause = clause.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedClause.isEmpty else { continue }

            let info = extractTimeAndCleanTitle(
                from: trimmedClause,
                referenceDate: referenceDate,
                inheritedDay: inheritedDay,
                calendar: calendar
            )

            if let explicitDay = info.time.explicitDay {
                inheritedDay = explicitDay
            }

            let cleanedTitle = info.cleanedTitle
            guard !cleanedTitle.isEmpty else { continue }

            let priority = detectPriority(in: trimmedClause)
            let tag = detectTag(in: trimmedClause)

            let resolvedDate = resolveDate(
                from: info.time,
                referenceDate: referenceDate,
                calendar: calendar
            )

            let reminderTime: Date?
            let deadline: Date?
            if let resolvedDate {
                if info.time.isDeadline {
                    reminderTime = nil
                    deadline = resolvedDate
                } else {
                    reminderTime = resolvedDate
                    deadline = nil
                }
            } else {
                reminderTime = nil
                deadline = nil
            }

            let item = TodoItem(
                title: cleanedTitle,
                tag: tag,
                priority: priority,
                reminderTime: reminderTime,
                deadline: deadline,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
            results.append(item)
        }

        return results
    }

    // MARK: - Clause Splitting

    private static func splitClauses(
        _ text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> [String] {
        // Normalize hard delimiters into "\n"
        var normalized = text
        let hardPatterns = [
            "\\r\\n", "\\n", ";", "；", "。",
            "(?i)\\band\\s+then\\b",
            "(?i)\\bthen\\b",
            "然后"
        ]
        for pattern in hardPatterns {
            normalized = regexReplacing(normalized, pattern: pattern, with: "\n")
        }

        let hardSegments = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rawClauses: [String] = []
        for segment in hardSegments {
            let softPieces = splitOnSoftBoundaries(segment)
            if softPieces.count > 1 && shouldKeepSoftSplit(softPieces, referenceDate: referenceDate, calendar: calendar) {
                rawClauses.append(contentsOf: softPieces)
            } else {
                rawClauses.append(segment)
            }
        }

        // Merge any pure-time prefix fragment (e.g. "明天，买菜" -> "明天 买菜") with the following clause
        var merged: [String] = []
        var pendingPrefix: String?
        for clause in rawClauses {
            let candidate = pendingPrefix.map { "\($0) \(clause)" } ?? clause
            let extracted = extractTimeAndCleanTitle(
                from: candidate,
                referenceDate: referenceDate,
                inheritedDay: nil,
                calendar: calendar
            )
            if extracted.cleanedTitle.isEmpty {
                pendingPrefix = candidate
            } else {
                merged.append(candidate)
                pendingPrefix = nil
            }
        }
        if let leftover = pendingPrefix, !leftover.isEmpty {
            merged.append(leftover)
        }

        return merged
    }

    private static func splitOnSoftBoundaries(_ segment: String) -> [String] {
        let withSentinels = regexReplacing(segment, pattern: "[,，]|(?i)\\band\\b|并且|并(?=\\S)", with: "\u{0000}")
        return withSentinels
            .components(separatedBy: "\u{0000}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func shouldKeepSoftSplit(
        _ pieces: [String],
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        var independentCount = 0
        for piece in pieces {
            let extracted = extractTimeAndCleanTitle(
                from: piece,
                referenceDate: referenceDate,
                inheritedDay: nil,
                calendar: calendar
            )
            if extracted.time.hasAnyTimeSignal && !extracted.cleanedTitle.isEmpty {
                independentCount += 1
            } else if hasActionCue(extracted.cleanedTitle.isEmpty ? piece : extracted.cleanedTitle) {
                independentCount += 1
            }
        }
        return independentCount >= 2
    }

    private static func hasActionCue(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for prefix in chineseActionPrefixes where trimmed.contains(prefix) {
            return true
        }
        let words = trimmed.lowercased().split { !$0.isLetter }
        if let first = words.first, englishActionPrefixes.contains(String(first)) {
            return true
        }
        return false
    }

    // MARK: - Time & Title Extraction

    private static func extractTimeAndCleanTitle(
        from clause: String,
        referenceDate: Date,
        inheritedDay: Date?,
        calendar: Calendar
    ) -> (time: ExtractedTimeInfo, cleanedTitle: String) {
        var info = ExtractedTimeInfo()
        let nsClause = clause as NSString
        let fullRange = NSRange(location: 0, length: nsClause.length)

        // 1. Relative duration offsets ("2小时后", "in 2 hours", "30分钟后", "in 30 minutes")
        if let match = firstMatch(
            in: clause,
            pattern: "(?:(\\d+|[零一二两三四五六七八九十]+)\\s*(?:个)?小时(?:之)?后|(?i)in\\s+(\\d+)\\s*hours?)"
        ) {
            let numStr = matchCapture(nsClause, match, group: 1) ?? matchCapture(nsClause, match, group: 2) ?? ""
            if let hours = parseFlexibleNumber(numStr), hours > 0 {
                info.offsetDate = calendar.date(byAdding: .hour, value: hours, to: referenceDate)
                    ?? referenceDate.addingTimeInterval(TimeInterval(hours * 3600))
                info.strippedRanges.append(match.range)
            }
        } else if let match = firstMatch(
            in: clause,
            pattern: "(?:(\\d+|[零一二两三四五六七八九十]+)\\s*分钟(?:之)?后|(?i)in\\s+(\\d+)\\s*min(?:ute)?s?)"
        ) {
            let numStr = matchCapture(nsClause, match, group: 1) ?? matchCapture(nsClause, match, group: 2) ?? ""
            if let mins = parseFlexibleNumber(numStr), mins > 0 {
                info.offsetDate = calendar.date(byAdding: .minute, value: mins, to: referenceDate)
                    ?? referenceDate.addingTimeInterval(TimeInterval(mins * 60))
                info.strippedRanges.append(match.range)
            }
        } else if let match = firstMatch(
            in: clause,
            pattern: "(?:(\\d+|[零一二两三四五六七八九十]+)\\s*天(?:之)?后|(?i)in\\s+(\\d+)\\s*days?)"
        ) {
            let numStr = matchCapture(nsClause, match, group: 1) ?? matchCapture(nsClause, match, group: 2) ?? ""
            if let days = parseFlexibleNumber(numStr), days > 0 {
                let startToday = calendar.startOfDay(for: referenceDate)
                info.explicitDay = calendar.date(byAdding: .day, value: days, to: startToday)
                info.strippedRanges.append(match.range)
            }
        }

        // 2. Explicit YYYY-MM-DD or MM月DD日
        if let match = firstMatch(in: clause, pattern: "(\\d{4})[-/.年](\\d{1,2})[-/.月](\\d{1,2})[日号]?") {
            if let y = Int(matchCapture(nsClause, match, group: 1) ?? ""),
               let m = Int(matchCapture(nsClause, match, group: 2) ?? ""),
               let d = Int(matchCapture(nsClause, match, group: 3) ?? "") {
                var comps = DateComponents()
                comps.year = y
                comps.month = m
                comps.day = d
                if let date = calendar.date(from: comps) {
                    info.explicitDay = calendar.startOfDay(for: date)
                    info.strippedRanges.append(match.range)
                }
            }
        } else if let match = firstMatch(in: clause, pattern: "(\\d{1,2})月(\\d{1,2})[日号]?") {
            if let m = Int(matchCapture(nsClause, match, group: 1) ?? ""),
               let d = Int(matchCapture(nsClause, match, group: 2) ?? "") {
                let year = calendar.component(.year, from: referenceDate)
                let comps = DateComponents(year: year, month: m, day: d)
                if var date = calendar.date(from: comps) {
                    let startToday = calendar.startOfDay(for: referenceDate)
                    if date < startToday, let nextYearDate = calendar.date(byAdding: .year, value: 1, to: date) {
                        date = nextYearDate
                    }
                    info.explicitDay = calendar.startOfDay(for: date)
                    info.strippedRanges.append(match.range)
                }
            }
        }

        // 3. Relative Chinese & English day tokens (with optional attached deadline cue)
        let chineseDayTokens: [(pattern: String, dayOffset: Int?, periodDefault: Int?, biasPM: Bool, biasAM: Bool)] = [
            ("大后天", 3, nil, false, false),
            ("后天", 2, nil, false, false),
            ("明早", 1, 9, false, true),
            ("明晚", 1, 20, true, false),
            ("明天", 1, nil, false, false),
            ("今早", 0, 9, false, true),
            ("今晚", 0, 20, true, false),
            ("今天", 0, nil, false, false)
        ]

        if info.explicitDay == nil {
            for token in chineseDayTokens {
                let pattern = "(?:(截止|最晚)\\s*(?:到|于)?\\s*)?\(token.pattern)(?:\\s*(之前|前|截止|到期))?"
                if let match = firstMatch(in: clause, pattern: pattern), let offset = token.dayOffset {
                    let startToday = calendar.startOfDay(for: referenceDate)
                    info.explicitDay = calendar.date(byAdding: .day, value: offset, to: startToday)
                    if let pHour = token.periodDefault {
                        info.periodDefaultHour = pHour
                    }
                    if token.biasPM { info.isPMBias = true }
                    if token.biasAM { info.isAMBias = true }
                    if matchCapture(nsClause, match, group: 1) != nil || matchCapture(nsClause, match, group: 2) != nil {
                        info.isDeadline = true
                    }
                    info.strippedRanges.append(match.range)
                    break
                }
            }
        }

        if info.explicitDay == nil {
            let engDayPattern = "(?i)(?:\\b(by|before|due|until|on)\\s+)?\\b(day\\s+after\\s+tomorrow|tomorrow|tonight|today)\\b"
            if let match = firstMatch(in: clause, pattern: engDayPattern),
               let word = matchCapture(nsClause, match, group: 2)?.lowercased() {
                let startToday = calendar.startOfDay(for: referenceDate)
                let offset: Int
                if word.contains("after") {
                    offset = 2
                } else if word == "tomorrow" {
                    offset = 1
                } else {
                    offset = 0
                }
                info.explicitDay = calendar.date(byAdding: .day, value: offset, to: startToday)
                if word == "tonight" {
                    info.periodDefaultHour = 20
                    info.isPMBias = true
                }
                if let prep = matchCapture(nsClause, match, group: 1)?.lowercased(),
                   ["by", "before", "due", "until"].contains(prep) {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        }

        // 4. Weekdays: Chinese (本周/下周/周X/星期X) and English (next/this/by Friday)
        if info.explicitDay == nil {
            let zhWeekdayPattern = "(?:(截止|最晚)\\s*(?:到|于)?\\s*)?(下|这|本)?(?:周|星期)([一二三四五六日天])(?:\\s*(之前|前|截止|到期))?"
            if let match = firstMatch(in: clause, pattern: zhWeekdayPattern),
               let dayChar = matchCapture(nsClause, match, group: 3),
               let targetIso = parseChineseWeekday(dayChar) {
                let modifier = matchCapture(nsClause, match, group: 2)
                let isNextWeek = (modifier == "下")
                info.explicitDay = resolveWeekday(targetIso: targetIso, forceNextWeek: isNextWeek, referenceDate: referenceDate, calendar: calendar)
                if matchCapture(nsClause, match, group: 1) != nil || matchCapture(nsClause, match, group: 4) != nil {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        }

        if info.explicitDay == nil {
            let engWeekdayPattern = "(?i)(?:\\b(by|before|due|until|on)\\s+)?(?:\\b(next|this)\\s+)?\\b(monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|sunday|sun)\\b"
            if let match = firstMatch(in: clause, pattern: engWeekdayPattern),
               let dayWord = matchCapture(nsClause, match, group: 3)?.lowercased(),
               let targetIso = parseEnglishWeekday(dayWord) {
                let modifier = matchCapture(nsClause, match, group: 2)?.lowercased()
                let isNextWeek = (modifier == "next")
                info.explicitDay = resolveWeekday(targetIso: targetIso, forceNextWeek: isNextWeek, referenceDate: referenceDate, calendar: calendar)
                if let prep = matchCapture(nsClause, match, group: 1)?.lowercased(),
                   ["by", "before", "due", "until"].contains(prep) {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        }

        // 5. Period-of-day modifiers ("上午", "下午", "晚上", "morning", "afternoon", "evening")
        let periodPatterns: [(pattern: String, defaultHour: Int, biasPM: Bool, biasAM: Bool)] = [
            ("凌晨", 2, false, true),
            ("早上|早晨|上午", 9, false, true),
            ("中午", 12, false, false),
            ("下午", 15, true, false),
            ("傍晚|晚上", 20, true, false),
            ("(?i)\\b(?:in\\s+the\\s+)?morning\\b", 9, false, true),
            ("(?i)\\bnoon\\b", 12, false, false),
            ("(?i)\\b(?:in\\s+the\\s+)?afternoon\\b", 14, true, false),
            ("(?i)\\b(?:in\\s+the\\s+)?(?:evening|night)\\b", 20, true, false)
        ]
        for p in periodPatterns {
            if let match = firstMatch(in: clause, pattern: p.pattern) {
                info.periodDefaultHour = p.defaultHour
                if p.biasPM { info.isPMBias = true }
                if p.biasAM { info.isAMBias = true }
                info.strippedRanges.append(match.range)
                break
            }
        }

        // 6. Clock times ("15:00", "3:30 PM", "3 PM", "三点半", "8点15分")
        if let match = firstMatch(
            in: clause,
            pattern: "(?i)(?:\\b(by|before|due|at)\\s+)?\\b(\\d{1,2}):(\\d{2})(?:\\s*(am|pm|a\\.m\\.|p\\.m\\.))?(?:\\s*(之前|前))?"
        ) {
            if let h = Int(matchCapture(nsClause, match, group: 2) ?? ""),
               let m = Int(matchCapture(nsClause, match, group: 3) ?? ""),
               (0...23).contains(h), (0...59).contains(m) {
                var hour = h
                if let ampm = matchCapture(nsClause, match, group: 4)?.lowercased() {
                    if ampm.hasPrefix("p") && hour < 12 { hour += 12 }
                    if ampm.hasPrefix("a") && hour == 12 { hour = 0 }
                } else if info.isPMBias && hour >= 1 && hour <= 11 {
                    hour += 12
                }
                info.hour = hour
                info.minute = m
                if let prep = matchCapture(nsClause, match, group: 1)?.lowercased(),
                   ["by", "before", "due"].contains(prep) {
                    info.isDeadline = true
                }
                if matchCapture(nsClause, match, group: 5) != nil {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        } else if let match = firstMatch(
            in: clause,
            pattern: "(?i)(?:\\b(by|before|due|at)\\s+)?\\b(\\d{1,2})\\s*(am|pm|a\\.m\\.|p\\.m\\.)\\b"
        ) {
            if let h = Int(matchCapture(nsClause, match, group: 2) ?? ""),
               let ampm = matchCapture(nsClause, match, group: 3)?.lowercased(),
               (1...12).contains(h) {
                var hour = h
                if ampm.hasPrefix("p") && hour < 12 { hour += 12 }
                if ampm.hasPrefix("a") && hour == 12 { hour = 0 }
                info.hour = hour
                info.minute = 0
                if let prep = matchCapture(nsClause, match, group: 1)?.lowercased(),
                   ["by", "before", "due"].contains(prep) {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        } else if let match = firstMatch(
            in: clause,
            pattern: "([零一二两三四五六七八九十\\d]{1,3})\\s*[点時时](?:\\s*(半|一刻|三刻|([零一二三四五六七八九十\\d]{1,3})分?))?(?:\\s*(之前|前|截止))?"
        ) {
            if let hStr = matchCapture(nsClause, match, group: 1),
               let parsedHour = parseFlexibleNumber(hStr),
               (0...23).contains(parsedHour) {
                var hour = parsedHour
                if info.isPMBias && hour >= 1 && hour <= 11 {
                    hour += 12
                }
                var minute = 0
                if let minToken = matchCapture(nsClause, match, group: 2) {
                    if minToken == "半" {
                        minute = 30
                    } else if minToken == "一刻" {
                        minute = 15
                    } else if minToken == "三刻" {
                        minute = 45
                    } else if let minDigits = matchCapture(nsClause, match, group: 3),
                              let m = parseFlexibleNumber(minDigits),
                              (0...59).contains(m) {
                        minute = m
                    }
                }
                info.hour = hour
                info.minute = minute
                if matchCapture(nsClause, match, group: 4) != nil {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        }

        // 7. Standalone deadline/reminder cue words ("deadline", "remind me to", "提醒我")
        let fillerPatterns = [
            "(?i)\\bremind\\s+me\\s+(?:to\\s+)?",
            "记得\\s*",
            "提醒(?:我)?\\s*",
            "(?i)\\bdeadline\\s*:?\\s*"
        ]
        for pattern in fillerPatterns {
            if let match = firstMatch(in: clause, pattern: pattern) {
                if pattern.contains("deadline") {
                    info.isDeadline = true
                }
                info.strippedRanges.append(match.range)
            }
        }

        // Apply inherited day if clause has a time signal (hour or period) but no explicit day
        if info.explicitDay == nil && info.offsetDate == nil && (info.hour != nil || info.periodDefaultHour != nil) {
            info.resolvedDay = inheritedDay ?? calendar.startOfDay(for: referenceDate)
        } else {
            info.resolvedDay = info.explicitDay
        }

        // Build clean title by removing matched time ranges
        var keepFlags = Array(repeating: true, count: fullRange.length)
        for range in info.strippedRanges {
            let start = max(0, range.location)
            let end = min(fullRange.length, range.location + range.length)
            if start < end {
                for i in start..<end {
                    keepFlags[i] = false
                }
            }
        }

        var titleChars = ""
        for idx in 0..<fullRange.length where keepFlags[idx] {
            let scalar = nsClause.character(at: idx)
            if let uScalar = UnicodeScalar(scalar) {
                titleChars.append(Character(uScalar))
            }
        }

        let cleaned = sanitizeTitle(titleChars)
        return (info, cleaned)
    }

    private static func resolveDate(
        from info: ExtractedTimeInfo,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        if let offsetDate = info.offsetDate {
            return offsetDate
        }
        guard let day = info.resolvedDay else {
            return nil
        }

        let targetHour: Int
        let targetMinute: Int
        if let h = info.hour {
            targetHour = h
            targetMinute = info.minute ?? 0
        } else if let p = info.periodDefaultHour {
            targetHour = p
            targetMinute = 0
        } else if info.isDeadline {
            let candidateEighteen = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
            if candidateEighteen > referenceDate {
                targetHour = 18
                targetMinute = 0
            } else {
                targetHour = 23
                targetMinute = 59
            }
        } else {
            let morningNine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            if morningNine > referenceDate {
                targetHour = 9
                targetMinute = 0
            } else {
                let nextHour = calendar.date(byAdding: .hour, value: 1, to: referenceDate) ?? referenceDate
                return nextHour
            }
        }

        guard var candidate = calendar.date(bySettingHour: targetHour, minute: targetMinute, second: 0, of: day) else {
            return day
        }

        // If no explicit day was given and the time already passed today, bump to tomorrow only when user didn't inherit a day
        if info.explicitDay == nil && info.resolvedDay == calendar.startOfDay(for: referenceDate) && candidate < referenceDate {
            // If AM/PM wasn't explicit and adding 12h lands later today, prefer PM (e.g. "3点开会" at 10am -> 15:00)
            if !info.isAMBias, !info.isPMBias, targetHour >= 1 && targetHour <= 11 {
                if let pmCandidate = calendar.date(bySettingHour: targetHour + 12, minute: targetMinute, second: 0, of: day),
                   pmCandidate >= referenceDate {
                    candidate = pmCandidate
                }
            }
        }

        return candidate
    }

    private static func sanitizeTitle(_ raw: String) -> String {
        var s = regexReplacing(raw, pattern: "\\s{2,}", with: " ")
        s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，;；:：-—·")))

        // Trim dangling leading prepositions left after stripping dates (e.g. "在 ... 开会" -> "在 开会" -> "开会")
        s = regexReplacing(s, pattern: "^(?:在|于|到)\\s+", with: "")
        s = regexReplacing(s, pattern: "(?i)^(?:to|on|at|by|for)\\s+", with: "")
        s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，;；:：-—·")))

        if let first = s.first, first.isASCII, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }

    // MARK: - Priority & Tag Heuristics

    private static func detectPriority(in text: String) -> TodoPriority {
        let lower = text.lowercased()
        let highKeywords = ["紧急", "重要", "必须", "马上", "立刻", "加急", "urgent", "asap", "high priority", "important", "critical", "!!!"]
        if highKeywords.contains(where: { lower.contains($0) }) {
            return .high
        }
        let lowKeywords = ["有空", "顺便", "不急", "low priority", "someday", "whenever"]
        if lowKeywords.contains(where: { lower.contains($0) }) {
            return .low
        }
        return .normal
    }

    private static func detectTag(in text: String) -> TodoTag {
        let lower = text.lowercased()
        let workKeywords = ["开会", "报告", "客户", "项目", "代码", "上线", "周报", "合同", "需求", "汇报", "meeting", "client", "report", "deploy", "project", "email", "pr"]
        if workKeywords.contains(where: { lower.contains($0) }) {
            return .work
        }
        let studyKeywords = ["学习", "复习", "读书", "论文", "作业", "考试", "课程", "单词", "study", "exam", "homework", "course", "lecture", "read"]
        if studyKeywords.contains(where: { lower.contains($0) }) {
            return .study
        }
        let lifeKeywords = ["买菜", "超市", "快递", "做饭", "健身", "医院", "缴费", "打扫", "买", "grocery", "gym", "doctor", "dentist", "clean", "laundry", "dinner"]
        if lifeKeywords.contains(where: { lower.contains($0) }) {
            return .life
        }
        let ideaKeywords = ["灵感", "想法", "点子", "脑暴", "prototype", "idea", "brainstorm"]
        if ideaKeywords.contains(where: { lower.contains($0) }) {
            return .idea
        }
        return .none
    }

    // MARK: - Number & Weekday Utilities

    private static func resolveWeekday(
        targetIso: Int,
        forceNextWeek: Bool,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        let startToday = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: referenceDate) // Sun=1, Mon=2...Sat=7
        let currentIso = ((weekday + 5) % 7) + 1 // Mon=1...Sun=7

        let delta: Int
        if forceNextWeek {
            let daysToNextMonday = 8 - currentIso
            delta = daysToNextMonday + (targetIso - 1)
        } else {
            delta = (targetIso - currentIso + 7) % 7
        }
        return calendar.date(byAdding: .day, value: delta, to: startToday) ?? startToday
    }

    private static func parseChineseWeekday(_ token: String) -> Int? {
        switch token {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日", "天": return 7
        default: return nil
        }
    }

    private static func parseEnglishWeekday(_ token: String) -> Int? {
        switch token.lowercased() {
        case "monday", "mon": return 1
        case "tuesday", "tue": return 2
        case "wednesday", "wed": return 3
        case "thursday", "thu": return 4
        case "friday", "fri": return 5
        case "saturday", "sat": return 6
        case "sunday", "sun": return 7
        default: return nil
        }
    }

    private static func parseFlexibleNumber(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ascii = Int(trimmed) {
            return ascii
        }
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if trimmed == "十" { return 10 }
        if trimmed.count == 1, let ch = trimmed.first, let val = digits[ch] {
            return val
        }
        if trimmed.contains("十") {
            let parts = trimmed.split(separator: "十", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let tens: Int
            if parts[0].isEmpty {
                tens = 1
            } else if parts[0].count == 1, let ch = parts[0].first, let v = digits[ch] {
                tens = v
            } else {
                return nil
            }
            let ones: Int
            if parts[1].isEmpty {
                ones = 0
            } else if parts[1].count == 1, let ch = parts[1].first, let v = digits[ch] {
                ones = v
            } else {
                return nil
            }
            return tens * 10 + ones
        }
        return nil
    }

    // MARK: - Regex Helpers

    private static func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func matchCapture(_ text: NSString, _ match: NSTextCheckingResult, group: Int) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let r = match.range(at: group)
        guard r.location != NSNotFound, r.length > 0 else { return nil }
        return text.substring(with: r)
    }

    private static func regexReplacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
