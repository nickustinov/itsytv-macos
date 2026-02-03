import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "Discovery")

/// Discovers Apple TV devices via Bonjour _companion-link._tcp and resolves their TXT records
/// to filter by device type (rpFl flags).
final class DeviceDiscovery: NSObject {
    private var browser: NetServiceBrowser?
    private var onChange: (([AppleTVDevice]) -> Void)?
    private var services: [String: NetService] = [:]
    private var devices: [String: AppleTVDevice] = [:]

    func start(onChange: @escaping ([AppleTVDevice]) -> Void) {
        self.onChange = onChange

        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_companion-link._tcp.", inDomain: "local.")
        self.browser = browser
    }

    func refresh() {
        // Re-resolve all known services to pick up address changes
        for service in services.values {
            service.resolve(withTimeout: 5.0)
        }
        // Restart the browse to discover new devices (keeps existing ones)
        browser?.stop()
        let newBrowser = NetServiceBrowser()
        newBrowser.delegate = self
        newBrowser.searchForServices(ofType: "_companion-link._tcp.", inDomain: "local.")
        self.browser = newBrowser
    }

    func stop() {
        browser?.stop()
        browser = nil
        services.removeAll()
        devices.removeAll()
    }

    fileprivate func notifyChange() {
        let current = Array(devices.values)
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(current)
        }
    }

    fileprivate func processResolved(_ service: NetService) {
        guard let txtData = service.txtRecordData() else {
            log.info("No TXT data for \(service.name)")
            return
        }

        let txtDict = NetService.dictionary(fromTXTRecord: txtData)
        var props: [String: String] = [:]
        for (key, value) in txtDict {
            if let str = String(data: value, encoding: .utf8) {
                props[key] = str
            }
        }

        let modelName = props["rpMd"]
        let flagStr = props["rpFl"] ?? "0x0"
        let flags = UInt64(flagStr.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0

        log.info("Resolved: \(service.name) model=\(modelName ?? "nil") flags=0x\(String(flags, radix: 16))")

        // Only show devices that support PIN pairing (Apple TVs).
        // HomePods, Macs, iPads etc. don't have the 0x4000 flag.
        guard flags & 0x4000 != 0 else {
            devices.removeValue(forKey: service.name)
            notifyChange()
            return
        }

        let device = AppleTVDevice(
            id: service.name,
            name: service.name,
            host: service.hostName ?? "",
            port: UInt16(service.port),
            modelName: modelName
        )
        devices[service.name] = device
        notifyChange()
    }
}

extension DeviceDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        log.info("Found service: \(service.name)")
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        log.info("Removed service: \(service.name)")
        services.removeValue(forKey: service.name)
        devices.removeValue(forKey: service.name)
        notifyChange()
    }
}

extension DeviceDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        processResolved(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        log.warning("Failed to resolve \(sender.name): \(errorDict)")
    }
}
