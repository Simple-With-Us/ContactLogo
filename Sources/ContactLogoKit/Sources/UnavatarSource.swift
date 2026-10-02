import Foundation

/// Source E: Unavatar Aggregated Logo & Avatar Service.
///
/// Queries `https://unavatar.io/:domain` across DuckDuckGo, Clearbit, Google,
/// Devicon, and Apple icons to surface canonical marks.
public struct UnavatarSource: LogoSource, Sendable {
    public let kind = SourceKind.unavatar
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
              let url = URL(string: "https://unavatar.io/\(encodedHost)?fallback=false") else {
            return []
        }
        return [
            LogoCandidate(
                source: .unavatar,
                imageURL: url,
                assetType: "icon",
                altText: "\(host) Unavatar"
            )
        ]
    }

    /// Resolves a personal avatar from an email address (used for the opt-in personal contact feature).
    public static func candidate(forEmail email: String) -> LogoCandidate? {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.contains("@"),
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://unavatar.io/\(encoded)?fallback=false") else {
            return nil
        }
        return LogoCandidate(
            source: .unavatarPersonal,
            imageURL: url,
            assetType: "avatar",
            altText: "\(clean) Avatar"
        )
    }
}
