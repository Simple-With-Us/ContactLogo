#if canImport(Combine)
import Combine
import Foundation

/// Persisted user settings.
///
/// Brandfetch used to activate only from `CONTACTLOGO_BRANDFETCH_CLIENT_ID` in
/// the process environment, which an app launched from Finder or Springboard
/// never has — so the best source in the stack was dead in every shipping
/// build (CL-19).  Credentials now live here; the process environment stays as
/// the fallback so the CLI and CI keep working unchanged.
@MainActor
public final class SettingsStore: ObservableObject {

    private enum Key {
        static let clientID = "contactlogo.brandfetch.clientID"
        static let apiKey = "contactlogo.brandfetch.apiKey"
        static let logoDevToken = "contactlogo.logodev.token"
        static let skipExistingPhoto = "contactlogo.skipContactsWithExistingPhoto"
        static let rescueSplitNameBusinesses = "contactlogo.rescueSplitNameBusinesses"
        static let includeSingleNameContacts = "contactlogo.includeSingleNameContacts"
        static let fetchPersonalAvatars = "contactlogo.fetchPersonalAvatars"
    }

    private enum Credential {
        static let service = "com.contactlogo.credentials"
        static let brandfetchAPIKey = "brandfetch.apiKey"
        static let logoDevToken = "logodev.token"
    }

    private let defaults: UserDefaults
    private var isLoading = true

    /// True when the API key or token could not be written to the Keychain, so it is
    /// live for this launch but will not survive it.
    @Published public private(set) var credentialStorageFailed = false

    @Published public var brandfetchClientID: String = "" { didSet { autosave() } }
    @Published public var brandfetchAPIKey: String = "" { didSet { autosave() } }
    @Published public var logoDevToken: String = "" { didSet { autosave() } }
    @Published public var skipContactsWithExistingPhoto: Bool = false { didSet { autosave() } }
    @Published public var rescueSplitNameBusinesses: Bool = true { didSet { autosave() } }
    @Published public var includeSingleNameContacts: Bool = true { didSet { autosave() } }
    @Published public var fetchPersonalAvatars: Bool = false { didSet { autosave() } }

    /// `suiteName` is the shell's concern (an App Group id when one is
    /// configured); nil uses `.standard`.
    public init(suiteName: String? = nil) {
        let store = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard
        defaults = store
        brandfetchClientID = store.string(forKey: Key.clientID) ?? ""
        skipContactsWithExistingPhoto = (store.object(forKey: Key.skipExistingPhoto) as? Bool) ?? false
        rescueSplitNameBusinesses = (store.object(forKey: Key.rescueSplitNameBusinesses) as? Bool) ?? true
        includeSingleNameContacts = (store.object(forKey: Key.includeSingleNameContacts) as? Bool) ?? true
        fetchPersonalAvatars = (store.object(forKey: Key.fetchPersonalAvatars) as? Bool) ?? false

        #if canImport(Security)
        if let stored = KeychainStore.read(account: Credential.brandfetchAPIKey, service: Credential.service) {
            brandfetchAPIKey = stored
        } else if let legacy = store.string(forKey: Key.apiKey), !legacy.isEmpty {
            brandfetchAPIKey = legacy
            if KeychainStore.write(legacy, account: Credential.brandfetchAPIKey, service: Credential.service) {
                store.removeObject(forKey: Key.apiKey)
            } else {
                credentialStorageFailed = true
            }
        }
        if let storedLogoDev = KeychainStore.read(account: Credential.logoDevToken, service: Credential.service) {
            logoDevToken = storedLogoDev
        } else if let legacyToken = store.string(forKey: Key.logoDevToken), !legacyToken.isEmpty {
            logoDevToken = legacyToken
            if KeychainStore.write(legacyToken, account: Credential.logoDevToken, service: Credential.service) {
                store.removeObject(forKey: Key.logoDevToken)
            } else {
                credentialStorageFailed = true
            }
        }
        #else
        brandfetchAPIKey = store.string(forKey: Key.apiKey) ?? ""
        logoDevToken = store.string(forKey: Key.logoDevToken) ?? ""
        #endif

        isLoading = false
    }

    /// Idempotent; shells that batch edits can call it once at the end.
    public func save() {
        defaults.set(brandfetchClientID, forKey: Key.clientID)
        defaults.set(skipContactsWithExistingPhoto, forKey: Key.skipExistingPhoto)
        defaults.set(rescueSplitNameBusinesses, forKey: Key.rescueSplitNameBusinesses)
        defaults.set(includeSingleNameContacts, forKey: Key.includeSingleNameContacts)
        defaults.set(fetchPersonalAvatars, forKey: Key.fetchPersonalAvatars)
        #if canImport(Security)
        let storedKey = KeychainStore.write(
            brandfetchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            account: Credential.brandfetchAPIKey,
            service: Credential.service
        )
        let storedToken = KeychainStore.write(
            logoDevToken.trimmingCharacters(in: .whitespacesAndNewlines),
            account: Credential.logoDevToken,
            service: Credential.service
        )
        let allStored = storedKey && storedToken
        if credentialStorageFailed != !allStored { credentialStorageFailed = !allStored }
        defaults.removeObject(forKey: Key.apiKey)
        defaults.removeObject(forKey: Key.logoDevToken)
        #else
        defaults.set(brandfetchAPIKey, forKey: Key.apiKey)
        defaults.set(logoDevToken, forKey: Key.logoDevToken)
        #endif
    }

    /// Non-empty client id, or nil so the caller falls back to the environment.
    public var resolvedBrandfetchClientID: String? {
        let value = brandfetchClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var resolvedBrandfetchAPIKey: String? {
        let value = brandfetchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var resolvedLogoDevToken: String? {
        let value = logoDevToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func autosave() {
        guard !isLoading else { return }
        save()
    }
}
#endif
