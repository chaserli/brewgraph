import Foundation

protocol BrewProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult
}

enum BrewProcessError: LocalizedError, Equatable {
    case timedOut(executable: String, timeout: TimeInterval)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(executable, timeout):
            "`\(executable)` timed out after \(Int(timeout)) seconds."
        case let .launchFailed(message):
            message
        }
    }
}

struct BrewProcessRunner: BrewProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 30
    ) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runSynchronously(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
        }
        .value
    }

    private static func runSynchronously(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let managedProcess = ManagedProcess()
        let process = managedProcess.process
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        let timeoutWork = DispatchWorkItem {
            managedProcess.terminateForTimeout()
        }

        do {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWork
            )
            try process.run()
            process.waitUntilExit()
            timeoutWork.cancel()
        } catch {
            timeoutWork.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw BrewProcessError.launchFailed(error.localizedDescription)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        if managedProcess.timedOut {
            throw BrewProcessError.timedOut(executable: executableURL.path, timeout: timeout)
        }

        return CommandResult(
            stdout: stdoutBuffer.stringValue,
            stderr: stderrBuffer.stringValue,
            exitCode: process.terminationStatus
        )
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var stringValue: String {
        lock.lock()
        let value = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
        return value
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}

private final class ManagedProcess: @unchecked Sendable {
    let process = Process()

    private let lock = NSLock()
    private var didTimeOut = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }

    func terminateForTimeout() {
        lock.lock()
        didTimeOut = true
        lock.unlock()

        if process.isRunning {
            process.terminate()
        }
    }
}
