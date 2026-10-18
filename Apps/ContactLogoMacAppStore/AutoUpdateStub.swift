import Combine
import Foundation

// The Mac App Store / TestFlight build of ContactLogo for Mac (CL-203).
//
// This file stands in for Apps/ContactLogoMac/AutoUpdate.swift, which imports
// Sparkle.  The App Store build must not contain Sparkle: the store delivers
// updates itself, and Sparkle's Autoupdate and Updater.app executables are not
// sandboxed, so App Store Connect refuses an upload that carries them.  The
// ContactLogoMacAppStore target compiles this file instead of AutoUpdate.swift
// and defines the same two names, so ContactLogoMacApp.swift and
// SettingsView.swift build unchanged.  See docs/AUTO-UPDATE.md, Mac TestFlight.

/// Updates never come from inside this build.
enum AutoUpdateAvailability: Equatable {
    case disabled(reason: String)

    var isEnabled: Bool { false }

    /// One line for Settings > Updates.
    var summary: String {
        switch self {
        case .disabled(let reason): "Off · \(reason)"
        }
    }
}

/// A no-op stand-in for the Sparkle updater.  `canCheckForUpdates` stays false,
/// so "Check For Updates…" is greyed out, and `start()` does nothing.
final class AppUpdater: ObservableObject, @unchecked Sendable {
    static let shared = AppUpdater()

    let availability = AutoUpdateAvailability.disabled(reason: "TestFlight and the App Store deliver updates.")
    @Published private(set) var canCheckForUpdates = false

    private init() {}

    @MainActor func start() {}

    @MainActor func checkForUpdates() {}
}
