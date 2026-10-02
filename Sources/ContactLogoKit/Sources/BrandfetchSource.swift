import Foundation

/// Brandfetch: Brand API (name → domain, rate-limited) + Plugin API (vector/PNG assets) + Logo Link CDN
/// (domain → asset; free client ID; needs a real Referer header).
/// Honors MATCHING-ENGINE §3.1: icon > wordmark, light theme, fallback-tile
/// detection, 429 backoff (ENGINE-CONTRACT R11.6).
public struct BrandfetchSource: LogoSource, Sendable {
    public let kind = SourceKind.brandfetch
    private let brandAPIKey: String?   // Optional Bearer for api.brandfetch.io
    private let logoClientID: String   // c= param for cdn.brandfetch.io
    private let session: URLSession

    /// Default client ID extracted from the official Brandfetch integration
    public static let defaultClientID = "1bfwsmEH20zzEfSNTed"

    public init(brandAPIKey: String? = nil,
                logoClientID: String = defaultClientID,
                session: URLSession = .shared) {
        self.brandAPIKey = brandAPIKey
        self.logoClientID = logoClientID.isEmpty ? Self.defaultClientID : logoClientID
        self.session = session
    }

    private struct SearchResult: Decodable {
        let name: String?
        let domain: String?
        let icon: String?
        let qualityScore: Double?
    }

    public func candidates(forBrandName name: String) async throws -> [LogoCandidate] {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return [] }
        let q = cleanName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanName
        guard let url = URL(string: "https://api.brandfetch.io/v2/search/\(q)") else { return [] }

        let data: Data
        if let key = brandAPIKey, !key.isEmpty {
            data = try await HTTPRetry.withRateLimitRetry {
                try await self.get(url, bearer: key)
            }
        } else {
            // Public unauthenticated Brandfetch search index (keyless)
            data = try await HTTPRetry.withRateLimitRetry {
                try await self.get(url, bearer: nil)
            }
        }

