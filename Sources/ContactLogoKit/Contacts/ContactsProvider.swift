import Foundation

/// Abstraction over the address book so the engine runs identically on
/// macOS, iOS, and the web (vCard-backed) shell.
public protocol ContactsProvider: Sendable {
    func requestAccess() async throws -> Bool
    /// Contacts worth considering: businesses and business cards.
    func fetchCandidates() async throws -> [ContactIdentity]
    func imageData(forContactID id: String) async throws -> Data?
    func setImage(_ data: Data, forContactID id: String) async throws
    func removeImage(forContactID id: String) async throws
    /// True when the user has granted Contacts `.limited` access.  When
    /// limited, `fetchCandidates` only returns the contacts the user
    /// explicitly picked; a scan that returns suspiciously few contacts
    /// is almost always a sign of this.  Default is `false` for non-Apple
    /// shells, which never receive limited grants.
    func isLimitedAccess() async -> Bool
    /// 2026-09-21 follow-up — finer-grained view of the authorization
    /// state so the UI can show a blocking banner on pre-iOS-18 too.
    /// See `LimitedAccessState` for the cases.
    func limitedAccessDiagnosis() async -> LimitedAccessState
    /// 2026-09-27 — how many contacts the app can currently see in the
    /// device Contacts database, independent of authorization state.
    ///
    /// This is the number that separates the two causes of a "tiny scan",
    /// and they have completely different fixes:
    ///
    /// 1. **`.limited` access** — the address book is large but the app may
    ///    only read a subset.  Fix is in Settings → ContactLogo → Contacts.
    /// 2. **Contacts are not in the device database** — the user keeps
    ///    their business contacts in Google / Exchange and that account's
    ///    Contacts Sync is off, so the device only holds a handful of
    ///    local entries.  Fix is in Settings → [account] → Contacts.
    ///
    /// The two are indistinguishable from `limitedAccessState` alone when
    /// the OS reports `.open` (full access) but the database is small, which
    /// is exactly the case that left the owner stuck on "still only 22".
    func visibleContactCount() async -> Int
    /// False when `visibleContactCount()` tripped an enumeration bound, so
    /// the returned number is a lower bound rather than the true total.
    func visibleContactCountIsExact() async -> Bool
}

extension ContactsProvider {
    public func requestAccess() async throws -> Bool { true }
    public func isLimitedAccess() async -> Bool { false }
    public func limitedAccessDiagnosis() async -> LimitedAccessState { .open }
    public func visibleContactCount() async -> Int { 0 }
    public func visibleContactCountIsExact() async -> Bool { true }
}

/// 2026-09-21 follow-up audit — the result of probing `.limited` Contacts
/// authorization.  `.definite` is the iOS 18+ API response; `.heuristic`
/// is a small-subset signal that fires on every iOS version (including
/// 17 and earlier where Apple's `.limited` status is not exposed).
/// `.denied` and `.restricted` mean the user must grant access before
/// any scan can run; `.open` means full or no access has been granted.
public enum LimitedAccessState: Sendable, Equatable {
    case open
    case definite
    case heuristic(Int) // visible contact count
    /// 2026-09-27 follow-up — the OS reports **full** access
    /// (`.authorized`) while the Contacts database the app can read is
    /// small.  This is deliberately its own case rather than a flavour of
    /// `.heuristic`.
    ///
    /// It used to be reported as `.heuristic`, which the UI headlines as
    /// "Limited contacts access" and fixes with "Settings → ContactLogo →
    /// Contacts → All Contacts".  On a full-access grant that fix provably
    /// cannot change anything, so the user does it, the number stays where
    /// it was, and the app looks broken.  That is the loop the owner was
    /// stuck in ("still only 22").
    ///
    /// The real cause is upstream of the app: the contacts are not in the
    /// device database, almost always because the Google / Exchange account
    /// that holds them has Contacts Sync switched off.
    case fullAccessSmallDatabase(Int) // visible contact count
    case denied
    case restricted

