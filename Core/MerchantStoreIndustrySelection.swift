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
    public let previousID: Int?
    public let selectedID: Int?
    public init?(baseline: MerchantOperationsDraft?, draft: MerchantOperationsDraft?) {
        guard case .decor(let before) = baseline, case .decor(let after) = draft,
              before.categoryID != after.categoryID else { return nil }
        previousID = before.categoryID; selectedID = after.categoryID
    }
}

/// Single-choice editing buffer. Applying changes local document state; saving remains
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
    public private(set) var selectedID: Int?
    public private(set) var loaded = false
    public private(set) var loading = false
    public private(set) var issue: MerchantOperationsIssue?
    public init?(owner: MerchantOperationsCoordinator) {
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .decor(let original) = owner.draft else { return nil }
        self.owner = owner; self.original = original; scope = owner.reader.scope; identity = owner.draftIdentity
        selectedID = original.categoryID
    }
    public var previousID: Int? { original.categoryID }
    public var isCurrent: Bool {
        !consumed && owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == identity && owner.draft == .decor(original)
    }
    public var previousIsUnavailable: Bool {
        guard loaded, let previousID else { return false }
        return !rows.contains { $0.id == previousID }
    }
    public var selected: MerchantStoreIndustry? { rows.first { $0.id == selectedID } }
    public var canApply: Bool { isCurrent && loaded && !loading && issue == nil && selected != nil }
    public func select(_ id: Int) {
        guard isCurrent, loaded, !loading, issue == nil, rows.contains(where: { $0.id == id }) else { return }
        selectedID = id
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
        guard canApply, let selected else { return nil }
        var edited = original; edited.categoryID = selected.id
        cancel(); return edited
    }
    public func cancel() { consumed = true; generation += 1; request?.cancel(); request = nil; loading = false }
}
