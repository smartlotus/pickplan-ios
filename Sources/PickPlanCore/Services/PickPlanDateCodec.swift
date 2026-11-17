import Foundation

/// Thread-safe ISO8601 and human-readable date/time codec supporting both standard
/// RFC3339 timestamps (`2026-11-17T18:00:00Z`) and Dart/Flutter `DateTime.toIso8601String()`
/// timestamps with fractional microseconds and no trailing timezone (`2026-09-10T12:30:00.123456`).
public enum PickPlanDateCodec {
    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private let isoFormatter: ISO8601DateFormatter
        private let isoFractionalFormatter: ISO8601DateFormatter
        private let displayFormatter: DateFormatter
        private let filenameFormatter: DateFormatter
        private let timeOnlyFormatter: DateFormatter
        private let monthDayTimeFormatter: DateFormatter

        init() {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            self.isoFormatter = iso

            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoFrac.timeZone = TimeZone(secondsFromGMT: 0)
            self.isoFractionalFormatter = isoFrac

            let display = DateFormatter()
            display.locale = Locale(identifier: "en_US_POSIX")
            display.dateFormat = "yyyy-MM-dd HH:mm"
            self.displayFormatter = display

            let filename = DateFormatter()
            filename.locale = Locale(identifier: "en_US_POSIX")
            filename.timeZone = TimeZone(secondsFromGMT: 0)
            filename.dateFormat = "yyyyMMdd-HHmmss"
            self.filenameFormatter = filename

            let timeOnly = DateFormatter()
            timeOnly.locale = Locale(identifier: "en_US_POSIX")
            timeOnly.dateFormat = "HH:mm"
            self.timeOnlyFormatter = timeOnly

            let monthDayTime = DateFormatter()
            monthDayTime.locale = Locale(identifier: "en_US_POSIX")
            monthDayTime.dateFormat = "MM-dd HH:mm"
            self.monthDayTimeFormatter = monthDayTime
        }

        func formatISO8601(_ date: Date, fractionalSeconds: Bool) -> String {
            lock.lock()
            defer { lock.unlock() }
            if fractionalSeconds {
                return isoFractionalFormatter.string(from: date)
            }
            return isoFormatter.string(from: date)
        }

        func formatDisplay(_ date: Date, timeZone: TimeZone) -> String {
            lock.lock()
            defer { lock.unlock() }
            displayFormatter.timeZone = timeZone
            return displayFormatter.string(from: date)
        }

        func formatFilename(_ date: Date) -> String {
            lock.lock()
            defer { lock.unlock() }
            return filenameFormatter.string(from: date)
        }

        func formatTimeOnly(_ date: Date, timeZone: TimeZone) -> String {
            lock.lock()
            defer { lock.unlock() }
            timeOnlyFormatter.timeZone = timeZone
            return timeOnlyFormatter.string(from: date)
        }

