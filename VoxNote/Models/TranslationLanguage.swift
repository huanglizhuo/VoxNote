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
    
    /// Short display name for compact UI
    var shortDisplayName: String {
        switch self {
        case .disabled: return "Off"
        case .english:  return "EN"
        case .japanese: return "JA"
        case .french:   return "FR"
        case .chinese:  return "ZH"
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
    
    /// All actual languages (excluding disabled)
    static var actualLanguages: [TranslationLanguage] {
        allCases.filter { $0 != .disabled }
    }
}

/// Represents source language configuration for translation
enum SourceLanguageMode: Codable, Equatable {
    case auto
    case single(TranslationLanguage)
    case multiple(Set<TranslationLanguage>)
    
    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .single(let lang):
            return lang.shortDisplayName
        case .multiple(let langs):
            if langs.isEmpty {
                return "Auto"
            }
            let sorted = langs.sorted { $0.rawValue < $1.rawValue }
            return sorted.map { $0.shortDisplayName }.joined(separator: "/")
        }
    }
    
    /// Returns the source locale for single language mode, nil otherwise
    var singleLocale: Locale.Language? {
        if case .single(let lang) = self {
            return lang.localeLanguage
        }
        return nil
    }
    
    /// Returns all selected languages for multiple mode
    var selectedLanguages: Set<TranslationLanguage> {
        switch self {
        case .auto:
            return []
        case .single(let lang):
            return [lang]
        case .multiple(let langs):
            return langs
        }
    }
}
