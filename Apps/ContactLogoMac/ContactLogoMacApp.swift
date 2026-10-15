import SwiftUI
import ContactLogoKit

/// ContactLogo for macOS — review-first logo matching for your address book.
@main
struct ContactLogoMacApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var model: ReviewSession

    init() {
        SentryTelemetry.start()
        let settings = SettingsStore()
        let session = ReviewSession(settings: settings)
        session.recordScanTelemetry = { report in
            SentryTelemetry.record(scan: report)
        }
        _settingsStore = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: session)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .frame(minWidth: 760, minHeight: 520)
                .appUpdatePrompt()
        }
        .windowStyle(.titleBar)

        // Reachable via the standard ContactLogo > Settings… (⌘,) menu item
        // (CL-19): previously the only way to set Brandfetch credentials was
        // a process environment variable, which GUI apps never have.
        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .frame(minWidth: 420, minHeight: 260)
        }
    }
}
