import Foundation

struct NowPlayingState {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var playbackRate: Float
    var timestamp: Date
    var artworkData: Data?

    var isPlaying: Bool { playbackRate > 0 }

    var currentPosition: TimeInterval {
        guard let elapsed = elapsedTime else { return 0 }
        return elapsed + Date().timeIntervalSince(timestamp) * Double(playbackRate)
    }
}
