import Foundation
import SwiftUI

@MainActor final class HomeFeedModel: ObservableObject {
    @Published private(set) var banners: [DiscoveryBanner] = []
    @Published private(set) var categories: [DiscoveryCategory] = []
    @Published private(set) var sections: [HomeFeedSection: [HomeFeedItem]] = [:]
    @Published private(set) var failedSections: Set<HomeFeedSection> = []
    @Published private(set) var bannerFailed = false
    @Published private(set) var categoryFailed = false
    @Published private(set) var pagination = HomeFeedPagination()
    @Published private(set) var loading = false
    @Published private(set) var loadingPage = false
    @Published private(set) var pageFailed = false
    private var generation = UUID()
    private var pageGeneration = UUID()
    private var activeScope: UUID?
    private var query = HomeFeedQuery()
    func reload(reader: any HomeFeedReading, query: HomeFeedQuery) async {
        let ticket = UUID(); generation = ticket; activeScope = reader.scope
        banners = []; categories = []; sections = [:]; failedSections = []
        bannerFailed = false; categoryFailed = false; loading = true
        async let a: Void = loadBanners(reader: reader)
        async let b: Void = loadCategories(reader: reader)
        async let c: Void = loadSection(.recommended, reader: reader)
        async let d: Void = loadSection(.nearby, reader: reader)
        async let e: Void = loadSection(.upcoming, reader: reader)
        async let f: Void = resetPage(reader: reader, query: query)
        _ = await (a, b, c, d, e, f)
        if valid(ticket, reader) { loading = false }
    }
    private func valid(_ ticket: UUID, _ reader: any HomeFeedReading) -> Bool {
        !Task.isCancelled && ticket == generation && activeScope == reader.scope
    }
    func invalidate() {
        generation = UUID(); pageGeneration = UUID(); activeScope = nil
        banners = []; categories = []; sections = [:]; pagination = HomeFeedPagination()
        failedSections = []; bannerFailed = false; categoryFailed = false; pageFailed = false
        loading = false; loadingPage = false
    }
    func loadBanners(reader: any HomeFeedReading) async {
        let ticket = generation
        do { let result = try await reader.banners(); if valid(ticket, reader) { banners = result; bannerFailed = false } }
        catch { if valid(ticket, reader) { bannerFailed = true } }
    }
    func loadCategories(reader: any HomeFeedReading) async {
        let ticket = generation
        do { let result = try await reader.categories(); if valid(ticket, reader) { var seen = Set<Int>(); categories = result.filter { seen.insert($0.id).inserted }; categoryFailed = false } }
        catch { if valid(ticket, reader) { categoryFailed = true } }
    }
    func loadSection(_ section: HomeFeedSection, reader: any HomeFeedReading) async {
        let ticket = generation
        do {
            let result = try await reader.section(section)
            if valid(ticket, reader) { var seen = Set<HomeFeedDestination>(); sections[section] = result.filter { seen.insert($0.id).inserted }; failedSections.remove(section) }
        } catch { if valid(ticket, reader) { failedSections.insert(section) } }
    }
    func resetPage(reader: any HomeFeedReading, query: HomeFeedQuery) async {
        pageGeneration = UUID(); self.query = query; pagination = HomeFeedPagination(); loadingPage = false; pageFailed = false
        await loadMore(reader: reader)
    }
    func loadMore(reader: any HomeFeedReading) async {
        guard !loadingPage, pagination.hasMore else { return }
        let ticket = generation; let pageTicket = pageGeneration; let requestedQuery = query
        loadingPage = true; pageFailed = false
        do {
            let result = try await reader.page(query: requestedQuery, number: pagination.nextPage)
            guard valid(ticket, reader), pageTicket == pageGeneration else { return }
            try pagination.accept(result)
        } catch { if valid(ticket, reader), pageTicket == pageGeneration { pageFailed = true } }
        if valid(ticket, reader), pageTicket == pageGeneration { loadingPage = false }
    }
}
