import Foundation
import Translation
import NaturalLanguage

/// A service that handles translation with support for mixed source languages.
/// It detects the source language per-segment and uses the appropriate translation session.
@MainActor
final class SmartTranslationService: ObservableObject {
    
    struct TranslationResult {
        let id: UUID
        let sourceText: String
        let translatedText: String
        let detectedSourceLanguage: Locale.Language?
    }
    
    /// Result of language detection with probabilities
    struct LanguageDetectionResult {
        let dominantLanguage: TranslationLanguage?
        let hypotheses: [(language: TranslationLanguage, probability: Double)]
        let confidence: LanguageConfidence
        
        enum LanguageConfidence {
            case high      // > 0.8 probability for top language
            case medium    // 0.5-0.8 probability
            case low       // < 0.5 probability
            case uncertain // Can't determine
        }
    }
    
    /// Expected source languages - if empty, uses auto-detection
    var expectedSourceLanguages: Set<TranslationLanguage> = []
    
    /// Target language for translation
    var targetLanguage: TranslationLanguage = .disabled
    
    /// The language recognizer for detecting source languages
    private let languageRecognizer = NLLanguageRecognizer()
    
    /// Mapping from NLLanguage to TranslationLanguage
    private static let nlLanguageMapping: [NLLanguage: TranslationLanguage] = [
        .english: .english,
        .japanese: .japanese,
        .french: .french,
        .simplifiedChinese: .chinese,
        .traditionalChinese: .chinese
    ]
    
    /// Detects the language of the given text and returns probabilities.
    /// If expectedSourceLanguages is set, constrains detection to those languages.
    func detectLanguage(for text: String) -> LanguageDetectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LanguageDetectionResult(
                dominantLanguage: nil,
                hypotheses: [],
                confidence: .uncertain
            )
        }
        
        languageRecognizer.reset()
        
        // If we have expected languages, constrain the recognizer
        if !expectedSourceLanguages.isEmpty {
            let constraints: [NLLanguage] = expectedSourceLanguages.compactMap { lang in
                switch lang {
                case .english: return .english
                case .japanese: return .japanese
                case .french: return .french
                case .chinese: return .simplifiedChinese
                case .disabled: return nil
                }
            }
            languageRecognizer.languageConstraints = constraints
        }
        
        languageRecognizer.processString(trimmed)
        
        // Get hypotheses with probabilities (up to 5)
        let nlHypotheses = languageRecognizer.languageHypotheses(withMaximum: 5)
        
        // Convert to our format
        var hypotheses: [(language: TranslationLanguage, probability: Double)] = []
        for (nlLang, probability) in nlHypotheses {
            if let transLang = Self.nlLanguageMapping[nlLang] {
                // Check if this language is in our expected set (if set)
                if expectedSourceLanguages.isEmpty || expectedSourceLanguages.contains(transLang) {
                    hypotheses.append((transLang, probability))
                }
            }
        }
        
        // Sort by probability
        hypotheses.sort { $0.probability > $1.probability }
        
        // Determine confidence
        let confidence: LanguageDetectionResult.LanguageConfidence
        if let topProbability = hypotheses.first?.probability {
            if topProbability > 0.8 {
                confidence = .high
            } else if topProbability > 0.5 {
                confidence = .medium
            } else {
                confidence = .low
            }
        } else {
            confidence = .uncertain
        }
        
        return LanguageDetectionResult(
            dominantLanguage: hypotheses.first?.language,
            hypotheses: hypotheses,
            confidence: confidence
        )
    }
    
    /// Translates text using the appropriate session based on detected or specified source language.
    func translate(
        id: UUID,
        text: String,
        using session: TranslationSession
    ) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranslationResult(
                id: id,
                sourceText: text,
                translatedText: text,
                detectedSourceLanguage: nil
            )
        }
        
        let response = try await session.translate(trimmed)
        
        return TranslationResult(
            id: id,
            sourceText: text,
            translatedText: response.targetText,
            detectedSourceLanguage: response.sourceLanguage
        )
    }
    
    /// Creates a translation configuration based on expected source languages and detected language.
    /// - If single language is expected, uses that as source (avoids popup)
    /// - If multiple languages, detects per-segment and uses the detected language
    /// - If detection confidence is high, uses detected language (avoids popup)
    func makeConfiguration(for text: String? = nil) -> TranslationSession.Configuration? {
        guard let targetLocale = targetLanguage.localeLanguage else {
            return nil
        }
        
        let sourceLocale: Locale.Language?
        
        switch expectedSourceLanguages.count {
        case 0:
            // Auto-detect (may popup)
            sourceLocale = nil
        case 1:
            // Single language - use it directly to avoid popup
            sourceLocale = expectedSourceLanguages.first?.localeLanguage
        default:
            // Multiple languages - try to detect from text
            if let text = text {
                let detection = detectLanguage(for: text)
                if detection.confidence == .high || detection.confidence == .medium,
                   let detected = detection.dominantLanguage {
                    sourceLocale = detected.localeLanguage
                } else {
                    // Low confidence - use nil but system will likely popup
                    sourceLocale = nil
                }
            } else {
                sourceLocale = nil
            }
        }
        
        return TranslationSession.Configuration(source: sourceLocale, target: targetLocale)
    }
    
    /// Checks if the given text likely needs a popup for language selection.
    /// Returns true if we can't confidently determine the source language.
    func mightNeedLanguagePopup(for text: String) -> Bool {
        if expectedSourceLanguages.count == 1 {
            return false // Single language, no popup
        }
        
        let detection = detectLanguage(for: text)
        return detection.confidence != .high && detection.confidence != .medium
    }
}
