import XCTest
@testable import HomebrewLens

final class HomebrewDiscoveryTests: XCTestCase {
    func testDiscoveryPrefersHomebrewBrewFileBeforeOtherCandidates() async throws {
        let runner = FakeBrewProcessRunner(
            results: [
                "/custom/bin/brew --prefix": CommandResult(stdout: "/custom\n", stderr: "", exitCode: 0)
            ]
        )
        let controller = HomebrewController(
            environment: FakeEnvironment(
                values: [
                    "HOMEBREW_BREW_FILE": "/custom/bin/brew",
                    "HOMEBREW_PREFIX": "/ignored"
                ]
            ),
            fileChecker: FakeFileChecker(executablePaths: ["/custom/bin/brew", "/ignored/bin/brew"]),
            processRunner: runner
        )

        let result = try await controller.discoverHomebrew()
        let calls = await runner.calls

        XCTAssertEqual(result.brewPath.path, "/custom/bin/brew")
        XCTAssertEqual(result.brewPrefix.path, "/custom")
        XCTAssertEqual(calls.map(\.executablePath), ["/custom/bin/brew"])
        XCTAssertEqual(calls.first?.arguments, ["--prefix"])
        XCTAssertEqual(calls.first?.environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertEqual(calls.first?.environment["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(calls.first?.environment["LC_ALL"], "C")
        XCTAssertEqual(result.attempts.last?.outcome, "found")
    }

    func testDiscoveryUsesPrefixBeforeStaticPaths() async throws {
        let runner = FakeBrewProcessRunner(
            results: [
                "/prefix/bin/brew --prefix": CommandResult(stdout: "/prefix\n", stderr: "", exitCode: 0)
            ]
        )
        let controller = HomebrewController(
            environment: FakeEnvironment(values: ["HOMEBREW_PREFIX": "/prefix"]),
            fileChecker: FakeFileChecker(executablePaths: ["/prefix/bin/brew", "/opt/homebrew/bin/brew"]),
            processRunner: runner
        )

        let result = try await controller.discoverHomebrew()

        XCTAssertEqual(result.brewPath.path, "/prefix/bin/brew")
        XCTAssertEqual(result.brewPrefix.path, "/prefix")
        XCTAssertEqual(result.attempts.map(\.source), ["HOMEBREW_BREW_FILE", "HOMEBREW_PREFIX/bin/brew"])
    }

    func testMissingHomebrewReturnsAllDiscoveryAttempts() async throws {
        let runner = FakeBrewProcessRunner(
            results: [
                "/bin/zsh -lc command -v brew": CommandResult(stdout: "", stderr: "", exitCode: 1)
            ]
        )
        let controller = HomebrewController(
            environment: FakeEnvironment(values: [:]),
            fileChecker: FakeFileChecker(executablePaths: []),
            processRunner: runner
        )

        do {
            _ = try await controller.discoverHomebrew()
            XCTFail("Expected Homebrew discovery to fail.")
        } catch let error as BrewDiscoveryError {
            guard case let .notFound(attempts) = error else {
                return XCTFail("Expected notFound, got \(error).")
            }
            XCTAssertEqual(attempts.count, 5)
            XCTAssertEqual(attempts.last?.source, "/bin/zsh -lc 'command -v brew'")
            XCTAssertEqual(attempts.last?.outcome, "not found")
        }
    }

    func testForcedMissingHomebrewEnvironmentBypassesRealDiscoveryForQA() async throws {
        let runner = FakeBrewProcessRunner(results: [:])
        let controller = HomebrewController(
            environment: FakeEnvironment(values: ["BREWGRAPH_FORCE_MISSING_HOMEBREW": "1"]),
            fileChecker: FakeFileChecker(executablePaths: ["/opt/homebrew/bin/brew"]),
            processRunner: runner
        )

        do {
            _ = try await controller.discoverHomebrew()
            XCTFail("Expected forced missing Homebrew discovery to fail.")
        } catch let error as BrewDiscoveryError {
            guard case let .notFound(attempts) = error else {
                return XCTFail("Expected notFound, got \(error).")
            }
            XCTAssertEqual(attempts.map(\.source), ["BREWGRAPH_FORCE_MISSING_HOMEBREW"])
            XCTAssertEqual(attempts.first?.outcome, "forced missing Homebrew for diagnostics QA")
            let calls = await runner.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testPrefixFailureIsReportedAsDiscoveryFailure() async throws {
        let runner = FakeBrewProcessRunner(
            results: [
                "/opt/homebrew/bin/brew --prefix": CommandResult(stdout: "", stderr: "boom", exitCode: 2)
            ]
        )
        let controller = HomebrewController(
            environment: FakeEnvironment(values: [:]),
            fileChecker: FakeFileChecker(executablePaths: ["/opt/homebrew/bin/brew"]),
            processRunner: runner
        )

        do {
            _ = try await controller.discoverHomebrew()
            XCTFail("Expected prefix failure.")
        } catch let error as BrewDiscoveryError {
            guard case let .prefixFailed(url, result) = error else {
                return XCTFail("Expected prefixFailed, got \(error).")
            }
            XCTAssertEqual(url.path, "/opt/homebrew/bin/brew")
            XCTAssertEqual(result.exitCode, 2)
            XCTAssertEqual(result.trimmedStderr, "boom")
        }
    }
}

private struct FakeEnvironment: EnvironmentProviding {
    let values: [String: String]

    func value(for key: String) -> String? {
        values[key]
    }

    var processEnvironment: [String: String] {
        values
    }
}

private struct FakeFileChecker: FileChecking {
    let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}

private actor FakeBrewProcessRunner: BrewProcessRunning {
    struct Call: Equatable {
        let executablePath: String
        let arguments: [String]
        let environment: [String: String]
    }

    private let results: [String: CommandResult]
    private(set) var calls: [Call] = []

    init(results: [String: CommandResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        calls.append(
            Call(
                executablePath: executableURL.path,
                arguments: arguments,
                environment: environment
            )
        )

        let key = ([executableURL.path] + arguments).joined(separator: " ")
        return results[key] ?? CommandResult(stdout: "", stderr: "missing fake result for \(key)", exitCode: 127)
    }
}
