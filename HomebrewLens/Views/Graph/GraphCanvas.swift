import SwiftUI

struct GraphCanvas: View {
    let layout: GraphLayout
    let selectedPackageID: String?
    let onSelectPackage: (String) -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var baseRotation: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var manualNodePositions: [String: CGPoint] = [:]
    @State private var nodeDragStartPositions: [String: CGPoint] = [:]
    @State private var draggedNodeID: String?

    var body: some View {
        GeometryReader { proxy in
            let priorityLabelIDs = visiblePriorityLabelIDs(in: proxy.size)
            let renderedNodes = visibleNodes(in: proxy.size, priorityLabelIDs: priorityLabelIDs)
            let overlayNodes = renderedNodes.filter { !rendersAsCanvasDot($0, priorityLabelIDs: priorityLabelIDs) }

            ZStack {
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawEdges(context: context, size: size, priorityLabelIDs: priorityLabelIDs)
                    drawCanvasNodes(context: context, size: size, nodes: renderedNodes, priorityLabelIDs: priorityLabelIDs)
                }

                ForEach(overlayNodes) { node in
                    GraphNodeLabel(
                        node: node,
                        isSelected: selectedPackageID == node.packageID,
                        isDirectDependencyHighlighted: directSelectedDependencyIDs.contains(node.packageID) && node.role == .dependency,
                        density: density,
                        labelMode: labelMode,
                        showsPriorityLabel: priorityLabelIDs.contains(node.id)
                    )
                    .contentShape(Rectangle())
                    .position(screenPoint(for: node, size: proxy.size))
                    .highPriorityGesture(nodeInteractionGesture(for: node, in: proxy.size))
                    .zIndex(selectedPackageID == node.packageID ? 3 : directSelectedDependencyIDs.contains(node.packageID) ? 2 : node.reverseCount > 0 ? 1 : 0)
                    .accessibilityLabel(node.label)
                    .accessibilityAddTraits(.isButton)
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        GraphLegend()
                        Spacer()
                        GraphViewportControls(
                            scale: scale,
                            canCenterSelection: selectedNode != nil,
                            canResetNodePositions: !manualNodePositions.isEmpty,
                            fitAll: { fitAll(in: proxy.size) },
                            centerSelection: { centerSelectedNode(in: proxy.size) },
                            resetNodePositions: { resetManualNodePositions(in: proxy.size) },
                            zoomOut: { zoom(by: 0.82, in: proxy.size) },
                            zoomIn: { zoom(by: 1.18, in: proxy.size) }
                        )
                    }
                    .padding(16)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(canvasTapGesture(in: proxy.size, nodes: renderedNodes, priorityLabelIDs: priorityLabelIDs))
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(rotationGesture)
            .onAppear {
                viewportSize = proxy.size
                fitAll(in: proxy.size, animated: false)
            }
            .onChange(of: proxy.size) { _, newSize in
                viewportSize = newSize
                fitAll(in: newSize, animated: false)
            }
            .onChange(of: layout) {
                manualNodePositions = [:]
                nodeDragStartPositions = [:]
                draggedNodeID = nil
                fitAll(in: viewportSize, animated: true)
            }
            .onChange(of: selectedPackageID) {
                centerSelectedNode(in: viewportSize)
            }
        }
        .clipped()
    }

    private var density: GraphDensity {
        switch layout.nodes.count {
        case 0..<45:
            .roomy
        case 45..<95:
            .compact
        default:
            .dense
        }
    }

    private var selectedNode: GraphNode? {
        guard let selectedPackageID else {
            return nil
        }

        return layout.nodes.first { $0.packageID == selectedPackageID }
    }

    private var selectedNeighborhoodIDs: Set<String> {
        guard let selectedPackageID else {
            return []
        }

        var ids: Set<String> = [selectedPackageID]
        for edge in layout.edges where edge.formulaID == selectedPackageID || edge.dependencyID == selectedPackageID {
            ids.insert(edge.formulaID)
            ids.insert(edge.dependencyID)
        }

        return ids
    }

    private var directSelectedDependencyIDs: Set<String> {
        guard let selectedPackageID else {
            return []
        }

        return Set(layout.edges
            .filter { $0.formulaID == selectedPackageID }
            .map(\.dependencyID))
    }

    private var labelMode: GraphLabelMode {
        switch density {
        case .roomy:
            return scale < 0.62 ? GraphLabelMode.priority : GraphLabelMode.expanded
        case .compact:
            return scale < 0.80 ? GraphLabelMode.priority : GraphLabelMode.expanded
        case .dense:
            if scale < 1.12 {
                return .dots
            }
            if scale < 1.72 {
                return .priority
            }
            return .expanded
        }
    }

