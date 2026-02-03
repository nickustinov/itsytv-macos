import XCTest
@testable import itsytv

final class CompanionConnectionTests: XCTestCase {

    // MARK: - Response dispatch

    func testDispatchResponseReturnsFalseForUnknownXID() {
        let conn = CompanionConnection()
        let message = OPACK.Value.dictionary([("_t", .int(3))])
        let found = conn.dispatchResponse(xid: 12345, message: message)
        XCTAssertFalse(found)
    }

    func testDispatchResponseCallsRegisteredHandler() {
        let conn = CompanionConnection()
        var receivedMessage: OPACK.Value?

        // sendRequest registers a handler and returns the XID used
        let xid = conn.sendRequest(
            eventName: "test",
            responseHandler: { message in
                receivedMessage = message
            }
        )

        let testMessage = OPACK.Value.dictionary([("result", .string("ok"))])
        let found = conn.dispatchResponse(xid: Int64(xid), message: testMessage)
        XCTAssertTrue(found)
        XCTAssertEqual(receivedMessage, testMessage)
    }

    func testDispatchResponseRemovesHandlerAfterCall() {
        let conn = CompanionConnection()

        let xid = conn.sendRequest(
            eventName: "test",
            responseHandler: { _ in }
        )

        // First dispatch should find and remove the handler
        let first = conn.dispatchResponse(xid: Int64(xid), message: .null)
        XCTAssertTrue(first)

        // Second dispatch for same XID should find nothing
        let second = conn.dispatchResponse(xid: Int64(xid), message: .null)
        XCTAssertFalse(second)
    }

    // MARK: - XID auto-increment

    func testSendRequestIncrementsXID() {
        let conn = CompanionConnection()
        let xid1 = conn.sendRequest(eventName: "a")
        let xid2 = conn.sendRequest(eventName: "b")
        XCTAssertEqual(xid2, xid1 + 1)
    }

    // MARK: - Encryption toggle

    func testEnableEncryptionSetsState() {
        let conn = CompanionConnection()
        let key = Data(repeating: 0xAA, count: 32)
        let crypto = CompanionCrypto(encryptKey: key, decryptKey: key)
        conn.enableEncryption(crypto)
        // No crash means the crypto state was accepted
    }

    // MARK: - Disconnect cleanup

    func testDisconnectClearsState() {
        let conn = CompanionConnection()

        let xid = conn.sendRequest(
            eventName: "test",
            responseHandler: { _ in
                XCTFail("Handler should not be called after disconnect")
            }
        )

        conn.disconnect()

        // After disconnect, pending handlers should be cleared
        let found = conn.dispatchResponse(xid: Int64(xid), message: .null)
        XCTAssertFalse(found)
    }
}
