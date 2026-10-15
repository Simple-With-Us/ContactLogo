import XCTest
@testable import ContactLogoKit

/// CL-164 / #103 — guards against the layered causes of "only ~25 of 15k
/// contacts" resurfacing: an artificial scan cap, concurrency regressions,
/// or dropping fetched identities before matching.
final class ScanCoverageRegressionTests: XCTestCase {

    func testNetworkMatchConcurrencyStaysAtSix() {
        XCTAssertEqual(
            ReviewSession.networkMatchConcurrencyLimit,
            6,
            "Raising this trips iOS per-process NSURLSession limits (CL-145 / CL-160)"
        )
    }

    @MainActor
    func testScanProcessesEveryContactReturnedByProvider() async {
        let count = 150
        let contacts = (0..<count).map { idx in
            ContactIdentity(
                id: "biz-\(idx)",
                displayName: "Vendor \(idx)",
                organization: "Vendor \(idx) LLC"
            )
        }
        struct BulkProvider: ContactsProvider {
            let contacts: [ContactIdentity]
            func requestAccess() async throws -> Bool { true }
            func fetchCandidates() async throws -> [ContactIdentity] { contacts }
            func fetchCandidate(id: String) async -> ContactIdentity? {
                contacts.first(where: { $0.id == id })
            }
            func imageData(forContactID id: String) async throws -> Data? { nil }
            func setImage(_ data: Data, forContactID id: String) async throws {}
            func removeImage(forContactID id: String) async throws {}
            func limitedAccessDiagnosis() async -> LimitedAccessState { .open }
            func visibleContactCount() async -> Int { contacts.count }
            func visibleContactCountIsExact() async -> Bool { true }
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ReviewQueueStore(directory: tempDir, currentChangeToken: { nil })
        let session = ReviewSession(queueStore: store)
        session.contactsProviderForTesting = BulkProvider(contacts: contacts)
        session.pipelineForTesting = MatchPipeline(sources: [], fetchImage: { _ in Data() })

        let completed = await session.scanAndMatch()
        XCTAssertTrue(completed)
        XCTAssertEqual(session.totalScannedCount, count)
        XCTAssertEqual(session.businessTargetsCount, count)
        XCTAssertEqual(session.results.count, count)
    }
}
