import Foundation

enum BuiltInApps {
    static let bundleIDs: Set<String> = [
        "com.apple.TVAppStore",
        "com.apple.Arcade",
        "com.apple.TVHomeSharing",
        "com.apple.TVMovies",
        "com.apple.TVMusic",
        "com.apple.TVPhotos",
        "com.apple.TVSearch",
        "com.apple.TVSettings",
        "com.apple.TVWatchList",
        "com.apple.TVShows",
        "com.apple.Sing",
        "com.apple.facetime",
        "com.apple.Fitness",
        "com.apple.podcasts",
    ]
}

enum AppOrderStorage {
    private static func key(for deviceID: String) -> String {
        "appOrder_\(deviceID)"
    }

    static func save(deviceID: String, order: [String]) {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: key(for: deviceID))
        }
    }

    static func load(deviceID: String) -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: key(for: deviceID)),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return order
    }

    /// Merge saved order with live installed apps: prune uninstalled, append new.
    /// Default order (no saved data): third-party alphabetically, then Apple built-in alphabetically.
    static func applyOrder(
        savedOrder: [String]?,
        apps: [(bundleID: String, name: String)],
        builtInBundleIDs: Set<String>
    ) -> [(bundleID: String, name: String)] {
        let appsByID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })

        guard let savedOrder, !savedOrder.isEmpty else {
            // Default: third-party alphabetical, then Apple alphabetical
            let thirdParty = apps
                .filter { !builtInBundleIDs.contains($0.bundleID) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let apple = apps
                .filter { builtInBundleIDs.contains($0.bundleID) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return thirdParty + apple
        }

        // Prune uninstalled apps from saved order
        var ordered: [(bundleID: String, name: String)] = []
        for id in savedOrder {
            if let app = appsByID[id] {
                ordered.append(app)
            }
        }

        // Append newly installed apps not in saved order
        let savedSet = Set(savedOrder)
        let newApps = apps
            .filter { !savedSet.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ordered.append(contentsOf: newApps)

        return ordered
    }
}
