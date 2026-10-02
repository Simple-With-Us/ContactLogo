import Foundation

/// Source C: Google Favicon v2 256px Service.
///
/// Fetches modern 256px high-resolution icons from Google's high-res asset cache
/// (`https://t1.gstatic.com/faviconV2?...&size=256`), providing significantly clearer
/// rendering than legacy 16/32/128px favicon endpoints.
public struct GoogleFaviconV2Source: LogoSource, Sendable {
    public let kind = SourceKind.googleFaviconV2
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

        guard let encodedURL = "https://\(host)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=\(encodedURL)&size=256") else {
            return []
        }
        return [
            LogoCandidate(
                source: .googleFaviconV2,
                imageURL: url,
                assetType: "icon",
                altText: "\(host) Google Favicon 256px"
            )
        ]
    }
}
