import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityTaskHistoryController {
    public private(set) var items: [CityTaskHistoryItem] = []
    public private(set) var nextBeforeID: String?
    public private(set) var detail: CityTaskHistoryDetail?
    public private(set) var receipt: CityTaskHistoryReceipt?
    public private(set) var busy = false
    public private(set) var messageKey = "cityHistory.status.initial"
    public private(set) var loaded = false
    private let service: CityTaskHistoryService?
    private let unauthorized: () -> Void
    private var generation = 0
    public init(service: CityTaskHistoryService?, unauthorized: @escaping () -> Void = {}) { self.service = service; self.unauthorized = unauthorized }
    public var current: Bool { service?.transport.isCurrent() == true }
    public func invalidate() { generation += 1; items = []; nextBeforeID = nil; detail = nil; receipt = nil; busy = false; loaded = false; messageKey = "cityHistory.status.disabled" }
    public enum ReadAction { case refresh, more, select(CityTaskHistoryItem), receipt(String), returnToList }
    public struct ReadReview: CustomStringConvertible, CustomDebugStringConvertible {
        fileprivate let controller: ObjectIdentifier
        fileprivate let generation: Int
        fileprivate let action: ReadAction
        fileprivate let cursor: String?
        fileprivate let items: [CityTaskHistoryItem]
        fileprivate let detail: CityTaskHistoryDetail?
        public var description: String { "CityTaskHistoryReadReview[redacted]" }
        public var debugDescription: String { description }
    }
    /// Freeze only a user-requested read; this never grants writes or current team qualification.
    public func captureRead(_ action: ReadAction) -> ReadReview? {
        guard current, !busy else { return nil }
        return .init(controller: ObjectIdentifier(self), generation: generation, action: action,
                     cursor: nextBeforeID, items: items, detail: detail)
    }
    public func perform(_ review: ReadReview) async {
        guard review.controller == ObjectIdentifier(self), review.generation == generation,
              review.cursor == nextBeforeID, review.items == items, review.detail == detail,
              current, !busy else { return }
        switch review.action {
        case .refresh: await load()
        case .more: await load(more: true)
        case .select(let item): await select(item)
        case .receipt(let request): await readReceipt(request)
        case .returnToList: closeDetail(); await load()
        }
    }
    public func load(more: Bool = false) async {
        guard !busy else { return }
        guard current, let service else { invalidate(); return }
        let before = more ? nextBeforeID : nil
        if more && before == nil { return }
        generation += 1; let issued = generation; busy = true; detail = nil; receipt = nil
        if !more { items = []; loaded = false; nextBeforeID = nil }
        defer { if issued == generation { busy = false } }
        do {
            let page = try await service.page(before: before); guard valid(issued) else { return }
            let existing = Set(items.map(\.id)); guard !more || page.items.allSatisfy({ !existing.contains($0.id) }) else { throw CityTaskHistoryError.malformed }
            items = more ? items + page.items : page.items; nextBeforeID = page.nextBeforeInstanceId; loaded = true
            messageKey = items.isEmpty ? "cityHistory.status.empty" : "cityHistory.status.ready"
        } catch { fail(error, issued) }
    }
    public func select(_ item: CityTaskHistoryItem) async {
        guard !busy, current, let service, items.contains(item) else { return }
        generation += 1; let issued = generation; busy = true; detail = nil; receipt = nil
        defer { if issued == generation { busy = false } }
        do { let value = try await service.detail(item.id); guard valid(issued) else { return }; detail = value; messageKey = "cityHistory.status.detail" }
        catch { fail(error, issued) }
    }
    public func readReceipt(_ requestID: String) async {
        guard !busy, current, let service, let original = detail else { return }
        guard requestID == original.instance.acceptRequestId || original.attempts.contains(where: { $0.requestId == requestID }) else { return }
        generation += 1; let issued = generation; busy = true; receipt = nil
        defer { if issued == generation { busy = false } }
        do { let value = try await service.receipt(requestID, in: original); guard valid(issued) else { return }; receipt = value; messageKey = value.status == "UNKNOWN" ? "cityHistory.status.unknown" : "cityHistory.status.receipt" }
        catch { fail(error, issued) }
    }
    public func closeDetail() { guard !busy else { return }; detail = nil; receipt = nil; messageKey = "cityHistory.status.ready" }
    private func valid(_ issued: Int) -> Bool { guard issued == generation else { return false }; guard current else { invalidate(); return false }; return true }
    private func fail(_ error: Error, _ issued: Int) {
        guard issued == generation else { return }; invalidate()
        if case APIError.unauthorized = error { unauthorized(); messageKey = "cityHistory.status.unauthorized" }
        else if !current { messageKey = "cityHistory.status.disabled" }
        else { messageKey = "cityHistory.status.failed" }
    }
}
