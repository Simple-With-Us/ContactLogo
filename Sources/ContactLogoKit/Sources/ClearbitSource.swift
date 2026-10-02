import Foundation

/// Source B: Clearbit Logo API.
///
/// Resolves high-resolution square brand marks at `https://logo.clearbit.com/:domain`.
/// Does not require an API key and provides extensive global brand coverage.
public struct ClearbitSource: LogoSource, Sendable {
    public let kind = SourceKind.clearbit
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

        guard let url = URL(string: "https://logo.clearbit.com/\(host)") else { return [] }
        return [
            LogoCandidate(
                source: .clearbit,
                imageURL: url,
                assetType: "icon",
                altText: "\(host) Clearbit"
            )
        ]
    }
}
