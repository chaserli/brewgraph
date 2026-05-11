import CoreGraphics
import Foundation

struct GraphLayoutEngine {
    private static let maxFullGraphNodesPerColumn = 9

    static func fullGraph(snapshot: BrewSnapshot) -> GraphLayout {
        let connectedFormulaIDs = Set(snapshot.edges.flatMap { [$0.formulaID, $0.dependencyID] })
        let formulaPackages = snapshot.packages.filter { package in
            package.kind == .formula && connectedFormulaIDs.contains(package.id)
        }
        let formulaNames = Set(formulaPackages.map(\.name))

        guard !formulaPackages.isEmpty else {
            return GraphLayout(nodes: [], edges: [])
        }

        let packageByName = Dictionary(uniqueKeysWithValues: formulaPackages.map { ($0.name, $0) })
        let columns = orderedFullGraphColumns(
            packageByName: packageByName,
            deps: snapshot.deps,
            reverseDeps: snapshot.reverseDeps,
            formulaNames: formulaNames
        )
        let columnCount = max(columns.count, 1)
        let columnStep = 0.88 / CGFloat(columnCount)
        var nodes: [GraphNode] = []

        for (column, columnNames) in columns.enumerated() {
            let rowCount = max(columnNames.count, 1)
            let rowStep = 0.84 / CGFloat(rowCount)
            let x = 0.06 + CGFloat(column) * columnStep + columnStep / 2

            for (row, name) in columnNames.enumerated() {
                guard let package = packageByName[name] else {
                    continue
                }

                let columnStagger = column.isMultiple(of: 2) ? 0 : min(rowStep * 0.12, 0.014)
                let y = min(0.96, max(0.04, 0.08 + CGFloat(row) * rowStep + rowStep / 2 + columnStagger))

                nodes.append(
                    GraphNode(
                        id: package.id,
                        label: package.name,
                        packageID: package.id,
                        position: CGPoint(x: x, y: y),
                        role: .normal,
                        reverseCount: package.reverseDependencies.count,
                        installReason: package.installReason,
                        isExternalTap: package.isExternalTap
                    )
                )
            }
        }

        nodes = relaxedFullGraphNodes(nodes, edges: snapshot.edges)

        let visibleNodeIDs = Set(nodes.map(\.id))
        let visibleEdges = snapshot.edges.filter { edge in
            visibleNodeIDs.contains(edge.formulaID) && visibleNodeIDs.contains(edge.dependencyID)
        }

        return GraphLayout(nodes: nodes, edges: visibleEdges)
    }

    static func localGraph(snapshot: BrewSnapshot, selectedName: String?, depth: Int) -> GraphLayout {
        guard let selectedName,
              let selected = snapshot.package(named: selectedName),
              selected.kind == .formula else {
            return fullGraph(snapshot: snapshot)
        }

        var nodes: [GraphNode] = [
            GraphNode(
                id: selected.id,
                label: selectedName,
                packageID: selected.id,
                position: CGPoint(x: 0.5, y: 0.5),
                role: .selected,
                reverseCount: selected.reverseDependencies.count,
                installReason: selected.installReason,
                isExternalTap: selected.isExternalTap
            )
        ]

        nodes.append(contentsOf: positionedClusteredLocalNodes(
            seed: selectedName,
            adjacency: snapshot.reverseDeps,
            role: .dependent,
            maxDepth: depth,
            snapshot: snapshot
        ))
        nodes.append(contentsOf: positionedClusteredLocalNodes(
            seed: selectedName,
            adjacency: snapshot.deps,
            role: .dependency,
            maxDepth: depth,
            snapshot: snapshot
        ))

        nodes = relaxedLocalNodes(dedupe(nodes))

        let nodeIDs = Set(nodes.map(\.id))
        let edges = snapshot.edges.filter { nodeIDs.contains($0.formulaID) && nodeIDs.contains($0.dependencyID) }

        nodes = relaxedLocalNodes(nodes, edges: edges)

        return GraphLayout(nodes: nodes, edges: edges)
    }

