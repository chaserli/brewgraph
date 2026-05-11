import CoreGraphics
import Foundation

struct GraphNode: Identifiable, Hashable {
    enum Role: Hashable {
        case normal
        case selected
        case dependency
        case dependent
    }

    let id: String
    let label: String
    let packageID: String
    let position: CGPoint
    let role: Role
    let reverseCount: Int
    let installReason: PackageInstallReason
    let isExternalTap: Bool
}

struct GraphLayout: Equatable {
    let nodes: [GraphNode]
    let edges: [DependencyEdge]

    var nodeByID: [String: GraphNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }
}
