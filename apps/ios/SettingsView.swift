import SwiftUI
import ContactLogoKit

/// Brandfetch/Google CSE credentials + matching preferences (CL-19).
/// ARCHITECTURE.md promises a settings screen; previously the only way to
/// enable Brandfetch was a `CONTACTLOGO_BRANDFETCH_*` process environment
/// variable, which GUI apps launched from Springboard never have set.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var model: ReviewSession
    @Environment(\.dismiss) private var dismiss
    @State private var showDiagnostic = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Client ID", text: $settings.brandfetchClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: settings.brandfetchClientID) { settings.save() }
                    SecureField("API Key", text: $settings.brandfetchAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: settings.brandfetchAPIKey) { settings.save() }
                    Link("Get a Brandfetch API Key ↗", destination: URL(string: "https://brandfetch.com/developers")!)
                        .font(.footnote)
                } header: {
                    Text("Brandfetch")
                }
                Section {
                    SecureField("Token", text: $settings.logoDevToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: settings.logoDevToken) { settings.save() }
                    Link("Get a Logo.dev API Key ↗", destination: URL(string: "https://logo.dev")!)
                        .font(.footnote)
                } header: {
                    Text("Logo.dev")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Optional.\u{00A0} Sharper Brandfetch and Logo.dev logos need a key.\u{00A0} Without one, ContactLogo uses built-in icons and website icons.")
                        if settings.credentialStorageFailed {
                            Text("The keychain would not save that credential.  High-resolution sources will stay off until it can.")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section {
                    Toggle("Find businesses saved as a person's name", isOn: $settings.rescueSplitNameBusinesses)
                        .onChange(of: settings.rescueSplitNameBusinesses) { settings.save() }
                    Toggle("Include single-name contacts", isOn: $settings.includeSingleNameContacts)
                        .onChange(of: settings.includeSingleNameContacts) { settings.save() }
                    Toggle("Skip contacts that already have a photo", isOn: $settings.skipContactsWithExistingPhoto)
                        .onChange(of: settings.skipContactsWithExistingPhoto) { settings.save() }
                } header: {
                    Text("What to Include")
                } footer: {
                    Text("Use this when a company was typed into the first and last name, such as Best Buy, or when the contact has only one name.")
                }
                Section {
                    Toggle("Look up profile photos for people", isOn: $settings.fetchPersonalAvatars)
                        .onChange(of: settings.fetchPersonalAvatars) { settings.save() }
                } header: {
                    Text("People")
                } footer: {
                    Text("When this is on, ContactLogo can search public profile photos from an email address.\u{00A0} It never replaces a personal photo on its own.")
                }
                // 2026-09-21 follow-up audit — direct route to the "Why am I only
                // seeing X contacts?" diagnostic so a user can verify whether
                // Limited Contacts access is the cause without guessing.
                Section {
                    Button {
                        showDiagnostic = true
                    } label: {
                        Label("Why So Few Contacts?", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Scan coverage")
                } footer: {
                    Text("Shows whether Contacts access or syncing is hiding part of your address book.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showDiagnostic) {
                DiagnosticView()
            }
        }
    }
}
