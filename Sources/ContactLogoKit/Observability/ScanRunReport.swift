import Foundation

/// One scan's shape, safe to leave the device.
///
/// Counts and an authorization label only.  No contact names, identifiers,
/// emails, phone numbers, or postal addresses.
public struct ScanRunReport: Equatable, Sendable {
    /// Identities `fetchCandidates` returned.
    public var fetched: Int
    /// Business cards plus affiliated people that entered matching.
    public var classified: Int
    /// Everyone else: protected people, non-brands, and skip-photo drops.
    public var dropped: Int
    /// `LimitedAccessState.telemetryLabel`, `access_denied`, or `unknown`.
    public var authorization: String
    /// Seconds from the start of `scanAndMatch` to this report.
    public var elapsedSeconds: Double

    public init(
        fetched: Int,
        classified: Int,
        dropped: Int,
        authorization: String,
        elapsedSeconds: Double
    ) {
        self.fetched = fetched
        self.classified = classified
        self.dropped = dropped
        self.authorization = authorization
        self.elapsedSeconds = elapsedSeconds
    }
}
