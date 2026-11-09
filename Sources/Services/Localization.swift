import Foundation

/// Traduce un testo italiano nella lingua scelta (le chiavi di Localizable.strings sono in italiano).
func L(_ text: String) -> String {
    NSLocalizedString(text, comment: "")
}

enum AppLanguage {
    static let options: [(code: String, name: String)] = [
        ("it", "Italiano"),
        ("en", "English"),
        ("es", "Español"),
        ("pt-PT", "Português"),
        ("pt-BR", "Português (Brasil)")
    ]

    /// Lingua attualmente in uso dall'app.
    static var current: String {
        if let chosen = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first {
            if let match = options.first(where: { chosen == $0.code }) { return match.code }
            if chosen.hasPrefix("pt") { return chosen.contains("BR") ? "pt-BR" : "pt-PT" }
            if let match = options.first(where: { chosen.hasPrefix($0.code) }) { return match.code }
        }
        return Bundle.main.preferredLocalizations.first ?? "it"
    }

    static func set(_ code: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}
