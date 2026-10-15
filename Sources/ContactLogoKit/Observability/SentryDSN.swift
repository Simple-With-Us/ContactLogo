import Foundation
#if canImport(os)
import os
#endif

/// What `SentryTelemetry.start` should do with the Info.plist `SENTRY_DSN` value.
///
/// Empty is intentional: local and CI builds stay dark when the secret is
/// unset.  An unsubstituted build setting is not empty.  Xcode leaves the
/// literal `$(SENTRY_DSN)` in the plist, `start()` used to treat any
/// non-empty string as a DSN, and the SDK then no-op'd.  That is why a
/// shipped iOS build reported nothing.
public enum SentryDSNOutcome: Equatable, Sendable {
    /// No DSN configured.  Do not start the SDK.
    case absent
    /// Safe to pass to `SentrySDK.start`.  The string is the trimmed value.
    case ready(String)
    /// The build setting was not substituted.
    case unresolvedPlaceholder
    /// Non-empty, substituted, and not a DSN URL.  The value is omitted.
    case malformed
}

public enum SentryDSN {
    /// Classify a plist value.  Never log or return a malformed secret-shaped
    /// string.  Placeholder detection runs before URL parsing so an
    /// unsubstituted build setting cannot reach the SDK.
    public static func outcome(for raw: String?) -> SentryDSNOutcome {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .absent }
        if trimmed.contains("$(") || trimmed.contains("${") {
            return .unresolvedPlaceholder
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              trimmed.contains("@"),
              url.host?.isEmpty == false else {
            return .malformed
        }
        return .ready(trimmed)
    }

    /// Loud failure for a value that must not be passed to the SDK.
    /// Debug builds trap.  Release builds still emit a public fault log,
    /// because `assertionFailure` is stripped from ship archives.  The DSN
    /// value is not included: a malformed string may be a credential, and
    /// the placeholder is not a usable DSN anyway.
    public static func reportUnusable(_ outcome: SentryDSNOutcome) {
        let message: String
        switch outcome {
        case .unresolvedPlaceholder:
            message = "Sentry DSN is the unsubstituted $(SENTRY_DSN) placeholder.  Telemetry will not start."
        case .malformed:
            message = "Sentry DSN is not a usable URL.  Telemetry will not start."
        case .absent, .ready(_):
            return
        }
        #if canImport(os)
        Logger(subsystem: "com.contactlogo", category: "sentry")
            .fault("\(message, privacy: .public)")
        #else
        FileHandle.standardError.write(Data((message + "\n").utf8))
        #endif
        #if DEBUG
        assertionFailure(message)
        #endif
    }
}