    /// A visible address book below this size is "suspiciously small" and
    /// worth explaining.  Single source of truth so the kit's diagnosis and
    /// the shells' copy cannot drift apart.
    public static let smallAddressBookThreshold = 100

    /// True when the app genuinely holds a limited-access grant, i.e. only
    /// "Settings → … → Contacts → All Contacts" can widen what it sees.
    /// `.heuristic` and `.fullAccessSmallDatabase` are both *not* this:
    /// the first is unproven, the second is disproven.
    public var isGenuineLimitedGrant: Bool {
        if case .definite = self { return true }
        return false
    }
}

#if canImport(Contacts)
import Contacts

/// Contacts.framework-backed provider (macOS / iOS).
public final class CNContactsProvider: ContactsProvider, @unchecked Sendable {
    private let store = CNContactStore()

    public init() {}

    public func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// iOS 18+ exposes `CNAuthorizationStatus.limited` directly.  Earlier
    /// versions report `.authorized` and we can only detect the narrow
    /// address book by asking the store for its visible container —
    /// `defaultContainerIdentifier` returns the system "iCloud" container
    /// regardless, but `CNContactStoreDidChange` plus a count delta from a
    /// known full grant lets us flag it heuristically.  We keep the
    /// check simple and Apple-version-aware: if the constant is available,
    /// use it; otherwise return `false` and let the post-scan UI prompt
    /// the user to open Settings if the address book looks suspiciously
    /// small.
    public func isLimitedAccess() async -> Bool {
        #if compiler(>=5.10) && canImport(Contacts) && os(iOS)
        if #available(iOS 18, *) {
            return CNContactStore.authorizationStatus(for: .contacts) == .limited
        }
        #endif
        return false
    }

    /// 2026-09-21 follow-up audit — the iOS 18 `.limited` API is the only
    /// direct signal; on iOS 17 and earlier the user may have granted
    /// Limited access (Apple has done this since iOS 16 for some flows)
    /// without us knowing.  Heuristic: enumerate with `unifyResults = true`
    /// AND check `defaultContainerIdentifier` against the iCloud container;
    /// any narrow container that is NOT the local default is treated as
    /// a likely `.limited` subset.  Returns `.heuristic` so callers can
    /// show a softer warning, plus `.definite` when iOS 18 reports it.
    public func limitedAccessDiagnosis() async -> LimitedAccessState {
        #if compiler(>=5.10) && canImport(Contacts) && os(iOS)
        if #available(iOS 18, *) {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .limited { return .definite }
            if status == .denied { return .denied }
            if status == .restricted { return .restricted }
            if status == .authorized {
                // FULL access.  This branch is the whole point: before it
                // existed, `.authorized` fell through to the "is it
                // suspiciously small?" heuristic below and came back as
                // `.heuristic(22)`, which the UI renders as a limited grant
                // and fixes with an All Contacts toggle that cannot help.
                //
                // With access already full, a small database is not a
                // permissions problem at all — the contacts simply are not
                // on this device.
                let visible = await visibleContactCount()
                let small = visible > 0 && visible < LimitedAccessState.smallAddressBookThreshold
                return small ? .fullAccessSmallDatabase(visible) : .open
            }
            // `.notDetermined` — no grant yet, so there is nothing to
            // diagnose.  Enumerating here would return 0 anyway.
            return .open
        }
        // Pre-iOS-18: Apple never exposes `.limited`, so a small subset is
        // the only signal available.  It genuinely cannot tell the two
        // causes apart, which is why `.heuristic` keeps the combined
        // two-cause copy and `.fullAccessSmallDatabase` does not.
        let visibleCount = await visibleContactCount()
        let likely = visibleCount > 0 && visibleCount < LimitedAccessState.smallAddressBookThreshold
        return likely ? .heuristic(visibleCount) : .open
        #else
        return .open
        #endif
    }

    /// Cheap enumeration — counts contacts without building identities.
    /// Used by `limitedAccessDiagnosis` to detect the small-subset case on
    /// iOS 17 and earlier where Apple's `.limited` status isn't exposed,
    /// and by the iOS Diagnostic screen to separate "access is limited"
    /// from "the device database is only this big".
    ///
    /// Only the identifier key is fetched, so this stays cheap; the early
    /// `stop` is a safety bound, not a silent truncation.  The bound is
    /// reported honestly to callers via `visibleContactCountIsExact`, which
    /// is false when the stop fired and the true total may be larger.
    public func visibleContactCount() async -> Int {
        #if canImport(Contacts)
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var count = 0
        do {
            try store.enumerateContacts(with: request) { _, stop in
                count += 1
                // `stop.pointee = true` halts the entire enumeration, not just the
                // current callback.  Without this the "1,000 contact bound" was a
                // no-op — every contact still ran, doubling scan cost.
                if count > Self.visibilityBound { stop.pointee = true }
            }
        } catch {
            return 0
        }
        return count
        #else
        return 0
        #endif
    }

    /// Enumeration ceiling.  Identifier-only enumeration is cheap, so this is
    /// set well above any real address book (the owner's is ~1,000) while
    /// still bounding a pathological case.
    static let visibilityBound = 25_000

    /// False when `visibleContactCount()` tripped the enumeration bound and
    /// the device may hold more than the returned number.
    public func visibleContactCountIsExact() async -> Bool {
        await visibleContactCount() < Self.visibilityBound
    }

    /// Enumeration keys for a full scan.
    ///
    /// 2026-09-27 — `CNContactImageDataKey` was here, and it is the reason a
    /// large address book never produced a queue.  `identity(from:)` only
    /// ever reads `imageDataAvailable` (a Bool), and `ContactIdentity`
    /// carries no image bytes, so every byte of photo data the framework
    /// materialized during enumeration was allocated and thrown away.
    ///
    /// With ~15,000 contacts that is 15,000 contact photos decoded in one
    /// synchronous pass.  The framework does not stream them and the
    /// provider accumulates identities in an array, so the run burns
    /// enormous memory and wall-clock inside a single `enumerateContacts`
    /// call.  iOS terminates the app for memory pressure (jetsam) or the
    /// background task expires, so `scanAndMatch` never reaches its
    /// `persistReviewQueue` call.  The app relaunches, `loadFresh` finds an
    /// unchanged change token, and restores the *previous* queue — which is
    /// why the number was stuck at the same small value on every run
    /// instead of growing.
    ///
    /// `CNContactImageDataAvailableKey` answers the only question the scan
    /// asks ("does this contact already have a photo?"), at a fraction of
    /// the cost.  The bytes are still fetched per contact in
    /// `mutableContact(id:)` for the actual get/set operations.
    internal static var keys: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor
        ]
    }

    public func fetchCandidates() async throws -> [ContactIdentity] {
        var out: [ContactIdentity] = []
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        try store.enumerateContacts(with: request) { contact, _ in
            if let identity = Self.identity(from: contact, requireCandidateShape: true) {
                out.append(identity)
            }
        }
        return out
    }

    /// One contact by identifier, for per-row Retry. Skips the enumerate-time
    /// people-only filter so a row already in the queue can be rematched.
    public func fetchCandidate(id: String) async -> ContactIdentity? {
        guard let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: Self.keys) else {
            return nil
        }
        return Self.identity(from: contact, requireCandidateShape: false)
    }

    private static func identity(from contact: CNContact, requireCandidateShape: Bool) -> ContactIdentity? {
        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)
        let org = contact.organizationName.trimmingCharacters(in: .whitespaces)
        let job = contact.jobTitle.trimmingCharacters(in: .whitespaces)
        let dept = contact.departmentName.trimmingCharacters(in: .whitespaces)

        // Label-aware email selection — work/business labels outrank home
        // so the brand-relevant inbox beats a personal gmail fallback.
        // Without this the user's first-listed email (often a personal one
        // entered first) overrides the work address that names the brand,
        // and an entire contact is mis-attributed.
        let emailDomains = rankedEmailDomains(from: contact)
        let fullEmails = contact.emailAddresses.map { $0.value as String }
        let fullURLs = contact.urlAddresses.map { $0.value as String }
        let websiteHosts: [String] = contact.urlAddresses.compactMap { labeled in
            let raw = labeled.value as String
            // MATCHING-ENGINE §4: only http(s) URLs — drop ms-outlook:// etc.
            guard raw.lowercased().hasPrefix("http") else { return nil }
            return URL(string: raw)?.host
        }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        let addresses = contact.postalAddresses.map { labeled -> String in
            let addr = labeled.value
            return [addr.street, addr.city, addr.state, addr.postalCode, addr.country]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        let display = [given, family].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let resolvedDisplay = display.isEmpty ? (org.isEmpty ? (websiteHosts.first ?? "") : org) : display

        // Drop empty placeholder contacts with zero identifying fields
        guard !resolvedDisplay.isEmpty || !phones.isEmpty || !emailDomains.isEmpty || !websiteHosts.isEmpty else { return nil }

        return ContactIdentity(
            id: contact.identifier,
            displayName: resolvedDisplay,
            givenName: given.isEmpty ? nil : given,
            familyName: family.isEmpty ? nil : family,
            organization: org.isEmpty ? nil : org,
            jobTitle: job.isEmpty ? nil : job,
            departmentName: dept.isEmpty ? nil : dept,
            emailDomains: emailDomains,
            websiteHosts: websiteHosts,
            phoneNumbers: phones,
            emails: fullEmails,
            urls: fullURLs,
            postalAddresses: addresses,
            hasImage: contact.imageDataAvailable
        )
    }

    /// Order `contact.emailAddresses` so work/business labels come first.
    /// Tie-break on declaration order, never on alphabetised hostname — an
    /// alphabetical tie-break silently reorders the user's address book
    /// (the web `google-contacts.ts` already pinned this rule, see the 2026-
    /// 09-20 audit).  Returns just the host portion (`gmail.com`) the same
    /// way the previous flat pass did.
    private static func rankedEmailDomains(from contact: CNContact) -> [String] {
        let indexed: [(Int, String, Int)] = contact.emailAddresses.enumerated().compactMap { (idx, labeled) -> (Int, String, Int)? in
            let email = labeled.value as String
            guard let host = email.split(separator: "@").last.map(String.init) else { return nil }
            let label = labeled.label ?? ""
            let score: Int
            if label.contains(CNLabelWork), label != CNLabelWork {
                score = 0 // CNLabelWork, _$!<Other>!$_, etc.
            } else if label == CNLabelWork {
                score = 0
            } else if label.contains(CNLabelSchool) {
                score = 2
            } else if label.contains(CNLabelHome) || label == CNLabelHome {
                score = 3
            } else {
                // Unlabeled / iCloud / custom — last resort; the user's
                // declaration order survives via the index tie-break.
                score = 4
            }
            return (score, host.lowercased(), idx)
        }
        return indexed.sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.2 < rhs.2
        }.map(\.1)
    }

    private func mutableContact(id: String) throws -> CNMutableContact {
        let keys: [CNKeyDescriptor] = [CNContactImageDataKey as CNKeyDescriptor]
        return try store.unifiedContact(withIdentifier: id, keysToFetch: keys).mutableCopy() as! CNMutableContact
    }

    public func imageData(forContactID id: String) async throws -> Data? {
        try mutableContact(id: id).imageData
    }

    public func setImage(_ data: Data, forContactID id: String) async throws {
        let contact = try mutableContact(id: id)
        contact.imageData = data
        let save = CNSaveRequest()
        save.update(contact)
        try store.execute(save)
    }

    public func removeImage(forContactID id: String) async throws {
        let contact = try mutableContact(id: id)
        contact.imageData = nil
        let save = CNSaveRequest()
        save.update(contact)
        try store.execute(save)
    }
}
#endif
