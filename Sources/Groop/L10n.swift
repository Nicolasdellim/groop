//
//  L10n.swift
//  Groop
//
//  English first, French as a localization. A droplet runs inside Droppy, so
//  Groop follows the Mac's first language: French
//  when it is French, English for any other.
//

import Foundation

enum Language {
    case english, french

    static let current: Language = {
        // The user's own language, not Droppy's: Droppy may ship in English only.
        let preferred = Locale.preferredLanguages.first ?? Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.lowercased().hasPrefix("fr") ? .french : .english
    }()
}

/// One whole sentence, in English and in French. Values go in as
/// interpolations, so each language keeps its own word order.
func L(_ english: String, _ french: String) -> String {
    Language.current == .french ? french : english
}
