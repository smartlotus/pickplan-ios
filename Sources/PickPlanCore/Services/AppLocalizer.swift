import Foundation

/// Supported UI languages for PickPlan.
public enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case zh
    case en

    public var id: String { rawValue }

    /// Native display name for language pickers.
    public var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }

    /// Resolves a stored language code (e.g. `"zh-Hans"`, `"en-US"`) into `AppLanguage`.
    public static func from(code: String) -> AppLanguage {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("en") {
            return .en
        }
        return .zh
    }
}

/// Centralized lightweight bilingual localization helper.
public enum AppLocalizer {
    /// Returns the localized string matching `language`.
    public static func t(zh: String, en: String, language: AppLanguage) -> String {
        switch language {
        case .zh: return zh
        case .en: return en
        }
    }

    /// Formats a byte count cleanly across locales.
    public static func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }
}
