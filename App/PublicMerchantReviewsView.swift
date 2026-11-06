import SwiftUI

@MainActor struct PublicMerchantReviewsView: View {
    let target: PublicMerchantReviewTarget
    let reader: any PublicMerchantReviewReading
    var imageReader: any RetainedPublicImageReading = RetainedPublicImageReader()
    var writes: PublicMerchantReviewWriteContext? = nil
    @State private var loadedRows = PublicMerchantReviewRows()
    private var itemPages: [Int: Int] { loadedRows.pages }
    @State private var snapshot: PublicMerchantReviewPage?
    private var items: [PublicMerchantReviewPage.Item] { loadedRows.items }
    @State private var reviewFilter: PublicMerchantReviewFilter = .all
    @State private var loading = false
    @State private var failure: PublicMerchantHomeFailure?
    @State private var failedPage = 1
    @State private var generation = 0
    @State private var loadedKey: Key?
    private struct Key: Hashable { let target: PublicMerchantReviewTarget; let scope: UUID }
    private var key: Key { .init(target: target, scope: reader.scope) }
    // Retain the original loaded offset when filtering. A matching row must keep
    // its photo selection and report target rather than inherit a different row's state.
    private var visibleItems: [(offset: Int, element: PublicMerchantReviewPage.Item)] {
        items.enumerated().filter { reviewFilter.matches($0.element) }
    }
    var body: some View {
        List {
            if !reader.isConfigured { Text("merchant.publicHome.notConfigured") }
            else {
                if reader.isOfflineExample { Text("merchant.publicHome.synthetic").font(.footnote) }
                Text(writes == nil ? "merchant.publicHome.reviewsReadOnly" : "merchant.publicHome.reviewBoundary").font(.footnote)
                if loadedKey == key, let snapshot {
                    Section("merchant.publicHome.summary") {
                        LabeledContent("merchant.publicHome.total", value: String(snapshot.total))
                            .accessibilityIdentifier("merchant.publicHome.total")
                        if let rating = snapshot.averageRating {
                            LabeledContent("merchant.publicHome.rating", value: String(format: "%.1f", rating))
                                .accessibilityIdentifier("merchant.publicHome.rating")
                        }
                        // Do not infer an authenticated action from a public read or start an upload/provider.
                        Text("merchant.publicHome.reviewBoundary").font(.footnote)
                    }
                    if let writes, snapshot.eligibility.canCreate, let registration = snapshot.eligibility.registrationId {
                        NavigationLink("merchant.publicHome.createReview") {
                            PublicMerchantReviewEditor(target: target, registrationID: registration, context: writes)
                        }.accessibilityIdentifier("merchant.publicHome.createReview")
                    }
                    Section {
                        Picker("merchant.publicHome.reviewFilter", selection: $reviewFilter) {
                            ForEach(PublicMerchantReviewFilter.allCases, id: \.self) { filter in
                                Text(LocalizedStringKey("merchant.publicHome.reviewFilter." + filter.rawValue)).tag(filter)
                            }
                        }.pickerStyle(.menu).accessibilityIdentifier("merchant.publicHome.reviewFilter")
                        Text("merchant.publicHome.reviewFilterScope").font(.footnote).foregroundStyle(.secondary)
                        if reviewFilter != .all {
                            Button("merchant.publicHome.clearReviewFilter") { reviewFilter = .all }
                                .accessibilityIdentifier("merchant.publicHome.clearReviewFilter")
                        }
                    }
                    if items.isEmpty {
                        Text("merchant.publicHome.noReviews").accessibilityIdentifier("merchant.publicHome.noReviews")
                    } else if visibleItems.isEmpty {
                        Text("merchant.publicHome.noMatchingReviews").accessibilityIdentifier("merchant.publicHome.noMatchingReviews")
                    }
                    ForEach(visibleItems, id: \.offset) { _, item in
                        Section {
                            HStack(alignment: .top, spacing: Theme.Space.s3) {
                                Group {
                                    if let first = item.authorNickname?.first { Text(String(first)).font(.title3.weight(.semibold)) }
                                    else { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                                }.frame(width: 44, height: 44)
                                    .background(Theme.Color.bgRaised(in: .merchant), in: Circle()).accessibilityHidden(true)
                                Group { if let name = item.authorNickname, !name.isEmpty { Text(verbatim: name) } else { Text("merchant.publicHome.player") } }
                                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                            }
                                // Keep the review ID on its heading, not on the Section: List
                                // section identifiers can override the nested Report action ID.
                                .accessibilityIdentifier("merchant.publicHome.review.\(item.id)")
                            LabeledContent("merchant.publicHome.rating", value: "\(item.rating) / 5")
                            if item.verifiedRedemption { Label("merchant.publicHome.verified", systemImage: "checkmark.seal") }
                            if let content = item.content { Text(verbatim: content).textSelection(.enabled) }
                            if let time = item.createTime { Text(verbatim: time).font(.caption) }
                            RetainedPublicReviewImages(urls: item.imageUrls, reader: imageReader)
                            if item.canReport, let writes, let page = itemPages[item.id] {
                                NavigationLink("merchant.publicHome.report") {
                                    PublicMerchantReviewEditor(target: target, reportItem: item, page: page, context: writes)
                                }.accessibilityIdentifier("merchant.publicHome.report.\(item.id)")
                            }
                            if let reply = item.merchantReply, !reply.isEmpty {
                                LabeledContent("merchant.publicHome.reply", value: reply)
                                if let time = item.repliedAt { Text(verbatim: time).font(.caption) }
                            }
                        }
                    }
                    if snapshot.hasMore, failure == nil {
                        Button("merchant.publicHome.more") { Task { await load(page: snapshot.pageNum + 1) } }.disabled(loading).accessibilityIdentifier("merchant.publicHome.more")
                    }
                }
                if let failure {
                    MerchantM02Notice(message: Text(LocalizedStringKey(failure.localizationKey)), symbol: "exclamationmark.circle", isError: true)
                    Button("merchant.publicHome.retry") { Task { await load(page: failedPage) } }.disabled(loading).accessibilityIdentifier("merchant.publicHome.retry")
                }
                if loading { ProgressView("merchant.publicHome.loading") }
            }
        }
        .merchantM02Page()
        .navigationTitle("merchant.publicHome.reviews")
        .task(id: key) { await load(page: 1) }
        // Pushing the editor must not delete the NavigationLink that owns it.
        // loadedKey == key still hides every retained row after a target/session change.
        .onDisappear { generation += 1; loading = false }
    }
    private func load(page: Int) async {
        guard reader.isConfigured else { return }
        // A changed scope supersedes an in-flight request; repeated same-scope taps do not.
        if loading && loadedKey == key { return }
        generation += 1; let ticket = generation; let current = key
        if page == 1 {
            // Same-scope refresh keeps the choice; a different merchant or account
            // read scope starts at All before exposing its fresh response.
            if loadedKey != current { reviewFilter = .all }
            snapshot = nil; loadedRows = .init(); loadedKey = current
        }
        loading = true; failure = nil; failedPage = page
        do {
            let result = try await reader.page(target, page: page)
            guard ticket == generation, current == key, !Task.isCancelled else { return }
            snapshot = result
            loadedRows.accept(result)
        } catch {
            guard ticket == generation, current == key, !Task.isCancelled else { return }
            failure = (error as? PublicMerchantHomeFailure) ?? .retryable
        }
        guard ticket == generation, current == key, !Task.isCancelled else { return }
        loadedKey = current; loading = false
    }
}
