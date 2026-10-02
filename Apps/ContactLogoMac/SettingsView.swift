import SwiftUI
import ContactLogoKit

/// Brandfetch/Google CSE credentials + matching preferences, reachable via
/// ContactLogo > Settings… (⌘,) (CL-19). ARCHITECTURE.md promises this
/// screen; previously the only way to enable Brandfetch was a
/// `CONTACTLOGO_BRANDFETCH_*` process environment variable, which GUI apps
/// launched from Finder never have set.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
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
                Text("Optional.  High-resolution Brandfetch and Logo.dev marks need a key.  Without one, ContactLogo uses Simple Icons, Clearbit, Apple Touch Icons, and favicons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.credentialStorageFailed {
                    Text("The keychain would not save that credential.  High-resolution sources will stay off until it can.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Pre-scan Discovery") {
                Toggle("Rescue split-name business contacts", isOn: $settings.rescueSplitNameBusinesses)
                    .onChange(of: settings.rescueSplitNameBusinesses) { settings.save() }
                Toggle("Include single-name contacts", isOn: $settings.includeSingleNameContacts)
                    .onChange(of: settings.includeSingleNameContacts) { settings.save() }
                Toggle("Skip contacts that already have a photo", isOn: $settings.skipContactsWithExistingPhoto)
                    .onChange(of: settings.skipContactsWithExistingPhoto) { settings.save() }
                Text("Off by default. A business card that already has a photo stays in Needs review, flagged \"replace existing\", and is never applied automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Personal Contacts (Optional)") {
                Toggle("Find personal avatars (via Unavatar)", isOn: $settings.fetchPersonalAvatars)
                    .onChange(of: settings.fetchPersonalAvatars) { settings.save() }
                Text("When enabled, searches public profile avatars for personal contacts via email. Never replaces personal photos automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
