import XCTest
@testable import HomebrewLens

final class BrewProcessRunnerTests: XCTestCase {
    func testProcessRunnerInjectsEnvironment() async throws {
        let runner = BrewProcessRunner()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            environment: ["HOMEBREW_LENS_TEST_KEY": "expected-value"],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("HOMEBREW_LENS_TEST_KEY=expected-value"))
    }

    func testProcessRunnerReturnsNonzeroExitCode() async throws {
        let runner = BrewProcessRunner()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo failure-message >&2; exit 7"],
            environment: [:],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.trimmedStderr, "failure-message")
    }

    func testProcessRunnerDrainsLargeOutputWhileProcessRuns() async throws {
        let runner = BrewProcessRunner()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "print \"x\" x 300000"],
            environment: [:],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 300000)
    }

    func testProcessRunnerThrowsWhenCommandTimesOut() async throws {
        let runner = BrewProcessRunner()

        do {
            _ = try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                environment: [:],
                timeout: 0.1
            )
            XCTFail("Expected timeout error")
        } catch let error as BrewProcessError {
            XCTAssertEqual(error, .timedOut(executable: "/bin/sleep", timeout: 0.1))
        }
    }
}
