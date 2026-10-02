import Foundation

/// A contact reduced to what the engine needs. Platform shells build these
/// from CNContact (native) or vCard entries (web).
public struct ContactIdentity: Sendable, Hashable {
    public let id: String
    public var displayName: String
    public var givenName: String?
    public var familyName: String?
    public var organization: String?
    public var jobTitle: String?
    public var departmentName: String?
    public var emailDomains: [String]
    public var websiteHosts: [String]
    /// Raw phone strings (published customer-service numbers from vendor/crest).
    public var phoneNumbers: [String]
    public var emails: [String]
    public var urls: [String]
    public var postalAddresses: [String]
    public var hasImage: Bool

    public init(id: String, displayName: String, givenName: String? = nil,
                familyName: String? = nil, organization: String? = nil,
                jobTitle: String? = nil, departmentName: String? = nil,
                emailDomains: [String] = [], websiteHosts: [String] = [],
                phoneNumbers: [String] = [], emails: [String] = [],
                urls: [String] = [], postalAddresses: [String] = [],
                hasImage: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.departmentName = departmentName
        self.emailDomains = emailDomains
        self.websiteHosts = websiteHosts
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.urls = urls
        self.postalAddresses = postalAddresses
        self.hasImage = hasImage
    }
}

public enum ContactClass: String, Sendable, Codable {
    /// Has given/family name. Photo-protected: never overwrite an existing photo.
    case person
    /// No person name — a pure business card ("FedEx", "H-E-B Pharmacy (…)").
    case businessCard
    /// Generic name that is not a brand ("Hospital", "Gift Card", "Printer …").
    case nonBrand
}

public enum SourceKind: String, Sendable, Codable {
    case brandfetch, logodev, wikimedia, googleCSE, googleScrape
    case simpleIcons, favicon, preferred, companiesLogo, manual
    case contactLogoCache
    case appleTouchIcon, clearbit, googleFaviconV2, socialAvatar, unavatar, unavatarPersonal

    public var displayName: String {
        switch self {
        case .brandfetch: return "Brandfetch"
        case .logodev: return "Logo.dev"
        case .wikimedia: return "Wikimedia"
        case .googleCSE: return "Google CSE"
        case .googleScrape: return "Google"
        case .simpleIcons: return "Simple Icons"
        case .favicon: return "Favicon"
        case .preferred: return "Preferred"
        case .companiesLogo: return "CompaniesLogo"
        case .manual: return "Custom Upload"
        case .contactLogoCache: return "Cache"
        case .appleTouchIcon: return "Apple Touch Icon"
        case .clearbit: return "Clearbit"
        case .googleFaviconV2: return "Google Favicon"
        case .socialAvatar: return "Social Profile"
        case .unavatar: return "Unavatar"
        case .unavatarPersonal: return "Personal Avatar"
        }
    }
}

/// One logo option for a contact. The pipeline keeps the top N, not just the winner.
public struct LogoCandidate: Sendable, Hashable, Codable {
    public let source: SourceKind
    public var imageURL: URL
    public let pageURL: URL?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// Brandfetch asset type: "icon" (pictographic) beats "logo" (wordmark).
    public var assetType: String?
    public var altText: String?
    /// Transparent iconic marks score higher than opaque wordmarks.
    public var hasAlpha: Bool?

    public var aspectRatio: Double? {
        guard let w = pixelWidth, let h = pixelHeight, h > 0 else { return nil }
        return Double(w) / Double(h)
    }

    /// Square rule: 0.8...1.25 required for auto-accept (MATCHING-ENGINE §5.1).
    public var isSquareish: Bool {
        guard let r = aspectRatio else { return false }
        return (0.8...1.25).contains(r)
    }

    public var isPictographic: Bool { assetType == "icon" }

    public init(source: SourceKind, imageURL: URL, pageURL: URL? = nil,
                pixelWidth: Int? = nil, pixelHeight: Int? = nil,
                assetType: String? = nil, altText: String? = nil,
                hasAlpha: Bool? = nil) {
        self.source = source
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.assetType = assetType
        self.altText = altText
        self.hasAlpha = hasAlpha
    }

