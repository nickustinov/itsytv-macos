import AppKit
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "AppIcons")

/// Fetches tvOS app icons from the iTunes Lookup API by bundle ID and caches them in memory.
@Observable
final class AppIconLoader {
    /// SF Symbol fallbacks for Apple built-in tvOS apps that aren't on the App Store.
    static let builtInSymbols: [String: String] = [
        "com.apple.TVAppStore": "bag",
        "com.apple.Arcade": "gamecontroller.fill",
        "com.apple.TVHomeSharing": "rectangle.inset.filled.on.rectangle",
        "com.apple.TVMovies": "film",
        "com.apple.TVMusic": "music.note",
        "com.apple.TVPhotos": "photo.fill",
        "com.apple.TVSearch": "magnifyingglass",
        "com.apple.TVSettings": "gearshape.fill",
        "com.apple.TVWatchList": "tv.fill",
        "com.apple.TVShows": "tv",
        "com.apple.Sing": "music.mic",
        "com.apple.facetime": "video.fill",
        "com.apple.Fitness": "figure.run",
        "com.apple.podcasts": "antenna.radiowaves.left.and.right",
    ]

    private(set) var icons: [String: NSImage] = [:]
    private var pending: Set<String> = []

    func loadIcons(for bundleIDs: [String]) {
        for bundleID in bundleIDs {
            guard icons[bundleID] == nil, !pending.contains(bundleID) else { continue }
            guard Self.builtInSymbols[bundleID] == nil else { continue }
            pending.insert(bundleID)
            fetchIcon(bundleID: bundleID)
        }
    }

    private func fetchIcon(bundleID: String) {
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&entity=tvSoftware&country=\(country)&limit=1") else {
            pending.remove(bundleID)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            defer {
                DispatchQueue.main.async { self?.pending.remove(bundleID) }
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let iconURLString = first["artworkUrl512"] as? String
                      ?? first["artworkUrl100"] as? String,
                  let iconURL = URL(string: iconURLString) else {
                return
            }

            // Download the actual image
            guard let imageData = try? Data(contentsOf: iconURL),
                  let image = NSImage(data: imageData) else {
                log.debug("Failed to download icon for \(bundleID)")
                return
            }

            DispatchQueue.main.async {
                self?.icons[bundleID] = image
            }
        }.resume()
    }
}
