import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case disabled = "disabled"
    case english  = "en"
    case japanese = "ja"
    case french   = "fr"
    case chinese  = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .english:  return "English"
        case .japanese: return "Japanese"
        case .french:   return "French"
        case .chinese:  return "Chinese"
        }
    }

    /// Maps to a `Locale.Language` for use with the Apple Translation framework.
    /// Returns `nil` for `.disabled`.
    var localeLanguage: Locale.Language? {
        switch self {
        case .disabled:  return nil
        case .english:   return Locale.Language(identifier: "en")
        case .japanese:  return Locale.Language(identifier: "ja")
        case .french:    return Locale.Language(identifier: "fr")
        case .chinese:   return Locale.Language(identifier: "zh-Hans")
        }
    }
}
