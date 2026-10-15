import XCTest
@testable import ContactLogoKit

/// CL-189 — a scan has to leave a counts-only report even when Sentry is dark.
final class ScanTelemetryTests: XCTestCase {
    private struct FixtureProvider: ContactsProvider {
        var contacts: [ContactIdentity]
        var state: LimitedAccessState = .open
        var allowAccess = true
        var explode = false

        func requestAccess() async throws -> Bool { allowAccess }
        func fetchCandidates() async throws -> [ContactIdentity] {
            if explode {
                struct Boom: Error {}
                throw Boom()
            }
            return contacts
        }
        func imageData(forContactID id: String) async throws -> Data? { nil }
        func setImage(_ data: Data, forContactID id: String) async throws {}
        func removeImage(forContactID id: String) async throws {}
        func limitedAccessDiagnosis() async -> LimitedAccessState { state }
        func visibleContactCount() async -> Int { contacts.count }
    }

    func testAuthorizationLabelsAreStable() {
        XCTAssertEqual(LimitedAccessState.open.telemetryLabel, "open")
        XCTAssertEqual(LimitedAccessState.definite.telemetryLabel, "limited")
        XCTAssertEqual(LimitedAccessState.heuristic(22).telemetryLabel, "heuristic")
        XCTAssertEqual(LimitedAccessState.fullAccessSmallDatabase(22).telemetryLabel, "full_access_small_database")
        XCTAssertEqual(LimitedAccessState.denied.telemetryLabel, "denied")
        XCTAssertEqual(LimitedAccessState.restricted.telemetryLabel, "restricted")
    }

    @MainActor
    private func session(provider: FixtureProvider) -> ReviewSession {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ReviewQueueStore(directory: tempDir, currentChangeToken: { nil })
        let session = ReviewSession(queueStore: store)
        session.contactsProviderForTesting = provider
        session.pipelineForTesting = MatchPipeline(sources: [], fetchImage: { _ in Data() })
        return session
    }

    @MainActor
    func testScanReportCountsFetchedClassifiedAndDropped() async {
        let contacts = [
            ContactIdentity(id: "biz", displayName: "Walgreens", givenName: "Walgreens"),
            ContactIdentity(id: "person", displayName: "Maya Chen", givenName: "Maya", familyName: "Chen"),
            ContactIdentity(id: "generic", displayName: "Hospital"),
        ]
        let session = session(provider: FixtureProvider(contacts: contacts, state: .definite))
        let recorded = ReportBox()
        session.recordScanTelemetry = { recorded.reports.append($0) }

        _ = await session.scanAndMatch()

        let report = try XCTUnwrap(session.lastScanReport)
        XCTAssertEqual(report.fetched, 3)
        XCTAssertEqual(report.classified, 1, "only the lone firm name enters matching")
        XCTAssertEqual(report.dropped, 2)
        XCTAssertEqual(report.authorization, "limited")
        XCTAssertGreaterThanOrEqual(report.elapsedSeconds, 0)
        XCTAssertLessThan(report.elapsedSeconds, 30)
        XCTAssertEqual(recorded.reports, [report])
    }

    @MainActor
    func testDeniedAccessStillEmitsAReport() async {
        let session = session(provider: FixtureProvider(contacts: [], allowAccess: false))
        _ = await session.scanAndMatch()
        let report = try XCTUnwrap(session.lastScanReport)
        XCTAssertEqual(report.fetched, 0)
        XCTAssertEqual(report.classified, 0)
        XCTAssertEqual(report.dropped, 0)
        XCTAssertEqual(report.authorization, "access_denied")
        XCTAssertGreaterThanOrEqual(report.elapsedSeconds, 0)
    }

    @MainActor
    func testThrownFetchStillEmitsAReport() async {
        let session = session(provider: FixtureProvider(contacts: [], state: .denied, explode: true))
        let completed = await session.scanAndMatch()
        XCTAssertFalse(completed)
        let report = try XCTUnwrap(session.lastScanReport)
        XCTAssertEqual(report.fetched, 0)
        XCTAssertEqual(report.classified, 0)
        XCTAssertEqual(report.dropped, 0)
        XCTAssertEqual(report.authorization, "denied")
    }
}

private final class ReportBox: @unchecked Sendable {
    var reports: [ScanRunReport] = []
}
