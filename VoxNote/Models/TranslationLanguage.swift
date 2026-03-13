import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case disabled    = "disabled"
    case english     = "en"
    case japanese    = "ja"
    case french      = "fr"
    case chinese     = "zh"
    case spanish     = "es"
    case german      = "de"
    case korean      = "ko"
    case portuguese  = "pt"
    case italian     = "it"
    case russian     = "ru"
    case arabic      = "ar"

    var id: String { rawValue }

    /// Used for target-language pickers ("Disabled" = off).
    var displayName: String {
        switch self {
        case .disabled:   return "Disabled"
        case .english:    return "English"
        case .japanese:   return "Japanese"
        case .french:     return "French"
        case .chinese:    return "Chinese (Simplified)"
        case .spanish:    return "Spanish"
        case .german:     return "German"
        case .korean:     return "Korean"
        case .portuguese: return "Portuguese"
        case .italian:    return "Italian"
        case .russian:    return "Russian"
        case .arabic:     return "Arabic"
        }
    }

    /// Used for source-language pickers ("Auto" = let the framework detect).
    var sourceDisplayName: String {
        self == .disabled ? "Auto" : displayName
    }

    /// Maps to a `Locale.Language` for use with the Apple Translation framework.
    /// Returns `nil` for `.disabled` (auto-detect).
    var localeLanguage: Locale.Language? {
        switch self {
        case .disabled:   return nil
        case .english:    return Locale.Language(identifier: "en")
        case .japanese:   return Locale.Language(identifier: "ja")
        case .french:     return Locale.Language(identifier: "fr")
        case .chinese:    return Locale.Language(identifier: "zh-Hans")
        case .spanish:    return Locale.Language(identifier: "es")
        case .german:     return Locale.Language(identifier: "de")
        case .korean:     return Locale.Language(identifier: "ko")
        case .portuguese: return Locale.Language(identifier: "pt")
        case .italian:    return Locale.Language(identifier: "it")
        case .russian:    return Locale.Language(identifier: "ru")
        case .arabic:     return Locale.Language(identifier: "ar")
        }
    }
}
