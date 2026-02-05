import XCTest
@testable import itsytv

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // no-op
    }
}

final class UpdateCheckerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UpdateChecker.testingMode = false
        UpdateChecker.sparkleAvailableOverride = nil
        UpdateChecker.lastUpdateMessage = nil
        UpdateChecker.sparkleChecker = { url in sparkle_checkForUpdates(feedURL: url) }
        super.tearDown()
    }

    func testFallbackDetectsUpdate() throws {
        UpdateChecker.testingMode = true
        UpdateChecker.sparkleAvailableOverride = false

        // Prepare mock release JSON with newer version (single object as returned by /releases/latest)
        let json = "{\"tag_name\": \"v9.9.9\", \"html_url\": \"https://example.com\"}".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("/releases") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let exp = expectation(description: "update check")
        UpdateChecker.check(session: session) {
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(UpdateChecker.lastUpdateMessage?.hasPrefix("available:"), true)
    }

    func testSparklePathInvokesSparkleChecker() throws {
        UpdateChecker.testingMode = true
        UpdateChecker.sparkleAvailableOverride = true

        let exp = expectation(description: "sparkle called")
        UpdateChecker.sparkleChecker = { url in
            UpdateChecker.lastUpdateMessage = "sparkle:\(url?.absoluteString ?? "nil")"
            exp.fulfill()
        }

        UpdateChecker.check() {
            // completion called after invoking sparkleChecker
        }

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(UpdateChecker.lastUpdateMessage?.hasPrefix("sparkle:"), true)
    }
}
