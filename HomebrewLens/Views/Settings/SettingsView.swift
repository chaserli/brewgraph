import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferenceKey.scanOnLaunch) private var scanOnLaunch = true
    @AppStorage(AppPreferenceKey.estimateFormulaSizes) private var estimateFormulaSizes = true
    @AppStorage(AppPreferenceKey.estimateCaskSizes) private var estimateCaskSizes = true
    @AppStorage(AppPreferenceKey.runCleanupDryRun) private var runCleanupDryRun = true
    @AppStorage(AppPreferenceKey.runBrewDoctor) private var runBrewDoctor = false
    @AppStorage(AppPreferenceKey.defaultGraphMode) private var defaultGraphModeRaw = GraphMode.fullGraph.rawValue
    @AppStorage(AppPreferenceKey.localGraphDepth) private var localGraphDepth = 1
    @AppStorage(AppPreferenceKey.appLanguage) private var appLanguageRaw = AppLanguage.english.rawValue

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Scan on launch", isOn: $scanOnLaunch)
                Picker("Default view", selection: defaultGraphModeBinding) {
                    ForEach(GraphMode.allCases) { mode in
                        Label(LocalizedStringKey(mode.title), systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                Stepper("Local graph depth: \(localGraphDepth)", value: localDepthBinding, in: 1...3)
            }

            Section("Language") {
                Picker("App language", selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Scan") {
                Toggle("Estimate formula sizes", isOn: $estimateFormulaSizes)
                Toggle("Estimate cask app sizes", isOn: $estimateCaskSizes)
                Toggle("Run cleanup dry-run", isOn: $runCleanupDryRun)
                Toggle("Run brew doctor", isOn: $runBrewDoctor)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 460)
    }

    private var defaultGraphModeBinding: Binding<GraphMode> {
        Binding {
            GraphMode(rawValue: defaultGraphModeRaw) ?? .fullGraph
        } set: { mode in
            defaultGraphModeRaw = mode.rawValue
        }
    }

    private var localDepthBinding: Binding<Int> {
        Binding {
            min(max(localGraphDepth, 1), 3)
        } set: { value in
            localGraphDepth = min(max(value, 1), 3)
        }
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding {
            AppLanguage(rawValue: appLanguageRaw) ?? .english
        } set: { language in
            appLanguageRaw = language.rawValue
        }
    }
}
