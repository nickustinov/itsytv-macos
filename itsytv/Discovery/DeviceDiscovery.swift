import Foundation
import Network

final class DeviceDiscovery {
    private var browser: NWBrowser?
    private var onChange: (([AppleTVDevice]) -> Void)?
    private var devices: [String: AppleTVDevice] = [:]

    func start(onChange: @escaping ([AppleTVDevice]) -> Void) {
        self.onChange = onChange

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: "_companion-link._tcp", domain: "local."),
            using: parameters
        )

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.devices.removeAll()
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint {
                    let metadata = result.metadata
                    var modelName: String?
                    if case let .bonjour(txtRecord) = metadata {
                        modelName = txtRecord["rpMd"]
                    }
                    let device = AppleTVDevice(
                        id: name,
                        name: name,
                        host: "",
                        port: 0,
                        modelName: modelName
                    )
                    self.devices[name] = device
                }
            }
            DispatchQueue.main.async {
                onChange(Array(self.devices.values))
            }
        }

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                print("Discovery failed: \(error)")
            default:
                break
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        devices.removeAll()
    }

    /// Resolve a discovered device endpoint to get its host and port.
    func resolve(_ device: AppleTVDevice, completion: @escaping (AppleTVDevice?) -> Void) {
        guard browser != nil else {
            completion(nil)
            return
        }

        let endpoint = NWEndpoint.service(
            name: device.name,
            type: "_companion-link._tcp",
            domain: "local.",
            interface: nil
        )

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = innerEndpoint {
                    let resolved = AppleTVDevice(
                        id: device.id,
                        name: device.name,
                        host: "\(host)",
                        port: port.rawValue,
                        modelName: device.modelName
                    )
                    DispatchQueue.main.async {
                        completion(resolved)
                    }
                    connection.cancel()
                } else {
                    DispatchQueue.main.async { completion(nil) }
                    connection.cancel()
                }
            case .failed:
                DispatchQueue.main.async { completion(nil) }
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }
}
