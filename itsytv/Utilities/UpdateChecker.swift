import AppKit
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "UpdateChecker")

// Optional Sparkle bridge is provided in `SparkleBridge.swift` when Sparkle is added via SPM.
enum UpdateChecker {

    // Test hooks
    public static var testingMode: Bool = false
    public static var sparkleAvailableOverride: Bool? = nil
    public static var lastUpdateMessage: String? = nil
    public static var sparkleChecker: (URL?) -> Void = { url in
        sparkle_checkForUpdates(feedURL: url)
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    // Public entry: performs an update check. If Sparkle is available (added via SPM),
    // Sparkle will be used and will handle download/installation. Otherwise falls back
    // to the existing behaviour (query GitHub API and open release page).
    static func check(session: URLSession = .shared, completion: (() -> Void)? = nil) {
        // If Sparkle is available at compile time, prefer it and point it at a hosted appcast.
        var sparkleAvailableCompile: Bool {
#if canImport(Sparkle)
            return true
#else
            return false
#endif
        }

        let sparkleAvailable = sparkleAvailableOverride ?? sparkleAvailableCompile
        if sparkleAvailable {
            let feedString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
            let appcastURL = feedString.flatMap { URL(string: $0) } ?? URL(string: "https://nickustinov.github.io/itsytv-macos/appcast.xml")
            sparkleChecker(appcastURL)
            completion?()
            return
        }

        // Fallback: simple GitHub release check and open the release page in browser.
        let url = URL(string: "https://api.github.com/repos/nickustinov/itsytv-macos/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    showAlert(message: "Failed to check for updates: \(error.localizedDescription)")
                    completion?()
                    return
                }
                guard let data else {
                    showAlert(message: "Failed to check for updates: no data received.")
                    completion?()
                    return
                }
                do {
                    let release = try JSONDecoder().decode(Release.self, from: data)
                    let remoteVersion = release.tag_name.hasPrefix("v")
                        ? String(release.tag_name.dropFirst())
                        : release.tag_name
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                    if isNewer(remoteVersion, than: currentVersion) {
                        showUpdateAvailable(version: release.tag_name, url: release.html_url)
                    } else {
                        showUpToDate(version: currentVersion)
                    }
                    completion?()
                } catch {
                    showAlert(message: "Failed to parse update info: \(error.localizedDescription)")
                    completion?()
                }
            }
        }.resume()
    }

    private static func isNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, currentParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    private static func showUpdateAvailable(version: String, url: String) {
        if testingMode {
            lastUpdateMessage = "available:\(version)"
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update available: \(version)"
        alert.informativeText = "A new version of itsytv is available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open downloads")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func showUpToDate(version: String) {
        if testingMode {
            lastUpdateMessage = "uptodate:\(version)"
            return
        }
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "itsytv \(version) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showAlert(message: String) {
        log.error("\(message)")
        if testingMode {
            lastUpdateMessage = "error:\(message)"
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
