import XCTest
@testable import ContactLogoKit

/// 2026-09-27 — regression cover for the "business contacts that are
/// businesses, not people" class of complaint.
///
/// The owner reported the iOS scan returning a tiny queue from a book of
/// 1,000+ business contacts.  A measured sweep of realistic business
/// contact shapes showed the *classifier* was in fact healthy — the
/// address book was simply small on the device.  These tests pin that
/// result so a future change that starts reclassifying businesses as
/// people fails loudly here instead of shipping as another mystery
/// "only 22 contacts" report.
///
/// The two shapes that did NOT survive (below) were fixed as part of the
/// same change; they are asserted as survivors now.
final class BusinessContactShapeTests: XCTestCase {

    private let pipeline = MatchPipeline(sources: [], fetchImage: { _ in Data() })

    private func identity(
        _ display: String,
        given: String = "", family: String = "", org: String = "",
        emails: [String] = [], urls: [String] = []
    ) -> ContactIdentity {
        ContactIdentity(
            id: display + org,
            displayName: display,
            givenName: given.isEmpty ? nil : given,
            familyName: family.isEmpty ? nil : family,
            organization: org.isEmpty ? nil : org,
            emailDomains: emails,
            websiteHosts: urls,
            phoneNumbers: [],
            hasImage: false
        )
    }

    /// A business contact is "survivable" when it either classifies as a
    /// business card, or it resolves an affiliation (which puts it in the
    /// opt-in Review tier rather than dropping it).  Only a contact that
    /// fails both vanishes from the queue entirely.
    private func assertSurvives(
        _ c: ContactIdentity,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let klass = pipeline.classify(c)
        if klass == .nonBrand {
            XCTFail("\(label): classified non-brand, so it is dropped outright", file: file, line: line)
            return
        }
        if klass == .person && pipeline.affiliation(for: c) == nil {
            XCTFail("\(label): classified person with no affiliation, so it is dropped outright", file: file, line: line)
        }
    }

    /// The measured baseline: organization-only business contacts — the
    /// shape the bulk of a real address book takes — classify directly as
    /// business cards and are not treated as people.
    func testOrganizationOnlyContactsAreBusinessCards() {
        let cases: [(String, ContactIdentity)] = [
            ("multiword trade", identity("", org: "Gulf Coast Roofing")),
            ("generic noun tail", identity("", org: "Sunrise Bakery")),
            ("single token catalog brand", identity("", org: "Costco")),
            ("org collides with role words", identity("", org: "Home Depot")),
            ("org collides with place words", identity("", org: "Riverside Center")),
        ]
        for (label, c) in cases {
            XCTAssertEqual(pipeline.classify(c), .businessCard, label)
        }
    }

    /// A business misfiled into a lone name field ("Joe's Plumbing") is
    /// rescued rather than protected as a person.
    func testLoneNameBusinessesSurvive() {
        XCTAssertEqual(pipeline.classify(identity("Bayou City Sprinkler", given: "Bayou City Sprinkler")), .businessCard)
        XCTAssertEqual(pipeline.classify(identity("Smith Roofing", family: "Smith Roofing")), .businessCard)
    }

    /// 2026-09-27 fix — a trailing all-caps acronym used to make a
    /// multi-word organization look like a personal name, dropping it
    /// ("Northwest Harris County MUD").  An acronym is not a name part.
    func testOrgWithTrailingAcronymSurvives() {
        let c = identity("Northwest Harris County MUD", family: "Northwest Harris County MUD")
        assertSurvives(c, "multi-word org ending in an acronym")
    }

    /// A person's name plus an organization is an *affiliated* contact:
    /// surfaced in Review, never auto-applied, never dropped.  This is the
    /// correct behavior — a person's headshot is not the company logo.
    func testPersonWithOrganizationSurfacesAsAffiliated() {
        let cases: [(String, ContactIdentity)] = [
            ("trade org", identity("Dana Reed", given: "Dana", family: "Reed", org: "Gulf Coast Roofing")),
            ("single token org", identity("Sam Cole", given: "Sam", family: "Cole", org: "Costco")),
            ("org with place word", identity("Alex Ray", given: "Alex", family: "Ray", org: "Cypress Auto Center")),
        ]
        for (label, c) in cases {
            assertSurvives(c, "person + \(label)")
            XCTAssertNotNil(pipeline.affiliation(for: c), "\(label) should resolve an affiliation")
        }
    }

    /// Head-tail display names ("Maya Chen - Texas Instruments") must keep
    /// resolving through the tail.
    func testHeadTailNamesResolveThroughTheBrand() {
        let c = identity("Maya Chen - Texas Instruments", given: "Maya", family: "Chen")
        XCTAssertNotNil(pipeline.affiliation(for: c))
    }

    /// Contacts with no name fields at all still classify on their
    /// email/URL evidence.
    func testEvidenceOnlyContactsAreBusinessCards() {
        XCTAssertEqual(pipeline.classify(identity("", emails: ["sales@sunrisebakery.com"])), .businessCard)
        XCTAssertEqual(pipeline.classify(identity("", urls: ["www.gulfcoastroofing.com"])), .businessCard)
    }
}
