import Foundation

/// Source F: DuckDuckGo Global Favicon Service.
///
/// Fetches square brand marks and icons from DuckDuckGo's high-uptime global cache
/// (`https://icons.duckduckgo.com/ip3/:domain.ico`).
/// Provides resilient, zero-authentication, keyless icon coverage replacing legacy endpoints.
public struct DuckDuckGoSource: LogoSource, Sendable {
    public let kind = SourceKind.duckduckgo
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

        guard let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(encodedHost).ico") else {
            return []
        }
        return [
            LogoCandidate(
                source: .duckduckgo,
                imageURL: url,
                assetType: "icon",
                altText: "\(host) DuckDuckGo"
            )
        ]
    }
}
