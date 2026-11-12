import SwiftUI
import ContactLogoKit

/// Brandfetch/Google CSE credentials + matching preferences, reachable via
/// ContactLogo > Settings… (⌘,) (CL-19). ARCHITECTURE.md promises this
/// screen; previously the only way to enable Brandfetch was a
/// `CONTACTLOGO_BRANDFETCH_*` process environment variable, which GUI apps
/// launched from Finder never have set.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section("Updates") {
                Text("Automatic updates: \(AppUpdater.shared.availability.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check For Updates…") {
                    Task { @MainActor in updater.checkForUpdates() }
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Section("Brandfetch") {
                SecureField("Client ID", text: $settings.brandfetchClientID)
                    .onChange(of: settings.brandfetchClientID) { settings.save() }
                SecureField("API Key", text: $settings.brandfetchAPIKey)
                    .onChange(of: settings.brandfetchAPIKey) { settings.save() }
                Link("Get a Brandfetch API Key ↗", destination: URL(string: "https://brandfetch.com/developers")!)
                    .font(.caption)
            }
            Section("Logo.dev") {
                SecureField("Token", text: $settings.logoDevToken)
                    .onChange(of: settings.logoDevToken) { settings.save() }
                Link("Get a Logo.dev API Key ↗", destination: URL(string: "https://logo.dev")!)
                    .font(.caption)
                Text("Optional.\u{00A0} Sharper Brandfetch and Logo.dev logos need a key.\u{00A0} Without one, ContactLogo uses built-in icons and website icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.credentialStorageFailed {
                    Text("The keychain would not save that credential.  High-resolution sources will stay off until it can.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("What to Include") {
                Toggle("Find businesses saved as a person's name", isOn: $settings.rescueSplitNameBusinesses)
                    .onChange(of: settings.rescueSplitNameBusinesses) { settings.save() }
                Toggle("Include single-name contacts", isOn: $settings.includeSingleNameContacts)
                    .onChange(of: settings.includeSingleNameContacts) { settings.save() }
                Toggle("Skip contacts that already have a photo", isOn: $settings.skipContactsWithExistingPhoto)
                    .onChange(of: settings.skipContactsWithExistingPhoto) { settings.save() }
                Text("Off by default.\u{00A0} A business that already has a photo stays in Needs Review until you approve a replacement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("People") {
                Toggle("Look up profile photos for people", isOn: $settings.fetchPersonalAvatars)
                    .onChange(of: settings.fetchPersonalAvatars) { settings.save() }
                Text("When this is on, ContactLogo can search public profile photos from an email address.\u{00A0} It never replaces a personal photo on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
