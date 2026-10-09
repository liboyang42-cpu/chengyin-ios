import SwiftUI

/// Hosts supply a session/region-scoped reader. Default construction cannot access the backend or media.
@MainActor struct PublicMerchantHomeContext {
    var reader: any PublicMerchantHomeReading = DisabledPublicMerchantHomeReader()
    var publicReviews: ((PublicMerchantReviewTarget) -> AnyView)?
    var featured: PublicMerchantFeaturedContext?
    var shopNpcChat = false
    // Correct future consumer: MerchantNpcApi /api/ai/npc/merchant-chat with merchant row ID.
    // Never route this public merchant card into play-node ShopNpc /shop-chat.
    var npcDestination: ((PublicMerchantRowID, PublicMerchantHome.NPC) -> AnyView)?
    // Optional approved renderer; nil always produces an accessible local placeholder.
    var image: ((String) -> AnyView)?
}

@MainActor struct PublicMerchantHomeView: View {
    @Environment(\.locale) private var locale
    let target: PublicMerchantHomeTarget?
    var context = PublicMerchantHomeContext()
    @State private var home: PublicMerchantHome?
    @State private var failure: PublicMerchantHomeFailure?
    @State private var loading = false
    @State private var generation = 0
    @State private var loadedKey: Key?
    @State private var snapshotID = UUID()
    @State private var featuredSelection: PublicMerchantFeaturedSelection?
    private struct Key: Hashable { let target: PublicMerchantHomeTarget?; let scope: UUID; let configured: Bool }
    private var key: Key { .init(target: target, scope: context.reader.scope, configured: context.reader.isConfigured) }
    var body: some View {
        List {
            if target == nil { issue(.invalid) }
            else if !context.reader.isConfigured { issue(.notConfigured) }
            else if loading || loadedKey != key { ProgressView("merchant.publicHome.loading").accessibilityIdentifier("merchant.publicHome.loading") }
            else if let failure { issue(failure) }
            else if let home { profile(home) }
        }
        .navigationTitle("merchant.publicHome.title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await load() }
        .navigationDestination(item: $featuredSelection) { selection in
            if canOpen(selection), let destination = context.featured {
                destination.destination(selection.route)
            } else { Text("merchant.publicHome.unavailable") }
        }
        .onChange(of: key) { _, _ in featuredSelection = nil }
        .onChange(of: context.featured?.scope) { _, _ in featuredSelection = nil }
        // Preserve the link backing a pushed reviews screen; key fencing still hides stale data.
        .onDisappear { generation += 1; loading = false }
    }
    @ViewBuilder private func issue(_ failure: PublicMerchantHomeFailure) -> some View {
        Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier(failure.localizationKey)
        if failure == .retryable {
            Button("merchant.publicHome.retry") { Task { await load() } }.accessibilityIdentifier("merchant.publicHome.retry")
        }
    }
    @ViewBuilder private func profile(_ value: PublicMerchantHome) -> some View {
        if context.reader.isOfflineExample { Text("merchant.publicHome.synthetic").font(.footnote) }
        Section {
            media(value.coverImage, label: "merchant.publicHome.cover")
            media(value.logo, label: "merchant.publicHome.logo")
            Text(value.name?.isEmpty == false ? value.name! : String(localized: LocalizedStringResource("merchant.publicHome.merchant", locale: locale))).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            PublicMerchantHomeBusinessStatusLabel(state: value.businessState)
            field(value.slogan); field(value.cityRole)
            if let categories = value.sysCategoryList {
                ForEach(Array(categories.enumerated()), id: \.offset) { _, category in field(category.categoryName) }
            }
            field(value.address); field(value.businessTime)
        }
        featuredCard(value)
        if let review = value.reviewTarget, let destination = context.publicReviews {
            NavigationLink { destination(review) } label: { Label("merchant.publicHome.reviews", systemImage: "star.bubble") }
                .accessibilityIdentifier("merchant.publicHome.reviews")
        }
        if value.hasNPCIdentity, let npc = value.npc {
            Section("merchant.publicHome.npc") {
                media(npc.avatar, label: "merchant.publicHome.npc")
                field(npc.name); field(npc.greeting)
                if value.canOfferNPCChat(shopNpcChat: context.shopNpcChat), let raw = value.id,
                   let row = PublicMerchantRowID(raw), let destination = context.npcDestination {
                    NavigationLink("merchant.publicHome.chat") { destination(row, npc) }.accessibilityIdentifier("merchant.publicHome.chat")
                }
            }
        }
        if !(value.storyTitle ?? "").isEmpty || !(value.description ?? "").isEmpty {
            Section("merchant.publicHome.about") { field(value.storyTitle); field(value.description) }
        }
        if !value.galleryItems.isEmpty {
            Section("merchant.publicHome.gallery") {
                ForEach(Array(value.galleryItems.enumerated()), id: \.offset) { _, item in media(item, label: "merchant.publicHome.photo") }
            }.accessibilityIdentifier("merchant.publicHome.gallery")
        }
        if !value.tagItems.isEmpty { Section("merchant.publicHome.tags") { Text(value.tagItems.joined(separator: " · ")) } }
        if value.hasCooperation {
            Section("merchant.publicHome.cooperation") {
                if let capacity = value.capacity, capacity > 0 { LabeledContent("merchant.publicHome.capacity", value: String(capacity)) }
                labeled(value.availableTime, label: "merchant.publicHome.availableTime")
                labeled(value.suitActivityTypes, label: "merchant.publicHome.activityTypes")
                labeled(value.demand, label: "merchant.publicHome.demand")
            }.accessibilityIdentifier("merchant.publicHome.cooperation")
        }
    }
    @ViewBuilder private func featuredCard(_ value: PublicMerchantHome) -> some View {
        if let target, let featured = value.publicFeatured(for: target), let route = featured.route {
            Section("merchant.publicHome.featured.title") {
                PublicMerchantFeaturedCard(featured: featured, image: context.image)
                if let destination = context.featured,
                   let selection = PublicMerchantFeaturedSelection(home: value, target: target,
                       homeScope: context.reader.scope, destinationScope: destination.scope, snapshotID: snapshotID),
                   canOpen(selection) {
                    Button(LocalizedStringKey(route == .couponWallet ? "merchant.publicHome.featured.openWallet" : "merchant.publicHome.featured.openActivity")) {
                        guard canOpen(selection) else { return }
                        featuredSelection = selection
                    }.accessibilityIdentifier("merchant.publicHome.featured.open")
                }
            }
        }
    }
    private func canOpen(_ selection: PublicMerchantFeaturedSelection) -> Bool {
        guard !loading, failure == nil, loadedKey == key, context.reader.isConfigured,
              let home, let target, let destination = context.featured, destination.isCurrent() else { return false }
        return selection.isCurrent(home: home, target: target, homeScope: context.reader.scope,
                                   destinationScope: destination.scope, snapshotID: snapshotID)
    }
    @ViewBuilder private func field(_ value: String?) -> some View { if let value, !value.isEmpty { Text(verbatim: value).textSelection(.enabled) } }
    @ViewBuilder private func labeled(_ value: String?, label: LocalizedStringKey) -> some View {
        if let value, !value.isEmpty { LabeledContent(label, value: value) }
    }
    @ViewBuilder private func media(_ value: String?, label: LocalizedStringKey) -> some View {
        if let value, !value.isEmpty {
            if let image = context.image { image(value).accessibilityLabel(Text(label)) }
            else { Label(label, systemImage: "photo").foregroundStyle(.secondary) }
        }
    }
    private func load() async {
        generation += 1
        let ticket = generation; let snapshot = key
        home = nil; failure = nil; loadedKey = nil; loading = true
        snapshotID = UUID(); featuredSelection = nil
        guard let target else { loading = false; failure = .invalid; loadedKey = snapshot; return }
        guard context.reader.isConfigured else { loading = false; failure = .notConfigured; loadedKey = snapshot; return }
        do {
            let result = try await context.reader.home(target)
            guard ticket == generation, snapshot == key, !Task.isCancelled else { return }
            home = result
        } catch {
            guard ticket == generation, snapshot == key, !Task.isCancelled else { return }
            failure = (error as? PublicMerchantHomeFailure) ?? .retryable
        }
        guard ticket == generation, snapshot == key, !Task.isCancelled else { return }
        loadedKey = snapshot; loading = false
    }
}

struct PublicMerchantHomeBusinessStatusLabel: View {
    let state: PublicMerchantBusinessState
    var localizationKey: String {
        switch state {
        case .open: "merchant.publicHome.open"
        case .closed: "merchant.publicHome.closed"
        case .unknown: "merchant.publicHome.businessUnknown"
        }
    }
    var symbol: String {
        switch state {
        case .open: "storefront"
        case .closed: "moon.zzz"
        case .unknown: "questionmark.circle"
        }
    }
    var body: some View {
        Label(LocalizedStringKey(localizationKey), systemImage: symbol)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("merchant.publicHome.businessStatus")
    }
}
