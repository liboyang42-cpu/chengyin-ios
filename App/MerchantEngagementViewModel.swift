import SwiftUI

@MainActor final class MerchantEngagementViewModel: ObservableObject {
    let reader: any MerchantEngagementReading
    let coordinator: MerchantEngagementCoordinator
    @Published private(set) var revision = 0
    @Published private(set) var access: MerchantEngagementAccess?
    @Published private(set) var segments: [MerchantSavedSegment] = []
    @Published private(set) var coupons: [MerchantCampaignCoupon] = []
    @Published private(set) var campaigns: [MerchantCampaignTask] = []
    @Published private(set) var detail: MerchantCampaignTask?
    @Published private(set) var loading = false
    @Published private(set) var issue: String?
    private var generation = 0
    init(reader: any MerchantEngagementReading, journal: any MerchantBusinessIntentStore, exports: any MerchantExportRecoveryStoring) {
        self.reader = reader; coordinator = .init(reader: reader, journal: journal, exportRecovery: exports)
    }
    func load() async {
        generation += 1; let stamp = generation, scope = reader.scope; loading = true; issue = nil
        defer { if stamp == generation { loading = false } }
        do {
            let grant = try await reader.access()
            guard stamp == generation, reader.scope == scope, !Task.isCancelled else { return }
            if access != grant { segments = []; coupons = []; campaigns = []; detail = nil; coordinator.invalidate() }
            access = grant
            if grant.identity?.allows("merchant:crm:read") == true {
                let result = try await reader.read(.segments)
                guard stamp == generation, reader.scope == scope else { return }
                if case .segments(let values) = result { segments = values }
            }
            if grant.identity?.allows("merchant:marketing:write") == true {
                let result = try await reader.read(.campaigns)
                guard stamp == generation, reader.scope == scope else { return }
                if case .campaigns(let values) = result { campaigns = values }
            }
            if grant.identity?.allows("merchant:coupon:manage") == true {
                let result = try await reader.read(.coupons)
                guard stamp == generation, reader.scope == scope else { return }
                if case .coupons(let values) = result { coupons = values }
            }
            await coordinator.refreshExport(); revision += 1
        } catch {
            guard stamp == generation, reader.scope == scope else { return }
            issue = (error as? MerchantBusinessFailure)?.key ?? "merchant.business.loadFailed"
            if error as? MerchantBusinessFailure == .denied || error as? APIError == .unauthorized {
                access = nil; segments = []; coupons = []; campaigns = []; detail = nil; coordinator.invalidate()
            }
            // Same-identity history survives transient refresh errors; it is visibly marked stale.
        }
    }
    func loadTask(_ id: Int) async {
        let scope = reader.scope
        do { guard case .campaign(let task) = try await reader.read(.campaign(id)), reader.scope == scope else { return }; detail = task }
        catch { if reader.scope == scope { issue = (error as? MerchantBusinessFailure)?.key ?? "merchant.business.loadFailed" } }
    }
    func prepare(_ command: MerchantEngagementCommand) async { revision += 1; await coordinator.prepare(command); revision += 1 }
    func confirm(_ review: MerchantEngagementReview) async {
        revision += 1; await coordinator.confirm(review); revision += 1
        if let receipt = coordinator.receipt {
            switch receipt {
            case .campaignCreated(let task), .campaignDispatched(let task), .campaignRetried(let task): detail = task
            default: break
            }
        }
    }
    func cancel() { coordinator.cancelReview(); revision += 1 }
    func clearReceipt() { coordinator.clearSensitiveReceipt(); revision += 1 }
    func invalidate() { generation += 1; access = nil; segments = []; coupons = []; campaigns = []; detail = nil; coordinator.invalidate(); revision += 1 }
    func pollExportsWhileVisible() async {
        while !Task.isCancelled && coordinator.exportTicket?.task.isRunning == true {
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            if coordinator.exportTicket?.task.isRunning == true { await coordinator.refreshExport(); revision += 1 }
        }
    }
}
