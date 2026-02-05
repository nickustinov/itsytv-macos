// This file provides a small compile-time bridge to Sparkle.
// If Sparkle is added to the project via Swift Package Manager the
// `sparkle_checkForUpdates(feedURL:)` function will use Sparkle to
// check, download, and install updates. When Sparkle is not present
// this is a no-op so the app can still compile and use the fallback.

import Foundation

#if canImport(Sparkle)
import Sparkle

public func sparkle_checkForUpdates(feedURL: URL?) {
    if let url = feedURL {
        SUUpdater.shared()?.feedURL = url
    }
    SUUpdater.shared()?.checkForUpdates(nil)
}

#else
public func sparkle_checkForUpdates(feedURL: URL?) {
    // No-op when Sparkle isn't added as a dependency.
}
#endif
