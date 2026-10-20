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
    struct Binding: Equatable {
        let revision = UUID()
        let reader: ObjectIdentifier
        let scope: UUID
        let configured: Bool
        let available: Bool
    }
    private var bound: Binding?
    private var snapshot: Binding?
    private var active = false
    private var pageLoaded = false

    // Bind before lifecycle tasks run so a replacement reader cannot display or
    // complete work into the previous reader's retained navigation snapshot.
    @discardableResult func bind(_ reader: any HomeFeedReading, available: Bool = true) -> Binding {
        let key = Binding(reader: ObjectIdentifier(reader), scope: reader.scope, configured: reader.isConfigured, available: available)
        if let bound, bound.reader == key.reader, bound.scope == key.scope,
           bound.configured == key.configured, bound.available == key.available { return bound }
        bound = key; snapshot = nil; active = false; generation = UUID(); pageGeneration = UUID()
        return key
    }
    func matches(_ reader: any HomeFeedReading) -> Bool {
        guard let snapshot, snapshot == bound else { return false }
        return snapshot.reader == ObjectIdentifier(reader) && snapshot.scope == reader.scope &&
            snapshot.configured == reader.isConfigured && snapshot.available
    }
    func canOpen(_ reader: any HomeFeedReading) -> Bool {
        active && matches(reader) && reader.isConfigured
    }
    func suspend() {
        active = false; generation = UUID(); pageGeneration = UUID()
        loading = false; loadingPage = false
    }
    func resume(reader: any HomeFeedReading, query: HomeFeedQuery, available: Bool = true, expectedBinding: Binding? = nil) async {
        guard !Task.isCancelled, expectedBinding == nil || expectedBinding == bound else { return }
        let key = bind(reader, available: available)
        guard key.configured, key.available else { invalidate(); return }
        if snapshot != key { invalidate(); bound = key; snapshot = key }
        active = true
        if self.query != query { self.query = query; pagination = HomeFeedPagination(); pageLoaded = false; pageFailed = false }
        await loadMissing(reader: reader)
    }
    private func loadMissing(reader: any HomeFeedReading) async {
        let needsRead = !bannersLoaded && !bannerFailed || !categoriesLoaded && !categoryFailed ||
            HomeFeedSection.allCases.contains { sections[$0] == nil && !failedSections.contains($0) } || !pageLoaded && !pageFailed
        guard needsRead else { return }
        let ticket = generation
        loading = true
        let bannersNeeded = !bannersLoaded && !bannerFailed
        let categoriesNeeded = !categoriesLoaded && !categoryFailed
        let recommendedNeeded = sections[.recommended] == nil && !failedSections.contains(.recommended)
        let nearbyNeeded = sections[.nearby] == nil && !failedSections.contains(.nearby)
        let upcomingNeeded = sections[.upcoming] == nil && !failedSections.contains(.upcoming)
        let pageNeeded = !pageLoaded && !pageFailed
        async let a: Void = bannersNeeded ? loadBanners(reader: reader, expected: ticket) : ()
        async let b: Void = categoriesNeeded ? loadCategories(reader: reader, expected: ticket) : ()
        async let c: Void = recommendedNeeded ? loadSection(.recommended, reader: reader, expected: ticket) : ()
        async let d: Void = nearbyNeeded ? loadSection(.nearby, reader: reader, expected: ticket) : ()
        async let e: Void = upcomingNeeded ? loadSection(.upcoming, reader: reader, expected: ticket) : ()
        async let f: Void = pageNeeded ? loadMore(reader: reader, expected: ticket) : ()
        _ = await (a, b, c, d, e, f)
        if owns(ticket, reader) { loading = false }
    }
    private var bannersLoaded = false
    private var categoriesLoaded = false
    private var query = HomeFeedQuery()
    func reload(reader: any HomeFeedReading, query: HomeFeedQuery) async {
        guard active, matches(reader), !Task.isCancelled else { return }
        let key = bound
        invalidate(); bound = key; snapshot = key; active = true; self.query = query
        await loadMissing(reader: reader)
    }
    private func owns(_ ticket: UUID, _ reader: any HomeFeedReading) -> Bool {
        active && ticket == generation && matches(reader) && reader.isConfigured
    }
    private func valid(_ ticket: UUID, _ reader: any HomeFeedReading) -> Bool {
        !Task.isCancelled && owns(ticket, reader)
    }
    func invalidate() {
        generation = UUID(); pageGeneration = UUID(); snapshot = nil; active = false
        pageLoaded = false; bannersLoaded = false; categoriesLoaded = false
        banners = []; categories = []; sections = [:]; pagination = HomeFeedPagination()
        failedSections = []; bannerFailed = false; categoryFailed = false; pageFailed = false
        loading = false; loadingPage = false
    }
    func loadBanners(reader: any HomeFeedReading, expected: UUID? = nil) async {
        let ticket = expected ?? generation
        guard valid(ticket, reader) else { return }
        do { let result = try await reader.banners(); if valid(ticket, reader) { banners = result; bannersLoaded = true; bannerFailed = false } }
        catch { if valid(ticket, reader) { bannerFailed = true } }
    }
    func loadCategories(reader: any HomeFeedReading, expected: UUID? = nil) async {
        let ticket = expected ?? generation
        guard valid(ticket, reader) else { return }
        do { let result = try await reader.categories(); if valid(ticket, reader) { var seen = Set<Int>(); categories = result.filter { seen.insert($0.id).inserted }; categoriesLoaded = true; categoryFailed = false } }
        catch { if valid(ticket, reader) { categoryFailed = true } }
    }
    func loadSection(_ section: HomeFeedSection, reader: any HomeFeedReading, expected: UUID? = nil) async {
        let ticket = expected ?? generation
        guard valid(ticket, reader) else { return }
        do {
            let result = try await reader.section(section)
            if valid(ticket, reader) { var seen = Set<HomeFeedDestination>(); sections[section] = result.filter { seen.insert($0.id).inserted }; failedSections.remove(section) }
        } catch { if valid(ticket, reader) { failedSections.insert(section) } }
    }
    func resetPage(reader: any HomeFeedReading, query: HomeFeedQuery) async {
        guard active, matches(reader), !Task.isCancelled else { return }
        pageLoaded = false
        pageGeneration = UUID(); self.query = query; pagination = HomeFeedPagination(); loadingPage = false; pageFailed = false
        await loadMore(reader: reader)
    }
    func loadMore(reader: any HomeFeedReading, expected: UUID? = nil) async {
        guard active, matches(reader), !Task.isCancelled, !loadingPage, pagination.hasMore else { return }
        let ticket = expected ?? generation
        guard valid(ticket, reader) else { return }
        let pageTicket = pageGeneration; let requestedQuery = query
        loadingPage = true; pageFailed = false
        defer { if owns(ticket, reader), pageTicket == pageGeneration { loadingPage = false } }
        do {
            let result = try await reader.page(query: requestedQuery, number: pagination.nextPage)
            guard valid(ticket, reader), pageTicket == pageGeneration else { return }
            try pagination.accept(result); pageLoaded = true
        } catch { if valid(ticket, reader), pageTicket == pageGeneration { pageFailed = true } }
    }
}
