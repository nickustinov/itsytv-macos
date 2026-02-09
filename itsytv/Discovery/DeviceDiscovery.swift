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
    /// Maps Bonjour service name → device unique ID (rpBA) for removal lookup.
    private var serviceToDeviceID: [String: String] = [:]

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
        serviceToDeviceID.removeAll()
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

        // Use rpBA (Bluetooth address) as a hardware-unique device ID.
        // Falls back to service name if rpBA is absent.
        let uniqueID = Self.extractUniqueID(props: props, serviceName: service.name)

        log.info("Resolved: \(service.name) id=\(uniqueID) model=\(modelName ?? "nil") flags=0x\(String(flags, radix: 16))")

        // Only show devices that support PIN pairing (Apple TVs).
        // HomePods, Macs, iPads etc. don't have the 0x4000 flag.
        guard flags & 0x4000 != 0 else {
            if let oldID = serviceToDeviceID.removeValue(forKey: service.name) {
                devices.removeValue(forKey: oldID)
            }
            notifyChange()
            return
        }

        serviceToDeviceID[service.name] = uniqueID

        // One-time migration: move credentials, hotkeys, and panel position
        // from the old service-name key to the new rpBA key.
        if uniqueID != service.name {
            Self.migrateDeviceData(from: service.name, to: uniqueID)
        }

        let device = AppleTVDevice(
            id: uniqueID,
            name: service.name,
            host: service.hostName ?? "",
            port: UInt16(service.port),
            modelName: modelName
        )
        devices[uniqueID] = device
        notifyChange()
    }

    /// Extracts a unique device ID from TXT record properties.
    /// Uses `rpBA` (Bluetooth address) when available, falls back to service name.
    static func extractUniqueID(props: [String: String], serviceName: String) -> String {
        if let rpBA = props["rpBA"], !rpBA.isEmpty {
            return rpBA
        }
        return serviceName
    }

    /// Migrates credentials, hotkeys, and panel position from an old device ID to a new one.
    /// Safe to call multiple times — skips if data already exists under the new ID.
    static func migrateDeviceData(from oldID: String, to newID: String) {
        // Credentials
        if KeychainStorage.load(for: newID) == nil,
           let creds = KeychainStorage.load(for: oldID) {
            do {
                try KeychainStorage.save(credentials: creds, for: newID)
                KeychainStorage.delete(for: oldID)
                log.info("Migrated credentials from '\(oldID)' to '\(newID)'")
            } catch {
                log.error("Failed to migrate credentials: \(error.localizedDescription)")
            }
        }

        // Hotkeys
        if HotkeyStorage.load(deviceID: newID) == nil,
           let keys = HotkeyStorage.load(deviceID: oldID) {
            HotkeyStorage.save(deviceID: newID, keys: keys)
            HotkeyStorage.save(deviceID: oldID, keys: nil)
            log.info("Migrated hotkey from '\(oldID)' to '\(newID)'")
        }

        // Panel position
        let oldKey = "panelOrigin_\(oldID)"
        let newKey = "panelOrigin_\(newID)"
        if UserDefaults.standard.dictionary(forKey: newKey) == nil,
           let pos = UserDefaults.standard.dictionary(forKey: oldKey) {
            UserDefaults.standard.set(pos, forKey: newKey)
            UserDefaults.standard.removeObject(forKey: oldKey)
            log.info("Migrated panel position from '\(oldID)' to '\(newID)'")
        }
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
        if let deviceID = serviceToDeviceID.removeValue(forKey: service.name) {
            devices.removeValue(forKey: deviceID)
        }
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
