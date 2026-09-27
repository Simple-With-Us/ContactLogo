import SwiftUI
import ContactLogoKit
#if canImport(UIKit)
import UIKit
#endif

/// Three-bucket review queue (same contract as macOS and the web app).
struct ContentView: View {
    @EnvironmentObject var model: ReviewSession
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .idle:
                    idle
                case .scanning:
                    ProgressView("Reading contacts…")
                case .matching(let done, let total):
                    ProgressView("Matching brands… \(done)/\(total)")
                case .review:
                    ReviewQueueView()
                case .applying:
                    ProgressView("Applying approved logos…")
                }
            }
            .navigationTitle("ContactLogo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Every element here must be ToolbarContent; a bare Button makes
                // toolbar(content:) ambiguous against its View overload.
                if model.stage == .idle || model.stage == .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Scan") { Task { await model.scanAndMatch() } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Brand icons for your address book.  Review every logo before it is written.")
                .foregroundStyle(.secondary)
            if AddressBookVisibilityNotice.applies(to: model) {
                AddressBookVisibilityNotice()
            }
            if case .scanFailed(let underlying) = model.lastError {
                Label("The last scan failed (\(underlying)). Tap Scan contacts to try again.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            Label("Ready to apply (\(model.autoAccepted.count))", systemImage: "checkmark.circle.fill")
            Label("Needs review (\(model.needsReview.count))", systemImage: "questionmark.circle")
            Label("Not found (\(model.notFound.count))", systemImage: "minus.circle")
            if model.totalScannedCount > 0 {
                ScanBreakdownRow(
                    scanned: model.totalScannedCount,
                    business: model.businessTargetsCount,
                    affiliated: model.affiliatedTargetsCount,
                    protected: model.protectedPersonCount
                )
            }
            Button("Scan contacts") { Task { await model.scanAndMatch() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 2026-09-27 — one honest notice for a small visible address book.
///
/// The three earlier notices (`.definite` / `.heuristic` / bool fallback)
/// all named the same single cause — a limited-access grant — and the same
/// single fix.  That is wrong for a user whose business contacts live in a
/// Google or Exchange account that is not syncing Contacts to the device:
/// they have full access, the OS says `.authorized`, the device database
/// really does only hold a handful of entries, and "select All Contacts"
/// fixes nothing.  That is exactly the loop the owner was stuck in ("still
/// only 22"), so the copy now names both causes and both Settings paths.
///
/// 2026-09-27 follow-up — the two causes are no longer just described side
/// by side, they are *told apart*, because the app can tell them apart on
/// iOS 18+.  When iOS reports full access, "All Contacts" is not offered at
/// all, because it cannot work.  Offering a fix that provably cannot change
/// the number is what made this look like a broken app.
struct AddressBookVisibilityNotice: View {
    @EnvironmentObject var model: ReviewSession

    /// What the app can actually prove about the tiny address book.
    private enum Diagnosis: Equatable {
        /// iOS reported a limited grant, so All Contacts is the real fix.
        case limitedGrant
        /// iOS reported full access, so the contacts are simply not on the
        /// device and Contacts Sync is the real fix.
        case notSyncedToDevice
        /// The OS does not expose enough to tell the two apart (pre-iOS 18).
        case cannotTell
        /// Access was refused, so nothing can be scanned until it is granted.
        case notAuthorized
    }

    private var looksSmall: Bool {
        let visible = model.visibleContactCount
        return visible > 0 && visible < LimitedAccessState.smallAddressBookThreshold
    }

    /// Shown when the app can see a suspiciously small address book, or when
    /// iOS reports a limited grant outright.
    static func applies(to model: ReviewSession) -> Bool {
        switch model.limitedAccessState {
        case .definite, .heuristic, .denied, .restricted, .fullAccessSmallDatabase:
            return true
        case .open:
            return model.visibleContactCount > 0
                && model.visibleContactCount < LimitedAccessState.smallAddressBookThreshold
        }
    }

    private var visible: String {
        let n = model.visibleContactCount
        guard n > 0 else { return "a very small number of" }
        return "\(n.formatted())"
    }

    private var diagnosis: Diagnosis {
        switch model.limitedAccessState {
        case .definite: return .limitedGrant
        case .denied, .restricted: return .notAuthorized
        // Pre-iOS 18 has no `.limited` signal at all, so a small book could
        // be either cause.  Say so rather than guessing.
        case .heuristic: return .cannotTell
        case .fullAccessSmallDatabase, .open: return .notSyncedToDevice
        }
    }

    private var headline: String {
        switch diagnosis {
        case .limitedGrant: return "Limited contacts access"
        case .notSyncedToDevice: return "Contacts aren't syncing to this iPhone"
        case .cannotTell: return "Address book looks incomplete"
        case .notAuthorized: return "ContactLogo has no access to Contacts"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(headline, systemImage: "person.crop.circle.badge.exclamationmark.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(explanation)
                .font(.subheadline)
            Text(fix)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "arrow.up.right.square.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var explanation: String {
        switch diagnosis {
        case .limitedGrant:
            return "ContactLogo was allowed to read only some of your contacts, so the database it can reach holds \(visible) entries. Every logo it can offer has to come from there, so the scan is capped at that number."
        case .notSyncedToDevice:
            return "ContactLogo has full access to Contacts, and the Contacts database on this iPhone holds only \(visible) entries. The business contacts you keep elsewhere simply aren't in it, so a scan cannot return more than that. This is not a permissions problem and ContactLogo is not filtering them out."
        case .cannotTell:
            return "ContactLogo reads the Contacts database on this iPhone, and it currently holds only \(visible) entries. Every logo it can offer has to come from there, so the scan is capped at that number no matter how many business contacts you keep elsewhere."
        case .notAuthorized:
            return "ContactLogo has not been allowed to read your Contacts, so there is nothing to scan yet."
        }
    }

    private var fix: String {
        switch diagnosis {
        case .limitedGrant:
            return "Fix:  Settings → ContactLogo → Contacts → All Contacts."
        case .notSyncedToDevice:
            return "Fix:  Settings → [Google / Exchange account] → Contacts → Sync Contacts.  Your access is already full, so changing ContactLogo's Contacts setting will not raise the number."
        case .cannotTell:
            return "Two different causes, two different fixes.  1.  Limited access was granted — Settings → ContactLogo → Contacts → All Contacts.  2.  Contacts Sync is off for the account that holds them — Settings → [Google / Exchange account] → Contacts → Sync Contacts.  If your business contacts live in Google or Exchange, this is usually the one."
        case .notAuthorized:
            return "Fix:  Settings → ContactLogo → Contacts → Allow Full Access."
        }
    }
}

/// Bottom-of-idle scan breakdown so a user can tell at a glance whether
/// the address book was actually scanned (vs. an empty `.limited` subset)
/// and how the 15k contacts split across business / affiliated / personal.
struct ScanBreakdownRow: View {
    let scanned: Int
    let business: Int
    let affiliated: Int
    let protected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last scan breakdown")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(scanned.formatted()) contacts scanned · \(business.formatted()) business · \(affiliated.formatted()) affiliated · \(protected.formatted()) personal protected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

struct ReviewQueueView: View {
    @EnvironmentObject var model: ReviewSession
    @State private var bucket: ReviewSession.Bucket = .auto
    @State private var searchText = ""
    @State private var previewResult: MatchResult?
    @State private var manualOverrideResult: MatchResult?
    @State private var showError = false

    var rows: [MatchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            switch bucket {
            case .auto: return model.autoAccepted
            case .review: return model.needsReview
            case .notFound: return model.notFound
            }
        }
        // Search spans every tab.  Filtering only the selected tab (default
        // Ready) hid every Review / Not found row from search, which read as
        // "search only finds the same ~25 contacts".
        let query = trimmed.lowercased()
        return model.results.filter { result in
            let name = model.displayName(for: result.contactID).lowercased()
            let flags = result.flags.joined(separator: " ").lowercased()
            return name.contains(query) || flags.contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if AddressBookVisibilityNotice.applies(to: model) {
                AddressBookVisibilityNotice()
                    .padding(.horizontal)
            }
            if case .scanIncomplete(let matched, let total) = model.lastError {
                Label("Scan stopped early: matched \(matched) of \(total). Tap Scan to finish.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }
            if model.totalScannedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkmark.fill")
                        .foregroundColor(.green)
                    Text("\(model.totalScannedCount) scanned · \(model.protectedPersonCount) personal protected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.affiliatedTargetsCount > 0 {
                        Text("· \(model.affiliatedTargetsCount) affiliated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            Picker("Bucket", selection: $bucket) {
                Text("Ready (\(model.autoAccepted.count))").tag(ReviewSession.Bucket.auto)
                Text("Review (\(model.needsReview.count))").tag(ReviewSession.Bucket.review)
                Text("Not found (\(model.notFound.count))").tag(ReviewSession.Bucket.notFound)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            HStack {
                Button("Select high") { model.selectHigh(true) }
                Button("Clear") { model.selectHigh(false) }
                Spacer()
                Button("Apply") { Task { await model.applySelected() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            undoHistoryRow
            List(rows, id: \.contactID) { result in
                ReviewRow(result: result, onPreview: {
                    previewResult = result
                }, onManualOverride: {
                    manualOverrideResult = result
                })
                .swipeActions(edge: .leading) {
                    Button {
                        model.setSelected(result.contactID, true)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    if result.isRetryable {
                        Button {
                            Task { await model.retryMatch(for: result.contactID) }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .tint(.orange)
                    } else if result.candidates.count > 1 {
                        Button {
                            model.cycleCandidate(result.contactID)
                        } label: {
                            Label("Next logo", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.orange)
                    }
                    Button(role: .destructive) {
                        model.setSelected(result.contactID, false)
                    } label: {
                        Label("Skip", systemImage: "xmark")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search all tabs…")
        }
        .sheet(item: $previewResult) { result in
            ContactSimulatorSheet(result: result)
        }
        .sheet(item: $manualOverrideResult) { result in
            ManualOverrideSheet(contactID: result.contactID)
        }
        .onChange(of: model.lastError) { _, newValue in
            showError = newValue != nil
        }
        .alert("ContactLogo", isPresented: $showError, presenting: model.lastError) { _ in
            Button("OK") {}
        } message: { error in
            Text(errorMessage(error))
        }
    }

    @ViewBuilder
    private var undoHistoryRow: some View {
        if let mostRecent = model.undoHistory.first {
            HStack {
                Button("Undo last batch") {
                    Task { await model.undo(batchID: mostRecent.id) }
                }
                if model.undoHistory.count > 1 {
                    Menu("History (\(model.undoHistory.count))") {
                        ForEach(model.undoHistory) { batch in
                            Button {
                                Task { await model.undo(batchID: batch.id) }
                            } label: {
                                Text("\(batch.contactCount) contact\(batch.contactCount == 1 ? "" : "s") — \(batch.createdAt.formatted(.relative(presentation: .named)))")
                            }
                        }
                    }
                }
                Spacer()
            }
            .font(.footnote)
            .padding(.horizontal)
        }
    }

    private func errorMessage(_ error: ReviewSessionError) -> String {
        switch error {
        case .applyFailed(let succeeded, let failed, let underlying):
            return "\(failed) of \(succeeded + failed) logos failed to apply (\(underlying))."
        case .nothingToApply:
            return "Nothing selected to apply."
        case .undoFailed(let batchID, let underlying):
            return "Couldn't undo batch \(batchID.prefix(8)) (\(underlying)). You can try again."
        case .noBatchToUndo:
            return "There's no batch to undo."
        case .scanFailed(let underlying):
            return "The scan failed (\(underlying)). Tap Scan to try again."
        case .scanIncomplete(let matched, let total):
            return "The scan stopped early: matched \(matched) of \(total). Showing what finished. Tap Scan to run it again."
        }
    }
}

extension MatchResult: @retroactive Identifiable {
    public var id: String { contactID }
}

struct ReviewRow: View {
    @EnvironmentObject var model: ReviewSession
    let result: MatchResult
    var onPreview: (() -> Void)? = nil
    var onManualOverride: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(result.contactID) },
                set: { model.setSelected(result.contactID, $0) }
            ))
            .labelsHidden()
            .disabled(result.candidates.isEmpty)
            Button {
                onPreview?()
            } label: {
                LogoThumb(url: model.chosenCandidate(for: result)?.imageURL)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName(for: result.contactID)).font(.headline)
                    if result.flags.contains("affiliated") {
                        Text("Affiliated")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if result.isRetryable {
                        RetryableBadge()
                    }
                    Spacer()
                    Button {
                        onPreview?()
                    } label: {
                        Image(systemName: "iphone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if let exhausted = result.exhaustedLabel {
                    Text(exhausted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !result.isRetryable {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if result.isRetryable {
                        if model.retryingIDs.contains(result.contactID) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Retry") {
                                Task { await model.retryMatch(for: result.contactID) }
                            }
                            .font(.caption)
                        }
                    } else if result.candidates.count > 1 {
                        Button("Try another") { model.cycleCandidate(result.contactID) }
                            .font(.caption)
                        Text("(\((model.chosenIndex[result.contactID] ?? 0) + 1)/\(result.candidates.count))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button("Choose your own…") { onManualOverride?() }
                        .font(.caption)
                }
            }
        }
    }

    private var detail: String {
        let source = model.chosenCandidate(for: result)?.source.rawValue ?? "none"
        let flags = result.flags.isEmpty ? "" : " · " + result.flags.joined(separator: ", ")
        return "\(label(result.confidence)) · \(source)\(flags)"
    }

    private func label(_ c: Confidence) -> String {
        switch c {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .skip: "skip"
        }
    }
}

/// Web `card--exhausted` treatment for a retryable skip row. Icon-only so
/// the action copy stays the web/native word "Retry", not a third bucket.
struct RetryableBadge: View {
    var body: some View {
        Image(systemName: "arrow.clockwise.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

struct ContactSimulatorSheet: View {
    @EnvironmentObject var model: ReviewSession
    @Environment(\.dismiss) var dismiss
    let result: MatchResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Live iOS Simulation")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top)

                    // Incoming Call Banner Simulation
                    VStack(spacing: 12) {
                        Text("INCOMING CALL").font(.caption2.bold()).foregroundStyle(.secondary)
                        LogoThumb(url: model.chosenCandidate(for: result)?.imageURL)
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                        Text(model.displayName(for: result.contactID))
                            .font(.title3.bold())
                        Text("mobile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 40) {
                            Circle().fill(Color.red).frame(width: 54, height: 54)
                                .overlay(Image(systemName: "phone.down.fill").foregroundStyle(.white))
                            Circle().fill(Color.green).frame(width: 54, height: 54)
                                .overlay(Image(systemName: "phone.fill").foregroundStyle(.white))
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // iMessage Header Simulation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iMESSAGE HEADER").font(.caption2.bold()).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            LogoThumb(url: model.chosenCandidate(for: result)?.imageURL)
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName(for: result.contactID))
                                    .font(.subheadline.bold())
                                Text("Verified Business")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "video.fill").foregroundStyle(.blue)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle(model.displayName(for: result.contactID))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct LogoThumb: View {
    let url: URL?
    @State private var decodedDataImage: UIImage?

    var body: some View {
        Group {
            if let url {
                if url.scheme == "data" {
                    if let decodedDataImage {
                        Image(uiImage: decodedDataImage).resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            placeholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            placeholder
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 52, height: 52)
        .background(Color.gray.opacity(0.08))
        .clipShape(Circle())
        .task(id: url) {
            await loadDataImageIfNeeded()
        }
    }

    // Decodes data: URLs once per distinct `url` (cached in state) instead
    // of synchronously re-decoding base64 on every body evaluation.
    private func loadDataImageIfNeeded() async {
        guard let url, url.scheme == "data" else {
            if decodedDataImage != nil { decodedDataImage = nil }
            return
        }
        // Only `Data` crosses the actor boundary — UIImage is not Sendable, so
        // constructing it inside the detached task and returning it is a Swift 6
        // concurrency error.  The base64 decode is the expensive part and still
        // happens off the main actor.
        let payload = url
        let raw = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: payload)
        }.value
        if let raw {
            decodedDataImage = UIImage(data: raw)
        } else {
            decodedDataImage = nil
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 2026-09-21 follow-up — a "Why am I only seeing X contacts?" Diagnostic
/// screen.  Shows the authorization state, the breakdown, and a sample of
/// the dropped contacts with the reason each was skipped.  Read-only; no
/// settings to change here.  Accessed from the Settings sheet.
struct DiagnosticView: View {
    @EnvironmentObject var model: ReviewSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Authorization") {
                    HStack {
                        Text("State")
                        Spacer()
                        Text(authStateText)
                            .foregroundStyle(authStateColor)
                    }
                    HStack {
                        Text("In this device's Contacts database")
                        Spacer()
                        Text(visibleContactsText)
                            .foregroundStyle(model.visibleContactCount > 0
                                             && model.visibleContactCount < LimitedAccessState.smallAddressBookThreshold
                                             ? .orange : .secondary)
                    }
                }
                if model.visibleContactCount > 0
                    && model.visibleContactCount < LimitedAccessState.smallAddressBookThreshold {
                    Section("Why the scan is capped") {
                        Text("ContactLogo can only offer logos for contacts that are in the Contacts database on this iPhone. That database currently holds \(model.visibleContactCount.formatted()) entries, so a scan cannot return more than that.")
                            .font(.caption)
                        if model.limitedAccessState.isGenuineLimitedGrant {
                            Text("You granted limited access, so only the contacts you selected are visible. Switch to All Contacts in Settings → ContactLogo → Contacts.")
                                .font(.caption)
                        } else {
                            Text("Your access is full, so the contacts are not reaching this iPhone. If your business contacts live in Google or Exchange rather than on the phone, the database is small because Contacts Sync is off for that account — not because ContactLogo is filtering them. Turn it on in Settings → [account] → Contacts.")
                                .font(.caption)
                        }
                    }
                }
                Section("Last scan") {
                    LabeledContent("Scanned", value: "\(model.totalScannedCount)")
                    LabeledContent("Business cards", value: "\(model.businessTargetsCount)")
                    LabeledContent("Affiliated", value: "\(model.affiliatedTargetsCount)")
                    LabeledContent("Personal protected", value: "\(model.protectedPersonCount)")
                }
                if !model.sampleDroppedContacts.isEmpty {
                    Section("Sample of dropped contacts (max 20)") {
                        ForEach(model.sampleDroppedContacts) { sample in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.displayName.isEmpty ? "(unnamed contact)" : sample.displayName)
                                    .font(.subheadline.bold())
                                Text(sample.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let org = sample.organization, !org.isEmpty {
                                    Text("Org: \(org)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section("How matching works") {
                    Text("ContactLogo is review-first, so a contact is only marked as a logo target when a brand can be inferred confidently. The engine treats as a business card: a given-only brand name, a contact whose name OR organization field matches the CompanyCatalog, or a contact with brand-tail decoration (e.g. 'Maya Chen - Texas Instruments'). Personal contacts with no organization, no work email, and no brand-tail are protected — adding a brand to someone's headshot is the wrong-logo outcome the product exists to prevent.")
                        .font(.caption)
                }
            }
            .navigationTitle("Diagnostic")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var visibleContactsText: String {
        guard model.visibleContactCount > 0 else { return "unknown" }
        return model.visibleContactCountIsExact
            ? model.visibleContactCount.formatted()
            : "\(model.visibleContactCount.formatted())+"
    }

    private var authStateText: String {
        switch model.limitedAccessState {
        case .open: return model.limitedAccessGranted ? "Detected limited (heuristic)" : "Full access"
        case .definite: return "Limited (iOS 18)"
        // 2026-09-27 — full access is a *good* state and the reason the
        // book is small is upstream.  Labelling it "likely limited" is what
        // kept pointing the owner at the All Contacts toggle.
        case .fullAccessSmallDatabase: return "Full access — small database"
        case .heuristic: return "Likely limited (heuristic)"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        }
    }

    private var authStateColor: any ShapeStyle {
        switch model.limitedAccessState {
        case .open where model.limitedAccessGranted: return AnyShapeStyle(.orange)
        case .definite, .heuristic: return AnyShapeStyle(.orange)
        // Access is fine; the database is the problem, so keep it green.
        case .fullAccessSmallDatabase, .open: return AnyShapeStyle(.green)
        case .denied, .restricted: return AnyShapeStyle(.red)
        }
    }
}
