import Foundation

/// Source D: Social Platform Avatar Resolver.
///
/// Discovers profile marks for organizations with verified social links
/// (Twitter/X, GitHub, LinkedIn, YouTube, Instagram).
public struct SocialAvatarSource: LogoSource, Sendable {
    public let kind = SourceKind.socialAvatar
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func candidates(forBrandName name: String) async throws -> [LogoCandidate] {
        guard let domain = CompanyCatalog.domain(forName: name) else { return [] }
        return try await candidates(forDomain: domain)
    }

    public func candidates(forDomain domain: String) async throws -> [LogoCandidate] {
        let clean = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        // If domain itself is a social profile URL or slug
        var candidates: [LogoCandidate] = []
        if clean.contains("twitter.com/") || clean.contains("x.com/") {
            let handle = clean.components(separatedBy: "/").last ?? ""
            if !handle.isEmpty, let url = URL(string: "https://unavatar.io/twitter/\(handle)") {
                candidates.append(LogoCandidate(source: .socialAvatar, imageURL: url, assetType: "icon", altText: "@\(handle) X/Twitter Avatar"))
            }
        } else if clean.contains("github.com/") {
            let user = clean.components(separatedBy: "/").last ?? ""
            if !user.isEmpty, let url = URL(string: "https://unavatar.io/github/\(user)") {
                candidates.append(LogoCandidate(source: .socialAvatar, imageURL: url, assetType: "icon", altText: "\(user) GitHub Avatar"))
            }
        }
        return candidates
    }

    /// Resolves social avatars from an array of arbitrary profile URLs found on the contact.
    public func candidates(forURLs urls: [String]) -> [LogoCandidate] {
        var out: [LogoCandidate] = []
        for raw in urls {
            guard let url = URL(string: raw), let host = url.host?.lowercased() else { continue }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else { continue }
            let handle = path.components(separatedBy: "/").first ?? path

            if host.contains("twitter.com") || host.contains("x.com") {
                if let avatarURL = URL(string: "https://unavatar.io/twitter/\(handle)") {
                    out.append(LogoCandidate(source: .socialAvatar, imageURL: avatarURL, assetType: "icon", altText: "@\(handle) on X"))
                }
            } else if host.contains("github.com") {
                if let avatarURL = URL(string: "https://unavatar.io/github/\(handle)") {
                    out.append(LogoCandidate(source: .socialAvatar, imageURL: avatarURL, assetType: "icon", altText: "\(handle) on GitHub"))
                }
            } else if host.contains("youtube.com") {
                if let avatarURL = URL(string: "https://unavatar.io/youtube/\(handle)") {
                    out.append(LogoCandidate(source: .socialAvatar, imageURL: avatarURL, assetType: "icon", altText: "\(handle) on YouTube"))
                }
            }
        }
        return out
    }
}
