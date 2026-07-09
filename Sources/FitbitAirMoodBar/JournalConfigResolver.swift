import Foundation

struct JournalResolution {
    let projectRoot: URL?
    let journalDirectory: URL?
    let databaseURL: URL
}

struct JournalConfigResolver {
    private let defaults = UserDefaults.standard
    private let overrideKey = "journalDirectoryOverridePath"

    func resolve() -> JournalResolution {
        let databaseURL = appSupportDirectory()
            .appendingPathComponent("FitbitAirMoodBar", isDirectory: true)
            .appendingPathComponent("checkins.sqlite3")

        // The journal override only replaces the journal folder; the project
        // root is still needed for the Fitbit CLI, so always detect it.
        let projectRoot = detectProjectRoot()

        if let overridePath = defaults.string(forKey: overrideKey), !overridePath.isEmpty {
            return JournalResolution(
                projectRoot: projectRoot,
                journalDirectory: URL(fileURLWithPath: overridePath, isDirectory: true),
                databaseURL: databaseURL
            )
        }

        let journalDirectory = projectRoot.flatMap(loadJournalDirectory(projectRoot:))
        return JournalResolution(
            projectRoot: projectRoot,
            journalDirectory: journalDirectory,
            databaseURL: databaseURL
        )
    }

    func storeOverride(_ url: URL) {
        defaults.set(url.path, forKey: overrideKey)
    }

    func clearOverride() {
        defaults.removeObject(forKey: overrideKey)
    }

    private func detectProjectRoot() -> URL? {
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let projectDir = env["FITBIT_AIR_JOURNAL_PROJECT_DIR"], !projectDir.isEmpty {
            candidates.append(URL(fileURLWithPath: projectDir, isDirectory: true))
        }

        if let embeddedRoot = embeddedProjectRoot() {
            candidates.append(embeddedRoot)
        }

        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        candidates.append(Bundle.main.bundleURL)

        for candidate in candidates {
            if let found = ascendForProjectRoot(startingAt: candidate) {
                return found
            }
        }

        return nil
    }

    private func embeddedProjectRoot() -> URL? {
        guard
            let url = Bundle.main.url(forResource: "project-root", withExtension: "txt"),
            let rawValue = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        let path = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func ascendForProjectRoot(startingAt start: URL) -> URL? {
        var current = start.standardizedFileURL
        let fileManager = FileManager.default

        while true {
            let envPath = current.appendingPathComponent(".env").path
            let goModPath = current.appendingPathComponent("go.mod").path
            let packagePath = current.appendingPathComponent("Package.swift").path
            if fileManager.fileExists(atPath: envPath),
               fileManager.fileExists(atPath: goModPath) || fileManager.fileExists(atPath: packagePath) {
                return current
            }

            // deletingLastPathComponent() on "/" yields "/..", so an equality
            // check alone never terminates; standardizing folds it back.
            if current.path == "/" {
                return nil
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private func loadJournalDirectory(projectRoot: URL) -> URL? {
        let envURL = projectRoot.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else {
            return nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard key == "JOURNAL_DIR" || key == "VAULT_JOURNAL_DIR" else {
                continue
            }

            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let expanded = (value as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        return nil
    }

    private func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
    }
}