    /// Remote candidates can be re-fetched on display.  Embedded photo bytes
    /// (data: URLs, local files) must never be written to the review-queue store.
    public var isPersistableURL: Bool {
        switch imageURL.scheme?.lowercased() {
        case "http", "https": return true
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source, imageURL, pageURL, pixelWidth, pixelHeight, assetType, altText, hasAlpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(SourceKind.self, forKey: .source)
        self.imageURL = try container.decode(URL.self, forKey: .imageURL)
        self.pageURL = try container.decodeIfPresent(URL.self, forKey: .pageURL)
        self.pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        self.pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        self.assetType = try container.decodeIfPresent(String.self, forKey: .assetType)
        self.altText = try container.decodeIfPresent(String.self, forKey: .altText)
        self.hasAlpha = try container.decodeIfPresent(Bool.self, forKey: .hasAlpha)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        var sanitizedURL = imageURL
        if source == .logodev, var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false) {
            if let items = components.queryItems, items.contains(where: { $0.name == "token" }) {
                components.queryItems = items.filter { $0.name != "token" }
                if let clean = components.url {
                    sanitizedURL = clean
                }
            }
        }
        try container.encode(sanitizedURL, forKey: .imageURL)
        try container.encodeIfPresent(pageURL, forKey: .pageURL)
        try container.encodeIfPresent(pixelWidth, forKey: .pixelWidth)
        try container.encodeIfPresent(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(assetType, forKey: .assetType)
        try container.encodeIfPresent(altText, forKey: .altText)
        try container.encodeIfPresent(hasAlpha, forKey: .hasAlpha)
    }
}

public enum Confidence: Int, Comparable, Sendable, Codable {
    case skip = 0, low = 1, medium = 2, high = 3
    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A source that failed during a run (ENGINE-CONTRACT R11.6).  A source that
/// errored is not the same as a source that found nothing, and neither may be
/// silent: a contact whose search was incomplete is retryable, not "not found".
public struct SourceFailure: Sendable, Hashable, Codable {
    public let source: SourceKind
    public let reason: String
    /// The source gave up after exhausting its 429 backoff budget.
    public let rateLimited: Bool

    public init(source: SourceKind, reason: String, rateLimited: Bool = false) {
        self.source = source
        self.reason = reason
        self.rateLimited = rateLimited
    }
}

public struct MatchResult: Sendable, Equatable, Codable {
    public let contactID: String
    public var contactClass: ContactClass
    /// Ranked, best first. Empty when nothing acceptable was found.
    public var candidates: [LogoCandidate]
    public var confidence: Confidence
    /// Trap flags for the review UI ("homonym-risk", "fallback-tile", ...).
    public var flags: [String]
    /// Sources that errored while matching this contact. Non-empty means the
    /// search was incomplete — the row belongs in a retryable state.
    /// ENGINE-CONTRACT R11.6: these must survive a process death so a
    /// background run cannot advertise a completed search that was not.
    public var sourceErrors: [SourceFailure]

    /// True when nothing was found *and* at least one source failed, i.e. the
    /// answer is "we do not know yet", not "there is no logo".
    public var isRetryable: Bool { candidates.isEmpty && !sourceErrors.isEmpty }

    /// Web `exhausted-label` copy for a completed miss. Nil when `isRetryable`
    /// — R11.6: that row is not "no logo exists". Person/non-brand cards are
    /// a different fact and do not use this string either.
    public var exhaustedLabel: String? {
        guard candidates.isEmpty, !isRetryable, contactClass == .businessCard else { return nil }
        return "No logo found"
    }

    public init(contactID: String, contactClass: ContactClass,
                candidates: [LogoCandidate], confidence: Confidence, flags: [String] = [],
                sourceErrors: [SourceFailure] = []) {
        self.contactID = contactID
        self.contactClass = contactClass
        self.candidates = candidates
        self.confidence = confidence
        self.flags = flags
        self.sourceErrors = sourceErrors
    }

    /// Drops candidates whose `imageURL` embeds photo bytes.  Issue #32: the
    /// persisted queue is identifiers + remote URLs, never image payloads.
    public func withoutEmbeddedImageBytes() -> MatchResult {
        var copy = self
        copy.candidates = candidates.filter(\.isPersistableURL)
        return copy
    }
}

/// What actually gets written — and what is needed to undo it.
public struct ChangeSet: Sendable {
    public struct Entry: Sendable {
        public let contactID: String
        public let newImageData: Data
        /// nil means the contact previously had no image.
        public let previousImageData: Data?

        public init(contactID: String, newImageData: Data, previousImageData: Data?) {
            self.contactID = contactID
            self.newImageData = newImageData
            self.previousImageData = previousImageData
        }
    }
    public let createdAt: Date
    public var entries: [Entry]
    public init(createdAt: Date = Date(), entries: [Entry]) {
        self.createdAt = createdAt
        self.entries = entries
    }
}