    private func visiblePriorityLabelIDs(in size: CGSize) -> Set<String> {
        guard labelMode == .priority, size.width > 0, size.height > 0 else {
            return []
        }

        var occupiedRects: [CGRect] = []
        var visibleIDs: Set<String> = []
        let selectionIDs = selectedNeighborhoodIDs
        let candidates = layout.nodes
            .filter { node in
                node.role == .normal
                    && selectedPackageID != node.packageID
                    && (selectionIDs.contains(node.packageID) || isPriorityHub(node))
            }
            .sorted { lhs, rhs in
                let lhsSelectionContext = selectionIDs.contains(lhs.packageID)
                let rhsSelectionContext = selectionIDs.contains(rhs.packageID)
                if lhsSelectionContext != rhsSelectionContext {
                    return lhsSelectionContext
                }
                if lhs.reverseCount == rhs.reverseCount {
                    return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                }

                return lhs.reverseCount > rhs.reverseCount
            }

        for node in candidates {
            let point = screenPoint(for: node, size: size)
            let rect = estimatedPriorityLabelRect(for: node, at: point)

            if !occupiedRects.contains(where: { $0.intersects(rect) }) {
                occupiedRects.append(rect)
                visibleIDs.insert(node.id)
            }
        }

        return visibleIDs
    }

