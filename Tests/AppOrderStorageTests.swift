import XCTest
@testable import itsytv

final class AppOrderStorageTests: XCTestCase {

    private typealias App = (bundleID: String, name: String)

    private let builtIn: Set<String> = ["com.apple.TVSettings", "com.apple.TVMusic"]

    private func makeApps(_ pairs: [(String, String)]) -> [App] {
        pairs.map { (bundleID: $0.0, name: $0.1) }
    }

    // MARK: - Default order (no saved data)

    func testDefaultOrderPutsThirdPartyBeforeApple() {
        let apps = makeApps([
            ("com.apple.TVMusic", "Music"),
            ("com.third.Zebra", "Zebra"),
            ("com.apple.TVSettings", "Settings"),
            ("com.third.Alpha", "Alpha"),
        ])

        let result = AppOrderStorage.applyOrder(savedOrder: nil, apps: apps, builtInBundleIDs: builtIn)
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, [
            "com.third.Alpha",
            "com.third.Zebra",
            "com.apple.TVMusic",
            "com.apple.TVSettings",
        ])
    }

    func testDefaultOrderWithEmptySavedArray() {
        let apps = makeApps([
            ("com.third.Beta", "Beta"),
            ("com.apple.TVSettings", "Settings"),
        ])

        let result = AppOrderStorage.applyOrder(savedOrder: [], apps: apps, builtInBundleIDs: builtIn)
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, ["com.third.Beta", "com.apple.TVSettings"])
    }

    // MARK: - Saved order applied

    func testSavedOrderIsPreserved() {
        let apps = makeApps([
            ("com.a", "A"),
            ("com.b", "B"),
            ("com.c", "C"),
        ])

        let result = AppOrderStorage.applyOrder(savedOrder: ["com.c", "com.a", "com.b"], apps: apps, builtInBundleIDs: [])
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, ["com.c", "com.a", "com.b"])
    }

    // MARK: - Prune uninstalled

    func testUninstalledAppsArePruned() {
        let apps = makeApps([
            ("com.a", "A"),
            ("com.c", "C"),
        ])

        let result = AppOrderStorage.applyOrder(savedOrder: ["com.a", "com.b", "com.c"], apps: apps, builtInBundleIDs: [])
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, ["com.a", "com.c"])
    }

    // MARK: - Append new apps

    func testNewAppsAppendedAlphabetically() {
        let apps = makeApps([
            ("com.a", "A"),
            ("com.b", "B"),
            ("com.new.z", "Zeta"),
            ("com.new.m", "Mike"),
        ])

        let result = AppOrderStorage.applyOrder(savedOrder: ["com.b", "com.a"], apps: apps, builtInBundleIDs: [])
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, ["com.b", "com.a", "com.new.m", "com.new.z"])
    }

    // MARK: - Combined prune + append

    func testPruneAndAppendTogether() {
        let apps = makeApps([
            ("com.a", "A"),
            ("com.c", "C"),
            ("com.new", "New"),
        ])

        let result = AppOrderStorage.applyOrder(
            savedOrder: ["com.removed", "com.a", "com.c"],
            apps: apps,
            builtInBundleIDs: []
        )
        let ids = result.map(\.bundleID)

        XCTAssertEqual(ids, ["com.a", "com.c", "com.new"])
    }

    // MARK: - Empty apps list

    func testEmptyAppsReturnsEmpty() {
        let result = AppOrderStorage.applyOrder(savedOrder: ["com.a"], apps: [], builtInBundleIDs: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyAppsWithNilSavedOrder() {
        let result = AppOrderStorage.applyOrder(savedOrder: nil, apps: [], builtInBundleIDs: [])
        XCTAssertTrue(result.isEmpty)
    }
}
