import SwiftUI

@MainActor struct PublicMerchantReviewsView: View {
    let target: PublicMerchantReviewTarget
    let reader: any PublicMerchantReviewReading
    var imageReader: any RetainedPublicImageReading = RetainedPublicImageReader()
    var writes: PublicMerchantReviewWriteContext? = nil
    @State private var itemPages: [Int: Int] = [:]
    @State private var snapshot: PublicMerchantReviewPage?
    @State private var items: [PublicMerchantReviewPage.Item] = []
    @State private var loading = false
    @State private var failure: PublicMerchantHomeFailure?
    @State private var failedPage = 1
    @State private var generation = 0
    @State private var loadedKey: Key?
    private struct Key: Hashable { let target: PublicMerchantReviewTarget; let scope: UUID }
    private var key: Key { .init(target: target, scope: reader.scope) }
    var body: some View {
        List {
            if !reader.isConfigured { Text("merchant.publicHome.notConfigured") }
            else {
                if reader.isOfflineExample { Text("merchant.publicHome.synthetic").font(.footnote) }
                Text(writes == nil ? "merchant.publicHome.reviewsReadOnly" : "merchant.publicHome.reviewBoundary").font(.footnote)
                if loadedKey == key, let snapshot {
                    Section("merchant.publicHome.summary") {
                        LabeledContent("merchant.publicHome.total", value: String(snapshot.total))
                        if let rating = snapshot.averageRating { LabeledContent("merchant.publicHome.rating", value: String(format: "%.1f", rating)) }
                        // Do not infer an authenticated action from a public read or start an upload/provider.
                        Text("merchant.publicHome.reviewBoundary").font(.footnote)
                    }
                    if let writes, snapshot.eligibility.canCreate, let registration = snapshot.eligibility.registrationId {
                        NavigationLink("merchant.publicHome.createReview") {
                            PublicMerchantReviewEditor(target: target, registrationID: registration, context: writes)
                        }.accessibilityIdentifier("merchant.publicHome.createReview")
                    }
                    if items.isEmpty { Text("merchant.publicHome.noReviews").accessibilityIdentifier("merchant.publicHome.noReviews") }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Section {
                            Group { if let name = item.authorNickname, !name.isEmpty { Text(verbatim: name) } else { Text("merchant.publicHome.player") } }.font(.headline)
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
                        }.accessibilityIdentifier("merchant.publicHome.review.\(item.id)")
                    }
                    if snapshot.hasMore, failure == nil {
                        Button("merchant.publicHome.more") { Task { await load(page: snapshot.pageNum + 1) } }.disabled(loading).accessibilityIdentifier("merchant.publicHome.more")
                    }
                }
                if let failure {
                    Text(LocalizedStringKey(failure.localizationKey))
                    Button("merchant.publicHome.retry") { Task { await load(page: failedPage) } }.disabled(loading).accessibilityIdentifier("merchant.publicHome.retry")
                }
                if loading { ProgressView("merchant.publicHome.loading") }
            }
        }
        .navigationTitle("merchant.publicHome.reviews")
        .task(id: key) { await load(page: 1) }
        .onDisappear { generation += 1; snapshot = nil; items = []; itemPages = [:]; loadedKey = nil; loading = false }
    }
    private func load(page: Int) async {
        guard reader.isConfigured else { return }
        // A changed scope supersedes an in-flight request; repeated same-scope taps do not.
        if loading && loadedKey == key { return }
        generation += 1; let ticket = generation; let current = key
        if page == 1 { snapshot = nil; items = []; itemPages = [:]; loadedKey = current }
        loading = true; failure = nil; failedPage = page
        do {
            let result = try await reader.page(target, page: page)
            guard ticket == generation, current == key, !Task.isCancelled else { return }
            snapshot = result
            for item in result.items { itemPages[item.id] = page }
            if page == 1 { items = result.items } else { items.append(contentsOf: result.items) }
        } catch {
            guard ticket == generation, current == key, !Task.isCancelled else { return }
            failure = (error as? PublicMerchantHomeFailure) ?? .retryable
        }
        guard ticket == generation, current == key, !Task.isCancelled else { return }
        loadedKey = current; loading = false
    }
}
