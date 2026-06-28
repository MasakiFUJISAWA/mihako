import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ExternalOpenRouter {
    private static var pendingURLs: [URL] = []
    private static var openWindow: (() -> Void)?

    static func configure(openWindow: @escaping () -> Void) {
        self.openWindow = openWindow
    }

    static func enqueue(_ urls: [URL]) {
        let destinations = urls.compactMap(destinationURL)
        let shodanaDestinations = destinations.filter { ExternalFileOpener.shouldOpenInShodana($0) }
        let externalDestinations = destinations.filter { !ExternalFileOpener.shouldOpenInShodana($0) }

        for url in externalDestinations {
            ExternalFileOpener.open(url) { error in
                guard let error else {
                    return
                }

                showExternalOpenError(error, for: url)
            }
        }

        guard !shodanaDestinations.isEmpty else {
            return
        }

        pendingURLs.append(contentsOf: shodanaDestinations)

        if let openWindow {
            for _ in shodanaDestinations {
                openWindow()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func consumeNextPendingURL() -> URL? {
        guard !pendingURLs.isEmpty else {
            return nil
        }

        return pendingURLs.removeFirst()
    }

    private static func destinationURL(from url: URL) -> URL? {
        if url.isFileURL {
            return url
        }

        guard ["shodana", "mihako"].contains(url.scheme?.lowercased() ?? ""),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = components.host?.lowercased()
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        guard host == "open" || path == "open" || host == nil else {
            return nil
        }

        let queryItems = components.queryItems ?? []

        if let rawURL = queryItems.first(where: { $0.name == "url" })?.value,
           let destination = URL(string: rawURL) {
            return destination
        }

        if let rawPath = queryItems.first(where: { $0.name == "path" })?.value {
            return URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        }

        return nil
    }

    private static func showExternalOpenError(_ error: Error, for url: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.string("Open File Failed")
        alert.informativeText = "\(url.lastPathComponent): \(error.localizedDescription)"
        alert.addButton(withTitle: L10n.string("OK"))
        alert.runModal()
    }
}

@MainActor
enum ExternalFileOpener {
    private static let shodanaBundleIdentifiers: Set<String> = [
        "dev.masakifujisawa.shodana",
        "dev.masakifujisawa.mihako"
    ]

    static func shouldOpenInShodana(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return true
        }

        guard let values = try? url.resourceValues(forKeys: [
            .isAliasFileKey,
            .isSymbolicLinkKey,
            .isDirectoryKey,
            .isPackageKey
        ]) else {
            return false
        }

        if values.isAliasFile == true || values.isSymbolicLink == true {
            return true
        }

        return values.isDirectory == true && values.isPackage != true
    }

    static func open(_ url: URL, completion: (@MainActor @Sendable (Error?) -> Void)? = nil) {
        let targetURL = url.standardizedFileURL

        if let preferredApplicationURL = preferredApplicationURL(for: targetURL) {
            NSWorkspace.shared.open(
                [targetURL],
                withApplicationAt: preferredApplicationURL,
                configuration: openConfiguration()
            ) { _, error in
                Task { @MainActor in
                    completion?(error)
                }
            }
            return
        }

        if let defaultApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: targetURL),
           !isShodanaApplication(defaultApplicationURL) {
            NSWorkspace.shared.open(targetURL, configuration: openConfiguration()) { _, error in
                Task { @MainActor in
                    completion?(error)
                }
            }
            return
        }

        if let applicationURL = alternateApplicationURL(for: targetURL) {
            NSWorkspace.shared.open(
                [targetURL],
                withApplicationAt: applicationURL,
                configuration: openConfiguration()
            ) { _, error in
                Task { @MainActor in
                    completion?(error)
                }
            }
            return
        }

        let error = NSError(
            domain: "dev.masakifujisawa.shodana.external-open",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: L10n.string("No external application is available for this file. Change the file's default application in Finder.")
            ]
        )
        completion?(error)
    }

    private static func preferredApplicationURL(for url: URL) -> URL? {
        guard isImageFile(url),
              let previewURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview"),
              !isShodanaApplication(previewURL) else {
            return nil
        }

        return previewURL
    }

    private static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    private static func alternateApplicationURL(for url: URL) -> URL? {
        applicationURLs(for: url)
            .first { !isShodanaApplication($0) }
    }

    private static func applicationURLs(for url: URL) -> [URL] {
        guard let unmanagedURLs = LSCopyApplicationURLsForURL(url as CFURL, .all) else {
            return []
        }

        let urls = unmanagedURLs.takeRetainedValue() as NSArray
        return urls.compactMap { $0 as? URL }
    }

    private static func isShodanaApplication(_ applicationURL: URL) -> Bool {
        if let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier,
           shodanaBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        return applicationURL.lastPathComponent.localizedCaseInsensitiveCompare("Shodana.app") == .orderedSame
            || applicationURL.lastPathComponent.localizedCaseInsensitiveCompare("Mihako.app") == .orderedSame
    }

    private static func openConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return configuration
    }
}
