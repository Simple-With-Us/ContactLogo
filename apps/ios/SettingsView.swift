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
                        Text("Optional.  High-resolution Brandfetch and Logo.dev marks need a key.  Without one, ContactLogo uses Simple Icons, Clearbit, Apple Touch Icons, Unavatar, and favicons.")
                        if settings.credentialStorageFailed {
                            Text("The keychain would not save that credential.  High-resolution sources will stay off until it can.")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section {
                    Toggle("Rescue split-name business contacts", isOn: $settings.rescueSplitNameBusinesses)
                        .onChange(of: settings.rescueSplitNameBusinesses) { settings.save() }
                    Toggle("Include single-name contacts", isOn: $settings.includeSingleNameContacts)
                        .onChange(of: settings.includeSingleNameContacts) { settings.save() }
                    Toggle("Skip contacts that already have a photo", isOn: $settings.skipContactsWithExistingPhoto)
                        .onChange(of: settings.skipContactsWithExistingPhoto) { settings.save() }
                } header: {
                    Text("Pre-scan Discovery Options")
                } footer: {
                    Text("Rescue contacts where business names were typed into First and Last Name fields (e.g. \"Best Buy\", \"Trader Joe's\") or lone name fields.")
                }
                Section {
                    Toggle("Find personal avatars (via Unavatar)", isOn: $settings.fetchPersonalAvatars)
                        .onChange(of: settings.fetchPersonalAvatars) { settings.save() }
                } header: {
                    Text("Personal Contacts (Optional)")
                } footer: {
                    Text("When enabled, searches public profile avatars for personal contacts via their email addresses. Personal contacts are never overwritten automatically.")
                }
                // 2026-09-21 follow-up audit — direct route to the "Why am I only
                // seeing X contacts?" diagnostic so a user can verify whether
                // Limited Contacts access is the cause without guessing.
                Section {
                    Button {
                        showDiagnostic = true
                    } label: {
                        Label("Diagnostic: Why am I only seeing X?", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Scan coverage")
                } footer: {
                    Text("Shows the authorization state, the scan breakdown, and a sample of dropped contacts so you can verify whether Limited contacts access is hiding part of your address book.")
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
