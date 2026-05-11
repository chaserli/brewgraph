import AppKit
import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
    let snapshot: BrewSnapshot
    let onSelectPackage: (String) -> Void
    @State private var warningsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                groupHeader("Overview", systemImage: "chart.pie", tint: .accentColor)
                inventorySection
                groupHeader("Needs Attention", systemImage: "exclamationmark.triangle", tint: AppTheme.outdatedColor)
                attentionSection
                groupHeader("Packages", systemImage: "list.bullet.rectangle", tint: AppTheme.formulaColor)
                packageSections
                warningsSection
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew Overview")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(snapshot.brewPrefix.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                Text("Scanned in \(AppFormatters.duration(snapshot.scanDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                SummaryTile(
                    title: "Installed Packages",
                    value: "\(snapshot.summary.formulaCount) + \(snapshot.summary.caskCount)",
                    detail: "formulae plus casks",
                    systemImage: "shippingbox",
                    tint: AppTheme.formulaColor
                )
                SummaryTile(
                    title: "Requested vs Dependency",
                    value: "\(snapshot.requestedPackageCount) / \(snapshot.dependencyOnlyPackageCount)",
                    detail: "direct installs vs dependency-only packages",
                    systemImage: "checkmark.circle",
                    tint: AppTheme.requestedColor
                )
                SummaryTile(
                    title: "Dependency Graph",
                    value: "\(snapshot.summary.edgeCount)",
                    detail: "direct formula dependency edges",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: AppTheme.dependencyColor
                )
                SummaryTile(
                    title: "Known Disk Use",
                    value: AppFormatters.size(snapshot.summary.totalKnownSize),
                    detail: "from enabled size estimation",
                    systemImage: "externaldrive",
                    tint: AppTheme.externalTapColor
                )
            }
        }
        .nativePanel(subtle: true)
    }

    // MARK: - Inventory

    private var inventorySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            InsightCard(
                title: "Inventory Mix",
                subtitle: "What Homebrew currently has on disk",
                rows: [
                    InsightRow(label: "Formulae", value: "\(snapshot.summary.formulaCount)", detail: "installed formula packages"),
                    InsightRow(label: "Casks", value: "\(snapshot.summary.caskCount)", detail: "installed app casks"),
                    InsightRow(label: "Requested", value: "\(snapshot.requestedPackageCount)", detail: "installed on request"),
                    InsightRow(label: "Dependencies", value: "\(snapshot.dependencyOnlyPackageCount)", detail: "installed for other packages")
                ]
            )

            InsightCard(
                title: "Graph Shape",
                subtitle: "How connected the formula graph is",
                rows: [
                    InsightRow(label: "Direct Edges", value: "\(snapshot.summary.edgeCount)", detail: "formula dependency links"),
                    InsightRow(label: "Dependency Hubs", value: "\(dependencyHubCount)", detail: "used by 3+ packages"),
                    InsightRow(label: "Leaf Formulae", value: "\(snapshot.summary.leafCount)", detail: "nothing depends on them"),
                    InsightRow(label: "Runtime Links", value: "\(runtimeDependencyLinkCount)", detail: "runtime dependency references")
                ]
            )

            InsightCard(
                title: "Package Flags",
                subtitle: "States worth keeping visible",
                rows: [
                    InsightRow(label: "Outdated", value: "\(snapshot.summary.outdatedCount)", detail: "reported by Homebrew"),
                    InsightRow(label: "Deprecated", value: "\(deprecatedPackageCount)", detail: "marked deprecated"),
                    InsightRow(label: "Disabled", value: "\(disabledPackageCount)", detail: "marked disabled"),
                    InsightRow(label: "Keg-only", value: "\(kegOnlyPackageCount)", detail: "not linked into default paths")
                ]
            )
        }
    }

    // MARK: - Attention

    private var attentionSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
            AttentionTile(
                title: "Outdated Packages",
                count: snapshot.summary.outdatedCount,
                detail: attentionDetail(
                    count: snapshot.summary.outdatedCount,
                    empty: "Everything reported by Homebrew is current.",
                    nonEmpty: "Select the first outdated package."
                ),
                tint: AppTheme.outdatedColor,
                package: issuePackages.first,
                onSelect: onSelectPackage
            )
            AttentionTile(
                title: "Unused Dependencies",
                count: snapshot.summary.unusedDependencyCount,
                detail: attentionDetail(
                    count: snapshot.summary.unusedDependencyCount,
                    empty: "No dependency-only leaves were found.",
                    nonEmpty: "Review dependency-only leaves before removing anything."
                ),
                tint: AppTheme.cleanupColor,
                package: unusedDependencies.first,
                onSelect: onSelectPackage
            )
            AttentionTile(
                title: "External Taps",
                count: snapshot.externalTapPackageCount,
                detail: attentionDetail(
                    count: snapshot.externalTapPackageCount,
                    empty: "Only the default Homebrew taps are present.",
                    nonEmpty: "Packages from third-party taps are mixed in."
                ),
                tint: AppTheme.externalTapColor,
                package: externalTapPackages.first,
                onSelect: onSelectPackage
            )
            CleanupTile(cleanup: snapshot.cleanupDryRun)

            if !snapshot.classifiedDoctorWarnings.isEmpty {
                DoctorAttentionTile(warnings: snapshot.classifiedDoctorWarnings)
            }
        }
    }

    // MARK: - Packages

    private var packageSections: some View {
        LazyVGrid(columns: DashboardGrid.rankingColumns, spacing: 14) {
            PackageListCard(
                title: "Most Depended On",
                subtitle: "Formulae that keep the most installed packages working",
                packages: dependencyCenters,
                metric: .reverseUsers,
                onSelect: onSelectPackage
            )
            PackageListCard(
                title: "Largest Known Packages",
                subtitle: "Only packages with a measured size are included",
                packages: largestPackages,
                metric: .size,
                onSelect: onSelectPackage
            )
            TapOriginsCard(taps: Array(snapshot.tapSummaries.prefix(8)))
            PackageListCard(
                title: "Direct Dependency Fanout",
                subtitle: "Packages with the most direct formula dependencies",
                packages: directFanoutPackages,
                metric: .directDeps,
                onSelect: onSelectPackage
            )
            PackageListCard(
                title: "Runtime Dependency Users",
                subtitle: "Packages with the most runtime dependency references",
                packages: runtimeDependencyPackages,
                metric: .runtimeDeps,
                onSelect: onSelectPackage
            )
            PackageListCard(
                title: "Flagged Packages",
                subtitle: "Pinned, keg-only, deprecated, disabled, or outdated",
                packages: flaggedPackages,
                metric: .flags,
                onSelect: onSelectPackage
            )
        }
    }

    // MARK: - Group Header

    /// Section divider with a colored accent bar, icon, and title.
    private func groupHeader(_ title: String, systemImage: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4, height: 20)
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(LocalizedStringKey(title))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(.top, 8)
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warningsSection: some View {
        if !snapshot.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        warningsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        warningCountText
                            .font(.headline)
                        Spacer()
                        Image(systemName: warningsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if warningsExpanded {
                    VStack(spacing: 8) {
                        ForEach(snapshot.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        }

                        HStack {
                            Spacer()
                            Button {
                                copyWarnings()
                            } label: {
                                Label("Copy Warnings", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .nativePanel(subtle: true)
        }
    }

    // MARK: - Data Queries

    private var dependencyCenters: [Package] {
        snapshot.packages
            .filter { $0.kind == .formula && !$0.reverseDependencies.isEmpty }
            .sorted { lhs, rhs in
                if lhs.reverseDependencies.count == rhs.reverseDependencies.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.reverseDependencies.count > rhs.reverseDependencies.count
            }
            .prefix(8)
            .map { $0 }
    }

    private var largestPackages: [Package] {
        snapshot.packages
            .filter { $0.size != nil }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
            .prefix(8)
            .map { $0 }
    }

    private var directFanoutPackages: [Package] {
        snapshot.packages
            .filter { $0.kind == .formula && !$0.dependencies.isEmpty }
            .sorted { lhs, rhs in
                if lhs.dependencies.count == rhs.dependencies.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.dependencies.count > rhs.dependencies.count
            }
            .prefix(8)
            .map { $0 }
    }

    private var runtimeDependencyPackages: [Package] {
        snapshot.packages
            .filter { !$0.runtimeDependencies.isEmpty }
            .sorted { lhs, rhs in
                if lhs.runtimeDependencies.count == rhs.runtimeDependencies.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.runtimeDependencies.count > rhs.runtimeDependencies.count
            }
            .prefix(8)
            .map { $0 }
    }

    private var flaggedPackages: [Package] {
        snapshot.packages
            .filter { $0.outdated || $0.deprecated || $0.disabled || $0.pinned || $0.kegOnly }
            .sorted { lhs, rhs in
                if lhs.statusBadges.count == rhs.statusBadges.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.statusBadges.count > rhs.statusBadges.count
            }
            .prefix(8)
            .map { $0 }
    }

    private var unusedDependencies: [Package] {
        snapshot.packages
            .filter(\.isUnusedDependency)
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
            .prefix(8)
            .map { $0 }
    }

    private var issuePackages: [Package] {
        snapshot.packages
            .filter { $0.outdated || $0.deprecated || $0.disabled }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private var externalTapPackages: [Package] {
        snapshot.packages
            .filter(\.isExternalTap)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private var dependencyHubCount: Int {
        snapshot.packages.filter { $0.kind == .formula && $0.reverseDependencies.count >= 3 }.count
    }

    private var runtimeDependencyLinkCount: Int {
        snapshot.packages.reduce(0) { $0 + $1.runtimeDependencies.count }
    }

    private var deprecatedPackageCount: Int {
        snapshot.packages.filter(\.deprecated).count
    }

    private var disabledPackageCount: Int {
        snapshot.packages.filter(\.disabled).count
    }

    private var kegOnlyPackageCount: Int {
        snapshot.packages.filter(\.kegOnly).count
    }

    // MARK: - Helpers

    private func attentionDetail(count: Int, empty: String, nonEmpty: String) -> String {
        count == 0 ? empty : nonEmpty
    }

    private func copyWarnings() {
        AppFormatters.copyToClipboard(snapshot.warnings.joined(separator: "\n"))
    }

    private var warningCountText: Text {
        snapshot.warnings.count == 1
            ? Text("1 Scan Warning")
            : Text("\(snapshot.warnings.count) Scan Warnings")
    }
}

private enum DashboardCardSize {
    static let summaryMinHeight: CGFloat = 112
    static let insightMinHeight: CGFloat = 226
    static let attentionMinHeight: CGFloat = 122
    static let rankingMinHeight: CGFloat = 366
}

private enum DashboardGrid {
    static var rankingColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)]
    }
}

// MARK: - Summary Tile

/// Large stat tile with icon watermark, used in the Overview header row.
private struct SummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint.opacity(0.10))
                .padding(10)
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary).lineLimit(1)
                Text(value)
                    .font(.title2.monospacedDigit()).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
                Text(LocalizedStringKey(detail))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.summaryMinHeight, alignment: .topLeading)
        .cardWithAccentBar(tint: tint)
    }
}

