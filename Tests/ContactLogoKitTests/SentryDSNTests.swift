import XCTest
@testable import ContactLogoKit

final class SentryDSNTests: XCTestCase {
    func testEmptyDSNStaysDark() {
        XCTAssertEqual(SentryDSN.outcome(for: nil), .absent)
        XCTAssertEqual(SentryDSN.outcome(for: ""), .absent)
        XCTAssertEqual(SentryDSN.outcome(for: "   \n"), .absent)
    }

    func testUnsubstitutedPlaceholderIsNotADsn() {
        XCTAssertEqual(SentryDSN.outcome(for: "$(SENTRY_DSN)"), .unresolvedPlaceholder)
        XCTAssertEqual(SentryDSN.outcome(for: "  $(SENTRY_DSN)  "), .unresolvedPlaceholder)
        XCTAssertEqual(SentryDSN.outcome(for: "${SENTRY_DSN}"), .unresolvedPlaceholder)
        XCTAssertEqual(
            SentryDSN.outcome(for: "https://$(SENTRY_DSN)@example.ingest.sentry.io/1"),
            .unresolvedPlaceholder
        )
    }

    func testMalformedValueIsNotReady() {
        XCTAssertEqual(SentryDSN.outcome(for: "not-a-dsn"), .malformed)
        XCTAssertEqual(SentryDSN.outcome(for: "https://example.ingest.sentry.io/1"), .malformed)
    }

    func testReadyDSNIsTrimmedAndDoesNotEchoAPlaceholder() {
        let dsn = "  https://public@example.ingest.sentry.io/1  "
        XCTAssertEqual(
            SentryDSN.outcome(for: dsn),
            .ready("https://public@example.ingest.sentry.io/1")
        )
    }
}
