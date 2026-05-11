import Foundation

struct CommandResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStderr: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BrewDiscoveryResult: Equatable, Sendable {
    let brewPath: URL
    let brewPrefix: URL
    let attempts: [DiscoveryAttempt]
}

struct DiscoveryAttempt: Identifiable, Equatable, Sendable {
    let source: String
    let candidate: String
    let outcome: String

    var id: String {
        "\(source)|\(candidate)|\(outcome)"
    }
}

enum HomebrewState: Equatable {
    case idle
    case discovering
    case scanning(BrewDiscoveryResult, String)
    case scanned(BrewSnapshot)
    case missing([DiscoveryAttempt])
    case failed(String)
}

enum BrewDiscoveryError: LocalizedError, Equatable {
    case notFound([DiscoveryAttempt])
    case prefixFailed(URL, CommandResult)
    case invalidPrefixOutput(URL, String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Homebrew not found"
        case let .prefixFailed(brewPath, result):
            if result.trimmedStderr.isEmpty {
                "`\(brewPath.path) --prefix` exited with code \(result.exitCode)."
            } else {
                "`\(brewPath.path) --prefix` failed: \(result.trimmedStderr)"
            }
        case let .invalidPrefixOutput(brewPath, output):
            "`\(brewPath.path) --prefix` returned an invalid prefix: \(output)"
        }
    }
}

extension Array where Element == DiscoveryAttempt {
    var diagnosticsText: String {
        map { attempt in
            "\(attempt.source): \(attempt.candidate) -> \(attempt.outcome)"
        }
        .joined(separator: "\n")
    }
}
