import Foundation

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case pairing
    case connected
    case error(String)
}

struct AppleTVDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
    let modelName: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppleTVDevice, rhs: AppleTVDevice) -> Bool {
        lhs.id == rhs.id
    }
}
