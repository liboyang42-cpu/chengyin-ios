import Foundation

/// Brand-center type1 industries, not the type4 gameplay category catalog.
public struct MerchantStoreIndustry: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let type: Int?
    private enum CodingKeys: String, CodingKey { case id, categoryName, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0, id <= Int(Int32.max) else { throw APIError.malformedResponse }
        self.id = id; name = try c.decode(String.self, forKey: .categoryName)
        type = try c.decodeIfPresent(Int.self, forKey: .type)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, type == nil || type == 1 else { throw APIError.malformedResponse }
    }
}
public struct MerchantStoreIndustryCatalog: Decodable, Equatable {
    public let rows: [MerchantStoreIndustry]
    public init(from decoder: Decoder) throws {
        rows = try decoder.singleValueContainer().decode([MerchantStoreIndustry].self)
        guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
    }
}

/// Review metadata only. No label, catalog type, approval flag, or clearing flag is writable.
public struct MerchantStoreIndustryChange: Equatable {
    public let previousIDs: [Int]
    public let selectedIDs: [Int]
    public var previousID: Int? { previousIDs.first }
    public var selectedID: Int? { selectedIDs.first }
    public init?(baseline: MerchantOperationsDraft?, draft: MerchantOperationsDraft?) {
        guard case .decor(let before) = baseline, case .decor(let after) = draft,
              before.selectedCategoryIDs != after.selectedCategoryIDs else { return nil }
        previousIDs = before.selectedCategoryIDs; selectedIDs = after.selectedCategoryIDs
    }
}

/// Complete ordered 1–5 choice editing buffer; the first retained item remains primary. Applying changes local document state; saving remains
/// the existing frozen-review/approved-transport flow and does not occur in this class.
@MainActor public final class MerchantStoreIndustrySelection {
    private let owner: MerchantOperationsCoordinator
    private let original: MerchantStoreDecor
    private let scope: UUID
    private let identity: UUID
    private var generation = 0
    private var consumed = false
    private var request: Task<MerchantStoreIndustryCatalog, Error>?
    public private(set) var rows: [MerchantStoreIndustry] = []
    public private(set) var selectedIDs: [Int] = []
    public var selectedID: Int? { selectedIDs.first }
    public private(set) var limitReached = false
    public private(set) var loaded = false
    public private(set) var loading = false
    public private(set) var issue: MerchantOperationsIssue?
    public init?(owner: MerchantOperationsCoordinator) {
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .decor(let original) = owner.draft, !original.categorySourceUnavailable else { return nil }
        self.owner = owner; self.original = original; scope = owner.reader.scope; identity = owner.draftIdentity
        selectedIDs = original.selectedCategoryIDs
    }
    public var previousID: Int? { original.selectedCategoryIDs.first }
    public var previousIDs: [Int] { original.selectedCategoryIDs }
    public var isCurrent: Bool {
        !consumed && owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == identity && owner.draft == .decor(original)
    }
    public var previousIsUnavailable: Bool {
        loaded && previousIDs.contains { id in !rows.contains { $0.id == id } }
    }
    public var selected: MerchantStoreIndustry? { rows.first { $0.id == selectedID } }
    public var selectedRows: [MerchantStoreIndustry] { selectedIDs.compactMap { id in rows.first { $0.id == id } } }
    public var canApply: Bool { isCurrent && loaded && !loading && issue == nil && (1...5).contains(selectedIDs.count) && selectedRows.count == selectedIDs.count }
    public func select(_ id: Int) {
        guard isCurrent, loaded, !loading, issue == nil, rows.contains(where: { $0.id == id }) || selectedIDs.contains(id) else { return }
        limitReached = false
        if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) }
        else if selectedIDs.count < 5 { selectedIDs.append(id) }
        else { limitReached = true }
    }
    public func reload() async {
        guard isCurrent else { return }
        request?.cancel(); generation += 1; let ticket = generation
        rows = []; loaded = false; loading = true; issue = nil
        let reader = owner.reader
        let pending = Task { try await reader.storeIndustries() }; request = pending
        defer { if ticket == generation { loading = false; request = nil } }
        do {
            let result = try await pending.value
            guard !Task.isCancelled, ticket == generation, isCurrent else { return }
            rows = result.rows; loaded = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), ticket == generation, isCurrent else { return }
            issue = .init(error)
        }
    }
    public func apply() -> MerchantStoreDecor? {
        guard canApply else { return nil }
        var edited = original
        guard (try? edited.selectIndustries(selectedIDs, catalog: rows)) != nil else { return nil }
        cancel(); return edited
    }
    public func cancel() { consumed = true; generation += 1; request?.cancel(); request = nil; loading = false }
}
