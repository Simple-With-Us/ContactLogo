import XCTest
@testable import ContactLogoKit

/// 2026-10-18 — CL-205 / Sentry CONTACTLOGO-4 "App Hang Fully Blocked",
/// 2.8-3.6 s, six seconds after `app_start_time`.
///
/// Two defects, one symptom, and both are invisible to the scan-key tests
/// that already exist:
///
/// 1. **The enumeration ran on the main thread.**  `visibleContactCount()` and
///    `fetchCandidates()` contain no `await`, and `ReviewSession` is
///    `@MainActor`, so the `Task { }` at cold launch inherited MainActor
///    isolation and the synchronous `store.enumerateContacts` executed inline
///    on it.  `async` is not a thread hop: a function with no suspension
///    point runs where it was called.
///
/// 2. **The address book was enumerated repeatedly.**  Cold launch called
///    `visibleContactCount()` and then `visibleContactCountIsExact()` — each
///    its own full pass — and `limitedAccessDiagnosis()` can add another.
///    An earlier private snapshot helper was meant to prevent this, but every
///    public method called it independently, so the double pass survived and
///    the comment claiming otherwise was simply wrong.
///
/// These tests pin the *shape* of the code, because the failure is structural:
/// a correct-looking `async` method that executes on the caller's actor.
/// A behavioural test needs a real address book; a source pin does not.
final class LaunchEnumerationExecutorTests: XCTestCase {

    private func url(for path: String) -> URL {
        // Walk up from the built test bundle to the package root.
        var root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ContactLogoKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        root.appendPathComponent(path)
        return root
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: url(for: path), encoding: .utf8)
    }

    /// The regression itself: the synchronous Contacts call must be wrapped in
    /// an explicit executor hop, not merely marked `async`.
    func testCountEnumerationIsWrappedInAnExplicitOffMainHop() throws {
        let text = try source("Sources/ContactLogoKit/Contacts/ContactsProvider.swift")
        let body = try XCTUnwrap(Self.funcBody("public func visibleContactCountSnapshot() async -> VisibleContactCount", in: text))

        XCTAssertTrue(
            body.contains("offMain"),
            "visibleContactCountSnapshot() must run store.enumerateContacts inside offMain; an async function with no await executes on the caller's executor and ReviewSession is @MainActor"
        )
        XCTAssertTrue(
            body.contains("enumerateContacts"),
            "the snapshot is supposed to be the one identifier-only pass"
        )
    }

    /// The full scan has the same trap and the same fix.
    func testFullScanEnumerationIsWrappedInAnExplicitOffMainHop() throws {
        let text = try source("Sources/ContactLogoKit/Contacts/ContactsProvider.swift")
        let body = try XCTUnwrap(Self.funcBody("public func fetchCandidates() async throws -> [ContactIdentity]", in: text))

        XCTAssertTrue(
            body.contains("offMainThrowing"),
            "fetchCandidates() must hop off the caller's executor before enumerating, or the scan blocks the main thread exactly like the cold-launch count did"
        )
    }

    /// `CNContactFetchRequest` is not `Sendable` and this package builds in
    /// Swift 6 language mode, so the request must be constructed inside the
    /// detached task rather than captured into it.
    func testFetchRequestIsBuiltInsideTheHopNotCapturedIntoIt() throws {
        let text = try source("Sources/ContactLogoKit/Contacts/ContactsProvider.swift")
        let body = try XCTUnwrap(Self.funcBody("public func visibleContactCountSnapshot() async -> VisibleContactCount", in: text))

        let hop = try XCTUnwrap(body.range(of: "offMain {"), "expected an offMain hop")
        let request = try XCTUnwrap(body.range(of: "CNContactFetchRequest(keysToFetch: keys)"))
        XCTAssertGreaterThan(
            request.lowerBound,
            hop.upperBound,
            "CNContactFetchRequest is not Sendable — build it inside the detached task, not before the hop"
        )
    }

    /// One pass for both numbers.  Asking for the count and the exactness
    /// flag separately costs a second full enumeration.
    func testLaunchAndScanPathsTakeBothValuesFromOneSnapshot() throws {
        let text = try source("Sources/ContactLogoKit/Store/ReviewSession.swift")

        XCTAssertTrue(
            text.contains("visibleContactCountSnapshot()"),
            "ReviewSession should read count and exactness from one enumeration"
        )
        XCTAssertFalse(
            text.contains("await provider.visibleContactCountIsExact()"),
            "visibleContactCountIsExact() re-enumerates the whole address book and must not be called alongside visibleContactCount(); use visibleContactCountSnapshot()"
        )
    }

    /// The protocol default has to keep honouring a stubbed
    /// `visibleContactCount()`.  Test doubles — and any other conformer —
    /// implement the two single-value methods, so a default snapshot that
    /// ignored them silently reported 0 (this caught
    /// `AffiliatedContactTests.testFullAccessSmallDatabaseIsNotFlaggedAsALimitedGrant`).
    func testDefaultSnapshotDerivesFromTheSingleValueMethods() async {
        final class CountOnly: ContactsProvider {
            func fetchCandidates() async throws -> [ContactIdentity] { [] }
            func imageData(forContactID id: String) async throws -> Data? { nil }
            func setImage(_ data: Data, forContactID id: String) async throws {}
            func removeImage(forContactID id: String) async throws {}
            func visibleContactCount() async -> Int { 22 }
            func visibleContactCountIsExact() async -> Bool { false }
        }

        let snap = await CountOnly().visibleContactCountSnapshot()
        XCTAssertEqual(snap.count, 22, "the default snapshot must honour a conformer's visibleContactCount()")
        XCTAssertFalse(snap.isExact, "the default snapshot must honour visibleContactCountIsExact()")
    }

    /// `visibleContactCountIsExact()` still reports the same thing it always
    /// did, and it is false exactly when the enumeration ceiling fired.
    func testExactnessIsFalseOnlyWhenTheCeilingFired() {
        let exact = VisibleContactCount(count: 10, isExact: true)
        let truncated = VisibleContactCount(count: CNContactsProvider.visibilityBound, isExact: false)

        XCTAssertTrue(exact.isExact)
        XCTAssertFalse(truncated.isExact)
        XCTAssertEqual(truncated.count, CNContactsProvider.visibilityBound)
    }

    // MARK: - Helpers

    /// Extracts a function body by brace-matching from its declaration.
    private static func funcBody(_ signature: String, in text: String) -> String? {
        // `.backwards`: the protocol's default extension and the concrete
        // override can share a signature, and the override is the later one.
        guard let sig = text.range(of: signature, options: .backwards) else { return nil }
        let rest = text[sig.upperBound...]
        guard let open = rest.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < rest.endIndex {
            if rest[index] == "{" { depth += 1 }
            if rest[index] == "}" {
                depth -= 1
                if depth == 0 { return String(rest[open...index]) }
            }
            index = rest.index(after: index)
        }
        return nil
    }
}