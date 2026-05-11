import Foundation

struct BrewSnapshot: Sendable, Equatable {
    let brewPath: URL
    let brewPrefix: URL
    let packages: [Package]
    let formulae: [String]
    let casks: [String]
    let deps: [String: [String]]
    let reverseDeps: [String: [String]]
    let edges: [DependencyEdge]
    let leaves: Set<String>
    let cleanupDryRun: CleanupSummary
    let summary: BrewSummary
    let scanDuration: Duration
    let warnings: [String]
    var brewDoctorWarnings: [String] = []
    private let packageIndexByID: [String: Package]
    private let formulaIndexByName: [String: Package]

    init(
        brewPath: URL,
        brewPrefix: URL,
        packages: [Package],
        formulae: [String],
        casks: [String],
        deps: [String: [String]],
        reverseDeps: [String: [String]],
        edges: [DependencyEdge],
        leaves: Set<String>,
        cleanupDryRun: CleanupSummary,
        summary: BrewSummary,
        scanDuration: Duration,
        warnings: [String],
        brewDoctorWarnings: [String] = []
    ) {
        self.brewPath = brewPath
        self.brewPrefix = brewPrefix
        self.packages = packages
        self.formulae = formulae
        self.casks = casks
        self.deps = deps
        self.reverseDeps = reverseDeps
        self.edges = edges
        self.leaves = leaves
        self.cleanupDryRun = cleanupDryRun
        self.summary = summary
        self.scanDuration = scanDuration
        self.warnings = warnings
        self.brewDoctorWarnings = brewDoctorWarnings
        self.packageIndexByID = packages.reduce(into: [:]) { result, package in
            result[package.id] = package
        }
        self.formulaIndexByName = packages.reduce(into: [:]) { result, package in
            guard package.kind == .formula else {
                return
            }
            result[package.name] = package
        }
    }

    func package(id: String?) -> Package? {
        guard let id else {
            return nil
        }

        return packageIndexByID[id]
    }

    func package(named name: String) -> Package? {
        formulaIndexByName[name]
    }

    var requestedPackageCount: Int {
        packages.filter { $0.installReason == .requested }.count
    }

    var dependencyOnlyPackageCount: Int {
        packages.filter { $0.installReason == .dependency }.count
    }

    var externalTapPackageCount: Int {
        packages.filter(\.isExternalTap).count
    }

    var classifiedDoctorWarnings: [ClassifiedDoctorWarning] {
        brewDoctorWarnings.map { ClassifiedDoctorWarning(raw: $0, category: DoctorWarningCategory.classify($0)) }
    }

    var doctorCategoryCounts: [DoctorWarningCategory: Int] {
        Dictionary(grouping: classifiedDoctorWarnings, by: \.category).mapValues(\.count)
    }

    var tapSummaries: [TapSummary] {
        Dictionary(grouping: packages, by: \.tapDisplayName)
            .map { tap, packages in
                TapSummary(
                    name: tap,
                    packageCount: packages.count,
                    formulaCount: packages.filter { $0.kind == .formula }.count,
                    caskCount: packages.filter { $0.kind == .cask }.count,
                    isExternal: !["homebrew/core", "homebrew/cask", "unknown"].contains(tap)
                )
            }
            .sorted { lhs, rhs in
                if lhs.packageCount == rhs.packageCount {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.packageCount > rhs.packageCount
            }
    }
}

struct TapSummary: Identifiable, Hashable, Sendable {
    let name: String
    let packageCount: Int
    let formulaCount: Int
    let caskCount: Int
    let isExternal: Bool

    var id: String { name }
}

struct DependencyEdge: Identifiable, Hashable, Sendable {
    let formulaID: String
    let dependencyID: String

    var id: String {
        "\(formulaID)->\(dependencyID)"
    }

    var formulaName: String {
        Self.formulaName(from: formulaID)
    }

    var dependencyName: String {
        Self.formulaName(from: dependencyID)
    }

    init(formulaName: String, dependencyName: String) {
        self.formulaID = PackageID.formula(formulaName)
        self.dependencyID = PackageID.formula(dependencyName)
    }

    init(formulaID: String, dependencyID: String) {
        self.formulaID = formulaID
        self.dependencyID = dependencyID
    }

    private static func formulaName(from id: String) -> String {
        id.hasPrefix(PackageID.formulaPrefix) ? String(id.dropFirst(PackageID.formulaPrefix.count)) : id
    }
}

struct CleanupSummary: Equatable, Sendable {
    let lines: [String]
    let reclaimText: String?

    static let empty = CleanupSummary(lines: [], reclaimText: nil)
}

struct BrewSummary: Equatable, Sendable {
    let formulaCount: Int
    let caskCount: Int
    let leafCount: Int
    let edgeCount: Int
    let outdatedCount: Int
    let unusedDependencyCount: Int
    let totalKnownSize: Int64
}

enum DoctorWarningCategory: CaseIterable, Identifiable, Sendable {
    case permissions
    case xcodeCLT
    case staleFiles
    case configIssues
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .permissions: "Permissions"
        case .xcodeCLT: "Xcode / CLT"
        case .staleFiles: "Stale Files"
        case .configIssues: "Config Issues"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .permissions: "lock.shield"
        case .xcodeCLT: "wrench.and.screwdriver"
        case .staleFiles: "folder"
        case .configIssues: "doc.text"
        case .other: "info.circle"
        }
    }

    var explanation: String {
        switch self {
        case .permissions: "Some Homebrew directories have incorrect permissions, which may prevent package installation."
        case .xcodeCLT: "Xcode or Command Line Tools may be outdated, which can cause build failures."
        case .staleFiles: "Files from previously removed packages remain on disk."
        case .configIssues: "Deprecated or outdated configuration detected."
        case .other: "Additional issues reported by brew doctor."
        }
    }

    static func classify(_ warning: String) -> DoctorWarningCategory {
        let lower = warning.lowercased()
        if lower.contains("writable") || lower.contains("permission") || lower.contains("chown") {
            return .permissions
        }
        if lower.contains("xcode") || lower.contains("command line") || lower.contains("clt") || lower.contains("developer") {
            return .xcodeCLT
        }
        if lower.contains("stale") || lower.contains("leftover") || lower.contains("unexpected") || lower.contains("dangling") {
            return .staleFiles
        }
        if lower.contains("config") || lower.contains("deprecated") {
            return .configIssues
        }
        return .other
    }
}

struct ClassifiedDoctorWarning: Identifiable, Equatable, Sendable {
    let raw: String
    let category: DoctorWarningCategory
    var id: String { raw }
}

enum PackageID {
    static let formulaPrefix = "formula:"
    static let caskPrefix = "cask:"

    static func formula(_ name: String) -> String {
        "\(formulaPrefix)\(name)"
    }

    static func cask(_ token: String) -> String {
        "\(caskPrefix)\(token)"
    }
}
