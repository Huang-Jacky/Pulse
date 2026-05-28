import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese
    case english

    static let userDefaultsKey = "pulse.appLanguage"

    var id: String { rawValue }

    var optionTitle: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    static var current: AppLanguage {
        if let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
           let language = AppLanguage(rawValue: rawValue) {
            return language
        }
        return .chinese
    }
}

enum AppText {
    static func localized(_ chinese: String, _ english: String, language: AppLanguage? = nil) -> String {
        switch language ?? AppLanguage.current {
        case .chinese:
            return chinese
        case .english:
            return english
        }
    }
}
