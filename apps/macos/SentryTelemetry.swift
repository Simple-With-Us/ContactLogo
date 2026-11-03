import Foundation
import Sentry
import ContactLogoKit

/// Native Sentry crash reporting and telemetry for ContactLogo macOS.
///
/// DSN is read only from Info.plist (`SENTRY_DSN`).  There is no hardcoded
/// fallback.  Empty skips init so a leaked default cannot be pointed at the
/// wrong project.  An unsubstituted `$(SENTRY_DSN)` placeholder fails loudly
/// and does not start the SDK.
///
/// Ship/CI should inject Infisical `SENTRY_DSN_MACOS` into the `SENTRY_DSN`
/// build setting (Sentry project `contactlogo-macos`).  Do not put a live
/// DSN in git.  Session Replay / screenshots are iOS-only in sentry-cocoa.
enum SentryTelemetry {
    static func start() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String
        let outcome = SentryDSN.outcome(for: raw)
        let dsn: String
        switch outcome {
        case .absent:
            return
        case .unresolvedPlaceholder, .malformed:
            SentryDSN.reportUnusable(outcome)
            return
        case .ready(let value):
            dsn = value
        }

        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            options.releaseName = "\(version)+\(build)"
            options.dist = build
            options.tracesSampleRate = 0.2
            options.configureProfiling = {
                $0.sessionSampleRate = 0.1
                $0.lifecycle = .trace
            }
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0
            options.enableCaptureFailedRequests = true
            options.failedRequestStatusCodes = [HttpStatusCodeRange(min: 500, max: 599)]
            options.sendDefaultPii = false
            options.beforeSend = { event in
                if let request = event.request, let url = request.url {
                    var sanitized = url
                    for param in ["token", "key", "secret", "auth", "password"] {
                        sanitized = sanitized.replacingOccurrences(
                            of: "([?&]\(param)=)[^&#\\s]+",
                            with: "$1[REDACTED]",
                            options: .regularExpression
                        )
                    }
                    request.url = sanitized
                }
                return event
            }
        }
    }

    /// Counts-only scan event.  Same contract as the iOS shell.
    static func record(scan report: ScanRunReport) {
        let crumb = Breadcrumb()
        crumb.level = .info
        crumb.category = "contactlogo.scan"
        crumb.type = "info"
        crumb.message = "scan"
        let data: [String: Any] = [
            "fetched": report.fetched,
            "classified": report.classified,
            "dropped": report.dropped,
            "authorization": report.authorization,
            "elapsed_seconds": report.elapsedSeconds,
        ]
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
        SentrySDK.capture(message: "contactlogo.scan") { scope in
            scope.setLevel(.info)
            scope.setTag(value: report.authorization, key: "scan.authorization")
            scope.setExtra(value: report.fetched, key: "scan.fetched")
            scope.setExtra(value: report.classified, key: "scan.classified")
            scope.setExtra(value: report.dropped, key: "scan.dropped")
            scope.setExtra(value: report.elapsedSeconds, key: "scan.elapsed_seconds")
        }
    }
}
