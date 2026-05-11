import Foundation

@MainActor
final class HomebrewManager: ObservableObject {
    @Published private(set) var state: HomebrewState = .idle
    @Published private(set) var lastRefreshDuration: TimeInterval?
    @Published var selectedPackageID: String?
    @Published var searchText = ""
    @Published var packageFilter: PackageFilter = .all
    @Published var packageSort: PackageSort = .name

    private let controller: HomebrewController
    private let scanner: BrewScanner

    init(
        controller: HomebrewController = HomebrewController(),
        scanner: BrewScanner = BrewScanner()
    ) {
        self.controller = controller
        self.scanner = scanner
    }

    var isRefreshing: Bool {
        if case .discovering = state {
            return true
        }
        if case .scanning = state {
            return true
        }
        return false
    }

    var snapshot: BrewSnapshot? {
        if case let .scanned(snapshot) = state {
            return snapshot
        }
        return nil
    }

    var selectedPackage: Package? {
        snapshot?.package(id: selectedPackageID)
    }

    var selectedFormulaName: String? {
        guard let selectedPackage, selectedPackage.kind == .formula else {
            return nil
        }
        return selectedPackage.name
    }

    var filteredPackages: [Package] {
        guard let snapshot else {
            return []
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var packages = snapshot.packages.filter { package in
            matchesFilter(package) && matchesSearch(package, query: query)
        }

        switch packageSort {
        case .name:
            packages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            packages.sort {
                if ($0.size ?? -1) == ($1.size ?? -1) {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return ($0.size ?? -1) > ($1.size ?? -1)
            }
        case .reverseUsers:
            packages.sort {
                if $0.reverseDependencies.count == $1.reverseDependencies.count {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.reverseDependencies.count > $1.reverseDependencies.count
            }
        case .directDeps:
            packages.sort {
                if $0.dependencies.count == $1.dependencies.count {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.dependencies.count > $1.dependencies.count
            }
        case .installedTime:
            packages.sort {
                switch ($0.installedAt, $1.installedAt) {
                case let (lhs?, rhs?):
                    return lhs > rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
        }

        return packages
    }

    func refreshIfNeeded(options: ScanOptions = .default) async {
        guard case .idle = state else {
            return
        }

        await refresh(options: options)
    }

    func refresh(options: ScanOptions = .default) async {
        state = .discovering
        lastRefreshDuration = nil
        let start = Date()

        do {
            let discovery = try await controller.discoverHomebrew()
            state = .scanning(discovery, "Starting read-only scan")
            let snapshot = try await scanner.scan(discovery: discovery, options: options) { [weak self] step in
                await MainActor.run {
                    self?.state = .scanning(discovery, step)
                }
            }
            lastRefreshDuration = Date().timeIntervalSince(start)
            state = .scanned(snapshot)

            if let selectedPackageID, snapshot.package(id: selectedPackageID) == nil {
                self.selectedPackageID = nil
            }
        } catch let error as BrewDiscoveryError {
            lastRefreshDuration = Date().timeIntervalSince(start)
            switch error {
            case let .notFound(attempts):
                state = .missing(attempts)
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            lastRefreshDuration = Date().timeIntervalSince(start)
            state = .failed(error.localizedDescription)
        }
    }

    private func matchesFilter(_ package: Package) -> Bool {
        switch packageFilter {
        case .all:
            true
        case .formulae:
            package.kind == .formula
        case .casks:
            package.kind == .cask
        case .requested:
            package.installReason == .requested
        case .leaves:
            package.isLeaf
        case .dependencies:
            package.installReason == .dependency
        case .externalTaps:
            package.isExternalTap
        case .unusedDependencies:
            package.isUnusedDependency
        case .outdated:
            package.outdated
        case .issues:
            package.deprecated || package.disabled || package.outdated
        }
    }

    private func matchesSearch(_ package: Package, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return package.name.localizedCaseInsensitiveContains(query)
            || package.description.localizedCaseInsensitiveContains(query)
            || package.tap?.localizedCaseInsensitiveContains(query) == true
    }
}
