import AppKit
import SwiftUI

struct PackageInspector: View {
    let package: Package
    let snapshot: BrewSnapshot?
    let onClose: () -> Void
    let onSelectPackage: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PackageIconView(package: package, size: 24)

                Text(package.name)
                    .font(.headline)
                    .foregroundStyle(kindColor)
                    .lineLimit(1)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help("Hide inspector")
            }
            .padding(14)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection
                    if package.kind == .formula, let snapshot {
                        installChainSection(for: snapshot)
                    }
                    detailsSection
                    dependencySection(
                        title: "Depends On",
                        names: package.dependencies,
                        tint: AppTheme.dependencyColor,
                        systemImage: "arrow.right"
                    )
                    dependencySection(
                        title: "Used By",
                        names: package.reverseDependencies,
                        tint: AppTheme.dependentColor,
                        systemImage: "arrow.left"
                    )
                    dependencySection(
                        title: "Runtime Dependencies",
                        names: package.runtimeDependencies,
                        tint: .secondary,
                        systemImage: "terminal"
                    )
                    commandsSection
                }
                .padding(14)
            }
        }
    }

    private var kindColor: Color {
        switch package.kind {
        case .formula: AppTheme.formulaColor
        case .cask: AppTheme.caskColor
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(package.kind.title))
                    .font(.caption)
                    .foregroundStyle(kindColor)
                Spacer()
                Text(package.version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !package.description.isEmpty {
                Text(package.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !package.statusBadges.isEmpty {
                FlowBadgeRow(badges: package.statusBadges)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCard
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Details", systemImage: "info.circle", tint: .secondary)

            LazyVGrid(columns: [GridItem(.fixed(76), alignment: .leading), GridItem(.flexible())], spacing: 6) {
                detailRow(label: "Install", value: package.installReason.title, localized: true)
                detailRow(label: "Tap", value: package.tap ?? "unknown")
                if let stableVersion = package.stableVersion {
                    detailRow(label: "Stable", value: stableVersion)
                }
                if let license = package.license {
                    detailRow(label: "License", value: license)
                }
                detailRow(label: "Size", value: AppFormatters.size(package.size))
                detailRow(label: "Installed", value: AppFormatters.date(package.installedAt))
            }

            if let homepage = package.homepage {
                Link(destination: homepage) {
                    Label("Homepage", systemImage: "safari")
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCard
    }

    private func detailRow(label: String, value: String, localized: Bool = false) -> some View {
        Group {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            if localized {
                Text(LocalizedStringKey(value))
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Install Chain

    private func installChainSection(for snapshot: BrewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Why Installed", systemImage: "arrow.triangle.branch", tint: AppTheme.requestedColor)

            if let path = DependencyPathFinder.findInstallPath(
                for: package.name,
                reverseDeps: snapshot.reverseDeps,
                packages: snapshot.packages
            ) {
                if path.count == 1 && path[0] == package.name {
                    Text("Directly installed")
                        .font(.callout)
                        .foregroundStyle(AppTheme.requestedColor)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(path.enumerated()), id: \.offset) { index, name in
                            Button {
                                onSelectPackage("formula:\(name)")
                            } label: {
                                Text(name)
                                    .font(.caption.monospaced())
                                    .fontWeight(index == 0 || index == path.count - 1 ? .medium : .regular)
                                    .foregroundStyle(index == 0 ? AppTheme.requestedColor : index == path.count - 1 ? kindColor : .secondary)
                            }
                            .buttonStyle(.plain)

                            if index < path.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                        }
                    }
                    .lineLimit(1)
                }
            } else {
                Text("No dependency chain found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCard
    }

    // MARK: - Dependencies

    @ViewBuilder
    private func dependencySection(title: String, names: [String], tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title, systemImage: systemImage, tint: tint)

            if names.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        DependencyChip(name: name, tint: tint, onSelect: onSelectPackage)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCard
    }

    // MARK: - Commands

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Copy Commands", systemImage: "terminal", tint: .secondary)

            CommandRow(command: "brew info \(package.name)")
            CommandRow(command: "brew deps \(package.name) --tree")
            CommandRow(command: "brew uses --installed \(package.name)")

            if package.kind == .formula {
                CommandRow(
                    command: "brew uninstall \(package.name)",
                    isDestructive: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCard
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .fontWeight(.semibold)
            Text(LocalizedStringKey(title))
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Dependency Chip

private struct DependencyChip: View {
    let name: String
    let tint: Color
    let onSelect: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(PackageID.formula(name))
        } label: {
            Text(displayName)
                .font(.caption.monospaced())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(isHovered ? tint.opacity(0.16) : tint.opacity(0.08))
                )
                .overlay {
                    Capsule()
                        .stroke(isHovered ? tint.opacity(0.35) : tint.opacity(0.16), lineWidth: 1)
                }
                .foregroundStyle(isHovered ? tint : .primary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(name)
    }

    private var displayName: String {
        guard name.count > 18 else {
            return name
        }

        return "\(name.prefix(10))…\(name.suffix(5))"
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.caption.monospaced())
                .foregroundStyle(isDestructive ? AppTheme.dangerColor : .primary)
                .textSelection(.enabled)
                .lineLimit(1)

            Spacer()

            Button {
                AppFormatters.copyToClipboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy command")
        }
        .padding(8)
        .background(
            isDestructive
                ? AppTheme.dangerColor.opacity(0.08)
                : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 7)
        )
    }
}

// MARK: - Flow Badge Row

private struct FlowBadgeRow: View {
    let badges: [PackageBadge]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges) { badge in
                Label(LocalizedStringKey(badge.title), systemImage: badge.systemImage)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(background(for: badge.role), in: Capsule())
                    .foregroundStyle(foreground(for: badge.role))
            }
        }
    }

    private func background(for role: PackageBadge.Role) -> Color {
        switch role {
        case .neutral:
            .secondary.opacity(0.12)
        case .success:
            AppTheme.requestedColor.opacity(0.14)
        case .accent:
            AppTheme.externalTapColor.opacity(0.14)
        case .warning:
            AppTheme.outdatedColor.opacity(0.14)
        case .danger:
            AppTheme.dangerColor.opacity(0.14)
        }
    }

    private func foreground(for role: PackageBadge.Role) -> Color {
        switch role {
        case .neutral:
            .secondary
        case .success:
            AppTheme.requestedColor
        case .accent:
            AppTheme.externalTapColor
        case .warning:
            AppTheme.outdatedColor
        case .danger:
            AppTheme.dangerColor
        }
    }
}

// MARK: - Section Card Modifier

private struct SectionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.subtleStroke)
            }
    }
}

private extension View {
    var sectionCard: some View {
        modifier(SectionCardModifier())
    }
}

// MARK: - Dependency Path Finder

private struct DependencyPathFinder {

    static func findInstallPath(
        for targetName: String,
        reverseDeps: [String: [String]],
        packages: [Package]
    ) -> [String]? {
        let requested = Set(packages.filter { $0.installReason == .requested && $0.kind == .formula }.map(\.name))

        guard requested.contains(targetName) || reverseDeps.keys.contains(targetName) else {
            return nil
        }

        if requested.contains(targetName) {
            return [targetName]
        }

        var visited: Set<String> = [targetName]
        var queue: [([String], String)] = [([targetName], targetName)]

        while !queue.isEmpty {
            let (path, current) = queue.removeFirst()

            for parent in reverseDeps[current] ?? [] {
                let newPath = [parent] + path

                if requested.contains(parent) {
                    return newPath
                }

                if !visited.contains(parent) {
                    visited.insert(parent)
                    queue.append((newPath, parent))
                }
            }
        }

        return reverseDeps[targetName]?.isEmpty == false ? [targetName] : nil
    }
}