// MARK: - Insight Card

private struct InsightRow: Hashable {
    let label: String
    let value: String
    let detail: String
}

private struct InsightCard: View {
    let title: String
    let subtitle: String
    let rows: [InsightRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline).fontWeight(.semibold)
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(row.label)).font(.callout).lineLimit(1)
                            Text(LocalizedStringKey(row.detail)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 130, alignment: .leading)
                        Text(row.value).font(.callout.monospacedDigit()).fontWeight(.semibold).lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    if row != rows.last { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.insightMinHeight, alignment: .topLeading)
        .nativePanel(subtle: false)
    }
}

// MARK: - Attention Tiles

private struct AttentionTile: View {
    let title: String
    let count: Int
    let detail: String
    let tint: Color
    let package: Package?
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            if let package { onSelect(package.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(title)).font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text("\(count)").font(.title3.monospacedDigit()).fontWeight(.semibold).foregroundStyle(tint)
                }
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let package {
                    Text(package.name).font(.caption.monospaced()).lineLimit(1).foregroundStyle(.primary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: DashboardCardSize.attentionMinHeight, alignment: .topLeading)
            .attentionBackground(tint: tint, active: count > 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(package == nil)
    }
}

private struct CleanupTile: View {
    let cleanup: CleanupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey("Cache / Old Versions")).font(.subheadline).fontWeight(.semibold)
                Spacer()
                if let reclaimText = cleanup.reclaimText {
                    Text(reclaimText)
                        .font(.title3.monospacedDigit()).fontWeight(.semibold)
                        .foregroundStyle(AppTheme.cleanupColor).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("None")
                        .font(.title3.monospacedDigit()).fontWeight(.semibold)
                        .foregroundStyle(AppTheme.cleanupColor).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Text(cleanup.reclaimText == nil
                ? LocalizedStringKey("No reclaimable cache or old-version data was reported.")
                : LocalizedStringKey("Read-only estimate of cache and old-version data. No packages are removed.")
            ).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.attentionMinHeight, alignment: .topLeading)
        .attentionBackground(tint: AppTheme.cleanupColor, active: cleanup.reclaimText != nil)
    }
}

