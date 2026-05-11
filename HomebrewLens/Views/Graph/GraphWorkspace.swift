import SwiftUI

struct GraphWorkspace: View {
    @Binding var mode: GraphMode
    @Binding var localDepth: Int
    @Binding var selectedPackageID: String?

    let state: HomebrewState
    let snapshot: BrewSnapshot?
    let selectedPackage: Package?

    @State private var cachedLayout: GraphLayout?
    @State private var cachedLayoutKey: String?

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar

            ZStack {
                if let snapshot {
                    workspace(for: snapshot)
                } else {
                    PlaceholderGraphCanvas(state: state)
                }

                overlay
                    .padding(24)
            }
        }
        .background(.background)
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            Picker("Graph Mode", selection: $mode) {
                ForEach(GraphMode.allCases) { mode in
                    Label(LocalizedStringKey(mode.title), systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            if mode == .localGraph {
                Stepper("Depth \(localDepth)", value: $localDepth, in: 1...3)
                    .frame(width: 120)
            }

            Spacer()

            subtitleText
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func workspace(for snapshot: BrewSnapshot) -> some View {
        Group {
        switch mode {
        case .fullGraph:
            graphCanvas(for: snapshot)
        case .localGraph:
            graphCanvas(for: snapshot)
        case .dashboard:
            DashboardView(snapshot: snapshot) { packageID in
                selectedPackageID = packageID
            }
        }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.snappy(duration: 0.22), value: mode)
        .id(mode)
    }

    @ViewBuilder
    private func graphCanvas(for snapshot: BrewSnapshot) -> some View {
        let key = layoutKey(for: snapshot)
        if let cachedLayout, cachedLayoutKey == key {
            GraphCanvas(
                layout: cachedLayout,
                selectedPackageID: selectedPackageID
            ) { packageID in
                selectedPackageID = packageID
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: key) {
                    cachedLayout = makeLayout(for: snapshot)
                    cachedLayoutKey = key
                }
        }
    }

    private func makeLayout(for snapshot: BrewSnapshot) -> GraphLayout {
        switch mode {
        case .fullGraph:
            return GraphLayoutEngine.fullGraph(snapshot: snapshot)
        case .localGraph:
            return GraphLayoutEngine.localGraph(
                snapshot: snapshot,
                selectedName: selectedPackage?.kind == .formula ? selectedPackage?.name : nil,
                depth: localDepth
            )
        case .dashboard:
            return GraphLayout(nodes: [], edges: [])
        }
    }

    private func layoutKey(for snapshot: BrewSnapshot) -> String {
        [
            mode.rawValue,
            "\(snapshot.packages.count)",
            "\(snapshot.edges.count)",
            "\(snapshot.scanDuration)",
            selectedPackage?.id ?? "none",
            "\(localDepth)"
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var overlay: some View {
        switch state {
        case .idle:
            EmptyView()
        case .discovering:
            EmptyView()
        case .scanning:
            EmptyView()
        case let .scanned(snapshot):
            if mode != .dashboard && snapshot.edges.isEmpty {
                GraphMessageCard(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "No formula edges",
                    message: "Installed packages loaded, but no direct formula dependency edges were reported."
                )
            }
        case let .missing(attempts):
            MissingHomebrewView(attempts: attempts)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case let .failed(message):
            GraphMessageCard(
                systemImage: "exclamationmark.triangle.fill",
                title: "Scan failed",
                message: message,
                warning: true
            )
        }
    }

    private var subtitleText: Text {
        guard let snapshot else {
            return Text(LocalizedStringKey(mode.subtitle))
        }

        switch mode {
        case .fullGraph:
            return Text("\(snapshot.summary.formulaCount) formulae, \(snapshot.summary.edgeCount) direct edges")
        case .localGraph:
            if selectedPackage?.kind == .formula, let name = selectedPackage?.name {
                return Text(name)
            }
            return Text("Select a formula")
        case .dashboard:
            return Text("\(snapshot.summary.outdatedCount) outdated, \(snapshot.summary.unusedDependencyCount) unused dependencies")
        }
    }
}

private struct PlaceholderGraphCanvas: View {
    let state: HomebrewState
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawGrid(context: context, size: size, phase: phase)
                drawGraph(context: context, size: size, phase: phase)
            }

            VStack(spacing: 10) {
                Label(LocalizedStringKey(title), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Text(LocalizedStringKey(message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if showsProgress {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(width: 240)
                        .padding(.top, 4)
                }
            }
            .nativePanel(subtle: false)
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var showsProgress: Bool {
        switch state {
        case .discovering, .scanning:
            true
        case .idle, .scanned, .missing, .failed:
            false
        }
    }

    private var progressFraction: Double {
        switch state {
        case .discovering:
            0.12
        case let .scanning(_, step):
            scanProgress(for: step)
        case .idle, .scanned, .missing, .failed:
            0
        }
    }

    private func scanProgress(for step: String) -> Double {
        BrewScanner.ScanStep(rawValue: step)?.fraction ?? 0.50
    }

    private var title: String {
        switch state {
        case .idle:
            "No scan yet"
        case .discovering:
            "Finding Homebrew"
        case .scanning:
            "Scanning Homebrew"
        case .scanned:
            "Graph ready"
        case .missing:
            "Homebrew not found"
        case .failed:
            "Scan failed"
        }
    }

    private var message: String {
        switch state {
        case .idle:
            "Waiting for read-only Homebrew data."
        case .discovering:
            "Checking known brew locations."
        case let .scanning(_, step):
            step
        case .scanned:
            "Formula relationships are ready."
        case .missing:
            "No brew executable was found."
        case let .failed(message):
            message
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, phase: Double) {
        var path = Path()
        let spacing: CGFloat = 56
        let gridOpacity = 0.025 + phase * 0.03

        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }

        context.stroke(path, with: .color(Color.secondary.opacity(gridOpacity)), lineWidth: 1)
    }

    private func drawGraph(context: GraphicsContext, size: CGSize, phase: Double) {
        let points = placeholderPoints.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let edgeOpacity = 0.08 + phase * 0.10
        let nodeBase = 0.35 + phase * 0.30
        let nodeHighlight = 0.55 + phase * 0.30

        for edge in placeholderEdges {
            var path = Path()
            path.move(to: points[edge.0])
            path.addLine(to: points[edge.1])
            context.stroke(path, with: .color(Color.secondary.opacity(edgeOpacity)), lineWidth: 1)
        }

        for (index, point) in points.enumerated() {
            let isRequested = [0, 3, 7, 10, 13].contains(index)
            let radius: CGFloat = isRequested ? 5.5 : 4
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let color = isRequested ? AppTheme.requestedColor.opacity(nodeHighlight) : Color.secondary.opacity(nodeBase)

            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(Color.secondary.opacity(edgeOpacity)), lineWidth: 1)
        }
    }

    private var placeholderPoints: [CGPoint] {
        [
            CGPoint(x: 0.18, y: 0.24),
            CGPoint(x: 0.34, y: 0.18),
            CGPoint(x: 0.50, y: 0.24),
            CGPoint(x: 0.68, y: 0.20),
            CGPoint(x: 0.82, y: 0.30),
            CGPoint(x: 0.24, y: 0.45),
            CGPoint(x: 0.42, y: 0.42),
            CGPoint(x: 0.58, y: 0.48),
            CGPoint(x: 0.76, y: 0.52),
            CGPoint(x: 0.16, y: 0.68),
            CGPoint(x: 0.36, y: 0.72),
            CGPoint(x: 0.54, y: 0.70),
            CGPoint(x: 0.70, y: 0.76),
            CGPoint(x: 0.86, y: 0.66)
        ]
    }

    private var placeholderEdges: [(Int, Int)] {
        [
            (0, 5), (1, 5), (1, 6), (2, 6), (2, 7), (3, 7), (3, 8),
            (4, 8), (5, 9), (6, 10), (7, 10), (7, 11), (8, 12), (8, 13),
            (10, 12), (11, 13)
        ]
    }
}

private struct GraphMessageCard: View {
    let systemImage: String
    let title: String
    let message: String
    var warning = false
    @State private var iconPhase: Double = 0

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(warning ? AppTheme.outdatedColor : .accentColor)
                .scaleEffect(warning ? 1.0 + iconPhase * 0.06 : 1.0)
            Text(LocalizedStringKey(title))
                .font(.headline)
            Text(LocalizedStringKey(message))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .nativePanel(subtle: false)
        .frame(maxWidth: 420)
        .onAppear {
            if warning {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    iconPhase = 1
                }
            }
        }
    }
}