    private static func orderedFullGraphColumns(
        packageByName: [String: Package],
        deps: [String: [String]],
        reverseDeps: [String: [String]],
        formulaNames: Set<String>
    ) -> [[String]] {
        let depthMemo = fullGraphDepths(
            packageByName: packageByName,
            deps: deps,
            formulaNames: formulaNames
        )
        var layers = Dictionary(grouping: formulaNames) { depthMemo[$0] ?? 0 }
            .mapValues { names in
                names.sorted { lhs, rhs in
                    fullGraphPriority(lhs, rhs, packageByName: packageByName)
                }
            }

        for _ in 0..<4 {
            for depth in layers.keys.sorted() where depth > 0 {
                guard let adjacentNames = layers[depth - 1], !adjacentNames.isEmpty else {
                    continue
                }

                layers[depth] = barycentricSorted(
                    names: layers[depth] ?? [],
                    adjacentNames: adjacentNames,
                    neighbors: { name in (deps[name] ?? packageByName[name]?.dependencies ?? []).filter { formulaNames.contains($0) } },
                    packageByName: packageByName
                )
            }

            for depth in layers.keys.sorted(by: >) {
                guard let adjacentNames = layers[depth + 1], !adjacentNames.isEmpty else {
                    continue
                }

                layers[depth] = barycentricSorted(
                    names: layers[depth] ?? [],
                    adjacentNames: adjacentNames,
                    neighbors: { name in (reverseDeps[name] ?? packageByName[name]?.reverseDependencies ?? []).filter { formulaNames.contains($0) } },
                    packageByName: packageByName
                )
            }
        }

        return layers.keys.sorted(by: >).flatMap { depth in
            tapBalancedOrder(layers[depth] ?? [], packageByName: packageByName)
                .chunked(maxSize: maxFullGraphNodesPerColumn)
        }
    }

