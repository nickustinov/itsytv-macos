// This file provides a small compile-time bridge to Sparkle.
// If Sparkle is added to the project via Swift Package Manager the
// `sparkle_checkForUpdates(feedURL:)` function will use Sparkle to
// check, download, and install updates. When Sparkle is not present
// this is a no-op so the app can still compile and use the fallback.

import Foundation

#if canImport(Sparkle)
import Sparkle

public func sparkle_checkForUpdates(feedURL: URL?) {
    DispatchQueue.main.async {
        guard let updater = SUUpdater.shared() else {
            NSLog("SparkleBridge: SUUpdater.shared() returned nil; skipping update check.")
            return
        }
        if let url = feedURL {
            updater.feedURL = url
        }
        updater.checkForUpdates(nil)
    }
}

#else
public func sparkle_checkForUpdates(feedURL: URL?) {
    // No-op when Sparkle isn't added as a dependency.
}
#endif