    private func visibleNodes(in size: CGSize, priorityLabelIDs: Set<String>) -> [GraphNode] {
        guard size.width > 0, size.height > 0 else {
            return layout.nodes
        }

        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: -140, dy: -140)
        return layout.nodes.filter { node in
            if selectedPackageID == node.packageID || node.role != .normal {
                return true
            }

            let point = screenPoint(for: node, size: size)
            let nodeSize = estimatedScreenNodeSize(for: node, priorityLabelIDs: priorityLabelIDs)
            let rect = CGRect(
                x: point.x - nodeSize.width / 2,
                y: point.y - nodeSize.height / 2,
                width: nodeSize.width,
                height: nodeSize.height
            )

            return rect.intersects(viewport)
        }
    }

    private func isPriorityHub(_ node: GraphNode) -> Bool {
        switch density {
        case .roomy:
            return node.reverseCount >= 2
        case .compact:
            return node.reverseCount >= 3
        case .dense:
            return node.reverseCount >= 5
        }
    }

    private func estimatedPriorityLabelRect(for node: GraphNode, at point: CGPoint) -> CGRect {
        let width = estimatedPriorityLabelWidth(for: node)
        let height: CGFloat = density == .dense ? 24 : 26

        return CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        .insetBy(dx: -8, dy: -6)
    }

    private func estimatedPriorityLabelWidth(for node: GraphNode) -> CGFloat {
        let visibleCharacterCount = min(node.label.count, density == .dense ? 12 : 18)
        let textWidth = CGFloat(visibleCharacterCount) * (density == .dense ? 6.2 : 6.8)
        let countWidth: CGFloat = node.reverseCount > 0 ? 18 : 0
        let dotAndSpacing: CGFloat = 13
        let padding: CGFloat = density == .dense ? 12 : 16

        return min(
            density == .dense ? 108 : 132,
            max(46, textWidth + countWidth + dotAndSpacing + padding)
        )
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedNodeID == nil else {
                    return
                }

                offset = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard draggedNodeID == nil else {
                    return
                }

                dragStart = offset
            }
    }

    private func nodeInteractionGesture(for node: GraphNode, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else {
                    return
                }

                if draggedNodeID == nil {
                    draggedNodeID = node.id
                    nodeDragStartPositions[node.id] = effectivePosition(for: node)
                }

                guard draggedNodeID == node.id,
                      let startPosition = nodeDragStartPositions[node.id] else {
                    return
                }

                guard hypot(value.translation.width, value.translation.height) >= 2 else {
                    return
                }

                let delta = normalizedGraphDelta(for: value.translation, size: size)
                manualNodePositions[node.id] = clampedNodePosition(
                    CGPoint(
                        x: startPosition.x + delta.x,
                        y: startPosition.y + delta.y
                    )
                )
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) < 3 {
                    onSelectPackage(node.packageID)
                }

                nodeDragStartPositions[node.id] = nil
                if draggedNodeID == node.id {
                    draggedNodeID = nil
                }
            }
    }

    private func canvasTapGesture(
        in size: CGSize,
        nodes: [GraphNode],
        priorityLabelIDs: Set<String>
    ) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard draggedNodeID == nil,
                      let node = nearestCanvasHit(
                        at: value.location,
                        in: size,
                        nodes: nodes,
                        priorityLabelIDs: priorityLabelIDs
                      ) else {
                    return
                }

                onSelectPackage(node.packageID)
            }
    }

    private func nearestCanvasHit(
        at point: CGPoint,
        in size: CGSize,
        nodes: [GraphNode],
        priorityLabelIDs: Set<String>
    ) -> GraphNode? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        var best: (node: GraphNode, distance: CGFloat)?
        for node in nodes where rendersAsCanvasDot(node, priorityLabelIDs: priorityLabelIDs) {
            let center = screenPoint(for: node, size: size)
            let radius = max(10, canvasDotDiameter(for: node) / 2 + 5)
            let distance = hypot(point.x - center.x, point.y - center.y)

            guard distance <= radius else {
                continue
            }
            if best == nil || distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (node, distance)
            }
        }

        return best?.node
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(3.0, max(0.45, baseScale * value))
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                rotation = baseRotation + value
            }
            .onEnded { _ in
                baseRotation = rotation
            }
    }

    private func screenPoint(for node: GraphNode, size: CGSize) -> CGPoint {
        transformedScreenPoint(
            for: effectivePosition(for: node),
            size: size,
            scale: scale,
            rotation: rotation,
            offset: offset
        )
    }

    private func effectivePosition(for node: GraphNode) -> CGPoint {
        manualNodePositions[node.id] ?? node.position
    }

    private func normalizedGraphDelta(for translation: CGSize, size: CGSize) -> CGPoint {
        let radians = rotation.radians
        let cosine = cos(radians)
        let sine = sin(radians)
        let scaledX = translation.width / max(scale, 0.001)
        let scaledY = translation.height / max(scale, 0.001)

        return CGPoint(
            x: (scaledX * cosine + scaledY * sine) / max(size.width, 1),
            y: (-scaledX * sine + scaledY * cosine) / max(size.height, 1)
        )
    }

    private func clampedNodePosition(_ position: CGPoint) -> CGPoint {
        CGPoint(
            x: min(0.98, max(0.02, position.x)),
            y: min(0.98, max(0.02, position.y))
        )
    }

    private func drawEdges(context: GraphicsContext, size: CGSize, priorityLabelIDs: Set<String>) {
        let routes = edgeRoutes(size: size, priorityLabelIDs: priorityLabelIDs)
        var highlightedRoutes: [EdgeRoute] = []

        for route in routes {
            if route.highlighted {
                highlightedRoutes.append(route)
                continue
            }

            drawEdge(route, context: context, size: size)
        }

        for route in highlightedRoutes {
            drawEdge(route, context: context, size: size)
        }
    }

    private func drawEdge(
        _ route: EdgeRoute,
        context: GraphicsContext,
        size: CGSize
    ) {
        guard route.highlighted || edgeIntersectsViewport(route: route, size: size) else {
            return
        }

        let curve = edgeCurve(for: route)

        let quietLineWidth = labelMode == .dots ? 0.7 : 1.0
        let color = edgeColor(highlighted: route.highlighted)

        if route.highlighted {
            context.stroke(
                curve.path,
                with: .color(color.opacity(0.18)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )
        }

        context.stroke(
            curve.path,
            with: .color(color),
            style: StrokeStyle(lineWidth: route.highlighted ? 2.1 : quietLineWidth, lineCap: .round)
        )

        if route.highlighted || scale > 0.58 {
            context.fill(
                arrowheadPath(for: curve, highlighted: route.highlighted),
                with: .color(color)
            )
        }
    }

    private func edgeIntersectsViewport(route: EdgeRoute, size: CGSize) -> Bool {
        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: -140, dy: -140)
        let minX = min(route.start.x, route.end.x, route.control1.x, route.control2.x)
        let minY = min(route.start.y, route.end.y, route.control1.y, route.control2.y)
        let maxX = max(route.start.x, route.end.x, route.control1.x, route.control2.x)
        let maxY = max(route.start.y, route.end.y, route.control1.y, route.control2.y)
        let edgeBounds = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
            .insetBy(dx: -40, dy: -40)

        return edgeBounds.intersects(viewport)
    }

    private func edgeRoutes(size: CGSize, priorityLabelIDs: Set<String>) -> [EdgeRoute] {
        let nodeByID = layout.nodeByID
        let frameByID = Dictionary(uniqueKeysWithValues: layout.nodes.map { node in
            let center = screenPoint(for: node, size: size)
            let nodeSize = estimatedScreenNodeSize(for: node, priorityLabelIDs: priorityLabelIDs)
            return (node.id, GraphNodeFrame(node: node, center: center, size: nodeSize))
        })
        let edgePlans: [EdgePlan] = layout.edges.enumerated().compactMap { index, edge in
            guard let fromNode = nodeByID[edge.formulaID],
                  let toNode = nodeByID[edge.dependencyID],
                  let fromFrame = frameByID[edge.formulaID],
                  let toFrame = frameByID[edge.dependencyID] else {
                return nil
            }

            let sides = preferredPortSides(from: fromFrame.center, to: toFrame.center)
            return EdgePlan(
                index: index,
                edge: edge,
                fromNode: fromNode,
                toNode: toNode,
                fromFrame: fromFrame,
                toFrame: toFrame,
                fromSide: sides.from,
                toSide: sides.to,
                highlighted: edgeIsHighlighted(edge, nodeByID: nodeByID)
            )
        }
        let portOffsets = portSlotOffsets(for: edgePlans)
        let laneOffsets = laneOffsets(for: edgePlans, portOffsets: portOffsets)

        return edgePlans.map { plan in
            let startOffset = portOffsets[PortSlotKey(edgeIndex: plan.index, endpoint: .source)] ?? 0
            let endOffset = portOffsets[PortSlotKey(edgeIndex: plan.index, endpoint: .target)] ?? 0
            let start = plan.fromFrame.portPoint(side: plan.fromSide, offset: startOffset, margin: plan.highlighted ? 4 : 3)
            let end = plan.toFrame.portPoint(side: plan.toSide, offset: endOffset, margin: plan.highlighted ? 5 : 4)
            let controls = edgeControls(
                start: start,
                end: end,
                fromSide: plan.fromSide,
                toSide: plan.toSide,
                laneOffset: laneOffsets[plan.index] ?? 0
            )

            return EdgeRoute(
                index: plan.index,
                edge: plan.edge,
                fromNode: plan.fromNode,
                toNode: plan.toNode,
                start: start,
                end: end,
                control1: controls.control1,
                control2: controls.control2,
                fromSide: plan.fromSide,
                toSide: plan.toSide,
                highlighted: plan.highlighted
            )
        }
    }

    private func preferredPortSides(from fromCenter: CGPoint, to toCenter: CGPoint) -> (from: EdgePortSide, to: EdgePortSide) {
        let deltaX = toCenter.x - fromCenter.x
        let deltaY = toCenter.y - fromCenter.y

        if abs(deltaX) >= abs(deltaY) * 0.72 {
            return deltaX >= 0 ? (.right, .left) : (.left, .right)
        }

        return deltaY >= 0 ? (.bottom, .top) : (.top, .bottom)
    }

    private func portSlotOffsets(for plans: [EdgePlan]) -> [PortSlotKey: CGFloat] {
        var connectionsByPort: [PortKey: [PortConnection]] = [:]

        for plan in plans {
            connectionsByPort[PortKey(nodeID: plan.fromNode.id, side: plan.fromSide), default: []].append(
                PortConnection(edgeIndex: plan.index, endpoint: .source, sortValue: plan.fromSide.sortValue(for: plan.toFrame.center))
            )
            connectionsByPort[PortKey(nodeID: plan.toNode.id, side: plan.toSide), default: []].append(
                PortConnection(edgeIndex: plan.index, endpoint: .target, sortValue: plan.toSide.sortValue(for: plan.fromFrame.center))
            )
        }

        var offsets: [PortSlotKey: CGFloat] = [:]
        for (port, connections) in connectionsByPort {
            let sortedConnections = connections.sorted {
                if $0.sortValue == $1.sortValue {
                    return $0.edgeIndex < $1.edgeIndex
                }

                return $0.sortValue < $1.sortValue
            }
            let count = sortedConnections.count
            let maxSpan = port.side == .left || port.side == .right ? CGFloat(count > 1 ? 18 : 0) : CGFloat(count > 1 ? 26 : 0)
            let gap = count > 1 ? min(7, (maxSpan * 2) / CGFloat(max(1, count - 1))) : 0

            for (slot, connection) in sortedConnections.enumerated() {
                let centeredSlot = CGFloat(slot) - CGFloat(count - 1) / 2
                offsets[PortSlotKey(edgeIndex: connection.edgeIndex, endpoint: connection.endpoint)] = centeredSlot * gap
            }
        }

        return offsets
    }

    private func laneOffsets(for plans: [EdgePlan], portOffsets: [PortSlotKey: CGFloat]) -> [Int: CGFloat] {
        var grouped: [LaneKey: [EdgePlan]] = [:]

        for plan in plans {
            let startOffset = portOffsets[PortSlotKey(edgeIndex: plan.index, endpoint: .source)] ?? 0
            let endOffset = portOffsets[PortSlotKey(edgeIndex: plan.index, endpoint: .target)] ?? 0
            let start = plan.fromFrame.portPoint(side: plan.fromSide, offset: startOffset, margin: 0)
            let end = plan.toFrame.portPoint(side: plan.toSide, offset: endOffset, margin: 0)
            let midXBucket = Int(((start.x + end.x) / 2 / 96).rounded(.down))
            let midYBucket = Int(((start.y + end.y) / 2 / 96).rounded(.down))
            grouped[LaneKey(fromSide: plan.fromSide, toSide: plan.toSide, midXBucket: midXBucket, midYBucket: midYBucket), default: []].append(plan)
        }

        var offsets: [Int: CGFloat] = [:]
        for (_, group) in grouped where group.count > 1 {
            let sortedGroup = group.sorted {
                if $0.fromNode.label == $1.fromNode.label {
                    return $0.toNode.label.localizedStandardCompare($1.toNode.label) == .orderedAscending
                }

                return $0.fromNode.label.localizedStandardCompare($1.fromNode.label) == .orderedAscending
            }
            let count = sortedGroup.count
            for (slot, plan) in sortedGroup.enumerated() {
                let centeredSlot = CGFloat(slot) - CGFloat(count - 1) / 2
                offsets[plan.index] = min(30, max(-30, centeredSlot * 7))
            }
        }

        return offsets
    }

    private func edgeControls(
        start: CGPoint,
        end: CGPoint,
        fromSide: EdgePortSide,
        toSide: EdgePortSide,
        laneOffset: CGFloat
    ) -> (control1: CGPoint, control2: CGPoint) {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let distance = max(1, hypot(deltaX, deltaY))
        let bend = min(max(distance * 0.34, 38), 170)
        let fromVector = fromSide.outwardVector
        let toVector = toSide.outwardVector
        let normal = CGPoint(x: -deltaY / distance, y: deltaX / distance)

        return (
            control1: CGPoint(
                x: start.x + fromVector.x * bend + normal.x * laneOffset,
                y: start.y + fromVector.y * bend + normal.y * laneOffset
            ),
            control2: CGPoint(
                x: end.x + toVector.x * bend + normal.x * laneOffset,
                y: end.y + toVector.y * bend + normal.y * laneOffset
            )
        )
    }

    private func estimatedScreenNodeSize(for node: GraphNode, priorityLabelIDs: Set<String>) -> CGSize {
        let showsPriorityLabel = priorityLabelIDs.contains(node.id)
        let showsText = selectedPackageID == node.packageID
            || node.role != .normal
            || labelMode == .expanded
            || showsPriorityLabel

        guard showsText else {
            let size = selectedPackageID == node.packageID || node.role == .selected ? 11 : node.reverseCount > 0 ? 8 : 6
            return CGSize(width: size, height: size)
        }

        let maxTextWidth = maxLabelWidth(for: node)
        let textWidth = min(maxTextWidth, estimatedTextWidth(for: node))
        let countWidth: CGFloat = node.reverseCount > 0 ? 14 : 0
        let countSpacing: CGFloat = node.reverseCount > 0 ? 4 : 0
        let dotWidth: CGFloat = node.role == .selected ? 7 : 6
        let horizontalPadding = horizontalPadding(for: node) * 2
        let verticalPadding = verticalPadding(for: node) * 2
        let width = dotWidth + 4 + textWidth + countSpacing + countWidth + horizontalPadding
        let height = max(node.role == .selected ? 17 : 14, 12) + verticalPadding

        return CGSize(width: width, height: height)
    }

    private func drawCanvasNodes(
        context: GraphicsContext,
        size: CGSize,
        nodes: [GraphNode],
        priorityLabelIDs: Set<String>
    ) {
        for node in nodes where rendersAsCanvasDot(node, priorityLabelIDs: priorityLabelIDs) {
            let point = screenPoint(for: node, size: size)
            let diameter = canvasDotDiameter(for: node)
            let rect = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            let path = Path(ellipseIn: rect)

            context.fill(path, with: .color(canvasNodeColor(for: node)))
            context.stroke(path, with: .color(canvasNodeStrokeColor(for: node)), lineWidth: 1)
        }
    }

    private func rendersAsCanvasDot(_ node: GraphNode, priorityLabelIDs: Set<String>) -> Bool {
        selectedPackageID != node.packageID
            && !directSelectedDependencyIDs.contains(node.packageID)
            && node.role == .normal
            && labelMode != .expanded
            && !priorityLabelIDs.contains(node.id)
    }

    private func canvasDotDiameter(for node: GraphNode) -> CGFloat {
        node.reverseCount >= 10 ? 9 : node.reverseCount > 0 ? 8 : 6
    }

    private func canvasNodeColor(for node: GraphNode) -> Color {
        switch node.installReason {
        case .requested:
            return AppTheme.requestedColor
        case .dependency:
            return AppTheme.dependencyOnlyColor
        case .unknown:
            return .secondary
        }
    }

    private func canvasNodeStrokeColor(for node: GraphNode) -> Color {
        node.isExternalTap ? AppTheme.externalTapColor.opacity(0.75) : canvasNodeColor(for: node).opacity(0.35)
    }

    private func estimatedTextWidth(for node: GraphNode) -> CGFloat {
        let characterCount = min(node.label.count, density == .dense ? 14 : 20)
        let characterWidth: CGFloat
        if selectedPackageID == node.packageID || node.role == .selected {
            characterWidth = 7.2
        } else {
            characterWidth = density == .roomy ? 6.4 : 6.1
        }

        return CGFloat(characterCount) * characterWidth
    }

    private func maxLabelWidth(for node: GraphNode) -> CGFloat {
        if labelMode == .priority {
            return density == .dense ? 76 : 92
        }

        switch density {
        case .roomy:
            return node.role == .selected ? 132 : 118
        case .compact:
            return node.role == .selected ? 116 : 96
        case .dense:
            return node.role == .selected ? 102 : 78
        }
    }

    private func horizontalPadding(for node: GraphNode) -> CGFloat {
        if node.role == .selected {
            return 9
        }
        if labelMode == .priority {
            return 5
        }

        return density == .dense ? 5 : 6
    }

    private func verticalPadding(for node: GraphNode) -> CGFloat {
        if node.role == .selected {
            return 6
        }

        return density == .dense ? 3 : 4
    }

    private func edgeIsHighlighted(_ edge: DependencyEdge, nodeByID: [String: GraphNode]) -> Bool {
        guard let selectedPackageID else {
            return false
        }

        return nodeByID[edge.formulaID]?.packageID == selectedPackageID
            || nodeByID[edge.dependencyID]?.packageID == selectedPackageID
    }

    private func edgeColor(highlighted: Bool) -> Color {
        if highlighted {
            return Color.accentColor.opacity(0.66)
        }

        return Color.secondary.opacity(edgeOpacity)
    }

    private func edgeCurve(for route: EdgeRoute) -> EdgeCurve {
        var path = Path()
        path.move(to: route.start)
        path.addCurve(
            to: route.end,
            control1: route.control1,
            control2: route.control2
        )

        return EdgeCurve(path: path, end: route.end, tangentStart: route.control2)
    }

    private func arrowheadPath(for curve: EdgeCurve, highlighted: Bool) -> Path {
        let deltaX = curve.end.x - curve.tangentStart.x
        let deltaY = curve.end.y - curve.tangentStart.y
        let length = max(1, hypot(deltaX, deltaY))
        let unit = CGPoint(x: deltaX / length, y: deltaY / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let arrowLength: CGFloat = highlighted ? 7 : 5
        let arrowWidth: CGFloat = highlighted ? 4.8 : 3.6
        let tip = curve.end
        let base = CGPoint(x: tip.x - unit.x * arrowLength, y: tip.y - unit.y * arrowLength)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + normal.x * arrowWidth, y: base.y + normal.y * arrowWidth))
        path.addLine(to: CGPoint(x: base.x - normal.x * arrowWidth, y: base.y - normal.y * arrowWidth))
        path.closeSubpath()
        return path
    }

    private var edgeOpacity: Double {
        switch labelMode {
        case .expanded:
            0.20
        case .priority:
            0.14
        case .dots:
            0.12
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var path = Path()
        let spacing = max(34, 48 * scale)
        let startX = offset.width.truncatingRemainder(dividingBy: spacing)
        let startY = offset.height.truncatingRemainder(dividingBy: spacing)

        var x = startX
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }

        var y = startY
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }

        context.stroke(path, with: .color(Color.secondary.opacity(0.05)), lineWidth: 1)
    }

    private func fitAll(in size: CGSize, animated: Bool = true) {
        guard size.width > 0, size.height > 0, !layout.nodes.isEmpty else {
            resetViewport(animated: animated)
            return
        }

        let bounds = rotatedGraphBounds(size: size, rotation: rotation)
        let targetScale = targetScaleToFit(bounds: bounds, size: size)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let targetOffset = CGSize(
            width: size.width / 2 - (size.width / 2 + center.x * targetScale),
            height: size.height / 2 - (size.height / 2 + center.y * targetScale)
        )

        updateViewport(scale: targetScale, offset: targetOffset, animated: animated)
    }

    private func centerSelectedNode(in size: CGSize) {
        guard size.width > 0, size.height > 0, let selectedNode else {
            return
        }

        let rotatedPosition = rotatedGraphVector(for: effectivePosition(for: selectedNode), size: size, rotation: rotation)
        let targetScale = max(scale, density == .dense ? 1.05 : scale)
        let targetOffset = CGSize(
            width: size.width / 2 - (size.width / 2 + rotatedPosition.x * targetScale),
            height: size.height / 2 - (size.height / 2 + rotatedPosition.y * targetScale)
        )

        updateViewport(scale: targetScale, offset: targetOffset, animated: true)
    }

    private func zoom(by factor: CGFloat, in size: CGSize) {
        let newScale = min(3.0, max(0.45, scale * factor))
        let viewportCenterVector = CGPoint(
            x: (size.width / 2 - offset.width - size.width / 2) / scale,
            y: (size.height / 2 - offset.height - size.height / 2) / scale
        )
        let newOffset = CGSize(
            width: size.width / 2 - (size.width / 2 + viewportCenterVector.x * newScale),
            height: size.height / 2 - (size.height / 2 + viewportCenterVector.y * newScale)
        )

        updateViewport(scale: newScale, offset: newOffset, animated: true)
    }

    private func resetViewport(animated: Bool) {
        updateViewport(scale: 1, rotation: .zero, offset: .zero, animated: animated)
    }

    private func resetManualNodePositions(in size: CGSize) {
        manualNodePositions = [:]
        nodeDragStartPositions = [:]
        draggedNodeID = nil
        fitAll(in: size)
    }

    private func updateViewport(
        scale newScale: CGFloat,
        rotation newRotation: Angle? = nil,
        offset newOffset: CGSize,
        animated: Bool
    ) {
        let changes = {
            scale = newScale
            baseScale = newScale
            if let newRotation {
                rotation = newRotation
                baseRotation = newRotation
            }
            offset = newOffset
            dragStart = newOffset
        }

        if animated {
            withAnimation(.snappy(duration: 0.24), changes)
        } else {
            changes()
        }
    }

    private func transformedScreenPoint(
        for normalizedPosition: CGPoint,
        size: CGSize,
        scale: CGFloat,
        rotation: Angle,
        offset: CGSize
    ) -> CGPoint {
        let rotated = rotatedGraphVector(for: normalizedPosition, size: size, rotation: rotation)

        return CGPoint(
            x: size.width / 2 + rotated.x * scale + offset.width,
            y: size.height / 2 + rotated.y * scale + offset.height
        )
    }

    private func rotatedGraphBounds(size: CGSize, rotation: Angle) -> CGRect {
        guard let first = layout.nodes.first else {
            return .zero
        }

        return layout.nodes.dropFirst().reduce(
            CGRect(origin: rotatedGraphVector(for: effectivePosition(for: first), size: size, rotation: rotation), size: .zero)
        ) { bounds, node in
            bounds.union(CGRect(origin: rotatedGraphVector(for: effectivePosition(for: node), size: size, rotation: rotation), size: .zero))
        }
    }

    private func targetScaleToFit(bounds: CGRect, size: CGSize) -> CGFloat {
        let horizontalSpan = max(80, bounds.width)
        let verticalSpan = max(80, bounds.height)
        return min(2.2, max(0.55, min((size.width * 0.86) / horizontalSpan, (size.height * 0.82) / verticalSpan)))
    }

    private func rotatedGraphVector(for normalizedPosition: CGPoint, size: CGSize, rotation: Angle) -> CGPoint {
        let x = normalizedPosition.x * size.width - size.width / 2
        let y = normalizedPosition.y * size.height - size.height / 2
        let radians = rotation.radians
        let cosine = cos(radians)
        let sine = sin(radians)

        return CGPoint(
            x: x * cosine - y * sine,
            y: x * sine + y * cosine
        )
    }
}