private struct DoctorAttentionTile: View {
    let warnings: [ClassifiedDoctorWarning]
    @State private var expanded = false

    private var byCategory: [(DoctorWarningCategory, [ClassifiedDoctorWarning], Int)] {
        Dictionary(grouping: warnings, by: \.category)
            .map { ($0.key, $0.value, $0.value.count) }
            .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("brew doctor").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("\(warnings.count)").font(.title3.monospacedDigit()).fontWeight(.semibold)
                    .foregroundStyle(warnings.isEmpty ? .secondary : AppTheme.outdatedColor)
            }
            ForEach(byCategory.prefix(expanded ? byCategory.count : 3), id: \.0) { (category, _, count) in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbolName).font(.caption).foregroundStyle(AppTheme.outdatedColor)
                        Text(LocalizedStringKey(category.title)).font(.caption).fontWeight(.medium)
                        Spacer()
                        Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(LocalizedStringKey(category.explanation)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if byCategory.count > 3 {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    if expanded {
                        Text("Show less")
                    } else {
                        Text("+\(byCategory.count - 3) more categories")
                    }
                }
                .font(.caption2).buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.attentionMinHeight, alignment: .topLeading)
        .attentionBackground(tint: AppTheme.outdatedColor, active: !warnings.isEmpty)
    }
}

