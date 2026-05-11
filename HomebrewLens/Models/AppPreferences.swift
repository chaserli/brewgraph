import Foundation

enum AppPreferenceKey {
    static let scanOnLaunch = "scanOnLaunch"
    static let estimateFormulaSizes = "estimateFormulaSizes"
    static let estimateCaskSizes = "estimateCaskSizes"
    static let runCleanupDryRun = "runCleanupDryRun"
    static let runBrewDoctor = "runBrewDoctor"
    static let defaultGraphMode = "defaultGraphMode"
    static let localGraphDepth = "localGraphDepth"
    static let appLanguage = "appLanguage"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        }
    }

    var localeCode: String {
        rawValue
    }
}

struct ScanOptions: Equatable, Sendable {
    var estimateFormulaSizes: Bool
    var estimateCaskSizes: Bool
    var runCleanupDryRun: Bool
    var runBrewDoctor: Bool = false

    static let `default` = ScanOptions(
        estimateFormulaSizes: true,
        estimateCaskSizes: true,
        runCleanupDryRun: true
    )
}
