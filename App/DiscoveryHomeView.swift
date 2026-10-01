import SwiftUI

/// First read-only home slice. Caller can route source-backed activity/topic banner destinations.
@MainActor
struct DiscoveryHomeView: View {
    let reader: any DiscoveryReading
    private let onBannerDestination: ((DiscoveryBanner.Destination) -> Void)?
    @StateObject private var banners = DiscoveryLoader<[DiscoveryBanner]>()
    @StateObject private var home = DiscoveryLoader<DiscoveryTemplateHome>()

    init(reader: any DiscoveryReading, onBannerDestination: ((DiscoveryBanner.Destination) -> Void)? = nil) {
        self.reader = reader
        self.onBannerDestination = onBannerDestination
    }

    var body: some View {
        NavigationStack {
            Group {
                if !reader.isConfigured {
                    ContentUnavailableView("discovery.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
                } else {
                    List {
                        Section {
                            NavigationLink {
                                DiscoveryTemplateBrowserView(reader: reader)
                            } label: {
                                Label("discovery.browseTemplates", systemImage: "square.stack.3d.up")
                            }.accessibilityIdentifier("discovery.openTemplates")
                        }
                        bannerSection
                        if let error = home.error {
                            DiscoveryErrorView(error: error) { Task { await loadHome() } }
                        }
                        if home.isLoading { ProgressView("discovery.loading") }
                        if let value = home.value {
                            if value.isEmpty && !home.isLoading && home.error == nil {
                                ContentUnavailableView("discovery.emptyGames", systemImage: "sparkles.rectangle.stack")
                            }
                            // Preserve the server's five separate sections without merging/relabeling rows.
                            playSection("discovery.featured", items: value.banner)
                            playSection("discovery.latest", items: value.latest)
                            playSection("discovery.recommended", items: value.recommended)
                            playSection("discovery.mustPlay", items: value.mustPlay)
                            playSection("discovery.hot", items: value.hot)
                        }
                    }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("discovery.title")
            .task { if reader.isConfigured { await reload() } }
        }
    }
    @ViewBuilder private var bannerSection: some View {
        if let error = banners.error {
            Section("discovery.banners") {
                DiscoveryErrorView(error: error) { Task { await loadBanners() } }
            }
        } else if banners.isLoading && banners.value == nil {
            Section("discovery.banners") { ProgressView("discovery.loading") }
        }
        if let items = banners.value, !items.isEmpty {
            Section("discovery.banners") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, banner in
                            if let destination = banner.destination, let onBannerDestination {
                                Button { onBannerDestination(destination) } label: {
                                    DiscoveryArtwork(source: banner.picUrl).frame(width: 280)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("discovery.openBanner \(index + 1)"))
                            } else {
                                DiscoveryArtwork(source: banner.picUrl).frame(width: 280)
                            }
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }
    @ViewBuilder private func playSection(_ title: LocalizedStringKey, items: [DiscoveryPlayTemplate]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        DiscoveryTemplateDetailView(id: item.id, reader: reader)
                    } label: { DiscoveryPlayRow(item: item) }
                    .accessibilityIdentifier("discovery.play.\(item.id)")
                }
            }
        }
    }
    private func loadBanners() async { await banners.load { try await reader.discoveryBanners() } }
    private func loadHome() async { await home.load { try await reader.discoveryTemplateHome() } }
    private func reload() async {
        async let a: Void = loadBanners()
        async let b: Void = loadHome()
        _ = await (a, b)
    }
}
