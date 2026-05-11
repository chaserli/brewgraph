import Foundation

enum PackageKind: String, CaseIterable, Sendable {
    case formula
    case cask

    var title: String {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }

    var symbolName: String {
        switch self {
        case .formula:
            "shippingbox"
        case .cask:
            "app.dashed"
        }
    }
}

enum PackageInstallReason: String, CaseIterable, Sendable {
    case requested
    case dependency
    case unknown

    var title: String {
        switch self {
        case .requested:
            "Installed on request"
        case .dependency:
            "Installed as dependency"
        case .unknown:
            "Install reason unknown"
        }
    }

    var shortTitle: String {
        switch self {
        case .requested:
            "Requested"
        case .dependency:
            "Dependency"
        case .unknown:
            "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .requested:
            "checkmark.circle.fill"
        case .dependency:
            "link.circle.fill"
        case .unknown:
            "questionmark.circle"
        }
    }
}

enum PackageFilter: String, CaseIterable, Identifiable {
    case all
    case formulae
    case casks
    case requested
    case leaves
    case dependencies
    case externalTaps
    case unusedDependencies
    case outdated
    case issues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .formulae:
            "Formulae"
        case .casks:
            "Casks"
        case .requested:
            "Requested"
        case .leaves:
            "Leaves"
        case .dependencies:
            "Dependencies"
        case .externalTaps:
            "Other Taps"
        case .unusedDependencies:
            "Unused Deps"
        case .outdated:
            "Outdated"
        case .issues:
            "Issues"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            "tray.full"
        case .formulae:
            "shippingbox"
        case .casks:
            "app.dashed"
        case .requested:
            "checkmark.circle"
        case .leaves:
            "leaf"
        case .dependencies:
            "link"
        case .externalTaps:
            "tray.and.arrow.down"
        case .unusedDependencies:
            "link.circle"
        case .outdated:
            "arrow.up.circle"
        case .issues:
            "exclamationmark.triangle"
        }
    }
}

enum PackageSort: String, CaseIterable, Identifiable {
    case name
    case size
    case reverseUsers
    case directDeps
    case installedTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            "Name"
        case .size:
            "Size"
        case .reverseUsers:
            "Used By"
        case .directDeps:
            "Deps"
        case .installedTime:
            "Installed"
        }
    }
}

// MARK: - Package

struct Package: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: PackageKind
    let version: String
    let stableVersion: String?
    let description: String
    let homepage: URL?
    let license: String?
    let tap: String?
    let installedAt: Date?
    let installedOnRequest: Bool
    let installedAsDependency: Bool
    let outdated: Bool
    let pinned: Bool
    let deprecated: Bool
    let disabled: Bool
    let kegOnly: Bool
    let size: Int64?
    let iconPath: String?
    let dependencies: [String]
    let reverseDependencies: [String]
    let runtimeDependencies: [String]

    var isLeaf: Bool {
        kind == .formula && reverseDependencies.isEmpty
    }

    var isUnusedDependency: Bool {
        kind == .formula && installReason == .dependency && reverseDependencies.isEmpty
    }

    var installReason: PackageInstallReason {
        if installedOnRequest {
            return .requested
        }
        if installedAsDependency {
            return .dependency
        }
        return .unknown
    }

    var tapDisplayName: String {
        guard let tap, !tap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "unknown"
        }
        return tap
    }

    var isExternalTap: Bool {
        guard let tap, !tap.isEmpty else {
            return false
        }

        return !["homebrew/core", "homebrew/cask"].contains(tap)
    }

    var statusBadges: [PackageBadge] {
        var badges: [PackageBadge] = []

        switch installReason {
        case .requested:
            badges.append(PackageBadge(title: "Requested", systemImage: PackageInstallReason.requested.symbolName, role: .success))
        case .dependency:
            badges.append(PackageBadge(title: "Dependency", systemImage: PackageInstallReason.dependency.symbolName, role: .neutral))
        case .unknown:
            break
        }
        if isExternalTap {
            badges.append(PackageBadge(title: tapDisplayName, systemImage: "tray.and.arrow.down.fill", role: .accent))
        }
        if outdated {
            badges.append(PackageBadge(title: "Outdated", systemImage: "arrow.up.circle.fill", role: .warning))
        }
        if pinned {
            badges.append(PackageBadge(title: "Pinned", systemImage: "pin.fill", role: .neutral))
        }
        if deprecated {
            badges.append(PackageBadge(title: "Deprecated", systemImage: "exclamationmark.triangle.fill", role: .danger))
        }
        if disabled {
            badges.append(PackageBadge(title: "Disabled", systemImage: "nosign", role: .danger))
        }
        if kegOnly {
            badges.append(PackageBadge(title: "Keg-only", systemImage: "archivebox.fill", role: .neutral))
        }
        if isUnusedDependency {
            badges.append(PackageBadge(title: "Unused dependency", systemImage: "link.circle", role: .warning))
        }

        return badges
    }
}

struct PackageBadge: Identifiable, Hashable, Sendable {
    enum Role: Sendable {
        case neutral
        case success
        case accent
        case warning
        case danger
    }

    let title: String
    let systemImage: String
    let role: Role

    var id: String {
        "\(title)-\(systemImage)"
    }
}
