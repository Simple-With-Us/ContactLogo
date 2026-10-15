import SwiftUI
import ContactLogoKit

/// ContactLogo for macOS — review-first logo matching for your address book.
@main
struct ContactLogoMacApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var model: ReviewSession
    @ObservedObject private var updater = AppUpdater.shared

    init() {
        SentryTelemetry.start()
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: ReviewSession(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .frame(minWidth: 760, minHeight: 520)
                .appUpdatePrompt()
                .task {
                    // Sparkle self-update starts first: a build whose
                    // Info.plist carries the feed updates itself hourly in
                    // the background.  A build without the feed is a silent
                    // no-op (see AutoUpdateAvailability).
                    AppUpdater.shared.start()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            // "Check For Updates…" sits after About in the app menu.  It is
            // greyed out while Sparkle is busy, and on a build that cannot
            // update itself it does nothing (see AutoUpdateAvailability).
            CommandGroup(after: .appInfo) {
                Button("Check For Updates…") {
                    Task { @MainActor in updater.checkForUpdates() }
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

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
