import Foundation

public struct MerchantTemplateCategory: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let type: Int?
    private enum CodingKeys: String, CodingKey { case id, categoryName, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), (1...9_007_199_254_740_991).contains(id) else { throw APIError.malformedResponse }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .categoryName) ?? ""
        type = try c.decodeIfPresent(Int.self, forKey: .type)
    }
}
public struct MerchantTemplateCategoryCatalog: Decodable, Equatable {
    public let rows: [MerchantTemplateCategory]
    public init(from decoder: Decoder) throws {
        rows = try decoder.singleValueContainer().decode([MerchantTemplateCategory].self)
        guard Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.type == nil || $0.type == 4) }) else {
            throw APIError.malformedResponse
        }
    }
}

/// Exact existing category fields. Merely opening/retrying a picker preserves raw CSV.
public struct MerchantTemplateCategories: Equatable {
    public private(set) var rawIDs: String?
    public private(set) var primaryID: Int?
    public private(set) var labels: [MerchantTemplateCategory]
    public private(set) var replacedUnsupportedSource = false
    public init(rawIDs: String? = nil, primaryID: Int? = nil, labels: [MerchantTemplateCategory] = []) {
        self.rawIDs = rawIDs; self.primaryID = primaryID; self.labels = labels
    }
    private var parsedIDs: [Int]? {
        guard let rawIDs, !rawIDs.isEmpty else { return [] }
        var result: [Int] = []
        for part in rawIDs.components(separatedBy: ",") {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(token),
                  (1...9_007_199_254_740_991).contains(id), String(id) == token, !result.contains(id) else { return nil }
            result.append(id)
        }
        return result
    }
    public var isSupported: Bool { parsedIDs != nil }
    public var selectedIDs: [Int] { parsedIDs ?? [] }
    public func name(_ id: Int) -> String? { labels.first(where: { $0.id == id })?.name }
    public var fields: [String: Any] {
        var fields: [String: Any] = [:]
        if let rawIDs { fields["activityCategoryids"] = rawIDs }
        if let primaryID { fields["categoryId"] = primaryID }
        return fields
    }
    public mutating func replace(with rows: [MerchantTemplateCategory]) throws {
        guard !rows.isEmpty, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.type == nil || $0.type == 4) }) else { throw APIError.invalidRequest }
        let ids = rows.map(\.id)
        if isSupported && selectedIDs == ids { return }
        replacedUnsupportedSource = !isSupported || replacedUnsupportedSource
        rawIDs = ids.map(String.init).joined(separator: ","); primaryID = ids[0]; labels = rows
    }
}

/// A catalog read gives choices, not permission to publish. Changes remain in this
/// cancellable buffer until the current merchant document explicitly accepts them.
@MainActor public final class MerchantTemplateCategorySelection {
    private let owner: MerchantOperationsCoordinator
    private let original: MerchantNodeTemplate
    private let scope: UUID
    private let identity: UUID
    private var generation = 0
    private var consumed = false
    private var request: Task<MerchantTemplateCategoryCatalog, Error>?
    private var replacementAccepted = false
    public private(set) var rows: [MerchantTemplateCategory] = []
    public private(set) var selectedIDs: [Int]
    public private(set) var loaded = false
    public private(set) var loading = false
    public private(set) var issue: MerchantOperationsIssue?
    public init?(owner: MerchantOperationsCoordinator) {
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .template(let original) = owner.draft else { return nil }
        self.owner = owner; self.original = original; scope = owner.reader.scope; identity = owner.draftIdentity
        selectedIDs = original.categories.selectedIDs
    }
    public var isCurrent: Bool {
        !consumed && owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == identity && owner.draft == .template(original)
    }
    public var needsReplacement: Bool { !original.categories.isSupported && !replacementAccepted }
    public var unavailableIDs: [Int] { selectedIDs.filter { id in !rows.contains(where: { $0.id == id }) } }
    public var canApply: Bool {
        isCurrent && loaded && !loading && issue == nil && !needsReplacement && !selectedIDs.isEmpty && unavailableIDs.isEmpty
    }
    public func beginReplacement() {
        guard isCurrent, loaded, !loading, issue == nil, needsReplacement else { return }
        replacementAccepted = true; selectedIDs = []
    }
    public func toggle(_ id: Int) {
        guard isCurrent, loaded, !loading, issue == nil, !needsReplacement, rows.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) { selectedIDs.removeAll { $0 == id } } else { selectedIDs.append(id) }
    }
    public func removeUnavailable(_ id: Int) {
        guard isCurrent, loaded, !loading, issue == nil, unavailableIDs.contains(id) else { return }
        selectedIDs.removeAll { $0 == id }
    }
    public func reload() async {
        guard isCurrent else { return }
        request?.cancel(); generation += 1; let ticket = generation
        loading = true; loaded = false; rows = []; issue = nil
        let reader = owner.reader
        let pending = Task { try await reader.templateCategories() }; request = pending
        defer { if ticket == generation { loading = false; request = nil } }
        do {
            let catalog = try await pending.value
            guard !Task.isCancelled, ticket == generation, isCurrent else { return }
            rows = catalog.rows; loaded = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), ticket == generation, isCurrent else { return }
            issue = .init(error)
        }
    }
    public func apply() -> MerchantNodeTemplate? {
        guard canApply else { return nil }
        let selected = selectedIDs.compactMap { id in rows.first { $0.id == id } }
        var edited = original
        do { try edited.categories.replace(with: selected) } catch { return nil }
        cancel(); return edited
    }
    public func cancel() { consumed = true; generation += 1; request?.cancel(); request = nil; loading = false }
}
