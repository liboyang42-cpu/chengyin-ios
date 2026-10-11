import Foundation

/// Read-only brand material from the existing authorized edit-profile projection.
/// This intentionally has no onboarding-license or write fields.
public struct MerchantBrandImages: Decodable, Equatable {
    public struct Item: Equatable, Identifiable {
        public let id: Int
        private let source: String
        public var url: URL? {
            guard !source.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let components = URLComponents(string: source), components.scheme == "https",
                  !(components.host ?? "").isEmpty, components.user == nil, components.password == nil else { return nil }
            return components.url
        }
        fileprivate init(id: Int, source: String) { self.id = id; self.source = source }
    }
    public let merchantID: Int
    public let items: [Item]
    private enum CodingKeys: String, CodingKey { case id, derivatives }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        merchantID = try c.decode(Int.self, forKey: .id)
        guard merchantID > 0 else { throw APIError.malformedResponse }
        let raw = try c.decodeIfPresent(String.self, forKey: .derivatives) ?? ""
        // Mini uses comma-separated URL candidates. Text merchandise descriptions
        // remain text; duplicate images retain their individual ordinal positions.
        items = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("https:") || $0.hasPrefix("http:") || $0.hasPrefix("/") }
            .enumerated().map { .init(id: $0.offset, source: $0.element) }
    }
}

/// Ephemeral viewer lease; no draft edit, mutation request, persistence or URL export.
@MainActor public final class MerchantBrandImagesSession {
    private weak var owner: MerchantOperationsCoordinator?
    private let original: MerchantOperationsDraft
    private let identity: UUID
    private let scope: UUID
    private let merchantID: Int
    private var active = true
    private var generation = 0
    private var request: Task<MerchantBrandImages, Error>?
    public private(set) var document: MerchantBrandImages?
    public private(set) var issue: MerchantOperationsIssue?
    public private(set) var isLoading = false
    public private(set) var selectedIndex: Int?
    public private(set) var zoom = 1.0
    public private(set) var imageGeneration = UUID()

    public init?(owner: MerchantOperationsCoordinator) {
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .profile(let profile) = owner.draft, let id = profile.id, id > 0,
              let original = owner.draft else { return nil }
        self.owner = owner; self.original = original; identity = owner.draftIdentity
        scope = owner.reader.scope; merchantID = id
    }
    public var isCurrent: Bool {
        guard active, let owner else { return false }
        return owner.isCurrent && owner.reader.isConfigured && owner.reader.scope == scope
            && owner.draftIdentity == identity && owner.draft == original
            && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    public var items: [MerchantBrandImages.Item] { isCurrent ? document?.items ?? [] : [] }
    public var currentURL: URL? {
        guard isCurrent, let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex].url
    }
    public var previousIndex: Int? {
        guard let selectedIndex else { return nil }
        return items.indices.last { $0 < selectedIndex && items[$0].url != nil }
    }
    public var nextIndex: Int? {
        guard let selectedIndex else { return nil }
        return items.indices.first { $0 > selectedIndex && items[$0].url != nil }
    }
    public func reload() async {
        guard isCurrent, let owner else { retire(); return }
        request?.cancel(); generation += 1; let ticket = generation
        document = nil; issue = nil; closeImage(); isLoading = true
        let task = Task { try await owner.reader.brandImages() }; request = task
        defer { if ticket == generation { isLoading = false; request = nil } }
        do {
            let value = try await task.value
            guard !Task.isCancelled, ticket == generation, isCurrent else { return }
            guard value.merchantID == merchantID else { throw APIError.malformedResponse }
            document = value
        } catch {
            guard !Task.isCancelled, ticket == generation, isCurrent else { return }
            issue = .init(error)
        }
    }
    @discardableResult public func select(_ index: Int) -> Bool {
        guard isCurrent, !isLoading, items.indices.contains(index), items[index].url != nil else { return false }
        selectedIndex = index; zoom = 1; imageGeneration = UUID(); return true
    }
    public func imageIsCurrent(_ ticket: UUID, index: Int) -> Bool {
        isCurrent && selectedIndex == index && imageGeneration == ticket && currentURL != nil
    }
    @discardableResult public func setZoom(_ value: Double, ticket: UUID, index: Int) -> Bool {
        guard value.isFinite, imageIsCurrent(ticket, index: index) else { return false }
        zoom = min(5, max(1, value)); return true
    }
    public func retryImage(ticket: UUID, index: Int) {
        guard imageIsCurrent(ticket, index: index) else { return }
        zoom = 1; imageGeneration = UUID()
    }
    public func closeImage() { selectedIndex = nil; zoom = 1; imageGeneration = UUID() }
    public func retire() {
        active = false; generation += 1; request?.cancel(); request = nil
        document = nil; issue = nil; isLoading = false; closeImage()
    }
}
