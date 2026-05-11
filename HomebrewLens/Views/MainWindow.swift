import SwiftUI

struct MainWindow: View {
    @ObservedObject var manager: HomebrewManager
    @AppStorage(AppPreferenceKey.scanOnLaunch) private var scanOnLaunch = true
    @AppStorage(AppPreferenceKey.estimateFormulaSizes) private var estimateFormulaSizes = true
    @AppStorage(AppPreferenceKey.estimateCaskSizes) private var estimateCaskSizes = true
    @AppStorage(AppPreferenceKey.runCleanupDryRun) private var runCleanupDryRun = true
    @AppStorage(AppPreferenceKey.runBrewDoctor) private var runBrewDoctor = false
    @AppStorage(AppPreferenceKey.localGraphDepth) private var localDepth = 1
    @AppStorage(AppPreferenceKey.appLanguage) private var appLanguageRaw = AppLanguage.english.rawValue
    @State private var currentGraphMode: GraphMode

    init(manager: HomebrewManager) {
        self.manager = manager
        let rawDefault = UserDefaults.standard.string(forKey: AppPreferenceKey.defaultGraphMode)
            ?? GraphMode.fullGraph.rawValue
        _currentGraphMode = State(initialValue: GraphMode(rawValue: rawDefault) ?? .fullGraph)
    }

    var body: some View {
        NavigationSplitView {
            PackageSidebar(manager: manager, refreshDuration: manager.lastRefreshDuration)
                .navigationSplitViewColumnWidth(
                    min: 260,
                    ideal: AppTheme.sidebarWidth,
                    max: 340
                )
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GraphWorkspace(
                        mode: graphModeBinding,
                        localDepth: localDepthBinding,
                        selectedPackageID: $manager.selectedPackageID,
                        state: manager.state,
                        snapshot: manager.snapshot,
                        selectedPackage: manager.selectedPackage
                    )

                    if let package = manager.selectedPackage {
                        Divider()
                            .transition(.move(edge: .trailing))
                        PackageInspector(package: package, snapshot: manager.snapshot, onClose: {
                            withAnimation(.snappy(duration: 0.2)) {
                                manager.selectedPackageID = nil
                            }
                        }, onSelectPackage: { id in
                            manager.selectedPackageID = id
                        })
                        .frame(width: AppTheme.inspectorWidth)
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.snappy(duration: 0.2), value: manager.selectedPackageID)

                DiscoveryStatusBar(
                    state: manager.state,
                    refreshDuration: manager.lastRefreshDuration
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
                    Text("BrewGraph")
                        .font(.headline)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    toggleLanguage()
                } label: {
                    Text(nextLanguageButtonTitle)
                        .font(.caption.weight(.semibold))
                }
                .help(nextLanguageHelp)

                Button {
                    Task { await manager.refresh(options: scanOptions) }
                } label: {
                    if manager.isRefreshing {
                        Label("Scanning", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Run read-only Homebrew scan")
                .disabled(manager.isRefreshing)
            }
        }
        .task {
            guard scanOnLaunch else {
                return
            }
            await manager.refreshIfNeeded(options: scanOptions)
        }
    }

    private var scanOptions: ScanOptions {
        ScanOptions(
            estimateFormulaSizes: estimateFormulaSizes,
            estimateCaskSizes: estimateCaskSizes,
            runCleanupDryRun: runCleanupDryRun,
            runBrewDoctor: runBrewDoctor
        )
    }

    private var graphModeBinding: Binding<GraphMode> {
        Binding {
            currentGraphMode
        } set: { mode in
            currentGraphMode = mode
        }
    }

    private var localDepthBinding: Binding<Int> {
        Binding {
            min(max(localDepth, 1), 3)
        } set: { value in
            localDepth = min(max(value, 1), 3)
        }
    }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    private var nextLanguage: AppLanguage {
        currentLanguage == .chinese ? .english : .chinese
    }

    private var nextLanguageButtonTitle: String {
        switch nextLanguage {
        case .english:
            "EN"
        case .chinese:
            "中"
        }
    }

    private var nextLanguageHelp: LocalizedStringKey {
        switch nextLanguage {
        case .english:
            "Switch to English"
        case .chinese:
            "Switch to Chinese"
        }
    }

    private func toggleLanguage() {
        appLanguageRaw = nextLanguage.rawValue
    }
}

#Preview {
    MainWindow(manager: HomebrewManager())
        .environment(\.locale, Locale(identifier: AppLanguage.english.localeCode))
}
