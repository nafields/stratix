//
//  SupportedGameLanguage.swift
//  StratixModels
//

import Foundation

/// Supported xCloud preferred game language values.
public enum SupportedGameLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemDefault = "system"
    case enUS = "en-US"
    case ruRU = "ru-RU"
    case deDE = "de-DE"
    case frFR = "fr-FR"
    case esES = "es-ES"
    case ptBR = "pt-BR"
    case jaJP = "ja-JP"
    case koKR = "ko-KR"
    case zhCN = "zh-CN"
    case itIT = "it-IT"
    case plPL = "pl-PL"
    case trTR = "tr-TR"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemDefault: return "System Default (Account Region)"
        case .enUS: return "English (United States)"
        case .ruRU: return "Russian"
        case .deDE: return "German"
        case .frFR: return "French"
        case .esES: return "Spanish (Spain)"
        case .ptBR: return "Portuguese (Brazil)"
        case .jaJP: return "Japanese"
        case .koKR: return "Korean"
        case .zhCN: return "Chinese (Simplified)"
        case .itIT: return "Italian"
        case .plPL: return "Polish"
        case .trTR: return "Turkish"
        }
    }

    public var localeCode: String {
        self == .systemDefault ? "en-US" : rawValue
    }
}