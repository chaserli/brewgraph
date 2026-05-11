import Foundation

protocol EnvironmentProviding: Sendable {
    func value(for key: String) -> String?
    var processEnvironment: [String: String] { get }
}

struct ProcessInfoEnvironment: EnvironmentProviding {
    func value(for key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    var processEnvironment: [String: String] {
        ProcessInfo.processInfo.environment
    }
}

protocol FileChecking: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

struct LocalFileChecker: FileChecking {
    func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

struct HomebrewController: Sendable {
    private let environment: any EnvironmentProviding
    private let fileChecker: any FileChecking
    private let processRunner: any BrewProcessRunning

    init(
        environment: any EnvironmentProviding = ProcessInfoEnvironment(),
        fileChecker: any FileChecking = LocalFileChecker(),
        processRunner: any BrewProcessRunning = BrewProcessRunner()
    ) {
        self.environment = environment
        self.fileChecker = fileChecker
        self.processRunner = processRunner
    }

    func discoverHomebrew() async throws -> BrewDiscoveryResult {
        if environment.value(for: "BREWGRAPH_FORCE_MISSING_HOMEBREW") == "1" {
            throw BrewDiscoveryError.notFound([
                DiscoveryAttempt(
                    source: "BREWGRAPH_FORCE_MISSING_HOMEBREW",
                    candidate: "1",
                    outcome: "forced missing Homebrew for diagnostics QA"
                )
            ])
        }

        var attempts: [DiscoveryAttempt] = []

        let brewFile = environment.value(for: "HOMEBREW_BREW_FILE") ?? ""
        let brewFileResolution = try await resolveCandidate(
            source: "HOMEBREW_BREW_FILE",
            candidate: brewFile,
            previousAttempts: attempts
        )
        attempts = brewFileResolution.attempts
        if let result = brewFileResolution.result {
            return result
        }

        let prefix = environment.value(for: "HOMEBREW_PREFIX") ?? ""
        let prefixCandidate = prefix.isEmpty ? "" : URL(fileURLWithPath: prefix).appendingPathComponent("bin/brew").path
        let prefixResolution = try await resolveCandidate(
            source: "HOMEBREW_PREFIX/bin/brew",
            candidate: prefixCandidate,
            previousAttempts: attempts
        )
        attempts = prefixResolution.attempts
        if let result = prefixResolution.result {
            return result
        }

        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            let resolution = try await resolveCandidate(
                source: path,
                candidate: path,
                previousAttempts: attempts
            )
            attempts = resolution.attempts
            if let result = resolution.result {
                return result
            }
        }

        let shellResolution = try await resolveShellFallback(previousAttempts: attempts)
        attempts = shellResolution.attempts
        if let result = shellResolution.result {
            return result
        }

        throw BrewDiscoveryError.notFound(attempts)
    }

    private func resolveCandidate(
        source: String,
        candidate: String,
        previousAttempts: [DiscoveryAttempt]
    ) async throws -> CandidateResolution {
        var attempts = previousAttempts

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            attempts.append(DiscoveryAttempt(source: source, candidate: "(not set)", outcome: "not set"))
            return CandidateResolution(attempts: attempts, result: nil)
        }

        guard fileChecker.isExecutableFile(atPath: candidate) else {
            attempts.append(DiscoveryAttempt(source: source, candidate: candidate, outcome: "not executable"))
            return CandidateResolution(attempts: attempts, result: nil)
        }

        attempts.append(DiscoveryAttempt(source: source, candidate: candidate, outcome: "found"))
        let brewURL = URL(fileURLWithPath: candidate)
        let prefixURL = try await readPrefix(using: brewURL)
        return CandidateResolution(
            attempts: attempts,
            result: BrewDiscoveryResult(brewPath: brewURL, brewPrefix: prefixURL, attempts: attempts)
        )
    }

    private func resolveShellFallback(previousAttempts: [DiscoveryAttempt]) async throws -> CandidateResolution {
        var attempts = previousAttempts
        let fallbackSource = "/bin/zsh -lc 'command -v brew'"
        let shellURL = URL(fileURLWithPath: "/bin/zsh")

        do {
            let result = try await processRunner.run(
                executableURL: shellURL,
                arguments: ["-lc", "command -v brew"],
                environment: brewCommandEnvironment,
                timeout: 5
            )

            guard result.exitCode == 0, let candidate = firstOutputLine(in: result.stdout), !candidate.isEmpty else {
                let detail = result.trimmedStderr.isEmpty ? "not found" : result.trimmedStderr
                attempts.append(DiscoveryAttempt(source: fallbackSource, candidate: "command -v brew", outcome: detail))
                return CandidateResolution(attempts: attempts, result: nil)
            }

            return try await resolveCandidate(
                source: fallbackSource,
                candidate: candidate,
                previousAttempts: attempts
            )
        } catch {
            attempts.append(DiscoveryAttempt(source: fallbackSource, candidate: "command -v brew", outcome: error.localizedDescription))
            return CandidateResolution(attempts: attempts, result: nil)
        }
    }

    private func readPrefix(using brewURL: URL) async throws -> URL {
        let result = try await processRunner.run(
            executableURL: brewURL,
            arguments: ["--prefix"],
            environment: brewCommandEnvironment,
            timeout: 10
        )

        guard result.exitCode == 0 else {
            throw BrewDiscoveryError.prefixFailed(brewURL, result)
        }

        guard let prefix = firstOutputLine(in: result.stdout), !prefix.isEmpty else {
            throw BrewDiscoveryError.invalidPrefixOutput(brewURL, result.stdout)
        }

        return URL(fileURLWithPath: prefix)
    }

    private var brewCommandEnvironment: [String: String] {
        var values = environment.processEnvironment
        values["HOMEBREW_NO_ENV_HINTS"] = "1"
        values["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        values["LC_ALL"] = "C"
        return values
    }

    private func firstOutputLine(in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct CandidateResolution: Sendable {
    let attempts: [DiscoveryAttempt]
    let result: BrewDiscoveryResult?
}
