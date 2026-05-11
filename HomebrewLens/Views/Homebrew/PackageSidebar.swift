import AppKit
import SwiftUI

struct PackageSidebar: View {
    @ObservedObject var manager: HomebrewManager
    let refreshDuration: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            controlPanel

            Divider()

            List(selection: $manager.selectedPackageID) {
                Section {
                    StatusRow(state: manager.state, refreshDuration: refreshDuration)
                } header: {
                    Text("Scan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }

                if let snapshot = manager.snapshot {
                    Section {
                        ForEach(manager.filteredPackages) { package in
                            PackageSidebarRow(package: package)
                                .tag(package.id)
                        }
                        .animation(.default, value: manager.filteredPackages.map(\.id))
                    } header: {
                        Text("\(manager.filteredPackages.count) of \(snapshot.packages.count) Packages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                } else {
                    Section {
                        PlaceholderSidebarRow(systemImage: "shippingbox", title: "Formulae")
                        PlaceholderSidebarRow(systemImage: "app.dashed", title: "Casks")
                        PlaceholderSidebarRow(systemImage: "leaf", title: "Leaves")
                    } header: {
                        Text("Packages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search packages", text: $manager.searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .disabled(manager.snapshot == nil)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            FilterChipRow(selection: $manager.packageFilter, snapshot: manager.snapshot)
                .disabled(manager.snapshot == nil)

            HStack {
                Text("Sort by")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Sort", selection: $manager.packageSort) {
                    ForEach(PackageSort.allCases) { sort in
                        Text(LocalizedStringKey(sort.title)).tag(sort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(manager.snapshot == nil)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }
}

// MARK: - Filter Chips

private struct FilterChipRow: View {
    @Binding var selection: PackageFilter
    let snapshot: BrewSnapshot?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PackageFilter.allCases) { filter in
                    FilterChip(
                        filter: filter,
                        count: count(for: filter),
                        isSelected: selection == filter
                    ) {
                        selection = filter
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func count(for filter: PackageFilter) -> Int {
        guard let snapshot else { return 0 }
        return switch filter {
        case .all: snapshot.packages.count
        case .formulae: snapshot.summary.formulaCount
        case .casks: snapshot.summary.caskCount
        case .requested: snapshot.requestedPackageCount
        case .leaves: snapshot.summary.leafCount
        case .dependencies: snapshot.dependencyOnlyPackageCount
        case .externalTaps: snapshot.externalTapPackageCount
        case .unusedDependencies: snapshot.summary.unusedDependencyCount
        case .outdated: snapshot.summary.outdatedCount
        case .issues: snapshot.packages.filter { $0.outdated || $0.deprecated || $0.disabled }.count
        }
    }
}

private struct FilterChip: View {
    let filter: PackageFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.symbolName)
                    .font(.caption2)
                Text(LocalizedStringKey(filter.title))
                    .font(.caption)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let state: HomebrewState
    let refreshDuration: TimeInterval?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if case .scanning = state {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                titleText
                    .font(.callout)
                    .fontWeight(.medium)
                if let subtitleText {
                    subtitleText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if showsProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 80)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .animation(.default, value: state)
    }

    private var iconName: String {
        switch state {
        case .idle: "clock"
        case .discovering: "magnifyingglass"
        case .scanning: "arrow.triangle.2.circlepath"
        case .scanned: "checkmark.circle.fill"
        case .missing: "xmark.octagon.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle: .secondary
        case .discovering: .blue
        case .scanning: .blue
        case .scanned: .green
        case .missing: .orange
        case .failed: .red
        }
    }

    private var titleText: Text {
        switch state {
        case .idle:
            Text("Ready to scan")
        case .discovering:
            Text("Finding Homebrew")
        case let .scanning(_, step):
            Text(LocalizedStringKey(step))
        case let .scanned(snapshot):
            Text("\(snapshot.summary.formulaCount) formulae, \(snapshot.summary.caskCount) casks")
        case .missing:
            Text("Homebrew not found")
        case .failed:
            Text("Scan failed")
        }
    }

    private var subtitleText: Text? {
        switch state {
        case .idle: nil
        case .discovering: Text("Checking known brew locations")
        case .scanning: nil
        case .scanned:
            if let duration = refreshDuration {
                elapsedText(seconds: duration)
            } else {
                nil
            }
        case .missing: nil
        case .failed: nil
        }
    }

    private func elapsedText(seconds: TimeInterval) -> Text {
        if seconds < 60 {
            Text("\(seconds, specifier: "%.0f")s ago")
        } else {
            Text("\(seconds / 60, specifier: "%.0f")m ago")
        }
    }

    private var showsProgress: Bool {
        switch state {
        case .discovering, .scanning: true
        default: false
        }
    }
}

// MARK: - Package Row

private struct PackageSidebarRow: View {
    let package: Package
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            PackageIconView(package: package, size: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(package.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    detailText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !statusChips.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary.opacity(0.5))
                            .font(.caption2)

                        ForEach(statusChips.prefix(3)) { chip in
                            Text(LocalizedStringKey(chip.title))
                                .font(.caption2)
                                .foregroundStyle(chip.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(chip.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }

                        if statusChips.count > 3 {
                            Text("+\(statusChips.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
        .overlay(alignment: .leading) {
            if isHovered {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
    }

    private var detailText: Text {
        switch package.kind {
        case .formula:
            return Text(LocalizedStringKey(package.installReason.shortTitle))
                + Text(", \(package.dependencies.count) ")
                + Text("deps")
                + Text(", \(package.reverseDependencies.count) ")
                + Text("users")
                + Text(", \(AppFormatters.size(package.size))")
                + externalTapText
        case .cask:
            return Text(LocalizedStringKey(package.installReason.shortTitle))
                + Text(", \(package.tapDisplayName), \(package.version)")
        }
    }

    private var externalTapText: Text {
        package.isExternalTap ? Text(", \(package.tapDisplayName)") : Text("")
    }

    private struct StatusChip: Identifiable {
        let id = UUID()
        let title: String
        let color: Color
    }

    private var statusChips: [StatusChip] {
        var chips: [StatusChip] = []
        if package.outdated {
            chips.append(StatusChip(title: "Outdated", color: AppTheme.outdatedColor))
        }
        if package.isUnusedDependency {
            chips.append(StatusChip(title: "Unused", color: AppTheme.cleanupColor))
        }
        if package.deprecated {
            chips.append(StatusChip(title: "Deprecated", color: AppTheme.dangerColor))
        }
        if package.disabled {
            chips.append(StatusChip(title: "Disabled", color: AppTheme.dangerColor))
        }
        if package.kegOnly {
            chips.append(StatusChip(title: "Keg-only", color: .secondary))
        }
        return chips
    }
}

// MARK: - Package Icon

struct PackageIconView: View {
    let package: Package
    var size: CGFloat

    var body: some View {
        Group {
            if let iconPath = package.iconPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(kindColor.opacity(0.12))
                        .frame(width: size, height: size)
                    Image(systemName: package.kind.symbolName)
                        .font(.system(size: size * 0.55, weight: .medium))
                        .foregroundStyle(kindColor)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var kindColor: Color {
        switch package.kind {
        case .formula:
            AppTheme.formulaColor
        case .cask:
            AppTheme.caskColor
        }
    }
}

// MARK: - Placeholder Row

private struct PlaceholderSidebarRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(LocalizedStringKey(title), systemImage: systemImage)
            .foregroundStyle(.secondary)
    }
}