private enum GraphDensity {
    case roomy
    case compact
    case dense
}

private enum GraphLabelMode {
    case expanded
    case priority
    case dots
}

private struct EdgeCurve {
    let path: Path
    let end: CGPoint
    let tangentStart: CGPoint
}

private enum EdgePortSide: Hashable {
    case left
    case right
    case top
    case bottom

    var outwardVector: CGPoint {
        switch self {
        case .left:
            CGPoint(x: -1, y: 0)
        case .right:
            CGPoint(x: 1, y: 0)
        case .top:
            CGPoint(x: 0, y: -1)
        case .bottom:
            CGPoint(x: 0, y: 1)
        }
    }

    func sortValue(for point: CGPoint) -> CGFloat {
        switch self {
        case .left, .right:
            point.y
        case .top, .bottom:
            point.x
        }
    }
}

private enum EdgeEndpoint: Hashable {
    case source
    case target
}

private struct GraphNodeFrame {
    let node: GraphNode
    let center: CGPoint
    let size: CGSize

    var rect: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func portPoint(side: EdgePortSide, offset: CGFloat, margin: CGFloat) -> CGPoint {
        let rect = rect

        switch side {
        case .left:
            return CGPoint(x: rect.minX - margin, y: clamped(center.y + offset, min: rect.minY + 4, max: rect.maxY - 4))
        case .right:
            return CGPoint(x: rect.maxX + margin, y: clamped(center.y + offset, min: rect.minY + 4, max: rect.maxY - 4))
        case .top:
            return CGPoint(x: clamped(center.x + offset, min: rect.minX + 6, max: rect.maxX - 6), y: rect.minY - margin)
        case .bottom:
            return CGPoint(x: clamped(center.x + offset, min: rect.minX + 6, max: rect.maxX - 6), y: rect.maxY + margin)
        }
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return value
        }

