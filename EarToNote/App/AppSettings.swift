import Foundation

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AppSettings {
    static let matchThresholdKey = "speakerMatchThreshold"
    static let localeKey = "transcriptionLocale"

    static let defaultMatchThreshold = 0.65
    static let matchThresholdRange: ClosedRange<Double> = 0.40...0.90
    static let defaultLocaleIdentifier = "tr-TR"
    static let minimumSpeechForVoiceprint = 3.0

    static let languages: [LanguageOption] = [
        LanguageOption(id: "tr-TR", name: "Türkçe"),
        LanguageOption(id: "en-US", name: "English (US)"),
        LanguageOption(id: "en-GB", name: "English (UK)"),
        LanguageOption(id: "de-DE", name: "Deutsch"),
        LanguageOption(id: "fr-FR", name: "Français"),
    ]

    static var matchThreshold: Double {
        let stored = UserDefaults.standard.object(forKey: matchThresholdKey) as? Double ?? defaultMatchThreshold
        return min(max(stored, matchThresholdRange.lowerBound), matchThresholdRange.upperBound)
    }

    static var localeIdentifier: String {
        UserDefaults.standard.string(forKey: localeKey) ?? defaultLocaleIdentifier
    }
}