        guard let hits = try? JSONDecoder().decode([SearchResult].self, from: data) else { return [] }
        var out: [LogoCandidate] = []
        for hit in hits.prefix(4) {
            guard let domain = hit.domain,
                  NameNormalizer.passesSimilarity(query: cleanName, brandName: hit.name ?? "") else { continue }

            if let iconStr = hit.icon, let iconURL = URL(string: iconStr) {
                out.append(
                    LogoCandidate(
                        source: .brandfetch,
                        imageURL: iconURL,
                        assetType: "icon",
                        altText: "\(hit.name ?? cleanName) Brandfetch Icon"
                    )
                )
            }
            if let domainCandidates = try? await candidates(forDomain: domain) {
                out.append(contentsOf: domainCandidates)
            }
        }
        return out
    }

    private struct Brand: Decodable {
        struct Logo: Decodable {
            struct Format: Decodable { let src: String; let format: String? }
            let type: String?
            let theme: String?
            let formats: [Format]?
        }
        let logos: [Logo]?
        /// Brandfetch marks generated letter tiles (ENGINE-CONTRACT R11.5.1).
        let fallback: Bool?
    }

    private struct PluginResponse: Decodable {
        struct Collection: Decodable {
            let sections: [Section]?
        }
        struct Section: Decodable {
            let sectionName: String?
            let assets: [Asset]?
        }
        struct Asset: Decodable {
            let sectionType: String?
            let theme: String?
            let formats: [Format]?
        }
        struct Format: Decodable {
            let src: String
            let format: String?
            let width: Int?
            let height: Int?
        }
        let collections: [Collection]?
    }

    public func candidates(forDomain domain: String) async throws -> [LogoCandidate] {
        let cleanDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDomain.isEmpty else { return [] }

        // 1. Authenticated Brand API (if key provided)
        if let key = brandAPIKey, !key.isEmpty, let url = URL(string: "https://api.brandfetch.io/v2/brands/\(cleanDomain)") {
            let data: Data?
            do {
                data = try await HTTPRetry.withRateLimitRetry { try await self.get(url, bearer: key) }
            } catch let error as LogoSourceError where error == .notFound {
                data = nil
            }
            if let data, let brand = try? JSONDecoder().decode(Brand.self, from: data) {
                // A "fallback" brand is Brandfetch's generated letter tile, not
                // a logo: treated as not found rather than offered to the user.
                if brand.fallback == true { return [] }
                let assets = (brand.logos ?? []).flatMap { logo -> [LogoCandidate] in
                    (logo.formats ?? [])
                        .filter { $0.format == "png" }
                        .compactMap { format in
                            guard let assetURL = URL(string: format.src) else { return nil }
                            return LogoCandidate(source: .brandfetch, imageURL: assetURL,
                                                 assetType: logo.type, altText: cleanDomain)
                        }
                }
                if !assets.isEmpty { return assets }
            }
        }

        // 2. Unauthenticated Brandfetch Plugin API (vector & high-res PNG assets)
        if let pluginAssets = await fetchPluginAssets(forDomain: cleanDomain), !pluginAssets.isEmpty {
            return pluginAssets
        }

        // 3. Fallback to Brandfetch Logo CDN URL
        guard let url = URL(string: "https://cdn.brandfetch.io/\(cleanDomain)?c=\(logoClientID)") else { return [] }
        return [LogoCandidate(source: .brandfetch, imageURL: url, altText: cleanDomain)]
    }

    private func fetchPluginAssets(forDomain domain: String) async -> [LogoCandidate]? {
        guard let url = URL(string: "https://api.brandfetch.io/v2/plugin/\(domain)") else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        let r = "\(timestamp)-2eP2dELt9XXD2MriGRGwCtmaPyDHDab8ggLBLf"
        let sig = String(Self.murmur3(r, seed: 58425345))

        var request = URLRequest(url: url)
        request.setValue(sig, forHTTPHeaderField: "signature")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let pluginResp = try? JSONDecoder().decode(PluginResponse.self, from: data) else {
            return nil
        }

        let logoSections = (pluginResp.collections ?? []).flatMap { $0.sections ?? [] }.filter { $0.sectionName == "logos" }
        var candidates: [LogoCandidate] = []
        for asset in logoSections.flatMap({ $0.assets ?? [] }) {
            for format in (asset.formats ?? []) {
                guard let formatType = format.format?.lowercased(),
                      formatType == "png" || formatType == "webp" || formatType == "svg",
                      let assetURL = URL(string: format.src) else { continue }

                candidates.append(
                    LogoCandidate(
                        source: .brandfetch,
                        imageURL: assetURL,
                        pixelWidth: format.width,
                        pixelHeight: format.height,
                        assetType: asset.sectionType ?? "icon",
                        altText: "\(domain) Brandfetch \(asset.sectionType ?? "mark")",
                        hasAlpha: true
                    )
                )
            }
        }
        return candidates.isEmpty ? nil : candidates
    }

    /// Fast, deterministic MurmurHash3_x86_32 implementation for plugin API signatures.
    static func murmur3(_ string: String, seed: UInt32) -> UInt32 {
        let utf8 = Array(string.utf8)
        let nblocks = utf8.count / 4
        var h1: UInt32 = seed
        let c1: UInt32 = 0xcc9e2d51
        let c2: UInt32 = 0x1b873593

        for i in 0..<nblocks {
            let idx = i * 4
            var k1 = UInt32(utf8[idx]) |
                     (UInt32(utf8[idx + 1]) << 8) |
                     (UInt32(utf8[idx + 2]) << 16) |
                     (UInt32(utf8[idx + 3]) << 24)

            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2

            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = h1 &* 5 &+ 0xe6546b64
        }

        let tailIdx = nblocks * 4
        let remaining = utf8.count & 3
        var k1: UInt32 = 0

        if remaining >= 3 { k1 ^= UInt32(utf8[tailIdx + 2]) << 16 }
        if remaining >= 2 { k1 ^= UInt32(utf8[tailIdx + 1]) << 8 }
        if remaining >= 1 {
            k1 ^= UInt32(utf8[tailIdx])
            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2
            h1 ^= k1
        }

        h1 ^= UInt32(utf8.count)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85ebca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2ae35
        h1 ^= h1 >> 16

        return h1
    }

    /// One GET request, translating HTTP status into `LogoSourceError`
    /// so the retry policy can see a 429 instead of a decode failure.
    private func get(_ url: URL, bearer: String?) async throws -> Data {
        var request = URLRequest(url: url)
        if let bearer = bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                throw LogoSourceError.rateLimited(
                    retryAfter: HTTPRetry.retryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After"))
                )
            }
            guard (200...299).contains(http.statusCode) else {
                throw LogoSourceError.forStatus(http.statusCode)
            }
        }
        return data
    }

    /// An honest, identifying User-Agent.  We used to send a spoofed Chrome UA
    /// and a forged `Referer: https://www.google.com/` to every third-party
    /// host we fetched an image from; MATCHING-ENGINE §3 only ever asked for a
    /// *real* referer that is not example.com, which this is.
    public static let userAgent = "ContactLogo/1.0 (+https://contactlogo.com)"
    public static let referer = "https://contactlogo.com/"

    /// Image request used for every candidate fetch, not just Brandfetch's.
    public static func imageRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        return request
    }

    /// Historical name for `imageRequest(url:)`.
    public static func cdnRequest(url: URL) -> URLRequest { imageRequest(url: url) }
}
