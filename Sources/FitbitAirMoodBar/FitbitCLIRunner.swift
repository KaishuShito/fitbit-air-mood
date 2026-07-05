import Foundation

struct FitbitDailySnapshot {
    let recordedAt: Date
    let payloadJSON: String

    init(recordedAt: Date = Date(), payloadJSON: String) {
        self.recordedAt = recordedAt
        self.payloadJSON = payloadJSON
    }

    var localDateString: String {
        Self.makeLocalDateFormatter().string(from: recordedAt)
    }

    var iso8601String: String {
        Self.makeISOFormatter().string(from: recordedAt)
    }

    var payloadBytes: Int {
        payloadJSON.lengthOfBytes(using: .utf8)
    }

    private static func makeLocalDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }
}

struct FitbitCLIRunner {
    func fetchTodayJSON(projectRoot: URL?) async throws -> FitbitDailySnapshot {
        try await Task.detached(priority: .utility) {
            guard let projectRoot else {
                throw FitbitCLIRunnerError.projectRootMissing
            }

            let executableURL = projectRoot
                .appendingPathComponent("dist", isDirectory: true)
                .appendingPathComponent("fitbit-air-cli")

            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                throw FitbitCLIRunnerError.executableMissing(executableURL.path)
            }

            let process = Process()
            process.executableURL = executableURL
            process.currentDirectoryURL = projectRoot
            process.arguments = ["today", "--json"]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw FitbitCLIRunnerError.launchFailed(error.localizedDescription)
            }

            process.waitUntilExit()

            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw FitbitCLIRunnerError.commandFailed(
                    status: process.terminationStatus,
                    message: errorOutput.isEmpty ? output : errorOutput
                )
            }

            guard !output.isEmpty else {
                throw FitbitCLIRunnerError.emptyOutput
            }

            return FitbitDailySnapshot(payloadJSON: output)
        }.value
    }
}

enum FitbitCLIRunnerError: LocalizedError {
    case projectRootMissing
    case executableMissing(String)
    case launchFailed(String)
    case commandFailed(status: Int32, message: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .projectRootMissing:
            return "Project root was not detected. Rebuild the app from the repository or set FITBIT_AIR_JOURNAL_PROJECT_DIR."
        case .executableMissing(let path):
            return "fitbit-air-cli is not executable at \(path). Install the optional CLI or set FITBIT_AIR_JOURNAL_PROJECT_DIR to a workspace that has dist/fitbit-air-cli."
        case .launchFailed(let message):
            return "Couldn't launch fitbit-air-cli: \(message)"
        case .commandFailed(let status, let message):
            if message.isEmpty {
                return "fitbit-air-cli exited with status \(status)."
            }
            return "fitbit-air-cli exited with status \(status): \(message)"
        case .emptyOutput:
            return "fitbit-air-cli returned an empty JSON payload."
        }
    }
}
