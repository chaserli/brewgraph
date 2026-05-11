import XCTest
@testable import HomebrewLens

final class GraphLayoutTests: XCTestCase {
    func testFullGraphPlacesDependenciesToTheRightOfDependents() {
        let zlib = package("zlib", dependencies: [], reverse: ["openssl@3"])
        let openssl = package("openssl@3", dependencies: ["zlib"], reverse: ["node"])
        let node = package("node", dependencies: ["openssl@3"], reverse: [])
        let snapshot = snapshot(
            packages: [node, openssl, zlib],
            deps: ["node": ["openssl@3"], "openssl@3": ["zlib"], "zlib": []],
            reverseDeps: ["zlib": ["openssl@3"], "openssl@3": ["node"], "node": []],
            edges: [
                DependencyEdge(formulaName: "node", dependencyName: "openssl@3"),
                DependencyEdge(formulaName: "openssl@3", dependencyName: "zlib")
            ]
        )

        let layout = GraphLayoutEngine.fullGraph(snapshot: snapshot)
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.label, $0.position.x) })

        XCTAssertGreaterThan(positions["zlib"] ?? 0, positions["openssl@3"] ?? 1)
        XCTAssertGreaterThan(positions["openssl@3"] ?? 0, positions["node"] ?? 1)
    }

    func testFullGraphSplitsDenseDependencyLayersIntoReadableColumns() {
        let packages = (0..<25).map { index in
            package("leaf-\(index)", dependencies: [], reverse: ["root"])
        }
        let root = package("root", dependencies: packages.map(\.name), reverse: [])
        let allPackages = packages + [root]
        let edges = packages.map { DependencyEdge(formulaName: "root", dependencyName: $0.name) }
        let snapshot = snapshot(
            packages: allPackages,
            deps: Dictionary(uniqueKeysWithValues: allPackages.map { ($0.name, $0.dependencies) }),
            reverseDeps: Dictionary(uniqueKeysWithValues: allPackages.map { ($0.name, $0.reverseDependencies) }),
            edges: edges
        )

        let layout = GraphLayoutEngine.fullGraph(snapshot: snapshot)
        let columns = Set(layout.nodes.map { round($0.position.x * 1_000) / 1_000 })

        XCTAssertGreaterThan(columns.count, 1)
    }

    func testFullGraphOmitsFormulaeWithNoDependenciesOrDependents() {
        let isolated = package("standalone", dependencies: [], reverse: [])
        let zlib = package("zlib", dependencies: [], reverse: ["node"])
        let node = package("node", dependencies: ["zlib"], reverse: [])
        let snapshot = snapshot(
            packages: [isolated, node, zlib],
            deps: ["standalone": [], "node": ["zlib"], "zlib": []],
            reverseDeps: ["standalone": [], "zlib": ["node"], "node": []],
            edges: [
                DependencyEdge(formulaName: "node", dependencyName: "zlib")
            ]
        )

        let layout = GraphLayoutEngine.fullGraph(snapshot: snapshot)

        XCTAssertEqual(Set(layout.nodes.map(\.label)), ["node", "zlib"])
        XCTAssertFalse(layout.nodes.contains { $0.label == "standalone" })
    }

    func testFullGraphOrdersLayerByAdjacentDependencyBarycenter() {
        let a = package("a-lib", dependencies: [], reverse: ["zeta-tool"])
        let b = package("b-lib", dependencies: [], reverse: ["alpha-tool"])
        let alpha = package("alpha-tool", dependencies: ["b-lib"], reverse: [])
        let zeta = package("zeta-tool", dependencies: ["a-lib"], reverse: [])
        let snapshot = snapshot(
            packages: [a, b, alpha, zeta],
            deps: [
                "a-lib": [],
                "b-lib": [],
                "alpha-tool": ["b-lib"],
                "zeta-tool": ["a-lib"]
            ],
            reverseDeps: [
                "a-lib": ["zeta-tool"],
                "b-lib": ["alpha-tool"],
                "alpha-tool": [],
                "zeta-tool": []
            ],
            edges: [
                DependencyEdge(formulaName: "alpha-tool", dependencyName: "b-lib"),
                DependencyEdge(formulaName: "zeta-tool", dependencyName: "a-lib")
            ]
        )

        let layout = GraphLayoutEngine.fullGraph(snapshot: snapshot)
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.label, $0.position.y) })

        XCTAssertLessThan(positions["zeta-tool"] ?? 1, positions["alpha-tool"] ?? 0)
    }

    func testLocalGraphIncludesSelectedDependenciesAndDependents() {
        let node = package("node", dependencies: ["openssl@3"], reverse: ["ffmpeg"])
        let openssl = package("openssl@3", dependencies: [], reverse: ["node"])
        let ffmpeg = package("ffmpeg", dependencies: ["node"], reverse: [])
        let snapshot = snapshot(
            packages: [node, openssl, ffmpeg],
            deps: ["node": ["openssl@3"], "ffmpeg": ["node"]],
            reverseDeps: ["openssl@3": ["node"], "node": ["ffmpeg"], "ffmpeg": []],
            edges: [
                DependencyEdge(formulaName: "node", dependencyName: "openssl@3"),
                DependencyEdge(formulaName: "ffmpeg", dependencyName: "node")
            ]
        )

        let layout = GraphLayoutEngine.localGraph(snapshot: snapshot, selectedName: "node", depth: 1)

        XCTAssertEqual(Set(layout.nodes.map(\.label)), ["node", "openssl@3", "ffmpeg"])
        XCTAssertEqual(Set(layout.edges.map(\.id)), ["formula:node->formula:openssl@3", "formula:ffmpeg->formula:node"])
    }

    func testLocalGraphSplitsBusyNeighborhoodsIntoSideColumns() {
        let dependencies = (0..<24).map { "dep-\($0)" }
        let node = package("node", dependencies: dependencies, reverse: [])
        let dependencyPackages = dependencies.map { package($0, dependencies: [], reverse: ["node"]) }
        let allPackages = [node] + dependencyPackages
        let snapshot = snapshot(
            packages: allPackages,
            deps: Dictionary(uniqueKeysWithValues: allPackages.map { ($0.name, $0.dependencies) }),
            reverseDeps: Dictionary(uniqueKeysWithValues: allPackages.map { ($0.name, $0.reverseDependencies) }),
            edges: dependencies.map { DependencyEdge(formulaName: "node", dependencyName: $0) }
        )

        let layout = GraphLayoutEngine.localGraph(snapshot: snapshot, selectedName: "node", depth: 1)
        let dependencyXs = Set(layout.nodes
            .filter { $0.role == .dependency }
            .map { round($0.position.x * 1_000) / 1_000 })

        XCTAssertGreaterThan(dependencyXs.count, 1)
    }

    func testLocalGraphPlacesNeighborsOnArcsInsteadOfSingleColumns() {
        let dependencies = (0..<7).map { "dep-\($0)" }
        let node = package("node", dependencies: dependencies, reverse: [])
        let dependencyPackages = dependencies.map { package($0, dependencies: [], reverse: ["node"]) }
        let snapshot = snapshot(
            packages: [node] + dependencyPackages,
            deps: ["node": dependencies],
            reverseDeps: Dictionary(uniqueKeysWithValues: ([node] + dependencyPackages).map { ($0.name, $0.reverseDependencies) }),
            edges: dependencies.map { DependencyEdge(formulaName: "node", dependencyName: $0) }
        )

        let layout = GraphLayoutEngine.localGraph(snapshot: snapshot, selectedName: "node", depth: 1)
        let dependencyPositions = layout.nodes.filter { $0.role == .dependency }.map(\.position)
        let dependencyXs = Set(dependencyPositions.map { round($0.x * 1_000) / 1_000 })
        let dependencyYs = Set(dependencyPositions.map { round($0.y * 1_000) / 1_000 })

        XCTAssertGreaterThan(dependencyXs.count, 2)
        XCTAssertGreaterThan(dependencyYs.count, 2)
        XCTAssertTrue(dependencyPositions.allSatisfy { $0.x > 0.5 })
    }

    func testLocalGraphKeepsTransitiveDependenciesNearTheirDirectParent() {
        let node = package("node", dependencies: ["alpha", "beta"], reverse: [])
        let alpha = package("alpha", dependencies: ["alpha-child"], reverse: ["node"])
        let beta = package("beta", dependencies: ["beta-child"], reverse: ["node"])
        let alphaChild = package("alpha-child", dependencies: [], reverse: ["alpha"])
        let betaChild = package("beta-child", dependencies: [], reverse: ["beta"])
        let allPackages = [node, alpha, beta, alphaChild, betaChild]
        let snapshot = snapshot(
            packages: allPackages,
            deps: [
                "node": ["alpha", "beta"],
                "alpha": ["alpha-child"],
                "beta": ["beta-child"],
                "alpha-child": [],
                "beta-child": []
            ],
            reverseDeps: Dictionary(uniqueKeysWithValues: allPackages.map { ($0.name, $0.reverseDependencies) }),
            edges: [
                DependencyEdge(formulaName: "node", dependencyName: "alpha"),
                DependencyEdge(formulaName: "node", dependencyName: "beta"),
                DependencyEdge(formulaName: "alpha", dependencyName: "alpha-child"),
                DependencyEdge(formulaName: "beta", dependencyName: "beta-child")
            ]
        )

        let layout = GraphLayoutEngine.localGraph(snapshot: snapshot, selectedName: "node", depth: 2)
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.label, $0.position) })

        XCTAssertLessThan(distance(positions["alpha-child"], positions["alpha"]), distance(positions["alpha-child"], positions["beta"]))
        XCTAssertLessThan(distance(positions["beta-child"], positions["beta"]), distance(positions["beta-child"], positions["alpha"]))
    }

    func testDenseFullGraphStaysInBoundsAndAvoidsSevereNodeOverlap() {
        let hubs = (0..<8).map { "hub-\($0)" }
        let leaves = (0..<42).map { "leaf-\($0)" }
        let apps = (0..<18).map { "app-\($0)" }
        var packages: [Package] = []
        var deps: [String: [String]] = [:]
        var reverseDeps: [String: [String]] = [:]
        var edges: [DependencyEdge] = []

        for (hubIndex, hub) in hubs.enumerated() {
            let hubDeps = leaves.enumerated().compactMap { index, leaf in index % 8 == hubIndex ? leaf : nil }
            packages.append(package(hub, dependencies: hubDeps, reverse: apps.enumerated().compactMap { appIndex, app in appIndex % 3 == hubIndex % 3 ? app : nil }))
            deps[hub] = hubDeps
            for leaf in hubDeps {
                reverseDeps[leaf, default: []].append(hub)
                edges.append(DependencyEdge(formulaName: hub, dependencyName: leaf))
            }
        }
        for (appIndex, app) in apps.enumerated() {
            let appDeps = hubs.enumerated().compactMap { hubIndex, hub in hubIndex % 3 == appIndex % 3 ? hub : nil }
            packages.append(package(app, dependencies: appDeps, reverse: []))
            deps[app] = appDeps
            for hub in appDeps {
                reverseDeps[hub, default: []].append(app)
                edges.append(DependencyEdge(formulaName: app, dependencyName: hub))
            }
        }
        for leaf in leaves {
            packages.append(package(leaf, dependencies: [], reverse: reverseDeps[leaf] ?? []))
            deps[leaf] = []
        }

        let layout = GraphLayoutEngine.fullGraph(snapshot: snapshot(
            packages: packages,
            deps: deps,
            reverseDeps: reverseDeps,
            edges: edges
        ))

        XCTAssertFalse(layout.nodes.isEmpty)
        XCTAssertTrue(layout.nodes.allSatisfy { node in
            (0.02...0.98).contains(node.position.x) && (0.03...0.97).contains(node.position.y)
        })
        XCTAssertLessThan(severeOverlapCount(layout.nodes), layout.nodes.count / 5)
    }

    func testLocalGraphDepthThreeStaysInBoundsAndKeepsSelectedCenterClear() throws {
        let root = package("root", dependencies: ["dep-a", "dep-b", "dep-c"], reverse: ["tool-a", "tool-b"])
        let depA = package("dep-a", dependencies: ["dep-a-2"], reverse: ["root"])
        let depB = package("dep-b", dependencies: ["dep-b-2"], reverse: ["root"])
        let depC = package("dep-c", dependencies: ["dep-c-2"], reverse: ["root"])
        let depA2 = package("dep-a-2", dependencies: ["dep-a-3"], reverse: ["dep-a"])
        let depB2 = package("dep-b-2", dependencies: ["dep-b-3"], reverse: ["dep-b"])
        let depC2 = package("dep-c-2", dependencies: ["dep-c-3"], reverse: ["dep-c"])
        let depA3 = package("dep-a-3", dependencies: [], reverse: ["dep-a-2"])
        let depB3 = package("dep-b-3", dependencies: [], reverse: ["dep-b-2"])
        let depC3 = package("dep-c-3", dependencies: [], reverse: ["dep-c-2"])
        let toolA = package("tool-a", dependencies: ["root"], reverse: ["wrapper-a"])
        let toolB = package("tool-b", dependencies: ["root"], reverse: ["wrapper-b"])
        let wrapperA = package("wrapper-a", dependencies: ["tool-a"], reverse: [])
        let wrapperB = package("wrapper-b", dependencies: ["tool-b"], reverse: [])
        let packages = [root, depA, depB, depC, depA2, depB2, depC2, depA3, depB3, depC3, toolA, toolB, wrapperA, wrapperB]
        let deps = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, $0.dependencies) })
        let reverseDeps = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, $0.reverseDependencies) })
        let edges = deps.flatMap { formula, dependencies in
            dependencies.map { DependencyEdge(formulaName: formula, dependencyName: $0) }
        }

        let layout = GraphLayoutEngine.localGraph(
            snapshot: snapshot(packages: packages, deps: deps, reverseDeps: reverseDeps, edges: edges),
            selectedName: "root",
            depth: 3
        )
        let selected = try XCTUnwrap(layout.nodes.first { $0.role == .selected })

        XCTAssertTrue(layout.nodes.allSatisfy { node in
            (0.02...0.98).contains(node.position.x) && (0.03...0.97).contains(node.position.y)
        })
        XCTAssertEqual(selected.position.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(selected.position.y, 0.5, accuracy: 0.001)
        XCTAssertLessThan(severeOverlapCount(layout.nodes), 2)
    }

    private func snapshot(
        packages: [Package],
        deps: [String: [String]],
        reverseDeps: [String: [String]],
        edges: [DependencyEdge]
    ) -> BrewSnapshot {
        BrewSnapshot(
            brewPath: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            brewPrefix: URL(fileURLWithPath: "/opt/homebrew"),
            packages: packages,
            formulae: packages.map(\.name).sorted(),
            casks: [],
            deps: deps,
            reverseDeps: reverseDeps,
            edges: edges,
            leaves: [],
            cleanupDryRun: .empty,
            summary: BrewSummary(
                formulaCount: packages.count,
                caskCount: 0,
                leafCount: packages.filter(\.isLeaf).count,
                edgeCount: edges.count,
                outdatedCount: 0,
                unusedDependencyCount: 0,
                totalKnownSize: 0
            ),
            scanDuration: .milliseconds(100),
            warnings: []
        )
    }

    private func package(_ name: String, dependencies: [String], reverse: [String]) -> Package {
        Package(
            id: PackageID.formula(name),
            name: name,
            kind: .formula,
            version: "1.0",
            stableVersion: "1.0",
            description: "",
            homepage: nil,
            license: nil,
            tap: nil,
            installedAt: nil,
            installedOnRequest: true,
            installedAsDependency: false,
            outdated: false,
            pinned: false,
            deprecated: false,
            disabled: false,
            kegOnly: false,
            size: nil,
            iconPath: nil,
            dependencies: dependencies,
            reverseDependencies: reverse,
            runtimeDependencies: []
        )
    }

    private func distance(_ lhs: CGPoint?, _ rhs: CGPoint?) -> CGFloat {
        guard let lhs, let rhs else {
            return .greatestFiniteMagnitude
        }

        return hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func severeOverlapCount(_ nodes: [GraphNode]) -> Int {
        var count = 0
        for lhsIndex in nodes.indices {
            for rhsIndex in nodes.indices where rhsIndex > lhsIndex {
                let dx = abs(nodes[lhsIndex].position.x - nodes[rhsIndex].position.x)
                let dy = abs(nodes[lhsIndex].position.y - nodes[rhsIndex].position.y)
                if dx < 0.026 && dy < 0.030 {
                    count += 1
                }
            }
        }
        return count
    }
}
