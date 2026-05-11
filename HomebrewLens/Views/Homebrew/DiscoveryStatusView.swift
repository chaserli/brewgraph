import AppKit
import SwiftUI

struct DiscoveryStatusBar: View {
    let state: HomebrewState
    let refreshDuration: TimeInterval?

    @State private var showingDiagnostics = false

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            statusText
                .lineLimit(1)
                .foregroundStyle(statusColor)
                .fontWeight(.medium)

            Spacer()

            scanDurationBadge

            if let diagnostics {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label {
                        diagnosticsActionTitle(diagnostics.actionTitle)
                            .font(.caption)
                    } icon: {
                        Image(systemName: diagnostics.systemImage)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(diagnostics.tint)
                .help("Show scan diagnostics")
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(statusColor.opacity(0.35))
                .frame(height: 1.5)
        }
        .sheet(isPresented: $showingDiagnostics) {
            if let diagnostics {
                DiagnosticsSheet(report: diagnostics)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .discovering, .scanning:
            ProgressView()
                .controlSize(.small)
                .tint(statusColor)
        case .scanned:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.successColor)
        case .missing:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.dangerColor)
        }
    }

    @ViewBuilder
    private var scanDurationBadge: some View {
        if let refreshDuration {
            Text("\(refreshDuration, specifier: "%.2f")s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.10))
                )
        }
    }

    private var statusColor: Color {
        switch state {
        case .idle:
            .secondary
        case .discovering, .scanning:
            AppTheme.formulaColor
        case .scanned:
            AppTheme.successColor
        case .missing:
            AppTheme.outdatedColor
        case .failed:
            AppTheme.dangerColor
        }
    }

    private var statusText: Text {
        switch state {
        case .idle:
            Text("Ready to discover Homebrew")
        case .discovering:
            Text("Discovering Homebrew...")
        case let .scanning(result, step):
            Text(LocalizedStringKey(step)) + Text(" · \(result.brewPath.path)")
        case let .scanned(snapshot):
            Text("Scanned \(snapshot.summary.formulaCount) formulae, \(snapshot.summary.caskCount) casks, \(snapshot.summary.edgeCount) edges from \(snapshot.brewPath.path)")
        case .missing:
            Text("Homebrew was not found on this machine")
        case let .failed(message):
            Text(message)
        }
    }

    private var diagnostics: DiagnosticsReport? {
        switch state {
        case let .scanned(snapshot) where !snapshot.warnings.isEmpty:
            DiagnosticsReport(
                title: "Scan Warnings",
                subtitle: "BrewGraph kept the successful scan data and recorded optional command problems.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                actionTitle: snapshot.warnings.count == 1 ? "1 Warning" : "\(snapshot.warnings.count) Warnings",
                items: snapshot.warnings,
                footer: "These warnings usually mean one read-only supporting command failed or returned partial output."
            )
        case let .missing(attempts):
            DiagnosticsReport(
                title: "Homebrew Not Found",
                subtitle: "Discovery checked Finder-safe paths and did not find an executable brew.",
                systemImage: "xmark.octagon.fill",
                tint: .orange,
                actionTitle: "Diagnostics",
                items: attempts.map { "\($0.source): \($0.candidate) -> \($0.outcome)" },
                footer: "BrewGraph does not install Homebrew. Install it separately, then refresh."
            )
        case let .failed(message):
            DiagnosticsReport(
                title: "Scan Failed",
                subtitle: "The scan stopped before a snapshot could be produced.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,
                actionTitle: "Error Details",
                items: [message],
                footer: nil
            )
        default:
            nil
        }
    }

    private func diagnosticsActionTitle(_ title: String) -> Text {
        if title == "1 Warning" {
            return Text("1 Warning")
        }
        if title.hasSuffix(" Warnings"), let count = Int(title.split(separator: " ").first ?? "") {
            return Text("\(count) Warnings")
        }
        return Text(LocalizedStringKey(title))
    }
}

struct DiagnosticsReport: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let items: [String]
    let footer: String?

    var text: String {
        var lines = [title, subtitle, ""]
        lines.append(contentsOf: items.map { "- \($0)" })
        if let footer {
            lines.append("")
            lines.append(footer)
        }
        return lines.joined(separator: "\n")
    }
}

private struct DiagnosticsSheet: View {
    let report: DiagnosticsReport

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: report.systemImage)
                    .font(.title2)
                    .foregroundStyle(report.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(report.title))
                        .font(.headline)
                    Text(LocalizedStringKey(report.subtitle))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.items, id: \.self) { item in
                        Text(item)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 280)

            if let footer = report.footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    copy(report.text)
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct MissingHomebrewView: View {
    let attempts: [DiscoveryAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew not found")
                        .font(.headline)
                    Text("The app checked the standard Finder-safe discovery paths and did not find an executable brew.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(attempts) { attempt in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(attempt.source)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 180, alignment: .leading)
                        Text(attempt.candidate)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(attempt.outcome)
                            .font(.caption)
                            .foregroundStyle(attempt.outcome == "found" ? AppTheme.successColor : .secondary)
                    }
                }
            }

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(attempts.diagnosticsText, forType: .string)
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }
        }
        .nativePanel()
        .frame(maxWidth: 680)
    }
}
