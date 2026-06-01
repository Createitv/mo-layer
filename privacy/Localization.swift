import Foundation
import SwiftUI

enum L {
    private static var bundle: Bundle {
        guard let code = AppLanguage.current.bundleCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLanguage.current.locale, arguments: arguments)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese
    case german
    case french
    case korean
    case spanish

    static let storageKey = "app.language.preference"
    private static let englishDefaultMigrationKey = "app.language.english-default.migrated"

    var id: String { rawValue }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.english.rawValue) ?? .english
    }

    static func installDefaultLanguagePreference() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: storageKey)
        let hasMigrated = defaults.bool(forKey: englishDefaultMigrationKey)
        if stored == nil || (!hasMigrated && stored == AppLanguage.system.rawValue) {
            defaults.set(AppLanguage.english.rawValue, forKey: storageKey)
        }
        defaults.set(true, forKey: englishDefaultMigrationKey)
    }

    var title: String {
        switch self {
        case .system: L.string("Follow System")
        case .english: "English"
        case .simplifiedChinese: "Chinese (Simplified)"
        case .traditionalChinese: "繁體中文"
        case .japanese: "Japanese"
        case .german: "Deutsch"
        case .french: "French"
        case .korean: "Korean"
        case .spanish: "Spanish"
        }
    }

    var bundleCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .german: "de"
        case .french: "fr"
        case .korean: "ko"
        case .spanish: "es"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system: Locale.autoupdatingCurrent.identifier
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .german: "de"
        case .french: "fr"
        case .korean: "ko"
        case .spanish: "es"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.appearance.preference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L.string("Follow System")
        case .light: L.string("Light Mode")
        case .dark: L.string("Dark Mode")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsPreferenceRefreshToken: Hashable {
    let language: String
    let appearance: String
}

struct LanguagePickerSection: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue

    var body: some View {
        Section(L.string("Language")) {
            Picker(L.string("App Language"), selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            Text(L.string("Default follows your iPhone language and region. Choose a language here to override it inside the app."))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}
