import Foundation
import Observation

@MainActor @Observable public final class CityMerchantValueController {
    private let service: CityMerchantValueService
    private let access: () async throws -> MerchantBusinessAccess
    private let current: () -> Bool
    private var generation = UUID()
    private var reportValue: CityMerchantValueReport?
    private var factValues: [CityMerchantValueFact] = []
    private var cursor: String?
    private var snapshotID: Int64?
    private var merchantID: Int?
    private var selectedWindow: CityMerchantValueWindow?
    private var requestID: String?
    private var loading = false
    private var issueValue: String?
    private var benefitGeneration = UUID()
    private var benefitValue: CityMerchantValueBenefitRecord?
    private var benefitLoading = false
    private var benefitIssueValue: String?
    public var benefit: CityMerchantValueBenefitRecord? { configured && service.allows(.benefit) ? benefitValue : nil }
    public var benefitBusy: Bool { configured && service.allows(.benefit) && benefitLoading }
    public var benefitIssue: String? { configured && service.allows(.benefit) ? benefitIssueValue : "NOT_CONFIGURED" }
    public var configured: Bool { service.isCurrent && current() }
    public var report: CityMerchantValueReport? { configured ? reportValue : nil }
    public var facts: [CityMerchantValueFact] { configured ? factValues : [] }
    public var busy: Bool { configured && loading }
    public var hasMore: Bool { configured && (cursor != nil || (reportValue != nil && snapshotID == nil)) }
    public var issue: String? { configured ? issueValue : "NOT_CONFIGURED" }
    public init(service: CityMerchantValueService, access: @escaping () async throws -> MerchantBusinessAccess, current: @escaping () -> Bool) {
        self.service = service; self.access = access; self.current = current
    }
    public func suspend() { generation = UUID(); loading = false; closeBenefit() }
    private func valid(_ ticket: UUID) -> Bool { ticket == generation && configured && !Task.isCancelled }
    private func permission(_ expected: Int? = nil) async throws -> Int {
        let value = try await access()
        guard configured, value.allows("merchant:verify:record:read"), expected.map({ $0 == value.merchantID }) ?? true else { throw CityMerchantValueFailure.noPermission }
        return value.merchantID
    }
    public func load(window: CityMerchantValueWindow, newSnapshot: Bool = true) async {
        guard configured, !loading, !Task.isCancelled else { return }
        if newSnapshot || selectedWindow != window { requestID = UUID().uuidString }
        let id = requestID ?? UUID().uuidString; requestID = id
        closeBenefit(); generation = UUID(); let ticket = generation; loading = true; issueValue = nil
        selectedWindow = window; reportValue = nil; factValues = []; cursor = nil; snapshotID = nil; merchantID = nil
        defer { if valid(ticket) { loading = false } }
        do {
            let merchant = try await permission(); guard valid(ticket) else { return }
            let value = try await service.send(.report(service.scope, window, requestID: id), as: CityMerchantValueReport.self)
            try value.validate(scope: service.scope, window: window, merchantID: merchant)
            guard valid(ticket) else { return }; reportValue = value; merchantID = merchant
            try await page(cursor: "", window: window, merchant: merchant, ticket: ticket)
        } catch { if valid(ticket) { fail(error, fallback: "READ_FAILED") } }
    }
    public func readBack() async {
        guard configured, !busy, let report = reportValue, let window = selectedWindow, let merchant = merchantID, !Task.isCancelled else { return }
        let ticket = generation; loading = true; issueValue = nil
        defer { if valid(ticket) { loading = false } }
        do {
            _ = try await permission(merchant); guard valid(ticket) else { return }
            let value = try await service.send(.result(service.scope, report.resultId), as: CityMerchantValueReport.self)
            try value.validate(scope: service.scope, window: window, merchantID: merchant)
            guard value.resultId == report.resultId else { throw APIError.malformedResponse }
            guard valid(ticket) else { return }; reportValue = value
        } catch { if valid(ticket) { reportValue = nil; factValues = []; cursor = nil; fail(error, fallback: "READ_FAILED") } }
    }
    public func loadMore() async {
        guard configured, !busy, hasMore, let window = selectedWindow, let merchant = merchantID, !Task.isCancelled else { return }
        let cursor = self.cursor ?? ""
        let ticket = generation; loading = true; issueValue = nil
        defer { if valid(ticket) { loading = false } }
        do {
            _ = try await permission(merchant); guard valid(ticket) else { return }
            try await page(cursor: cursor, window: window, merchant: merchant, ticket: ticket)
        } catch { if valid(ticket) { fail(error, fallback: "PAGE_FAILED") } } // Cursor is advanced only after validated success; same retry is lossless.
    }
    public func canReadBenefit(_ fact: CityMerchantValueFact) -> Bool {
        configured && service.allows(.benefit) && !busy && snapshotID != nil && selectedWindow != nil &&
        fact.kind == "SERVICE_SUCCESS" && fact.merchantId == merchantID && factValues.contains(fact)
    }
    /// Read-only detail keeps the parent report, window, loaded pages and cursor untouched.
    public func readBenefit(_ fact: CityMerchantValueFact) async {
        guard canReadBenefit(fact), !benefitLoading, !Task.isCancelled,
              let snapshot = snapshotID, let window = selectedWindow, let merchant = merchantID else { return }
        benefitGeneration = UUID(); let detailTicket = benefitGeneration, ticket = generation
        benefitValue = nil; benefitIssueValue = nil; benefitLoading = true
        func validDetail() -> Bool { valid(ticket) && benefitGeneration == detailTicket && service.allows(.benefit) && snapshotID == snapshot }
        defer { if validDetail() { benefitLoading = false } }
        do {
            _ = try await permission(merchant); guard validDetail() else { return }
            let value = try await service.send(.benefit(service.scope, window, snapshotID: snapshot, eventID: fact.id), as: CityMerchantValueBenefitRecord.self)
            try value.validate(scope: service.scope, window: window, snapshotID: snapshot, fact: fact, merchantID: merchant)
            guard validDetail() else { return }; benefitValue = value
        } catch {
            if validDetail() {
                benefitValue = nil; benefitIssueValue = "BENEFIT_FAILED"
                if error as? CityMerchantValueFailure == .noPermission || error as? MerchantBusinessFailure == .denied {
                    fail(error, fallback: "BENEFIT_FAILED"); benefitIssueValue = "NO_PERMISSION"
                }
            }
        }
    }
    public func closeBenefit() {
        benefitGeneration = UUID(); benefitValue = nil; benefitLoading = false; benefitIssueValue = nil
    }
    private func fail(_ error: Error, fallback: String) {
        if error as? CityMerchantValueFailure == .noPermission || error as? MerchantBusinessFailure == .denied {
            closeBenefit(); reportValue = nil; factValues = []; cursor = nil; snapshotID = nil; merchantID = nil; issueValue = "NO_PERMISSION"
        } else { issueValue = fallback }
    }
    private func page(cursor requested: String, window: CityMerchantValueWindow, merchant: Int, ticket: UUID) async throws {
        let value = try await service.send(.events(service.scope, window, cursor: requested), as: CityMerchantValueFactPage.self)
        try value.validate(scope: service.scope, window: window, merchantID: merchant, snapshot: snapshotID)
        guard requested.isEmpty || value.retryCursor == requested,
              Set(factValues.map(\.id)).isDisjoint(with: value.events.map(\.id)) else { throw APIError.malformedResponse }
        guard valid(ticket) else { return }
        snapshotID = value.snapshotId; factValues += value.events; cursor = value.nextCursor
    }
}
