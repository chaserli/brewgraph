import Foundation

struct BrewScanner: Sendable {
    private let processRunner: any BrewProcessRunning

    init(
        processRunner: any BrewProcessRunning = BrewProcessRunner()
    ) {
        self.processRunner = processRunner
    }

    func scan(
        discovery: BrewDiscoveryResult,
        options: ScanOptions = .default,
        progress: @Sendable (String) async -> Void = { _ in }
    ) async throws -> BrewSnapshot {
        let start = Date()
        var warnings: [String] = []

        await progress(ScanStep.metadata.rawValue)
        let infoResult = try await runRequired(
            discovery: discovery,
            arguments: ["info", "--json=v2", "--installed"],
            timeout: 120
        )

        let payload = try JSONDecoder().decode(BrewInfoPayload.self, from: Data(infoResult.stdout.utf8))

        await progress(ScanStep.formulaList.rawValue)
        let formulae = await runOptionalLines(
            discovery: discovery,
            arguments: ["list", "--formula"],
            timeout: 30,
            warnings: &warnings
        )

        await progress(ScanStep.caskList.rawValue)
        let casks = await runOptionalLines(
            discovery: discovery,
            arguments: ["list", "--cask"],
            timeout: 30,
            warnings: &warnings
        )

        await progress(ScanStep.deps.rawValue)
        let depsOutput = await runOptionalText(
            discovery: discovery,
            arguments: ["deps", "--installed", "--for-each", "--direct"],
            timeout: 60,
            warnings: &warnings
        )
        let deps = Self.parseDirectDependencies(depsOutput)
        let reverseDeps = Self.buildReverseDependencies(from: deps)
        let edges = Self.buildEdges(from: deps)

        await progress(ScanStep.leaves.rawValue)
        let leaves = Set(await runOptionalLines(
            discovery: discovery,
            arguments: ["leaves"],
            timeout: 30,
            warnings: &warnings
        ).map(Self.canonicalFormulaName))

        let outdatedOutput = await runOptionalText(
            discovery: discovery,
            arguments: ["outdated", "--json=v2"],
            timeout: 45,
            allowedExitCodes: [0, 1],
            warnings: &warnings
        )
        let outdated = Self.parseOutdated(outdatedOutput)

        let cleanup: CleanupSummary
        if options.runCleanupDryRun {
            await progress(ScanStep.cleanup.rawValue)
            let cleanupOutput = await runOptionalText(
                discovery: discovery,
                arguments: ["cleanup", "--dry-run"],
                timeout: 60,
                warnings: &warnings
            )
            cleanup = CleanupDryRunParser.parse(cleanupOutput)
        } else {
            cleanup = .empty
        }

        let brewDoctorWarnings: [String]
        if options.runBrewDoctor {
            await progress(ScanStep.doctor.rawValue)
            brewDoctorWarnings = await doctorWarnings(discovery: discovery, warnings: &warnings)
        } else {
            brewDoctorWarnings = []
        }

        let sizeByFormula: [String: Int64]
        if options.estimateFormulaSizes {
            await progress(ScanStep.formulaSizes.rawValue)
            sizeByFormula = await formulaSizes(
                formulae: Set(formulae.isEmpty ? payload.formulae.map(\.name) : formulae),
                prefix: discovery.brewPrefix
            )
        } else {
            sizeByFormula = [:]
        }

        let sizeByCask: [String: Int64]
        if options.estimateCaskSizes {
            await progress(ScanStep.caskSizes.rawValue)
            sizeByCask = await caskSizes(casks: payload.casks)
        } else {
            sizeByCask = [:]
        }

        let packages = Self.buildPackages(
            payload: payload,
            formulaeFallback: formulae,
            casksFallback: casks,
            deps: deps,
            reverseDeps: reverseDeps,
            leaves: leaves,
            outdated: outdated,
            sizeByFormula: sizeByFormula,
            sizeByCask: sizeByCask
        )

        let summary = BrewSummary(
            formulaCount: packages.filter { $0.kind == .formula }.count,
            caskCount: packages.filter { $0.kind == .cask }.count,
            leafCount: packages.filter(\.isLeaf).count,
            edgeCount: edges.count,
            outdatedCount: packages.filter(\.outdated).count,
            unusedDependencyCount: packages.filter(\.isUnusedDependency).count,
            totalKnownSize: packages.compactMap(\.size).reduce(0, +)
        )

        var snapshot = BrewSnapshot(
            brewPath: discovery.brewPath,
            brewPrefix: discovery.brewPrefix,
            packages: packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            formulae: formulae.isEmpty ? payload.formulae.map(\.name).sorted() : formulae.map(Self.canonicalFormulaName).sorted(),
            casks: casks.isEmpty ? payload.casks.compactMap(\.token).sorted() : casks,
            deps: deps,
            reverseDeps: reverseDeps,
            edges: edges,
            leaves: leaves,
            cleanupDryRun: cleanup,
            summary: summary,
            scanDuration: .milliseconds(Int64(Date().timeIntervalSince(start) * 1_000)),
            warnings: warnings
        )
        snapshot.brewDoctorWarnings = brewDoctorWarnings
        return snapshot
    }

