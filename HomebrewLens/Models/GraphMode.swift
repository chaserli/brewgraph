import Foundation

enum GraphMode: String, CaseIterable, Identifiable {
    case fullGraph
    case localGraph
    case dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullGraph:
            "Full Graph"
        case .localGraph:
            "Local Graph"
        case .dashboard:
            "Dashboard"
        }
    }

    var symbolName: String {
        switch self {
        case .fullGraph:
            "point.3.connected.trianglepath.dotted"
        case .localGraph:
            "scope"
        case .dashboard:
            "chart.bar.xaxis"
        }
    }

    var subtitle: String {
        switch self {
        case .fullGraph:
            "Graph workspace"
        case .localGraph:
            "Selected package neighborhood"
        case .dashboard:
            "Summary workspace"
        }
    }
}