    private static func tapBalancedOrder(_ names: [String], packageByName: [String: Package]) -> [String] {
        let grouped = Dictionary(grouping: names) { name in
            packageByName[name]?.tapDisplayName ?? "unknown"
        }
        let tapOrder = grouped.keys.sorted { lhs, rhs in
            let lhsExternal = !["homebrew/core", "homebrew/cask", "unknown"].contains(lhs)
            let rhsExternal = !["homebrew/core", "homebrew/cask", "unknown"].contains(rhs)
            if lhsExternal != rhsExternal {
                return !lhsExternal
            }
            if (grouped[lhs]?.count ?? 0) != (grouped[rhs]?.count ?? 0) {
                return (grouped[lhs]?.count ?? 0) > (grouped[rhs]?.count ?? 0)
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        var buckets = Dictionary(uniqueKeysWithValues: grouped.map { tap, values in
            (tap, values)
        })
        var result: [String] = []

        while result.count < names.count {
            var appended = false
            for tap in tapOrder {
                guard let next = buckets[tap]?.first else {
                    continue
                }
                result.append(next)
                buckets[tap]?.removeFirst()
                appended = true
            }
            if !appended {
                break
            }
        }

        return result
    }

    private static func fullGraphDepths(
        packageByName: [String: Package],
        deps: [String: [String]],
        formulaNames: Set<String>
    ) -> [String: Int] {
        var depthMemo: [String: Int] = [:]
        var visiting: Set<String> = []

        func depth(for name: String) -> Int {
            if let depth = depthMemo[name] {
                return depth
            }
            if visiting.contains(name) {
                return 0
            }

            visiting.insert(name)
            defer { visiting.remove(name) }

            let directDeps = (deps[name] ?? packageByName[name]?.dependencies ?? [])
                .filter { formulaNames.contains($0) }

            let depth = directDeps.isEmpty ? 0 : (directDeps.map(depth(for:)).max() ?? 0) + 1
            depthMemo[name] = depth
            return depth
        }

        for name in formulaNames {
            _ = depth(for: name)
        }

        return depthMemo
    }

    private static func barycentricSorted(
        names: [String],
        adjacentNames: [String],
        neighbors: (String) -> [String],
        packageByName: [String: Package]
    ) -> [String] {
        guard !names.isEmpty, !adjacentNames.isEmpty else {
            return names.sorted { lhs, rhs in
                fullGraphPriority(lhs, rhs, packageByName: packageByName)
            }
        }

        let adjacentIndex = Dictionary(uniqueKeysWithValues: adjacentNames.enumerated().map { ($0.element, $0.offset) })

        return names.sorted { lhs, rhs in
            let lhsCenter = barycenter(for: lhs, neighbors: neighbors, adjacentIndex: adjacentIndex)
            let rhsCenter = barycenter(for: rhs, neighbors: neighbors, adjacentIndex: adjacentIndex)

            switch (lhsCenter, rhsCenter) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return fullGraphPriority(lhs, rhs, packageByName: packageByName)
            }
        }
    }

    private static func barycenter(
        for name: String,
        neighbors: (String) -> [String],
        adjacentIndex: [String: Int]
    ) -> Double? {
        let indexes = neighbors(name).compactMap { adjacentIndex[$0] }
        guard !indexes.isEmpty else {
            return nil
        }

        return Double(indexes.reduce(0, +)) / Double(indexes.count)
    }

    private static func fullGraphPriority(
        _ lhs: String,
        _ rhs: String,
        packageByName: [String: Package]
    ) -> Bool {
        guard let lhsPackage = packageByName[lhs], let rhsPackage = packageByName[rhs] else {
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        if lhsPackage.reverseDependencies.count != rhsPackage.reverseDependencies.count {
            return lhsPackage.reverseDependencies.count > rhsPackage.reverseDependencies.count
        }
        if lhsPackage.dependencies.count != rhsPackage.dependencies.count {
            return lhsPackage.dependencies.count > rhsPackage.dependencies.count
        }

        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func positionedClusteredLocalNodes(
        seed: String,
        adjacency: [String: [String]],
        role: GraphNode.Role,
        maxDepth: Int,
        snapshot: BrewSnapshot
    ) -> [GraphNode] {
        guard maxDepth > 0 else {
            return []
        }

        var recordsByName: [String: LocalPlacementRecord] = [:]
        var visited: Set<String> = [seed]
        var frontier: [(name: String, root: String)] = [(seed, seed)]

        for level in 1...maxDepth {
            var next: [(name: String, root: String)] = []

            for source in frontier.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let neighbors = sortedLocalNames(adjacency[source.name] ?? [], snapshot: snapshot)
                for neighbor in neighbors where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    let root = level == 1 ? neighbor : source.root
                    recordsByName[neighbor] = LocalPlacementRecord(
                        name: neighbor,
                        level: level,
                        root: root,
                        parent: source.name
                    )
                    next.append((neighbor, root))
                }
            }

            if next.isEmpty {
                break
            }

            frontier = next
        }

        let roots = sortedLocalNames(Array(Set(recordsByName.values.map(\.root))), snapshot: snapshot)
        let rootIndex = Dictionary(uniqueKeysWithValues: roots.enumerated().map { ($0.element, $0.offset) })
        let recordsByRoot = Dictionary(grouping: recordsByName.values, by: \.root)
        let recordsByParent = Dictionary(grouping: recordsByName.values, by: \.parent)
        let sideCenter = role == .dependent ? CGFloat.pi : CGFloat.zero
        let sideSign: CGFloat = role == .dependent ? -1 : 1
        let arcWidth = localRootArcWidth(count: roots.count)
        let orderedRecords = recordsByName.values
            .sorted { lhs, rhs in
                if lhs.root != rhs.root {
                    return (rootIndex[lhs.root] ?? 0) < (rootIndex[rhs.root] ?? 0)
                }
                if lhs.level != rhs.level {
                    return lhs.level < rhs.level
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        var anchorByName: [String: CGPoint] = [seed: CGPoint(x: 0.5, y: 0.5)]
        var nodes: [GraphNode] = []

        for record in orderedRecords {
            guard let package = snapshot.package(named: record.name),
                  let rootOffset = rootIndex[record.root] else {
                continue
            }

            let rootAngle = localRootAngle(index: rootOffset, count: roots.count, center: sideCenter, arcWidth: arcWidth)
            let groupRecords = recordsByRoot[record.root] ?? []
            let siblings = recordsByParent[record.parent]?
                .filter { $0.level == record.level }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
            let siblingIndex = siblings.firstIndex(where: { $0.name == record.name }) ?? 0
            let position: CGPoint

            if record.level == 1 {
                let groupWeight = min(0.040, CGFloat(max(0, groupRecords.count - 2)) * 0.004)
                let radiusX = min(0.320, 0.255 + groupWeight)
                let radiusY = min(0.295, 0.235 + groupWeight * 0.7)
                let position = CGPoint(
                    x: clamp(0.5 + cos(rootAngle) * radiusX, lower: 0.06, upper: 0.94),
                    y: clamp(0.5 + sin(rootAngle) * radiusY, lower: 0.08, upper: 0.92)
                )
                anchorByName[record.name] = position
                nodes.append(localNode(package: package, record: record, position: position, role: role))
                continue
            }

            if let parentPosition = anchorByName[record.parent] {
                let siblingOffset = localSiblingLinearOffset(index: siblingIndex, count: siblings.count)
                let branchDistance = min(0.150, 0.110 + CGFloat(record.level - 2) * 0.020)
                let branchSkew = CGFloat((siblingIndex % 3) - 1) * 0.010
                position = CGPoint(
                    x: clamp(parentPosition.x + sideSign * (branchDistance + abs(branchSkew)), lower: 0.06, upper: 0.94),
                    y: clamp(parentPosition.y + siblingOffset + branchSkew, lower: 0.08, upper: 0.92)
                )
            } else {
                let siblings = groupRecords
                    .filter { $0.level == record.level }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let siblingIndex = siblings.firstIndex(where: { $0.name == record.name }) ?? 0
                let siblingSpread = localSiblingSpread(index: siblingIndex, count: siblings.count, level: record.level)
                let angle = rootAngle + siblingSpread
                let radiusX = min(0.445, 0.230 + CGFloat(record.level - 1) * 0.095)
                let radiusY = min(0.355, 0.215 + CGFloat(record.level - 1) * 0.050)
                position = CGPoint(
                    x: clamp(0.5 + cos(angle) * radiusX, lower: 0.06, upper: 0.94),
                    y: clamp(0.5 + sin(angle) * radiusY, lower: 0.08, upper: 0.92)
                )
            }

            anchorByName[record.name] = position
            nodes.append(localNode(package: package, record: record, position: position, role: role))
        }

        return nodes
    }

    private static func localNode(
        package: Package,
        record: LocalPlacementRecord,
        position: CGPoint,
        role: GraphNode.Role
    ) -> GraphNode {
        GraphNode(
            id: package.id,
            label: record.name,
            packageID: package.id,
            position: position,
            role: role,
            reverseCount: package.reverseDependencies.count,
            installReason: package.installReason,
            isExternalTap: package.isExternalTap
        )
    }

    private static func localRootArcWidth(count: Int) -> CGFloat {
        guard count > 1 else {
            return 0
        }

        return min(CGFloat.pi * 0.78, max(CGFloat.pi * 0.30, CGFloat(count - 1) * CGFloat.pi * 0.052))
    }

    private static func localRootAngle(index: Int, count: Int, center: CGFloat, arcWidth: CGFloat) -> CGFloat {
        guard count > 1 else {
            return center
        }

        let progress = CGFloat(index) / CGFloat(count - 1)
        return center + (progress - 0.5) * arcWidth
    }

    private static func localSiblingSpread(index: Int, count: Int, level: Int) -> CGFloat {
        guard count > 1, level > 1 else {
            return 0
        }

        let progress = CGFloat(index) / CGFloat(count - 1)
        let width = min(CGFloat.pi * 0.34, max(CGFloat.pi * 0.08, CGFloat(count - 1) * CGFloat.pi * 0.022))
        let alternatingOffset = index.isMultiple(of: 2) ? CGFloat.pi * 0.010 : -CGFloat.pi * 0.010

        return (progress - 0.5) * width / CGFloat(level) + alternatingOffset
    }

    private static func localSiblingLinearOffset(index: Int, count: Int) -> CGFloat {
        guard count > 1 else {
            return 0
        }

        let progress = CGFloat(index) / CGFloat(count - 1)
        let spread = min(0.220, max(0.070, CGFloat(count - 1) * 0.034))

        return (progress - 0.5) * spread
    }

    private static func relaxedLocalNodes(_ nodes: [GraphNode], edges: [DependencyEdge] = []) -> [GraphNode] {
        guard nodes.count > 2 else {
            return nodes
        }

        var bodies = nodes.map { node in
            let halfSize = estimatedLocalNodeHalfSize(for: node)
            return LocalLayoutBody(
                node: node,
                anchor: node.position,
                position: node.position,
                halfWidth: halfSize.width,
                halfHeight: halfSize.height
            )
        }
        let indexByID = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($0.element.node.id, $0.offset) })
        let edgeIndexes = edges.compactMap { edge -> (Int, Int)? in
            guard let from = indexByID[edge.formulaID], let to = indexByID[edge.dependencyID] else {
                return nil
            }

            return (from, to)
        }

        for iteration in 0..<170 {
            let cooling = 1 - CGFloat(iteration) / 170
            var offsets = Array(repeating: CGPoint.zero, count: bodies.count)

            for lhs in bodies.indices {
                for rhs in bodies.indices where rhs > lhs {
                    let deltaX = bodies[rhs].position.x - bodies[lhs].position.x
                    let deltaY = bodies[rhs].position.y - bodies[lhs].position.y
                    let fallbackAngle = CGFloat((lhs * 41 + rhs * 17) % 360) * .pi / 180
                    let unitX = abs(deltaX) < 0.0001 && abs(deltaY) < 0.0001 ? cos(fallbackAngle) : deltaX / max(0.0001, hypot(deltaX, deltaY))
                    let unitY = abs(deltaX) < 0.0001 && abs(deltaY) < 0.0001 ? sin(fallbackAngle) : deltaY / max(0.0001, hypot(deltaX, deltaY))
                    let overlapX = bodies[lhs].halfWidth + bodies[rhs].halfWidth + 0.020 - abs(deltaX)
                    let overlapY = bodies[lhs].halfHeight + bodies[rhs].halfHeight + 0.028 - abs(deltaY)

                    if overlapX > 0 && overlapY > 0 {
                        let push = min(0.018, (min(overlapX, overlapY) / 2) + 0.002)
                        if overlapX < overlapY {
                            applyLocalPush(
                                lhs: lhs,
                                rhs: rhs,
                                x: unitX.signOrOne * push,
                                y: 0,
                                bodies: bodies,
                                offsets: &offsets
                            )
                        } else {
                            applyLocalPush(
                                lhs: lhs,
                                rhs: rhs,
                                x: 0,
                                y: unitY.signOrOne * push,
                                bodies: bodies,
                                offsets: &offsets
                            )
                        }
                    } else {
                        let distance = max(0.001, hypot(deltaX, deltaY))
                        let comfort = max(0.090, min(0.18, bodies[lhs].halfWidth + bodies[rhs].halfWidth + 0.055))
                        guard distance < comfort else {
                            continue
                        }

                        let strength = min(0.010, (comfort - distance) * 0.045)
                        applyLocalPush(
                            lhs: lhs,
                            rhs: rhs,
                            x: unitX * strength,
                            y: unitY * strength,
                            bodies: bodies,
                            offsets: &offsets
                        )
                    }
                }
            }

            for (from, to) in edgeIndexes {
                let deltaX = bodies[to].position.x - bodies[from].position.x
                let deltaY = bodies[to].position.y - bodies[from].position.y
                let distance = max(0.001, hypot(deltaX, deltaY))
                let idealLength: CGFloat = bodies[from].node.role == .selected || bodies[to].node.role == .selected ? 0.245 : 0.155
                let strength = (distance - idealLength) * 0.010
                let x = deltaX / distance * strength
                let y = deltaY / distance * strength

                if !bodies[from].isFixed {
                    offsets[from].x += x
                    offsets[from].y += y
                }
                if !bodies[to].isFixed {
                    offsets[to].x -= x
                    offsets[to].y -= y
                }
            }

            for index in bodies.indices where !bodies[index].isFixed {
                let anchorStrength: CGFloat = bodies[index].node.role == .normal ? 0.030 : 0.045
                offsets[index].x += (bodies[index].anchor.x - bodies[index].position.x) * anchorStrength
                offsets[index].y += (bodies[index].anchor.y - bodies[index].position.y) * anchorStrength

                switch bodies[index].node.role {
                case .dependency where bodies[index].position.x < 0.54:
                    offsets[index].x += (0.54 - bodies[index].position.x) * 0.12
                case .dependent where bodies[index].position.x > 0.46:
                    offsets[index].x -= (bodies[index].position.x - 0.46) * 0.12
                default:
                    break
                }
            }

            for index in bodies.indices where !bodies[index].isFixed {
                let maxStep = 0.012 * max(0.32, cooling)
                let stepLength = max(0.001, hypot(offsets[index].x, offsets[index].y))
                let scale = min(1, maxStep / stepLength)

                bodies[index].position.x = clamp(
                    bodies[index].position.x + offsets[index].x * scale,
                    lower: 0.045 + bodies[index].halfWidth,
                    upper: 0.955 - bodies[index].halfWidth
                )
                bodies[index].position.y = clamp(
                    bodies[index].position.y + offsets[index].y * scale,
                    lower: 0.070 + bodies[index].halfHeight,
                    upper: 0.930 - bodies[index].halfHeight
                )
            }
        }

        return bodies.map { body in
            GraphNode(
                id: body.node.id,
                label: body.node.label,
                packageID: body.node.packageID,
                position: body.position,
                role: body.node.role,
                reverseCount: body.node.reverseCount,
                installReason: body.node.installReason,
                isExternalTap: body.node.isExternalTap
            )
        }
    }

    private static func relaxedFullGraphNodes(_ nodes: [GraphNode], edges: [DependencyEdge]) -> [GraphNode] {
        guard nodes.count > 8 else {
            return nodes
        }

        let edgeIDs = Set(edges.flatMap { [$0.formulaID, $0.dependencyID] })
        var bodies = nodes.map { node in
            FullLayoutBody(
                node: node,
                anchor: node.position,
                position: node.position,
                halfWidth: estimatedFullNodeHalfSize(for: node).width,
                halfHeight: estimatedFullNodeHalfSize(for: node).height,
                isConnected: edgeIDs.contains(node.id)
            )
        }

        for iteration in 0..<90 {
            let cooling = 1 - CGFloat(iteration) / 90
            var offsets = Array(repeating: CGPoint.zero, count: bodies.count)

            for lhs in bodies.indices {
                for rhs in bodies.indices where rhs > lhs {
                    let deltaX = bodies[rhs].position.x - bodies[lhs].position.x
                    let deltaY = bodies[rhs].position.y - bodies[lhs].position.y
                    let fallbackAngle = CGFloat((lhs * 31 + rhs * 13) % 360) * .pi / 180
                    let distance = max(0.0001, hypot(deltaX, deltaY))
                    let unitX = distance < 0.0002 ? cos(fallbackAngle) : deltaX / distance
                    let unitY = distance < 0.0002 ? sin(fallbackAngle) : deltaY / distance
                    let overlapX = bodies[lhs].halfWidth + bodies[rhs].halfWidth + 0.012 - abs(deltaX)
                    let overlapY = bodies[lhs].halfHeight + bodies[rhs].halfHeight + 0.020 - abs(deltaY)

                    guard overlapX > 0, overlapY > 0 else {
                        continue
                    }

                    let push = min(0.010, min(overlapX, overlapY) / 2 + 0.0015)
                    if overlapX < overlapY {
                        offsets[lhs].x -= unitX.signOrOne * push
                        offsets[rhs].x += unitX.signOrOne * push
                    } else {
                        offsets[lhs].y -= unitY.signOrOne * push
                        offsets[rhs].y += unitY.signOrOne * push
                    }
                }
            }

            for index in bodies.indices {
                let anchorStrength: CGFloat = bodies[index].isConnected ? 0.060 : 0.080
                offsets[index].x += (bodies[index].anchor.x - bodies[index].position.x) * anchorStrength
                offsets[index].y += (bodies[index].anchor.y - bodies[index].position.y) * anchorStrength

                let maxStep = 0.010 * max(0.35, cooling)
                let stepLength = max(0.001, hypot(offsets[index].x, offsets[index].y))
                let scale = min(1, maxStep / stepLength)
                bodies[index].position.x = clamp(
                    bodies[index].position.x + offsets[index].x * scale,
                    lower: 0.035 + bodies[index].halfWidth,
                    upper: 0.965 - bodies[index].halfWidth
                )
                bodies[index].position.y = clamp(
                    bodies[index].position.y + offsets[index].y * scale,
                    lower: 0.055 + bodies[index].halfHeight,
                    upper: 0.945 - bodies[index].halfHeight
                )
            }
        }

        return bodies.map { body in
            GraphNode(
                id: body.node.id,
                label: body.node.label,
                packageID: body.node.packageID,
                position: body.position,
                role: body.node.role,
                reverseCount: body.node.reverseCount,
                installReason: body.node.installReason,
                isExternalTap: body.node.isExternalTap
            )
        }
    }

    private static func estimatedFullNodeHalfSize(for node: GraphNode) -> CGSize {
        let characterCount = CGFloat(min(node.label.count, 14))
        let countWidth: CGFloat = node.reverseCount > 0 ? 0.012 : 0
        let width = min(0.120, max(0.044, 0.030 + characterCount * 0.0048 + countWidth))
        let height: CGFloat = 0.020

        return CGSize(width: width / 2, height: height / 2)
    }

    private static func applyLocalPush(
        lhs: Int,
        rhs: Int,
        x: CGFloat,
        y: CGFloat,
        bodies: [LocalLayoutBody],
        offsets: inout [CGPoint]
    ) {
        if !bodies[lhs].isFixed {
            offsets[lhs].x -= x
            offsets[lhs].y -= y
        }
        if !bodies[rhs].isFixed {
            offsets[rhs].x += x
            offsets[rhs].y += y
        }
    }

    private static func estimatedLocalNodeHalfSize(for node: GraphNode) -> CGSize {
        let characterCount = CGFloat(min(node.label.count, node.role == .selected ? 22 : 18))
        let countWidth: CGFloat = node.reverseCount > 0 ? 0.018 : 0
        let minimumWidth: CGFloat = node.role == .selected ? 0.090 : 0.072
        let width = min(0.170, max(minimumWidth, 0.045 + characterCount * 0.0062 + countWidth))
        let height: CGFloat = node.role == .selected ? 0.040 : 0.032

        return CGSize(width: width / 2, height: height / 2)
    }

    private static func sortedLocalNames(_ names: [String], snapshot: BrewSnapshot) -> [String] {
        names.sorted { lhs, rhs in
            guard let lhsPackage = snapshot.package(named: lhs),
                  let rhsPackage = snapshot.package(named: rhs) else {
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

            if lhsPackage.reverseDependencies.count != rhsPackage.reverseDependencies.count {
                return lhsPackage.reverseDependencies.count > rhsPackage.reverseDependencies.count
            }
            if lhsPackage.dependencies.count != rhsPackage.dependencies.count {
                return lhsPackage.dependencies.count > rhsPackage.dependencies.count
            }

            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func dedupe(_ nodes: [GraphNode]) -> [GraphNode] {
        var seen: Set<String> = []
        var result: [GraphNode] = []

        for node in nodes where !seen.contains(node.id) {
            seen.insert(node.id)
            result.append(node)
        }

        return result
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }
}

private struct LocalLayoutBody {
    let node: GraphNode
    let anchor: CGPoint
    var position: CGPoint
    let halfWidth: CGFloat
    let halfHeight: CGFloat

    var isFixed: Bool {
        node.role == .selected
    }
}

private struct FullLayoutBody {
    let node: GraphNode
    let anchor: CGPoint
    var position: CGPoint
    let halfWidth: CGFloat
    let halfHeight: CGFloat
    let isConnected: Bool
}

private struct LocalPlacementRecord {
    let name: String
    let level: Int
    let root: String
    let parent: String
}

private extension CGFloat {
    var signOrOne: CGFloat {
        self < 0 ? -1 : 1
    }
}

private extension Array {
    func chunked(maxSize: Int) -> [[Element]] {
        guard maxSize > 0, !isEmpty else {
            return []
        }

        var result: [[Element]] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: maxSize, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