        return Swift.min(maximum, Swift.max(minimum, value))
    }
}

private struct EdgePlan {
    let index: Int
    let edge: DependencyEdge
    let fromNode: GraphNode
    let toNode: GraphNode
    let fromFrame: GraphNodeFrame
    let toFrame: GraphNodeFrame
    let fromSide: EdgePortSide
    let toSide: EdgePortSide
    let highlighted: Bool
}

private struct EdgeRoute {
    let index: Int
    let edge: DependencyEdge
    let fromNode: GraphNode
    let toNode: GraphNode
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let fromSide: EdgePortSide
    let toSide: EdgePortSide
    let highlighted: Bool
}

private struct PortKey: Hashable {
    let nodeID: String
    let side: EdgePortSide
}

private struct PortSlotKey: Hashable {
    let edgeIndex: Int
    let endpoint: EdgeEndpoint
}

private struct PortConnection {
    let edgeIndex: Int
    let endpoint: EdgeEndpoint
    let sortValue: CGFloat
}

private struct LaneKey: Hashable {
    let fromSide: EdgePortSide
    let toSide: EdgePortSide
    let midXBucket: Int
    let midYBucket: Int
}

private struct GraphNodeLabel: View {
    let node: GraphNode
    let isSelected: Bool
    let isDirectDependencyHighlighted: Bool
    let density: GraphDensity
    let labelMode: GraphLabelMode
    let showsPriorityLabel: Bool

