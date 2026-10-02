import SwiftUI
import ContactLogoKit
#if canImport(AppKit)
import AppKit
#endif

/// Three-bucket review layout (VISION: Auto / Review / Not-found).
/// Approve / try-another / upload / skip actions live on each row.
struct ContentView: View {
    @EnvironmentObject var model: ReviewSession

    var body: some View {
        NavigationSplitView {
            List(selection: $model.bucket) {
                Label("Ready to apply (\(model.autoAccepted.count))", systemImage: "checkmark.circle.fill")
                    .tag(ReviewSession.Bucket.auto)
                Label("Needs review (\(model.needsReview.count))", systemImage: "questionmark.circle")
                    .tag(ReviewSession.Bucket.review)
                Label("Not found (\(model.notFound.count))", systemImage: "minus.circle")
                    .tag(ReviewSession.Bucket.notFound)
            }
            .navigationTitle("ContactLogo")
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                switch model.stage {
                case .idle:
                    ContentUnavailableView("Scan your contacts",
                                           systemImage: "person.crop.square.filled.and.at.rectangle",
                                           description: Text("ContactLogo finds brand logos for the businesses in your address book — you approve every change."))
                    if case .definite = model.limitedAccessState {
                        MacLimitedAccessBlocker()
                    } else if case .heuristic(let count) = model.limitedAccessState {
                        MacLimitedAccessHeuristicNotice(visibleCount: count)
                    } else if case .fullAccessSmallDatabase(let count) = model.limitedAccessState {
                        MacContactsNotSyncedNotice(visibleCount: count)
                    } else if model.limitedAccessGranted {
                        LimitedAccessBanner()
                    }
                    Button("Scan contacts") { Task { await model.scanAndMatch() } }
                        .buttonStyle(.borderedProminent)
                    if model.totalScannedCount > 0 {
                        MacScanBreakdown(
                            scanned: model.totalScannedCount,
                            business: model.businessTargetsCount,
                            affiliated: model.affiliatedTargetsCount,
                            protected: model.protectedPersonCount
                        )
                    }
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
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 2026-09-20 audit — surfaces Apple `.limited` Contacts access on macOS.
struct LimitedAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Limited contacts access", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("ContactLogo can only see the contacts you chose.  Open System Settings → Privacy & Security → Contacts to grant full access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption.bold())
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// macOS idle scan breakdown — same shape as the iOS card, no UIKit import.
struct MacScanBreakdown: View {
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
    @State private var searchText = ""
    @State private var inspectedResult: MatchResult?
    @State private var manualOverrideResult: MatchResult?
    @State private var showError = false

    var rows: [MatchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            switch model.bucket {
            case .auto: return model.autoAccepted
            case .review: return model.needsReview
            case .notFound: return model.notFound
            }
        }
        // Search spans every tab, not just the selected one.
        let query = trimmed.lowercased()
        return model.results.filter { result in
            let name = model.displayName(for: result.contactID).lowercased()
            let flags = result.flags.joined(separator: " ").lowercased()
            return name.contains(query) || flags.contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .definite = model.limitedAccessState {
                MacLimitedAccessBlocker()
            } else if case .heuristic(let count) = model.limitedAccessState {
                MacLimitedAccessHeuristicNotice(visibleCount: count)
            } else if case .fullAccessSmallDatabase(let count) = model.limitedAccessState {
                MacContactsNotSyncedNotice(visibleCount: count)
            } else if model.limitedAccessGranted {
                LimitedAccessBanner()
            }
            HStack {
                Text("Review queue").font(.title2.bold())
                Spacer()
                Button("Select high") { model.selectHigh(true) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Clear high") { model.selectHigh(false) }
                Button("Apply selected (\(model.selected.count))") { Task { await model.applySelected() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                if let mostRecent = model.undoHistory.first {
                    Button("Undo last batch") { Task { await model.undo(batchID: mostRecent.id) } }
                        .keyboardShortcut("z", modifiers: .command)
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
                    .fixedSize()
                }
            }
            if model.totalScannedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkmark.fill")
                        .foregroundColor(.green)
                    Text("\(model.totalScannedCount) contacts scanned · \(model.protectedPersonCount) personal contacts protected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if model.affiliatedTargetsCount > 0 {
                        Text("· \(model.affiliatedTargetsCount) affiliated (opt-in)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("High-confidence business matches are pre-checked. Personal contacts with company affiliations, favicon fallbacks, and guessed domains stay in Needs review.")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 560), spacing: 14)], spacing: 14) {
                    ForEach(rows, id: \.contactID) { result in
                        ReviewRow(result: result, onInspect: {
                            inspectedResult = result
                        }, onManualOverride: {
                            manualOverrideResult = result
                        })
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .searchable(text: $searchText, prompt: "Search all tabs…")
        }
        .sheet(item: $inspectedResult) { result in
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
            return "The scan failed (\(underlying)). Click Scan to try again."
        case .scanIncomplete(let matched, let total):
            return "The scan stopped early: matched \(matched) of \(total). Showing what finished. Click Scan to run it again."
        }
    }
}

extension MatchResult: @retroactive Identifiable {
    public var id: String { contactID }
}

struct ReviewRow: View {
    @EnvironmentObject var model: ReviewSession
    let result: MatchResult
    var onInspect: (() -> Void)? = nil
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
                    onInspect?()
                } label: {
                    LogoThumb(url: model.chosenCandidate(for: result)?.imageURL)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Button {
                            onInspect?()
                        } label: {
                            Text(model.displayName(for: result.contactID))
                                .font(.headline)
                                .foregroundStyle(.primary)
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
                            onInspect?()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inspect details")
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

                    HStack(spacing: 10) {
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
                        Button("Details") { onInspect?() }
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
    }

    private var candidateStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Candidates (\(result.candidates.count)):")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click to select")
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
        .padding(.leading, 36)
    }

    private var detail: String {
        let source = model.chosenCandidate(for: result)?.source.displayName ?? "none"
        let flags = result.flags.isEmpty ? "" : " · " + result.flags.joined(separator: ", ")
        return "\(label(result.confidence)) · \(source) · \(result.candidates.count) options\(flags)"
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
                VStack(spacing: 18) {
                    headerCard
                    candidateGallerySection
                    contactInfoSection
                    matchingRationaleSection
                }
                .padding()
            }
            .navigationTitle(model.displayName(for: result.contactID))
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
        .frame(minWidth: 500, minHeight: 550)
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    model.setChosenIndex(result.contactID, idx)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .topTrailing) {
                                        LogoThumb(url: candidate.imageURL)
                                            .frame(width: 60, height: 60)
                                            .background(Color.gray.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isChosen ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isChosen ? 3 : 1)
                                            )
                                        if isChosen {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.accentColor)
                                                .background(Circle().fill(Color.white))
                                                .offset(x: 4, y: -4)
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
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var actionBar: some View {
        let isSelected = model.selected.contains(result.contactID)
        return HStack(spacing: 12) {
            Button {
                model.setSelected(result.contactID, !isSelected)
            } label: {
                Label(isSelected ? "Approved" : "Approve", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSelected ? .green : .accentColor)
            .disabled(result.candidates.isEmpty)

            Button(role: .destructive) {
                model.setSelected(result.contactID, false)
                dismiss()
            } label: {
                Label("Skip", systemImage: "xmark.circle")
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .trailing)
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

struct LogoThumb: View {
    let url: URL?
    @State private var decodedDataImage: NSImage?

    var body: some View {
        Group {
            if let url {
                if url.scheme == "data" {
                    if let decodedDataImage {
                        Image(nsImage: decodedDataImage).resizable().scaledToFit()
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
        .frame(width: 56, height: 56)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        // Only `Data` crosses the actor boundary — NSImage is not Sendable, so
        // constructing it inside the detached task and returning it is a Swift 6
        // concurrency error.  The base64 decode is the expensive part and still
        // happens off the main actor.
        let payload = url
        let raw = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: payload)
        }.value
        if let raw {
            decodedDataImage = NSImage(data: raw)
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

/// 2026-09-21 follow-up — macOS blocking call to action when Limited
/// contacts access is detected.  Same shape as the iOS blocker but with
/// a System Settings deep-link to Privacy & Security → Contacts.
struct MacLimitedAccessBlocker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Limited contacts access detected", systemImage: "person.crop.circle.badge.exclamationmark.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("ContactLogo is set to 'Only selected contacts'. To scan your full address book, open System Settings → Privacy & Security → Contacts and select 'All Contacts' for ContactLogo.")
                .font(.subheadline)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open System Settings", systemImage: "arrow.up.right.square.fill")
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
}

/// 2026-09-21 — pre-macOS-14 / pre-iOS-18 fallback when the OS is silent
/// about Limited.  Soft warning + the same fix instructions.
struct MacLimitedAccessHeuristicNotice: View {
    let visibleCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Only \(visibleCount) contacts are visible", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("ContactLogo scanned your address book and only found \(visibleCount) entries. If you granted Limited access in System Settings, only the contacts you selected are visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption.bold())
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 2026-09-27 — the Contacts authorization is full, but the address book on
/// this Mac is small.  Previously this reported itself as a limited grant
/// and pointed at Privacy & Security → Contacts → All Contacts, which
/// cannot change anything when access is already full.  The contacts are
/// simply not in the Mac's Contacts database — usually because they live in
/// a Google / Exchange account whose Contacts sync is off.
struct MacContactsNotSyncedNotice: View {
    let visibleCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Only \(visibleCount) contacts are on this Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("ContactLogo has full access to Contacts, and the Contacts database on this Mac holds \(visibleCount) entries. Contacts you keep in Google or Exchange are not in it, so a scan cannot return more than that. Your access is already full, so changing the Contacts permission will not raise the number.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Fix:  System Settings → [Google / Exchange account] → Contacts → Sync Contacts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption.bold())
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView().environmentObject(ReviewSession())
}