        func formatMonthDayTime(_ date: Date, timeZone: TimeZone) -> String {
            lock.lock()
            defer { lock.unlock() }
            monthDayTimeFormatter.timeZone = timeZone
            return monthDayTimeFormatter.string(from: date)
        }
    }

    private static let cache = FormatterCache()

    /// Parses ISO8601 strings with or without `Z` / numeric timezone offset,
    /// and with or without fractional seconds (1–9 digits, e.g. Dart microseconds).
    public static func parseISO8601(_ rawString: String) -> Date? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let datePart: Substring
        let timeAndZonePart: Substring?

        if let sepIndex = trimmed.firstIndex(where: { $0 == "T" || $0 == "t" || $0 == " " }) {
            datePart = trimmed[..<sepIndex]
            let afterSep = trimmed.index(after: sepIndex)
            timeAndZonePart = afterSep < trimmed.endIndex ? trimmed[afterSep...] : nil
        } else {
            datePart = trimmed[...]
            timeAndZonePart = nil
        }

        let dateComponents = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard dateComponents.count == 3,
              dateComponents[0].count == 4,
              let year = Int(dateComponents[0]),
              let month = Int(dateComponents[1]), (1...12).contains(month),
              let day = Int(dateComponents[2]), (1...31).contains(day)
        else {
            return nil
        }

        var gregorian = Calendar(identifier: .gregorian)
        var resolvedTimeZone = TimeZone.current
        var hour = 0
        var minute = 0
        var second = 0
        var fractionalSeconds = 0.0

        if let rawTimeZonePart = timeAndZonePart, !rawTimeZonePart.isEmpty {
            var timeBody = rawTimeZonePart

            if timeBody.hasSuffix("Z") || timeBody.hasSuffix("z") {
                resolvedTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
                timeBody = timeBody.dropLast()
            } else if let tzIndex = timeBody.lastIndex(where: { $0 == "+" || $0 == "-" }) {
                let sign = timeBody[tzIndex] == "-" ? -1 : 1
                let offsetRaw = timeBody[timeBody.index(after: tzIndex)...]
                guard let offsetSeconds = parseTimezoneOffset(offsetRaw) else {
                    return nil
                }
                guard let tz = TimeZone(secondsFromGMT: sign * offsetSeconds) else {
                    return nil
                }
                resolvedTimeZone = tz
                timeBody = timeBody[..<tzIndex]
            }

            if let dotIndex = timeBody.firstIndex(of: ".") {
                let fracPart = timeBody[timeBody.index(after: dotIndex)...]
                guard !fracPart.isEmpty, fracPart.allSatisfy(\.isASCII), fracPart.allSatisfy(\.isNumber) else {
                    return nil
                }
                let cappedFrac = String(fracPart.prefix(9))
                fractionalSeconds = Double("0." + cappedFrac) ?? 0.0
                timeBody = timeBody[..<dotIndex]
            }

            let clockParts = timeBody.split(separator: ":", omittingEmptySubsequences: false)
            guard clockParts.count == 2 || clockParts.count == 3,
                  let parsedHour = Int(clockParts[0]), (0...23).contains(parsedHour),
                  let parsedMinute = Int(clockParts[1]), (0...59).contains(parsedMinute)
            else {
                return nil
            }
            let parsedSecond: Int
            if clockParts.count == 3 {
                guard let s = Int(clockParts[2]), (0...59).contains(s) else {
                    return nil
                }
                parsedSecond = s
            } else {
                parsedSecond = 0
            }

            hour = parsedHour
            minute = parsedMinute
            second = parsedSecond
        }

        gregorian.timeZone = resolvedTimeZone
        var comps = DateComponents()
        comps.calendar = gregorian
        comps.timeZone = resolvedTimeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second

        guard comps.isValidDate(in: gregorian), let baseDate = gregorian.date(from: comps) else {
            return nil
        }
        return fractionalSeconds == 0 ? baseDate : baseDate.addingTimeInterval(fractionalSeconds)
    }

    private static func parseTimezoneOffset(_ offset: Substring) -> Int? {
        let digitsOnly = offset.filter { $0 != ":" }
        guard digitsOnly.allSatisfy(\.isASCII), digitsOnly.allSatisfy(\.isNumber) else {
            return nil
        }
        let hh: Int
        let mm: Int
        switch digitsOnly.count {
        case 2:
            guard let h = Int(digitsOnly) else { return nil }
            hh = h
            mm = 0
        case 4:
            let hSlice = digitsOnly.prefix(2)
            let mSlice = digitsOnly.dropFirst(2)
            guard let h = Int(hSlice), let m = Int(mSlice) else { return nil }
            hh = h
            mm = m
        default:
            return nil
        }
        guard (0...18).contains(hh), (0...59).contains(mm) else { return nil }
        return hh * 3600 + mm * 60
    }

    /// Formats a `Date` as a UTC ISO8601 string (`2026-11-17T18:00:00Z`).
    public static func formatISO8601(_ date: Date, fractionalSeconds: Bool = false) -> String {
        cache.formatISO8601(date, fractionalSeconds: fractionalSeconds)
    }

    /// Formats a `Date` as `yyyy-MM-dd HH:mm`.
    public static func formatDisplayDateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        cache.formatDisplay(date, timeZone: timeZone)
    }

    /// Formats a `Date` compactly (`今天 15:00`, `Tomorrow 09:00`, or `MM-dd HH:mm`).
    public static func formatShortDateTime(
        _ date: Date,
        language: AppLanguage = .zh,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let timeStr = cache.formatTimeOnly(date, timeZone: calendar.timeZone)
        let startToday = calendar.startOfDay(for: now)
        guard let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday),
              let startDayAfter = calendar.date(byAdding: .day, value: 2, to: startToday),
              let startYesterday = calendar.date(byAdding: .day, value: -1, to: startToday)
        else {
            return cache.formatMonthDayTime(date, timeZone: calendar.timeZone)
        }

        if date >= startToday && date < startTomorrow {
            return "\(AppLocalizer.t(zh: "今天", en: "Today", language: language)) \(timeStr)"
        } else if date >= startTomorrow && date < startDayAfter {
            return "\(AppLocalizer.t(zh: "明天", en: "Tomorrow", language: language)) \(timeStr)"
        } else if date >= startYesterday && date < startToday {
            return "\(AppLocalizer.t(zh: "昨天", en: "Yesterday", language: language)) \(timeStr)"
        } else {
            return cache.formatMonthDayTime(date, timeZone: calendar.timeZone)
        }
    }

    /// Formats a UTC timestamp suitable for snapshot filenames (`yyyyMMdd-HHmmss`).
    public static func formatTimestampForFilename(_ date: Date) -> String {
        cache.formatFilename(date)
    }

    /// Decodes a `Date` from either an ISO8601 string or a numeric timestamp fallback.
    public static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            if let parsed = parseISO8601(stringValue) {
                return parsed
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date string: \(stringValue)"
            )
        }
        if let numericSeconds = try? container.decode(Double.self) {
            return Date(timeIntervalSinceReferenceDate: numericSeconds)
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO8601 string or numeric timestamp for Date"
        )
    }

    /// Decodes an optional `Date` field from a keyed container using ISO8601 string or Date fallback.
    public static func decodeDateIfPresent<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) {
            return nil
        }
        if let rawString = try? container.decode(String.self, forKey: key) {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            if let parsed = parseISO8601(trimmed) {
                return parsed
            }
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid date string '\(rawString)' for key \(key.stringValue)"
            )
        }
        return try container.decode(Date.self, forKey: key)
    }
}