// MARK: - Package Cards

private enum DashboardRankMetric {
    case reverseUsers, size, installReason, directDeps, runtimeDeps, flags
}

private struct PackageListCard: View {
    let title: String
    let subtitle: String
    let packages: [Package]
    let metric: DashboardRankMetric
    let onSelect: (String) -> Void
    private var maxSize: Int64 { packages.compactMap(\.size).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline).fontWeight(.semibold)
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if packages.isEmpty {
                Text("None").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(packages.enumerated()), id: \.element.id) { index, pkg in
                        Button { onSelect(pkg.id) } label: {
                            PackageListRow(package: pkg, rank: index + 1, metric: metric, maxSize: maxSize)
                        }
                        .buttonStyle(.plain)
                        if index < packages.count - 1 { Divider().padding(.leading, 40) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.rankingMinHeight, alignment: .topLeading)
        .nativePanel(subtle: false)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.3))
                .frame(width: 3).padding(.vertical, 12).padding(.leading, 1)
        }
    }

}

private struct PackageListRow: View {
    let package: Package
    let rank: Int
    let metric: DashboardRankMetric
    let maxSize: Int64
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20, alignment: .center)
            PackageIconView(package: package, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(package.name).font(.callout).fontWeight(.medium).lineLimit(1)
                metricLabel
            }
            Spacer()
            if let size = package.size, metric == .size { BarIndicator(value: size, maxValue: maxSize) }
        }
        .padding(.vertical, 8).padding(.horizontal, 2)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var metricLabel: some View {
        switch metric {
        case .reverseUsers:
            Text("\(package.reverseDependencies.count) packages depend on this")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .size:
            Text(AppFormatters.size(package.size)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .installReason:
            (Text(LocalizedStringKey(package.kind.title)) + Text(", \(package.tapDisplayName)"))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .directDeps:
            (Text("\(package.dependencies.count) ") + Text(LocalizedStringKey("direct dependencies")))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .runtimeDeps:
            (Text("\(package.runtimeDependencies.count) ") + Text(LocalizedStringKey("runtime dependencies")))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .flags:
            HStack(spacing: 0) {
                Text(LocalizedStringKey(primaryFlagTitle))
                if additionalFlagCount > 0 { Text(", +\(additionalFlagCount)") }
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var flagTitles: [String] {
        package.statusBadges.filter { !["Requested", "Dependency"].contains($0.title) }.map(\.title)
    }

    private var primaryFlagTitle: String {
        flagTitles.first ?? "No package flags"
    }

    private var additionalFlagCount: Int { max(0, flagTitles.count - 1) }
}

private struct TapOriginsCard: View {
    let taps: [TapSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey("Tap Origins")).font(.subheadline).fontWeight(.semibold)
                Text(LocalizedStringKey("Where installed packages came from")).font(.caption).foregroundStyle(.secondary)
            }
            if taps.isEmpty {
                Text("None").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(taps.enumerated()), id: \.element.id) { index, tap in
                        TapOriginRow(tap: tap)
                        if index < taps.count - 1 { Divider().padding(.leading, 28) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DashboardCardSize.rankingMinHeight, alignment: .topLeading)
        .nativePanel(subtle: false)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(AppTheme.externalTapColor.opacity(0.4))
                .frame(width: 3).padding(.vertical, 12).padding(.leading, 1)
        }
    }
}

private struct TapOriginRow: View {
    let tap: TapSummary
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(tap.isExternal ? AppTheme.externalTapColor : Color.secondary).frame(width: 8, height: 8).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(tap.name).font(.callout).fontWeight(tap.isExternal ? .medium : .regular).lineLimit(1)
                Text("\(tap.formulaCount) formulae, \(tap.caskCount) casks")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\(tap.packageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).padding(.horizontal, 2)
    }
}

// MARK: - Bar Indicator

private struct BarIndicator: View {
    let value: Int64
    let maxValue: Int64
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(AppTheme.formulaColor.opacity(0.55))
                    .frame(width: Swift.max(6, proxy.size.width * barFraction), height: 6)
            }
        }
        .frame(width: 60, height: 6)
    }
    private var barFraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return min(1, Swift.max(0.01, CGFloat(value) / CGFloat(maxValue)))
    }
}
