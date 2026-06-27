import Foundation

struct GitRepositoryInfo: Hashable {
    let rootURL: URL
    let branchName: String
    let upstreamName: String?
    let trackingStatus: GitTrackingStatus?
}

struct GitTrackingStatus: Hashable {
    let aheadCount: Int
    let behindCount: Int

    var indicator: String? {
        switch (aheadCount > 0, behindCount > 0) {
        case (true, true):
            return "↑↓"
        case (true, false):
            return "↑"
        case (false, true):
            return "↓"
        case (false, false):
            return nil
        }
    }
}

enum GitClientError: Error, LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

enum GitClient {
    static func repositoryInfo(for directoryURL: URL, refreshRemote: Bool = false) async -> GitRepositoryInfo? {
        guard directoryURL.isFileURL,
              let rootPath = try? await output(
                  arguments: ["rev-parse", "--show-toplevel"],
                  currentDirectoryURL: directoryURL
              ).trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let currentBranch = (try? await output(
            arguments: ["branch", "--show-current"],
            currentDirectoryURL: rootURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let shortHead = (try? await output(
            arguments: ["rev-parse", "--short", "HEAD"],
            currentDirectoryURL: rootURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let branchName = currentBranch
            ?? shortHead.map { "HEAD \($0)" }
            ?? "unknown"
        let upstreamName = (try? await output(
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            currentDirectoryURL: rootURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if refreshRemote, upstreamName != nil {
            _ = try? await run(
                arguments: ["fetch", "--quiet"],
                currentDirectoryURL: rootURL,
                includeOutputOnSuccess: false
            )
        }

        let trackingStatus = await trackingStatus(in: rootURL, upstreamName: upstreamName)

        return GitRepositoryInfo(
            rootURL: rootURL,
            branchName: branchName,
            upstreamName: upstreamName,
            trackingStatus: trackingStatus
        )
    }

    static func branchNames(in repositoryURL: URL) async throws -> [String] {
        try await output(
            arguments: ["branch", "--format=%(refname:short)"],
            currentDirectoryURL: repositoryURL
        )
        .split(separator: "\n")
        .map(String.init)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static func pull(in repositoryURL: URL) async throws -> String {
        try await run(arguments: ["pull"], currentDirectoryURL: repositoryURL)
    }

    static func push(in repositoryURL: URL) async throws -> String {
        try await run(arguments: ["push"], currentDirectoryURL: repositoryURL)
    }

    static func add(paths: [String], in repositoryURL: URL) async throws -> String {
        guard !paths.isEmpty else {
            return ""
        }

        return try await run(arguments: ["add", "--"] + paths, currentDirectoryURL: repositoryURL)
    }

    static func commit(paths: [String], message: String, in repositoryURL: URL) async throws -> String {
        _ = try await add(paths: paths, in: repositoryURL)
        return try await run(arguments: ["commit", "-m", message, "--"] + paths, currentDirectoryURL: repositoryURL)
    }

    static func checkout(branchName: String, in repositoryURL: URL) async throws -> String {
        try await run(arguments: ["checkout", branchName], currentDirectoryURL: repositoryURL)
    }

    static func merge(branchName: String, in repositoryURL: URL) async throws -> String {
        try await run(arguments: ["merge", branchName], currentDirectoryURL: repositoryURL)
    }

    private static func trackingStatus(in repositoryURL: URL, upstreamName: String?) async -> GitTrackingStatus? {
        guard upstreamName != nil,
              let output = try? await output(
                  arguments: ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
                  currentDirectoryURL: repositoryURL
              ) else {
            return nil
        }

        let parts = output.split(whereSeparator: \.isWhitespace)

        guard parts.count >= 2,
              let aheadCount = Int(parts[0]),
              let behindCount = Int(parts[1]) else {
            return nil
        }

        return GitTrackingStatus(aheadCount: aheadCount, behindCount: behindCount)
    }

    private static func output(arguments: [String], currentDirectoryURL: URL) async throws -> String {
        try await run(arguments: arguments, currentDirectoryURL: currentDirectoryURL, includeOutputOnSuccess: true)
    }

    private static func run(
        arguments: [String],
        currentDirectoryURL: URL,
        includeOutputOnSuccess: Bool = true
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["GIT_TERMINAL_PROMPT": "0"],
                uniquingKeysWith: { _, newValue in newValue }
            )

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [output, errorOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard process.terminationStatus == 0 else {
                throw GitClientError.commandFailed(
                    message.isEmpty
                        ? "git \(arguments.joined(separator: " ")) failed with status \(process.terminationStatus)."
                        : message
                )
            }

            return includeOutputOnSuccess ? message : ""
        }.value
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
