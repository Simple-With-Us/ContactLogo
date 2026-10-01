import XCTest
@testable import ContactLogoKit

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
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

    override func stopLoading() {}
}

final class LogoDevSourceTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDomainCandidatesWithEmptyTokenThrowsMisconfigured() async {
        let source = LogoDevSource(token: "")
        do {
            _ = try await source.candidates(forDomain: "apple.com")
            XCTFail("Expected LogoSourceError.misconfigured")
        } catch let LogoSourceError.misconfigured(reason) {
            XCTAssertTrue(reason.contains("Logo.dev token missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDomainCandidatesWithTokenEmitsCandidate() async throws {
        let source = LogoDevSource(token: "pk_test_123")
        let candidates = try await source.candidates(forDomain: "stripe.com")
        XCTAssertEqual(candidates.count, 1)
        guard let first = candidates.first else {
            XCTFail("Expected a candidate")
            return
        }
        XCTAssertEqual(first.source, .logodev)
        XCTAssertEqual(first.imageURL.host, "img.logo.dev")
        XCTAssertEqual(first.imageURL.path, "/stripe.com")
        XCTAssertTrue(first.imageURL.query?.contains("token=pk_test_123") == true)
        XCTAssertEqual(first.assetType, "icon")
        XCTAssertEqual(first.pixelWidth, 512)
        XCTAssertEqual(first.pixelHeight, 512)
        XCTAssertEqual(first.hasAlpha, true)
    }

    func testSearchByNameWithEmptyTokenThrowsMisconfigured() async {
        let source = LogoDevSource(token: "")
        do {
            _ = try await source.candidates(forBrandName: "Stripe")
            XCTFail("Expected LogoSourceError.misconfigured")
        } catch let LogoSourceError.misconfigured(reason) {
            XCTAssertTrue(reason.contains("Logo.dev token missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchByNameWithMockSessionParsesResults() async throws {
        let sampleJSON = """
        [
            {
                "name": "Stripe",
                "domain": "stripe.com"
            }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "api.logo.dev")
            XCTAssertEqual(request.url?.path, "/search")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pk_test_123")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, sampleJSON)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let source = LogoDevSource(token: "pk_test_123", session: session)
        let candidates = try await source.candidates(forBrandName: "Stripe")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.source, .logodev)
        XCTAssertEqual(candidates.first?.imageURL.path, "/stripe.com")
    }

    func testCandidateRankerScoresLogoDev() {
        let candidate = LogoCandidate(
            source: .logodev,
            imageURL: URL(string: "https://img.logo.dev/apple.com?token=pk_test")!,
            pixelWidth: 512,
            pixelHeight: 512,
            assetType: "icon",
            altText: "Apple",
            hasAlpha: true
        )
        // 100 (square) + 40 (icon) + 20 (logodev) + 12 (alpha) + 5 (>=256) = 177
        XCTAssertEqual(CandidateRanker.score(candidate), 177)
    }
}