    var body: some View {
        Group {
            if shouldRenderAsDot {
                Circle()
                    .fill(roleColor)
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        Circle()
                            .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
                    }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(roleColor)
                        .frame(width: node.role == .selected ? 7 : 6, height: node.role == .selected ? 7 : 6)

                    if shouldShowText {
                        Text(displayLabel)
                            .font(labelFont)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if shouldShowReverseCount {
                        Text("\(node.reverseCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(capsuleBackground, in: Capsule())
                .overlay {
                    if isSelected || node.role == .selected {
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.06), lineWidth: 6)
                    } else if isDirectDependencyHighlighted {
                        Capsule()
                            .stroke(roleColor.opacity(0.065), lineWidth: 5)
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(strokeColor, lineWidth: isSelected || node.role == .selected ? 1.8 : isDirectDependencyHighlighted ? 1.6 : 1)
                }
                .shadow(
                    color: .black.opacity(
                        isSelected || node.role == .selected ? 0.16 :
                        isDirectDependencyHighlighted ? 0.12 :
                        node.role == .dependency ? 0.08 : 0
                    ),
                    radius: isSelected || node.role == .selected ? 10 : isDirectDependencyHighlighted ? 8 : node.role == .dependency ? 6 : 0,
                    x: 0,
                    y: 3
                )
            }
        }
    }

    private var capsuleBackground: Color {
        if isSelected || node.role == .selected {
            return Color.accentColor.opacity(0.12)
        }
        if isDirectDependencyHighlighted {
            return roleColor.opacity(0.18)
        }

        return switch node.role {
        case .dependency:
            roleColor.opacity(0.14)
        case .dependent:
            roleColor.opacity(0.10)
        case .normal:
            Color(nsColor: .controlBackgroundColor).opacity(0.90)
        case .selected:
            Color.accentColor.opacity(0.12)
        }
    }

    private var labelFont: Font {
        if node.role == .selected {
            return .callout.weight(.semibold)
        }

        if node.role == .dependency {
            let baseFont: Font = labelMode == .priority ? .caption2 : .caption
            return baseFont.weight(.medium)
        }

        if node.role == .normal && node.reverseCount >= 10 {
            return labelMode == .priority ? .caption2.weight(.medium) : .caption.weight(.medium)
        }

        switch density {
        case .roomy:
            return labelMode == .priority ? .caption : .caption
        case .compact, .dense:
            return labelMode == .priority ? .caption2 : .caption2
        }
    }

    private var horizontalPadding: CGFloat {
        if node.role == .selected {
            return 9
        }

        if labelMode == .priority {
            return 5
        }

        return density == .dense ? 5 : 6
    }

    private var verticalPadding: CGFloat {
        if node.role == .selected {
            return 6
        }

        return density == .dense ? 3 : 4
    }

    private var shouldRenderAsDot: Bool {
        !isSelected && !isDirectDependencyHighlighted && node.role == .normal && labelMode != .expanded && !showsPriorityLabel
    }

    private var shouldShowText: Bool {
        isSelected || isDirectDependencyHighlighted || node.role != .normal || labelMode == .expanded || showsPriorityLabel
    }

    private var shouldShowReverseCount: Bool {
        node.reverseCount > 0 && shouldShowText
    }

    private var displayLabel: String {
        guard node.label.count > maxVisibleCharacters else {
            return node.label
        }

        let headCount = max(3, (maxVisibleCharacters - 1) / 2)
        let tailCount = max(2, maxVisibleCharacters - headCount - 1)
        return "\(node.label.prefix(headCount))…\(node.label.suffix(tailCount))"
    }

    private var maxVisibleCharacters: Int {
        if node.role == .selected {
            return density == .dense ? 16 : 22
        }
        if labelMode == .priority {
            return density == .dense ? 10 : 13
        }

        switch density {
        case .roomy:
            return 18
        case .compact:
            return 15
        case .dense:
            return 12
        }
    }

    private var dotSize: CGFloat {
        if isSelected || node.role == .selected {
            return 12
        }
        if node.reverseCount >= 10 {
            return 9
        }
        return node.reverseCount > 0 ? 8 : 6
    }

    private var roleColor: Color {
        if isDirectDependencyHighlighted {
            return .cyan
        }

        switch node.role {
        case .normal:
            switch node.installReason {
            case .requested:
                return AppTheme.requestedColor
            case .dependency:
                return AppTheme.dependencyOnlyColor
            case .unknown:
                return .secondary
            }
        case .selected:
            return .accentColor
        case .dependency:
            return .indigo
        case .dependent:
            return .orange
        }
    }

    private var strokeColor: Color {
        if isSelected || node.role == .selected {
            return .accentColor.opacity(0.75)
        }
        if isDirectDependencyHighlighted {
            return roleColor.opacity(0.72)
        }
        if node.role == .dependency {
            return roleColor.opacity(0.60)
        }
        if node.role == .normal && node.isExternalTap {
            return AppTheme.externalTapColor.opacity(0.75)
        }

        return roleColor.opacity(0.35)
    }
}

private struct GraphViewportControls: View {
    let scale: CGFloat
    let canCenterSelection: Bool
    let canResetNodePositions: Bool
    let fitAll: () -> Void
    let centerSelection: () -> Void
    let resetNodePositions: () -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: zoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Text(scale, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46)

            Button(action: zoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in")

            Divider()
                .frame(height: 18)

            Button(action: fitAll) {
                Label("Fit Graph", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit graph")

            Button(action: centerSelection) {
                Label("Center Selection", systemImage: "scope")
            }
            .help("Center selected package")
            .disabled(!canCenterSelection)

            Button(action: resetNodePositions) {
                Label("Reset Node Positions", systemImage: "arrow.counterclockwise")
            }
            .help("Reset manual node positions")
            .disabled(!canResetNodePositions)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct GraphLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            LegendItem(color: .accentColor, title: "Selected")
            LegendItem(color: AppTheme.requestedColor, title: "Requested")
            LegendItem(color: AppTheme.dependencyOnlyColor, title: "Dependency")
            LegendItem(color: AppTheme.externalTapColor, title: "Other tap")
            LegendItem(color: .indigo, title: "Depends on")
            LegendItem(color: .orange, title: "Used by")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(LocalizedStringKey(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
