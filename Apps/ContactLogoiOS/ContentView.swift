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
                    protected: model.protectedPersonCount,
                    scannedAt: model.lastScanDate
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
    /// 2026-09-27 — a run that dies before persisting leaves the previous
    /// queue in place, and it is restored on the next launch looking exactly
    /// like a fresh scan.  Stamping the date is what makes that visible.
    let scannedAt: Date?

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last scan breakdown")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(scanned.formatted()) contacts scanned · \(business.formatted()) business · \(affiliated.formatted()) affiliated · \(protected.formatted()) personal protected")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let scannedAt {
                Text("Scanned \(Self.stamp.string(from: scannedAt)) — if this looks stale, the scan did not finish.  Tap Scan contacts to run it again.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

            if horizontalSizeClass == .regular {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360, maximum: 560), spacing: 16)], spacing: 16) {
                        ForEach(rows, id: \.contactID) { result in
                            ReviewRow(result: result, onPreview: {
                                previewResult = result
                            }, onManualOverride: {
                                manualOverrideResult = result
                            })
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .searchable(text: $searchText, prompt: "Search all tabs…")
            } else {
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
        }
        .sheet(item: $previewResult) { result in
            ContactDetailSheet(result: result)
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

    private var identity: ContactIdentity? {
        model.identity(for: result.contactID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    HStack(alignment: .firstTextBaseline) {
                        Button {
                            onPreview?()
                        } label: {
                            Text(model.displayName(for: result.contactID))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)

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
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View contact details and preview")
                    }

                    if let job = identity?.jobTitle, !job.isEmpty {
                        Text(job)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

                    HStack(spacing: 12) {
                        if result.isRetryable {
                            if model.retryingIDs.contains(result.contactID) {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button("Retry") {
                                    Task { await model.retryMatch(for: result.contactID) }
                                }
                                .font(.caption.bold())
                            }
                        }
                        Button("Details") { onPreview?() }
                            .font(.caption)
                        Button("Choose own…") { onManualOverride?() }
                            .font(.caption)
                    }
                    .padding(.top, 2)
                }
            }

            // Candidate Carousel Thumbnail Strip
            if result.candidates.count > 1 {
                candidateStrip
            }
        }
        .padding(.vertical, 2)
    }

    private var candidateStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Candidates (\(result.candidates.count)):")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Tap to select")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(result.candidates.enumerated()), id: \.offset) { idx, candidate in
                        let isChosen = (model.chosenIndex[result.contactID] ?? 0) == idx
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                model.setChosenIndex(result.contactID, idx)
                            }
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                        } label: {
                            VStack(spacing: 3) {
                                ZStack(alignment: .topTrailing) {
                                    LogoThumb(url: candidate.imageURL)
                                        .frame(width: 44, height: 44)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isChosen ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isChosen ? 2.5 : 1)
                                        )
                                    if isChosen {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.accentColor)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 4, y: -4)
                                    }
                                }
                                Text(candidate.source.displayName)
                                    .font(.system(size: 9, weight: isChosen ? .bold : .regular))
                                    .foregroundStyle(isChosen ? Color.accentColor : .secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 56)
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.leading, 40)
    }

    private var detail: String {
        let source = model.chosenCandidate(for: result)?.source.displayName ?? "none"
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

struct ContactDetailSheet: View {
    @EnvironmentObject var model: ReviewSession
    @Environment(\.dismiss) var dismiss
    let result: MatchResult
    @State private var showingManualOverride = false

    private var identity: ContactIdentity? {
        model.identity(for: result.contactID)
    }

    private var chosenCandidate: LogoCandidate? {
        model.chosenCandidate(for: result)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    candidateGallerySection
                    contactInfoSection
                    matchingRationaleSection
                    liveSimulationSection
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
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .sheet(isPresented: $showingManualOverride) {
                ManualOverrideSheet(contactID: result.contactID)
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                LogoThumb(url: chosenCandidate?.imageURL)
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName(for: result.contactID))
                        .font(.title3.bold())
                        .lineLimit(2)

                    if let job = identity?.jobTitle, !job.isEmpty {
                        Text(job)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let org = identity?.organization, !org.isEmpty {
                        Text(org)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    if let dept = identity?.departmentName, !dept.isEmpty {
                        Text(dept)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        confidenceBadge(result.confidence)
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
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var candidateGallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Candidate Logos (\(result.candidates.count))", systemImage: "photo.stack")
                    .font(.headline)
                Spacer()
                Button("Custom image…") {
                    showingManualOverride = true
                }
                .font(.caption.bold())
            }

            if result.candidates.isEmpty {
                Text("No candidate logos found for this contact.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(result.candidates.enumerated()), id: \.offset) { idx, candidate in
                            let isChosen = (model.chosenIndex[result.contactID] ?? 0) == idx
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.setChosenIndex(result.contactID, idx)
                                }
                                #if canImport(UIKit)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .topTrailing) {
                                        LogoThumb(url: candidate.imageURL)
                                            .frame(width: 64, height: 64)
                                            .background(Color.gray.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isChosen ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isChosen ? 3 : 1)
                                            )
                                        if isChosen {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(Color.accentColor)
                                                .background(Circle().fill(Color.white))
                                                .offset(x: 5, y: -5)
                                        }
                                    }

                                    Text(candidate.source.displayName)
                                        .font(.caption.weight(isChosen ? .bold : .regular))
                                        .foregroundStyle(isChosen ? Color.accentColor : .primary)
                                        .lineLimit(1)

                                    if let w = candidate.pixelWidth, let h = candidate.pixelHeight {
                                        Text("\(w)×\(h)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else if let assetType = candidate.assetType {
                                        Text(assetType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(isChosen ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var contactInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Contact Information", systemImage: "person.text.rectangle")
                .font(.headline)

            if let ident = identity {
                if !ident.phoneNumbers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phones").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(ident.phoneNumbers, id: \.self) { phone in
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(phone)
                                    .font(.subheadline)
                                Spacer()
                                let cleaned = phone.replacingOccurrences(of: " ", with: "")
                                if let url = URL(string: "tel:\(cleaned)") {
                                    Link("Call", destination: url)
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }

                if !ident.emails.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emails").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(ident.emails, id: \.self) { email in
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text(email)
                                    .font(.subheadline)
                                Spacer()
                                if let url = URL(string: "mailto:\(email)") {
                                    Link("Mail", destination: url)
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }

                if !ident.urls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Websites").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(ident.urls, id: \.self) { urlString in
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(urlString)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                let dest = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                                if let url = URL(string: dest) {
                                    Link("Open", destination: url)
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }

                if !ident.postalAddresses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Addresses").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(ident.postalAddresses, id: \.self) { address in
                            HStack(alignment: .top) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                    .padding(.top, 2)
                                Text(address)
                                    .font(.subheadline)
                                Spacer()
                                if let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                   let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                                    Link("Map", destination: url)
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("Existing photo on contact:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ident.hasImage ? "Yes" : "No")
                        .font(.caption.bold())
                        .foregroundStyle(ident.hasImage ? .orange : .secondary)
                }
            } else {
                Text("No additional details stored for this contact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var matchingRationaleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Match Rationale", systemImage: "sparkles")
                .font(.headline)

            if !result.flags.isEmpty {
                Text("Engine flags: \(result.flags.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let chosen = chosenCandidate {
                Text("Selected source: \(chosen.source.displayName) (\(chosen.source.rawValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let page = chosen.pageURL {
                    Text("Page: \(page.absoluteString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let exhausted = result.exhaustedLabel {
                Text(exhausted)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var liveSimulationSection: some View {
        VStack(spacing: 16) {
            Text("Live iOS Simulation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Incoming Call Banner Simulation
            VStack(spacing: 12) {
                Text("INCOMING CALL").font(.caption2.bold()).foregroundStyle(.secondary)
                LogoThumb(url: chosenCandidate?.imageURL)
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
                    LogoThumb(url: chosenCandidate?.imageURL)
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

            // Lock Screen Notification Simulation
            VStack(alignment: .leading, spacing: 8) {
                Text("LOCK SCREEN NOTIFICATION").font(.caption2.bold()).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    LogoThumb(url: chosenCandidate?.imageURL)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(model.displayName(for: result.contactID))
                                .font(.caption.bold())
                            Spacer()
                            Text("now")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Your order has been confirmed and is ready for pickup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionBar: some View {
        let isSelected = model.selected.contains(result.contactID)
        return HStack(spacing: 12) {
            Button {
                model.setSelected(result.contactID, !isSelected)
            } label: {
                Label(isSelected ? "Approved" : "Approve", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSelected ? .green : .accentColor)
            .disabled(result.candidates.isEmpty)

            Button(role: .destructive) {
                model.setSelected(result.contactID, false)
                dismiss()
            } label: {
                Label("Skip", systemImage: "xmark.circle")
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func confidenceBadge(_ c: Confidence) -> some View {
        let text: String
        let color: Color
        switch c {
        case .high:
            text = "High Confidence"
            color = .green
        case .medium:
            text = "Medium Confidence"
            color = .orange
        case .low:
            text = "Low Confidence"
            color = .purple
        case .skip:
            text = "Not Found"
            color = .secondary
        }
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

typealias ContactSimulatorSheet = ContactDetailSheet

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
