import XCTest
#if canImport(Contacts)
import Contacts
@testable import ContactLogoKit
#endif

/// 2026-09-27 — scale guard for a large address book.
///
/// The owner has ~15,000 contacts, all shared with the app, and the iOS
/// scan never got past 22.  The cause was not permissions and not the
/// matching engine: `CNContactImageDataKey` was in the enumeration key
/// set, so the Contacts framework decoded the photo of every contact in
/// a single synchronous `enumerateContacts` pass.  Nothing ever read those
/// bytes — `identity(from:)` asks only `imageDataAvailable` — so the cost
/// bought nothing.  The run was killed by memory pressure or background
/// expiry before it could persist, and every relaunch restored the
/// previous queue, which is why the number was pinned at the same small
/// value rather than growing.
final class ContactEnumerationKeyTests: XCTestCase {

    #if canImport(Contacts)
    /// True when every one of `constants` is present in the scan's key set.
    /// Compared by descriptor equality rather than by string name, because
    /// the String constants are opaque once bridged to `CNKeyDescriptor`.
    private func enumerationIncludes(_ constants: String...) -> Bool {
        let present = CNContactsProvider.keys.map { "\($0)" }
        return constants.allSatisfy { present.contains($0) }
    }

    /// The regression itself.  Adding `imageData` back to this set is
    /// enough to stop a 15,000-contact book from ever producing a queue.
    func testEnumerationNeverFetchesImageBytes() {
        XCTAssertFalse(
            enumerationIncludes(CNContactImageDataKey),
            "CNContactImageDataKey must not be in the scan enumeration keys — the scan never reads the bytes and the cost OOMs a large address book"
        )
    }

    /// `imageDataAvailable` is what `identity(from:)` actually reads, so it
    /// must survive the removal above.
    func testEnumerationStillAsksWhetherAPhotoExists() {
        XCTAssertTrue(
            enumerationIncludes(CNContactImageDataAvailableKey),
            "the scan needs imageDataAvailable to flag 'replace-existing' and to protect people with headshots"
        )
    }

    /// Everything the classifier and the identity resolver read has to stay
    /// in the key set, or a large scan silently degrades.
    func testEnumerationKeepsEveryFieldTheScanReads() {
        XCTAssertTrue(
            enumerationIncludes(
                CNContactIdentifierKey,
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactOrganizationNameKey,
                CNContactEmailAddressesKey,
                CNContactUrlAddressesKey,
                CNContactPhoneNumbersKey
            ),
            "enumeration keys lost a field the scan reads"
        )
    }

    /// The per-contact read path is separate and still needs real bytes.
    func testPerContactReadPathStillFetchesImageData() throws {
        // `mutableContact(id:)` fetches CNContactImageDataKey on its own for
        // get/set/remove.  This pins that the bytes are gone only from the
        // bulk enumeration, not from the operations that need them.
        let source = try String(
            contentsOf: url(for: "Sources/ContactLogoKit/Contacts/ContactsProvider.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("let keys: [CNKeyDescriptor] = [CNContactImageDataKey as CNKeyDescriptor]"),
            "mutableContact(id:) must still request image data to read or write a contact photo"
        )
    }

    private func url(for relativePath: String) -> URL {
        // Tests run from the package root under SwiftPM.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ContactLogoKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent(relativePath)
    }
    #endif
}