    // MARK: - Parsing

    /// Parses `brew deps --installed --for-each --direct` output.
    /// Format: `formula: dep1 dep2 dep3` or `tap/formula: dep1 dep2`
    /// Returns `[formulaName: [dependencyNames]]`, normalizing tap-prefixed names.
    static func parseDirectDependencies(_ output: String) -> [String: [String]] {
        var deps: [String: [String]] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
            guard let rawFormula = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !rawFormula.isEmpty else {
                continue
            }
            let formula = canonicalFormulaName(rawFormula)

            guard parts.count == 2 else {
                deps[formula] = []
                continue
            }

            deps[formula] = parts[1]
                .split { $0 == " " || $0 == "," || $0 == "\t" }
                .map { canonicalFormulaName(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }
        }

        return deps
    }

    static func canonicalFormulaName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    static func buildReverseDependencies(from deps: [String: [String]]) -> [String: [String]] {
        var reverse: [String: Set<String>] = [:]

        for (formula, dependencies) in deps {
            if reverse[formula] == nil {
                reverse[formula] = []
            }
            for dependency in dependencies {
                reverse[dependency, default: []].insert(formula)
            }
        }

        return reverse.mapValues { $0.sorted() }
    }

    static func buildEdges(from deps: [String: [String]]) -> [DependencyEdge] {
        deps.flatMap { formula, dependencies in
            dependencies.map { DependencyEdge(formulaName: formula, dependencyName: $0) }
        }
        .sorted { $0.id < $1.id }
    }

    private func runRequired(
        discovery: BrewDiscoveryResult,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        let result = try await processRunner.run(
            executableURL: discovery.brewPath,
            arguments: arguments,
            environment: brewEnvironment,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw BrewScanError.commandFailed(arguments.joined(separator: " "), result)
        }

        return result
    }

