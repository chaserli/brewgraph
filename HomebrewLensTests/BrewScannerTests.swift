import XCTest
@testable import HomebrewLens

final class BrewScannerTests: XCTestCase {
    func testScanOptionsCanSkipCleanupDryRun() async throws {
        let runner = ScannerFakeProcessRunner(results: scannerResults())
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false
            )
        )

        let environments = await runner.recordedEnvironments()
        let firstEnv = environments.first ?? [:]
        XCTAssertEqual(firstEnv["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertEqual(firstEnv["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(firstEnv["LC_ALL"], "C")
        XCTAssertEqual(snapshot.cleanupDryRun, .empty)
        XCTAssertEqual(snapshot.summary.totalKnownSize, 0)
    }

    func testOptionalCommandFailureProducesWarningAndKeepsSnapshot() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew list --cask"] = CommandResult(stdout: "", stderr: "casks unavailable", exitCode: 1)
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: true
            )
        )

        XCTAssertEqual(snapshot.summary.formulaCount, 2)
        XCTAssertTrue(snapshot.warnings.contains { warning in
            warning.contains("list --cask exited with 1") && warning.contains("casks unavailable")
        })
    }

    func testMalformedRequiredBrewInfoJSONIsHardFailure() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew info --json=v2 --installed"] = CommandResult(
            stdout: #"{"formulae": ["#,
            stderr: "",
            exitCode: 0
        )
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        do {
            _ = try await scanner.scan(
                discovery: scannerDiscovery,
                options: ScanOptions(
                    estimateFormulaSizes: false,
                    estimateCaskSizes: false,
                    runCleanupDryRun: false
                )
            )
            XCTFail("Expected malformed required brew info JSON to fail the scan.")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testScanExposesInstallReasonAndTapOrigin() async throws {
        let runner = ScannerFakeProcessRunner(results: scannerResults())
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false
            )
        )

        let requested = try XCTUnwrap(snapshot.package(named: "node"))
        let dependency = try XCTUnwrap(snapshot.package(named: "openssl@3"))

        XCTAssertEqual(requested.installReason, .requested)
        XCTAssertEqual(dependency.installReason, .dependency)
        XCTAssertFalse(requested.isExternalTap)
        XCTAssertTrue(dependency.isExternalTap)
        XCTAssertEqual(snapshot.requestedPackageCount, 1)
        XCTAssertEqual(snapshot.dependencyOnlyPackageCount, 1)
        XCTAssertEqual(snapshot.externalTapPackageCount, 1)
        XCTAssertEqual(Set(snapshot.tapSummaries.map(\.name)), ["homebrew/core", "custom/crypto"])
    }

    func testSnapshotDerivedDashboardMetrics() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew doctor"] = CommandResult(
            stdout: """
            Warning: Some directories are not writable.
            Warning: You have unlinked kegs in your Cellar.
            """,
            stderr: "",
            exitCode: 0
        )
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: true,
                runBrewDoctor: true
            )
        )

        XCTAssertEqual(snapshot.requestedPackageCount, 1)
        XCTAssertEqual(snapshot.dependencyOnlyPackageCount, 1)
        XCTAssertEqual(snapshot.summary.unusedDependencyCount, 0)
        XCTAssertEqual(snapshot.cleanupDryRun.reclaimText, "1.2MB")
        XCTAssertEqual(snapshot.doctorCategoryCounts[.permissions], 1)
        XCTAssertEqual(snapshot.doctorCategoryCounts[.other], 1)
        XCTAssertEqual(snapshot.tapSummaries.first?.name, "custom/crypto")
        XCTAssertEqual(snapshot.tapSummaries.first?.isExternal, true)
    }

    func testScanDoesNotMarkRequestedTappedLeavesAsUnusedDependencies() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew info --json=v2 --installed"] = CommandResult(
            stdout:
            """
            {
              "formulae": [
                {
                  "name": "oh-my-posh",
                  "full_name": "jandedobbeleer/oh-my-posh/oh-my-posh",
                  "desc": "Prompt theme engine",
                  "tap": "jandedobbeleer/oh-my-posh",
                  "versions": { "stable": "29.12.0" },
                  "installed": [{"version": "29.12.0", "installed_on_request": true}],
                  "dependencies": [],
                  "runtime_dependencies": []
                },
                {
                  "name": "opencode",
                  "full_name": "anomalyco/tap/opencode",
                  "desc": "AI coding agent",
                  "tap": "anomalyco/tap",
                  "versions": { "stable": "1.14.30" },
                  "installed": [{"version": "1.14.30", "installed_on_request": true}],
                  "dependencies": ["ripgrep"],
                  "runtime_dependencies": [{"full_name": "ripgrep"}]
                },
                {
                  "name": "ripgrep",
                  "desc": "Search tool",
                  "tap": "homebrew/core",
                  "versions": { "stable": "15.1.0" },
                  "installed": [{"version": "15.1.0", "installed_as_dependency": true}],
                  "dependencies": ["pcre2"],
                  "runtime_dependencies": [{"full_name": "pcre2"}]
                }
              ],
              "casks": []
            }
            """,
            stderr: "",
            exitCode: 0
        )
        results["/opt/homebrew/bin/brew list --formula"] = CommandResult(stdout: "oh-my-posh\nopencode\nripgrep\n", stderr: "", exitCode: 0)
        results["/opt/homebrew/bin/brew deps --installed --for-each --direct"] = CommandResult(
            stdout: "jandedobbeleer/oh-my-posh/oh-my-posh:\nanomalyco/tap/opencode: ripgrep\nripgrep: pcre2\n",
            stderr: "",
            exitCode: 0
        )
        results["/opt/homebrew/bin/brew leaves"] = CommandResult(
            stdout: "jandedobbeleer/oh-my-posh/oh-my-posh\nanomalyco/tap/opencode\n",
            stderr: "",
            exitCode: 0
        )

        let scanner = BrewScanner(processRunner: ScannerFakeProcessRunner(results: results))
        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false
            )
        )

        let ohMyPosh = try XCTUnwrap(snapshot.package(named: "oh-my-posh"))
        let opencode = try XCTUnwrap(snapshot.package(named: "opencode"))

        XCTAssertEqual(ohMyPosh.installReason, .requested)
        XCTAssertEqual(opencode.installReason, .requested)
        XCTAssertFalse(ohMyPosh.isUnusedDependency)
        XCTAssertFalse(opencode.isUnusedDependency)
        XCTAssertEqual(snapshot.deps["opencode"], ["ripgrep"])
        XCTAssertEqual(snapshot.reverseDeps["ripgrep"], ["opencode"])
    }

    func testDirectDependencyParsingPreservesEmptyRows() {
        let deps = BrewScanner.parseDirectDependencies(
            """
            node: brotli c-ares icu4c
            zlib:
            openssl@3: ca-certificates
            """
        )

        XCTAssertEqual(deps["node"], ["brotli", "c-ares", "icu4c"])
        XCTAssertEqual(deps["zlib"], [])
        XCTAssertEqual(deps["openssl@3"], ["ca-certificates"])
    }

    func testDirectDependencyParsingNormalizesTappedFormulaNames() {
        let deps = BrewScanner.parseDirectDependencies(
            """
            jandedobbeleer/oh-my-posh/oh-my-posh:
            anomalyco/tap/opencode: ripgrep
            """
        )

        XCTAssertEqual(deps["oh-my-posh"], [])
        XCTAssertEqual(deps["opencode"], ["ripgrep"])
    }

    func testReverseDependencyConstruction() {
        let reverse = BrewScanner.buildReverseDependencies(
            from: [
                "node": ["brotli", "openssl@3"],
                "ffmpeg": ["openssl@3"]
            ]
        )

        XCTAssertEqual(reverse["openssl@3"], ["ffmpeg", "node"])
        XCTAssertEqual(reverse["brotli"], ["node"])
    }

    func testDependencyEdgesUseFormulaPackageIDs() {
        let edges = BrewScanner.buildEdges(from: ["node": ["openssl@3"]])

        XCTAssertEqual(edges.first?.formulaID, "formula:node")
        XCTAssertEqual(edges.first?.dependencyID, "formula:openssl@3")
        XCTAssertEqual(edges.first?.formulaName, "node")
        XCTAssertEqual(edges.first?.dependencyName, "openssl@3")
    }

    func testCleanupDryRunParserExtractsReclaimText() {
        let summary = CleanupDryRunParser.parse(
            """
            Would remove: /opt/homebrew/Cellar/foo/1.0
            ==> This operation would free approximately 655.1MB of disk space.
            """
        )

        XCTAssertEqual(summary.reclaimText, "655.1MB")
        XCTAssertEqual(summary.lines.count, 2)
    }

    func testBrewInfoPayloadDecodesFormulaAndCaskSubset() throws {
        let data = Data(
            """
            {
              "formulae": [
                {
                  "name": "node",
                  "full_name": "node",
                  "desc": "Platform",
                  "homepage": "https://nodejs.org/",
                  "license": ["MIT"],
                  "tap": "homebrew/core",
                  "versions": { "stable": "24.0.0" },
                  "installed": [
                    {
                      "version": "24.0.0",
                      "installed_on_request": true,
                      "installed_as_dependency": false,
                      "time": 1710000000
                    }
                  ],
                  "dependencies": ["openssl@3"],
                  "runtime_dependencies": [{"full_name": "openssl@3"}],
                  "pinned": false,
                  "deprecated": false,
                  "disabled": false,
                  "keg_only": false
                }
              ],
              "casks": [
                {
                  "token": "visual-studio-code",
                  "name": ["Visual Studio Code"],
                  "desc": "Code editor",
                  "version": "1.0",
                  "installed": "1.0",
                  "homepage": "https://code.visualstudio.com/",
                  "tap": "homebrew/cask",
                  "outdated": false,
                  "artifacts": [
                    { "app": "Visual Studio Code.app" },
                    { "app": [{ "target": "Code Helper.app" }] },
                    "ignored-shape"
                  ]
                }
              ]
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(BrewInfoPayload.self, from: data)

        XCTAssertEqual(payload.formulae.first?.name, "node")
        XCTAssertEqual(payload.formulae.first?.license?.text, "MIT")
        XCTAssertEqual(payload.casks.first?.token, "visual-studio-code")
        XCTAssertEqual(payload.casks.first?.artifacts?.flatMap(\.apps), ["Visual Studio Code.app", "Code Helper.app"])
    }

    func testCaskIconPathPrefersExistingArtifactCandidate() throws {
        let data = Data(
            """
            {
              "token": "visual-studio-code",
              "artifacts": [
                { "app": "Visual Studio Code.app" },
                { "app": [{ "target": "Code Helper.app" }] }
              ]
            }
            """.utf8
        )
        let cask = try JSONDecoder().decode(BrewCask.self, from: data)
        let home = URL(fileURLWithPath: "/Users/example")

        let path = BrewScanner.firstInstalledCaskArtifactPath(
            artifacts: cask.artifacts,
            homeDirectory: home,
            exists: { $0.path == "/Users/example/Applications/Code Helper.app" }
        )

        XCTAssertEqual(path, "/Users/example/Applications/Code Helper.app")
    }

    // MARK: - Edge Cases

    func testParseOutdatedEmptyJSON() {
        let result = BrewScanner.parseOutdated("")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseOutdatedInvalidJSON() {
        let result = BrewScanner.parseOutdated("not json at all")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseOutdatedWithData() {
        let json = """
        {"formulae":[{"name":"node","installed_versions":["24.0.0"],"current_version":"25.0.0"}],"casks":[]}
        """
        let result = BrewScanner.parseOutdated(json)
        XCTAssertTrue(result.contains("node"))
    }

    func testParseDirectDependenciesWithWhitespace() {
        let deps = BrewScanner.parseDirectDependencies(
            """
            node:   brotli   c-ares
            zlib:
            openssl@3: ca-certificates
            """
        )
        XCTAssertEqual(deps["node"], ["brotli", "c-ares"])
        XCTAssertEqual(deps["zlib"], [])
    }

    func testParseDirectDependenciesEmptyInput() {
        let deps = BrewScanner.parseDirectDependencies("")
        XCTAssertTrue(deps.isEmpty)
    }

    func testParseDirectDependenciesMixedDelimiters() {
        let deps = BrewScanner.parseDirectDependencies(
            "node: brotli, c-ares icu4c"
        )
        XCTAssertEqual(deps["node"], ["brotli", "c-ares", "icu4c"])
    }

    func testDoctorScanCanBeEnabled() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew doctor"] = CommandResult(
            stdout: "Warning: Some directories are not writable.\n",
            stderr: "",
            exitCode: 0
        )
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false,
                runBrewDoctor: true
            )
        )

        XCTAssertEqual(snapshot.brewDoctorWarnings.count, 1)
        XCTAssertTrue(snapshot.brewDoctorWarnings.first?.contains("Some directories") == true)
    }

    func testDoctorScanExitedWithError() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew doctor"] = CommandResult(
            stdout: "Warning: Problem one.\nError: Something is broken.\n",
            stderr: "",
            exitCode: 1
        )
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false,
                runBrewDoctor: true
            )
        )

        XCTAssertEqual(snapshot.brewDoctorWarnings.count, 2)
    }

    func testDoctorScanDisabledByDefault() async throws {
        var results = scannerResults()
        results["/opt/homebrew/bin/brew doctor"] = CommandResult(
            stdout: "Warning: test\n",
            stderr: "",
            exitCode: 0
        )
        let runner = ScannerFakeProcessRunner(results: results)
        let scanner = BrewScanner(processRunner: runner)

        let snapshot = try await scanner.scan(
            discovery: scannerDiscovery,
            options: ScanOptions(
                estimateFormulaSizes: false,
                estimateCaskSizes: false,
                runCleanupDryRun: false,
                runBrewDoctor: false
            )
        )

        XCTAssertTrue(snapshot.brewDoctorWarnings.isEmpty)
    }

    private var scannerDiscovery: BrewDiscoveryResult {
        BrewDiscoveryResult(
            brewPath: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            brewPrefix: URL(fileURLWithPath: "/opt/homebrew"),
            attempts: []
        )
    }

    private func scannerResults() -> [String: CommandResult] {
        [
            "/opt/homebrew/bin/brew info --json=v2 --installed": CommandResult(
                stdout:
                """
                {
                  "formulae": [
                    {
                      "name": "node",
                      "desc": "Platform",
                      "homepage": "https://nodejs.org/",
                      "tap": "homebrew/core",
                      "versions": { "stable": "24.0.0" },
                      "installed": [{"version": "24.0.0", "installed_on_request": true, "installed_as_dependency": false}],
                      "dependencies": ["openssl@3"],
                      "runtime_dependencies": [{"full_name": "openssl@3"}],
                      "pinned": false,
                      "deprecated": false,
                      "disabled": false,
                      "keg_only": false
                    },
                    {
                      "name": "openssl@3",
                      "desc": "TLS",
                      "homepage": "https://openssl.org/",
                      "tap": "custom/crypto",
                      "versions": { "stable": "3.0.0" },
                      "installed": [{"version": "3.0.0", "installed_on_request": false, "installed_as_dependency": true}],
                      "dependencies": [],
                      "runtime_dependencies": [],
                      "pinned": false,
                      "deprecated": false,
                      "disabled": false,
                      "keg_only": false
                    }
                  ],
                  "casks": []
                }
                """,
                stderr: "",
                exitCode: 0
            ),
            "/opt/homebrew/bin/brew list --formula": CommandResult(stdout: "node\nopenssl@3\n", stderr: "", exitCode: 0),
            "/opt/homebrew/bin/brew list --cask": CommandResult(stdout: "", stderr: "", exitCode: 0),
            "/opt/homebrew/bin/brew deps --installed --for-each --direct": CommandResult(stdout: "node: openssl@3\nopenssl@3:\n", stderr: "", exitCode: 0),
            "/opt/homebrew/bin/brew leaves": CommandResult(stdout: "node\n", stderr: "", exitCode: 0),
            "/opt/homebrew/bin/brew outdated --json=v2": CommandResult(stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", exitCode: 0),
            "/opt/homebrew/bin/brew cleanup --dry-run": CommandResult(
                stdout: "==> This operation would free approximately 1.2MB of disk space.\n",
                stderr: "",
                exitCode: 0
            )
        ]
    }
}

private actor ScannerFakeProcessRunner: BrewProcessRunning {
    struct Call {
        let arguments: [String]
        let environment: [String: String]
    }

    private let results: [String: CommandResult]
    private var calls: [Call] = []

    init(results: [String: CommandResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        calls.append(Call(arguments: arguments, environment: environment))
        let key = ([executableURL.path] + arguments).joined(separator: " ")
        return results[key] ?? CommandResult(stdout: "", stderr: "missing fake result for \(key)", exitCode: 127)
    }

    func recordedArguments() -> [[String]] {
        calls.map(\.arguments)
    }

    func recordedEnvironments() -> [[String: String]] {
        calls.map(\.environment)
    }
}

// MARK: - Package Model Tests

final class PackageModelTests: XCTestCase {

    func testLeafWhenNoReverseDependenciesAndFormula() {
        let pkg = makePackage(name: "yaml", kind: .formula, reverseDeps: [])
        XCTAssertTrue(pkg.isLeaf)
    }

    func testNotLeafWhenHasReverseDependencies() {
        let pkg = makePackage(name: "openssl", kind: .formula, reverseDeps: ["node"])
        XCTAssertFalse(pkg.isLeaf)
    }

    func testCaskIsNotLeaf() {
        let pkg = makePackage(name: "firefox", kind: .cask, reverseDeps: [])
        XCTAssertFalse(pkg.isLeaf)
    }

    func testUnusedDependencyWhenDependencyWithNoReverseDeps() {
        let pkg = makePackage(name: "libyaml", kind: .formula, installedOnRequest: false, installedAsDependency: true, reverseDeps: [])
        XCTAssertTrue(pkg.isUnusedDependency)
    }

    func testNotUnusedDependencyWhenRequested() {
        let pkg = makePackage(name: "node", kind: .formula, installedOnRequest: true, installedAsDependency: false, reverseDeps: [])
        XCTAssertFalse(pkg.isUnusedDependency)
    }

    func testCaskIsNotUnusedDependency() {
        let pkg = makePackage(name: "firefox", kind: .cask, installedOnRequest: false, installedAsDependency: true, reverseDeps: [])
        XCTAssertFalse(pkg.isUnusedDependency)
    }

    func testInternalTap() {
        XCTAssertFalse(makePackage(name: "node", tap: "homebrew/core").isExternalTap)
        XCTAssertFalse(makePackage(name: "firefox", tap: "homebrew/cask").isExternalTap)
    }

    func testExternalTap() {
        XCTAssertTrue(makePackage(name: "oh-my-posh", tap: "jandedobbeleer/oh-my-posh").isExternalTap)
    }

    func testEmptyTapIsNotExternal() {
        XCTAssertFalse(makePackage(name: "legacy", tap: "").isExternalTap)
    }

    func testStatusBadgesForRequestedPackage() {
        let pkg = makePackage(name: "node", installedOnRequest: true, installedAsDependency: false)
        XCTAssertTrue(pkg.statusBadges.contains { $0.title == "Requested" })
    }

    func testStatusBadgesForOutdatedAndDeprecated() {
        let pkg = makePackage(name: "old-lib", outdated: true, deprecated: true)
        let badges = pkg.statusBadges
        XCTAssertTrue(badges.contains { $0.title == "Outdated" })
        XCTAssertTrue(badges.contains { $0.title == "Deprecated" })
    }

    func testStatusBadgesUnique() {
        let pkg = makePackage(name: "clean", installedOnRequest: true)
        let titles = pkg.statusBadges.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testSnapshotNameLookupPrefersFormulaWhenCaskHasSameName() {
        let formula = makePackage(name: "shared", kind: .formula)
        let cask = makePackage(name: "shared", kind: .cask, tap: "homebrew/cask")
        let snapshot = BrewSnapshot(
            brewPath: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            brewPrefix: URL(fileURLWithPath: "/opt/homebrew"),
            packages: [formula, cask],
            formulae: ["shared"],
            casks: ["shared"],
            deps: [:],
            reverseDeps: [:],
            edges: [],
            leaves: [],
            cleanupDryRun: .empty,
            summary: BrewSummary(
                formulaCount: 1,
                caskCount: 1,
                leafCount: 1,
                edgeCount: 0,
                outdatedCount: 0,
                unusedDependencyCount: 0,
                totalKnownSize: 0
            ),
            scanDuration: .milliseconds(100),
            warnings: []
        )

        XCTAssertEqual(snapshot.package(named: "shared")?.id, PackageID.formula("shared"))
        XCTAssertEqual(snapshot.package(id: PackageID.cask("shared"))?.kind, .cask)
    }

    // MARK: - Helpers

    private func makePackage(
        name: String,
        kind: PackageKind = .formula,
        tap: String? = "homebrew/core",
        installedOnRequest: Bool = true,
        installedAsDependency: Bool = false,
        outdated: Bool = false,
        deprecated: Bool = false,
        disabled: Bool = false,
        kegOnly: Bool = false,
        reverseDeps: [String] = []
    ) -> Package {
        Package(
            id: kind == .formula ? "formula:\(name)" : "cask:\(name)",
            name: name,
            kind: kind,
            version: "1.0.0",
            stableVersion: "1.0.0",
            description: "Test package",
            homepage: nil,
            license: nil,
            tap: tap,
            installedAt: nil,
            installedOnRequest: installedOnRequest,
            installedAsDependency: installedAsDependency,
            outdated: outdated,
            pinned: false,
            deprecated: deprecated,
            disabled: disabled,
            kegOnly: kegOnly,
            size: nil,
            iconPath: nil,
            dependencies: [],
            reverseDependencies: reverseDeps,
            runtimeDependencies: []
        )
    }
}

// MARK: - Localization Catalog Tests

final class LocalizationCatalogTests: XCTestCase {
    func testStringCatalogHasEnglishAndSimplifiedChineseValuesForEveryKey() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HomebrewLens/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)

        var missing: [String] = []
        for key in catalog.strings.keys.sorted() {
            let localizations = catalog.strings[key]?.localizations ?? [:]
            for language in ["en", "zh-Hans"] {
                let value = localizations[language]?.stringUnit?.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value?.isEmpty ?? true {
                    missing.append("\(key) [\(language)]")
                }
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing localized values: \(missing.prefix(20).joined(separator: ", "))")
    }
}

private struct StringCatalog: Decodable {
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringCatalogLocalization]?
}

private struct StringCatalogLocalization: Decodable {
    let stringUnit: StringCatalogStringUnit?
}

private struct StringCatalogStringUnit: Decodable {
    let value: String
}
