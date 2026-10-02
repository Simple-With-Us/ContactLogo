import XCTest
@testable import ContactLogoKit

final class SourcesExpansionTests: XCTestCase {

    func testAppleTouchIconSourceGeneratesStandardAndPrecomposedURLs() async throws {
        let source = AppleTouchIconSource()
        let candidates = try await source.candidates(forDomain: "stripe.com")
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].source, .appleTouchIcon)
        XCTAssertEqual(candidates[0].imageURL.absoluteString, "https://stripe.com/apple-touch-icon.png")
        XCTAssertEqual(candidates[1].imageURL.absoluteString, "https://stripe.com/apple-touch-icon-precomposed.png")
    }

    func testClearbitSourceGeneratesDomainURL() async throws {
        let source = ClearbitSource()
        let candidates = try await source.candidates(forDomain: "github.com")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, .clearbit)
        XCTAssertEqual(candidates[0].imageURL.absoluteString, "https://logo.clearbit.com/github.com")
    }

    func testGoogleFaviconV2SourceGenerates256pxURL() async throws {
        let source = GoogleFaviconV2Source()
        let candidates = try await source.candidates(forDomain: "apple.com")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, .googleFaviconV2)
        XCTAssertTrue(candidates[0].imageURL.absoluteString.contains("size=256"))
        XCTAssertTrue(candidates[0].imageURL.absoluteString.contains("https://apple.com"))
    }

    func testSocialAvatarSourceResolvesSupportedProfiles() {
        let source = SocialAvatarSource()
        let urls = [
            "https://twitter.com/stripe",
            "https://github.com/apple",
            "https://youtube.com/@veritasium",
            "https://unknown-domain.com/user"
        ]
        let candidates = source.candidates(forURLs: urls)
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates[0].imageURL.absoluteString, "https://unavatar.io/twitter/stripe")
        XCTAssertEqual(candidates[1].imageURL.absoluteString, "https://unavatar.io/github/apple")
        XCTAssertEqual(candidates[2].imageURL.absoluteString, "https://unavatar.io/youtube/@veritasium")
    }

    func testUnavatarSourceGeneratesDomainAndPersonalEmailURLs() async throws {
        let source = UnavatarSource()
        let domainCandidates = try await source.candidates(forDomain: "linear.app")
        XCTAssertEqual(domainCandidates.count, 1)
        XCTAssertEqual(domainCandidates[0].source, .unavatar)
        XCTAssertEqual(domainCandidates[0].imageURL.absoluteString, "https://unavatar.io/linear.app?fallback=false")

        let personal = UnavatarSource.candidate(forEmail: "alex@example.com")
        XCTAssertNotNil(personal)
        XCTAssertEqual(personal?.source, .unavatarPersonal)
        XCTAssertEqual(personal?.imageURL.absoluteString, "https://unavatar.io/alex@example.com?fallback=false")
    }

    func testDuckDuckGoSourceGeneratesDomainURL() async throws {
        let source = DuckDuckGoSource()
        let candidates = try await source.candidates(forDomain: "github.com")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, .duckduckgo)
        XCTAssertEqual(candidates[0].imageURL.absoluteString, "https://icons.duckduckgo.com/ip3/github.com.ico")
    }

    func testBrandfetchSourceUsesDefaultClientIDWhenUnset() async throws {
        let source = BrandfetchSource()
        let candidates = try await source.candidates(forDomain: "example.com")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, .brandfetch)
        XCTAssertTrue(candidates[0].imageURL.absoluteString.contains("c=\(BrandfetchSource.defaultClientID)"))
    }

    func testLogoDevSourcePublishableKeyBrandNameLookup() async throws {
        let source = LogoDevSource(token: "pk_test_12345")
        let candidates = try await source.candidates(forBrandName: "Stripe")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].source, .logodev)
        XCTAssertEqual(candidates[0].imageURL.absoluteString, "https://img.logo.dev/name/Stripe?token=pk_test_12345&size=512&format=png&fallback=404")
    }

    func testSourceKindDisplayNames() {
        XCTAssertEqual(SourceKind.brandfetch.displayName, "Brandfetch")
        XCTAssertEqual(SourceKind.logodev.displayName, "Logo.dev")
        XCTAssertEqual(SourceKind.clearbit.displayName, "Clearbit")
        XCTAssertEqual(SourceKind.duckduckgo.displayName, "DuckDuckGo")
        XCTAssertEqual(SourceKind.appleTouchIcon.displayName, "Apple Touch Icon")
        XCTAssertEqual(SourceKind.googleFaviconV2.displayName, "Google Favicon")
        XCTAssertEqual(SourceKind.socialAvatar.displayName, "Social Profile")
        XCTAssertEqual(SourceKind.unavatar.displayName, "Unavatar")
        XCTAssertEqual(SourceKind.unavatarPersonal.displayName, "Personal Avatar")
    }
}
