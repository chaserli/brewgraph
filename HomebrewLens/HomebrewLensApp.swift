import SwiftUI

@main
struct HomebrewLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var homebrewManager = HomebrewManager()
    @AppStorage(AppPreferenceKey.estimateFormulaSizes) private var estimateFormulaSizes = true
    @AppStorage(AppPreferenceKey.estimateCaskSizes) private var estimateCaskSizes = true
    @AppStorage(AppPreferenceKey.runCleanupDryRun) private var runCleanupDryRun = true
    @AppStorage(AppPreferenceKey.runBrewDoctor) private var runBrewDoctor = false
    @AppStorage(AppPreferenceKey.appLanguage) private var appLanguageRaw = AppLanguage.english.rawValue

    var body: some Scene {
        WindowGroup("BrewGraph") {
            MainWindow(manager: homebrewManager)
                .environment(\.locale, appLocale)
                .frame(minWidth: 1050, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BrewGraph") {
                    NSApp.sendAction(#selector(AppDelegate.showAboutWindow), to: appDelegate, from: nil)
                }
            }

            CommandMenu("Homebrew") {
                Button("Refresh Homebrew") {
                    Task { await homebrewManager.refresh(options: scanOptions) }
                }
                .keyboardShortcut("r")
                .disabled(homebrewManager.isRefreshing)
            }
        }

        Settings {
            SettingsView()
                .environment(\.locale, appLocale)
        }
    }

    private var appLocale: Locale {
        Locale(identifier: AppLanguage(rawValue: appLanguageRaw)?.localeCode ?? AppLanguage.english.localeCode)
    }

    private var scanOptions: ScanOptions {
        ScanOptions(
            estimateFormulaSizes: estimateFormulaSizes,
            estimateCaskSizes: estimateCaskSizes,
            runCleanupDryRun: runCleanupDryRun,
            runBrewDoctor: runBrewDoctor
        )
    }
}
