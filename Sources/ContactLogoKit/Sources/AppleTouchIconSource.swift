import Foundation

/// Source A: Apple Touch Icon scraper.
///
/// Discovers official high-resolution homescreen icons (typically 180×180 or 192×192
/// square PNGs with native touch-icon styling) directly from the organization's domain.
public struct AppleTouchIconSource: LogoSource, Sendable {
    public let kind = SourceKind.appleTouchIcon
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func candidates(forBrandName name: String) async throws -> [LogoCandidate] {
        guard let domain = CompanyCatalog.domain(forName: name) else { return [] }
        return try await candidates(forDomain: domain)
    }

    public func candidates(forDomain domain: String) async throws -> [LogoCandidate] {
        let host = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return [] }

        var candidates: [LogoCandidate] = []
        // Primary: standard /apple-touch-icon.png
        if let primaryURL = URL(string: "https://\(host)/apple-touch-icon.png") {
            candidates.append(
                LogoCandidate(
                    source: .appleTouchIcon,
                    imageURL: primaryURL,
                    assetType: "icon",
                    altText: "\(host) Apple Touch Icon"
                )
            )
        }
        // Fallback: /apple-touch-icon-precomposed.png
        if let precomposedURL = URL(string: "https://\(host)/apple-touch-icon-precomposed.png") {
            candidates.append(
                LogoCandidate(
                    source: .appleTouchIcon,
                    imageURL: precomposedURL,
                    assetType: "icon",
                    altText: "\(host) Precomposed Touch Icon"
                )
            )
        }
        return candidates
    }
}