    private func runOptionalText(
        discovery: BrewDiscoveryResult,
        arguments: [String],
        timeout: TimeInterval,
        allowedExitCodes: Set<Int32> = [0],
        warnings: inout [String]
    ) async -> String {
        do {
            let result = try await processRunner.run(
                executableURL: discovery.brewPath,
                arguments: arguments,
                environment: brewEnvironment,
                timeout: timeout
            )

            guard allowedExitCodes.contains(result.exitCode) else {
                warnings.append("\(arguments.joined(separator: " ")) exited with \(result.exitCode): \(result.trimmedStderr)")
                return ""
            }

            return result.stdout
        } catch {
            warnings.append("\(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
            return ""
        }
    }

    private func runOptionalLines(
        discovery: BrewDiscoveryResult,
        arguments: [String],
        timeout: TimeInterval,
        warnings: inout [String]
    ) async -> [String] {
        let output = await runOptionalText(
            discovery: discovery,
            arguments: arguments,
            timeout: timeout,
            warnings: &warnings
        )

        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var brewEnvironment: [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["HOMEBREW_NO_ENV_HINTS"] = "1"
        values["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        values["LC_ALL"] = "C"
        return values
    }

    private func doctorWarnings(discovery: BrewDiscoveryResult, warnings: inout [String]) async -> [String] {
        let output = await runOptionalText(
            discovery: discovery,
            arguments: ["doctor"],
            timeout: 30,
            allowedExitCodes: [0, 1],
            warnings: &warnings
        )

        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.hasPrefix("Warning:") || line.hasPrefix("Error:")
            }
    }

    private func formulaSizes(formulae: Set<String>, prefix: URL) async -> [String: Int64] {
        let cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
        let maxConcurrentScans = 6
        var sizes: [String: Int64] = [:]

        for batch in formulae.sorted().chunked(maxSize: maxConcurrentScans) {
            let batchSizes = await withTaskGroup(of: (String, Int64)?.self) { group in
                for formula in batch {
                    group.addTask(priority: .utility) {
                        let fileManager = FileManager.default
                        let url = cellar.appendingPathComponent(formula, isDirectory: true)
                        guard fileManager.fileExists(atPath: url.path) else {
                            return nil
                        }

                        return (formula, Self.directorySize(url: url, fileManager: fileManager))
                    }
                }

                var result: [String: Int64] = [:]
                for await item in group {
                    if let (formula, size) = item {
                        result[formula] = size
                    }
                }
                return result
            }

            sizes.merge(batchSizes) { current, _ in current }
        }

        return sizes
    }

    private func caskSizes(casks: [BrewCask]) async -> [String: Int64] {
        let caskArtifacts = casks.compactMap { cask -> (String, [String])? in
            guard let token = cask.token else {
                return nil
            }
            let apps = cask.artifacts?
                .flatMap(\.apps)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
            guard !apps.isEmpty else {
                return nil
            }
            return (token, apps)
        }

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            var sizes: [String: Int64] = [:]

            for (token, apps) in caskArtifacts {
                let urls = apps.flatMap {
                    Self.caskArtifactCandidateURLs(
                        for: $0,
                        homeDirectory: fileManager.homeDirectoryForCurrentUser
                    )
                }
                let total = urls.reduce(Int64(0)) { partialResult, url in
                    guard fileManager.fileExists(atPath: url.path) else {
                        return partialResult
                    }
                    return partialResult + Self.directorySize(url: url, fileManager: fileManager)
                }

                if total > 0 {
                    sizes[token] = total
                }
            }

            return sizes
        }
        .value
    }

    private static func caskArtifactCandidateURLs(for artifact: String, homeDirectory: URL) -> [URL] {
        let path = NSString(string: artifact).expandingTildeInPath
        if path.hasPrefix("/") {
            return [URL(fileURLWithPath: path)]
        }

        return [
            URL(fileURLWithPath: "/Applications").appendingPathComponent(path),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(path)
        ]
    }

    private static func directorySize(url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(resourceValues?.totalFileAllocatedSize ?? resourceValues?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func parseOutdated(_ output: String) -> Set<String> {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BrewOutdatedPayload.self, from: data) else {
            return []
        }

        return Set((payload.formulae + payload.casks).compactMap(\.name))
    }

    private static func buildPackages(
        payload: BrewInfoPayload,
        formulaeFallback: [String],
        casksFallback: [String],
        deps: [String: [String]],
        reverseDeps: [String: [String]],
        leaves: Set<String>,
        outdated: Set<String>,
        sizeByFormula: [String: Int64],
        sizeByCask: [String: Int64]
    ) -> [Package] {
        let formulaNames = Set(formulaeFallback.map(canonicalFormulaName)).union(payload.formulae.map(\.name))
        let formulaByName = Dictionary(uniqueKeysWithValues: payload.formulae.map { ($0.name, $0) })
        let formulas = formulaNames.map { name -> Package in
            let formula = formulaByName[name]
            let install = formula?.installed?.last
            let installDate = install?.time.map { Date(timeIntervalSince1970: $0) }
            let dependencyNames = deps[name] ?? formula?.dependencies?.map(canonicalFormulaName) ?? []
            let runtimeDependencyNames = formula?.runtimeDependencies?
                .compactMap { $0.fullName ?? $0.name }
                .map(canonicalFormulaName) ?? []
            let isLeaf = leaves.contains(name)
                || formula?.fullName.map { leaves.contains(canonicalFormulaName($0)) } == true
            let installedOnRequest = install?.installedOnRequest ?? isLeaf

            return Package(
                id: PackageID.formula(name),
                name: name,
                kind: .formula,
                version: install?.version ?? formula?.versions?.stable ?? "unknown",
                stableVersion: formula?.versions?.stable,
                description: formula?.description ?? "",
                homepage: formula?.homepage.flatMap(URL.init(string:)),
                license: formula?.license?.text.nilIfEmpty,
                tap: formula?.tap,
                installedAt: installDate,
                installedOnRequest: installedOnRequest,
                installedAsDependency: install?.installedAsDependency ?? !installedOnRequest,
                outdated: outdated.contains(name),
                pinned: formula?.pinned ?? false,
                deprecated: formula?.deprecated ?? false,
                disabled: formula?.disabled ?? false,
                kegOnly: formula?.kegOnly ?? false,
                size: sizeByFormula[name],
                iconPath: nil,
                dependencies: dependencyNames.sorted(),
                reverseDependencies: reverseDeps[name] ?? [],
                runtimeDependencies: runtimeDependencyNames.sorted()
            )
        }

        let caskTokens = Set(casksFallback).union(payload.casks.compactMap(\.token))
        let caskByToken = Dictionary(uniqueKeysWithValues: payload.casks.compactMap { cask in
            cask.token.map { ($0, cask) }
        })
        let casks = caskTokens.map { token -> Package in
            let cask = caskByToken[token]
            return Package(
                id: PackageID.cask(token),
                name: token,
                kind: .cask,
                version: cask?.installed ?? cask?.version ?? "unknown",
                stableVersion: cask?.version,
                description: cask?.description?.joinedText ?? cask?.name?.joinedText ?? "",
                homepage: cask?.homepage.flatMap(URL.init(string:)),
                license: nil,
                tap: cask?.tap,
                installedAt: nil,
                installedOnRequest: true,
                installedAsDependency: false,
                outdated: outdated.contains(token) || (cask?.outdated ?? false),
                pinned: false,
                deprecated: false,
                disabled: false,
                kegOnly: false,
                size: sizeByCask[token],
                iconPath: Self.firstInstalledCaskArtifactPath(
                    artifacts: cask?.artifacts,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    exists: { FileManager.default.fileExists(atPath: $0.path) }
                ),
                dependencies: [],
                reverseDependencies: [],
                runtimeDependencies: []
            )
        }

        return formulas + casks
    }

    static func firstInstalledCaskArtifactPath(
        artifacts: [BrewCaskArtifact]?,
        homeDirectory: URL,
        exists: (URL) -> Bool
    ) -> String? {
        let apps = artifacts?
            .flatMap(\.apps)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []

        for app in apps {
            let candidates = caskArtifactCandidateURLs(for: app, homeDirectory: homeDirectory)
            if let url = candidates.first(where: exists) {
                return url.path
            }
        }

        return nil
    }
}

enum BrewScanError: LocalizedError, Equatable {
    case commandFailed(String, CommandResult)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, result):
            let detail = result.trimmedStderr.isEmpty ? result.trimmedStdout : result.trimmedStderr
            return "`brew \(command)` failed with code \(result.exitCode): \(detail)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

extension BrewScanner {
    enum ScanStep: String, Sendable {
        case metadata = "Reading installed package metadata"
        case formulaList = "Reading formula list"
        case caskList = "Reading cask list"
        case deps = "Reading direct dependency edges"
        case leaves = "Reading leaves and outdated packages"
        case cleanup = "Estimating cleanup hints"
        case formulaSizes = "Estimating formula sizes"
        case caskSizes = "Estimating cask sizes"
        case doctor = "Running brew doctor"

        var fraction: Double {
            switch self {
            case .metadata: 0.28
            case .formulaList: 0.44
            case .caskList: 0.58
            case .deps: 0.72
            case .leaves: 0.86
            case .cleanup: 0.92
            case .formulaSizes: 0.96
            case .caskSizes: 0.98
            case .doctor: 0.99
            }
        }
    }
}
