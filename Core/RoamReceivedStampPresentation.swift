import Foundation
import Observation

/// I11 (`POST api/roam/stamp/received`) tab selector pairing the existing stamp album
/// (`集章册`) with the received-stamps feed (`收到的章`).
public enum RoamReceivedStampTab: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case collected
    case received

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .collected: return "集章册"
        case .received: return "收到的章"
        }
    }

    public var routePath: String {
        switch self {
        case .collected: return RoamAlbumMetadataReadRoute.path
        case .received: return RoamReceivedStampReadRoute.path
        }
    }

    public var emptyTitle: String {
        switch self {
        case .collected: return "还没有留下城市签"
        case .received: return "还没有收到交换的城市签"
        }
    }

    public var emptySubtitle: String {
        switch self {
        case .collected: return "完成一次漫游印章记录后会显示在集章册中"
        case .received: return "通过印章交换获得的城市签会展示在这里"
        }
    }

    public var accessibilityID: String {
        switch self {
        case .collected: return "roam.receivedStamp.tab.collected"
        case .received: return "roam.receivedStamp.tab.received"
        }
    }
}

/// Honest admission state for a stamp tab reader. Unconfigured or signed-out readers never
/// synthesize an empty stamp list.
public enum RoamReceivedStampAvailability: Equatable, Sendable {
    case signInRequired
    case notConfigured
    case ready

    public var canLoad: Bool { self == .ready }

    public var statusTitle: String? {
        switch self {
        case .signInRequired: return "请先登录"
        case .notConfigured: return "暂未开放"
        case .ready: return nil
        }
    }

    public var statusSubtitle: String? {
        switch self {
        case .signInRequired: return "登录后可查看当前账号的印章记录"
        case .notConfigured: return "当前环境尚未开启该印章读取授权"
        case .ready: return nil
        }
    }

    @MainActor public static func resolve(reader: (any RoamExperienceReading)?) -> Self {
        guard let reader else { return .notConfigured }
        guard reader.identity != nil else { return .signInRequired }
        guard reader.isConfigured else { return .notConfigured }
        return .ready
    }
}

/// Pure card projection of a `RoamAlbumStamp` row returned by `RoamReceivedStampReader`
/// or the collected album reader.
public struct RoamReceivedStampCardPresentation: Equatable, Identifiable, Sendable {
    public let id: Int
    public let serialText: String
    public let captionText: String
    public let hasCaption: Bool
    public let dateText: String?
    public let approvedImageURL: String?
    public let isVisible: Bool

    public init(_ stamp: RoamAlbumStamp) {
        self.id = stamp.id
        self.serialText = String(format: "NO. %04d", max(0, stamp.id) % 10000)
        let trimmedCaption = stamp.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedCaption.isEmpty {
            self.captionText = "未留寄语"
            self.hasCaption = false
        } else {
            self.captionText = stamp.caption ?? trimmedCaption
            self.hasCaption = true
        }
        let formattedDate = stamp.createTime?
            .replacingOccurrences(of: "T", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.dateText = formattedDate.isEmpty ? nil : formattedDate
        self.approvedImageURL = Self.sanitizeHTTPSURL(stamp.picUrl)
        self.isVisible = stamp.isVisible
    }

    private static func sanitizeHTTPSURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            return nil
        }
        return trimmed
    }
}

/// Coordinates the `"集章册"` / `"收到的章"` tabs backed by `RoamReceivedStampReader` and
/// `RoamAlbumPager`, preserving honest `.signInRequired` / `.notConfigured` states when the
/// underlying reader has no session or grant.
@MainActor @Observable public final class RoamReceivedStampPresentation {
    public var selectedTab: RoamReceivedStampTab
    public let receivedPager: RoamAlbumPager?
    public let collectedPager: RoamAlbumPager?
    private let receivedReader: (any RoamExperienceReading)?
    private let collectedReader: (any RoamExperienceReading)?
    private var stateRevision = 0

    public init(
        receivedReader: (any RoamExperienceReading)? = nil,
        collectedReader: (any RoamExperienceReading)? = nil,
        initialTab: RoamReceivedStampTab = .received,
        pageSize: Int = 20
    ) {
        self.receivedReader = receivedReader
        self.collectedReader = collectedReader
        self.selectedTab = initialTab
        self.receivedPager = receivedReader.map { RoamAlbumPager(reader: $0, pageSize: pageSize) }
        self.collectedPager = collectedReader.map { RoamAlbumPager(reader: $0, pageSize: pageSize) }
    }

    public convenience init(
        reader: (any RoamExperienceReading)?,
        initialTab: RoamReceivedStampTab = .received,
        pageSize: Int = 20
    ) {
        self.init(
            receivedReader: reader,
            collectedReader: nil,
            initialTab: initialTab,
            pageSize: pageSize
        )
    }

    public var tabs: [RoamReceivedStampTab] { RoamReceivedStampTab.allCases }

    public func reader(for tab: RoamReceivedStampTab) -> (any RoamExperienceReading)? {
        switch tab {
        case .collected: return collectedReader
        case .received: return receivedReader
        }
    }

    public var activeReader: (any RoamExperienceReading)? {
        reader(for: selectedTab)
    }

    public func pager(for tab: RoamReceivedStampTab) -> RoamAlbumPager? {
        switch tab {
        case .collected: return collectedPager
        case .received: return receivedPager
        }
    }

    public var activePager: RoamAlbumPager? {
        pager(for: selectedTab)
    }

    public func availability(for tab: RoamReceivedStampTab? = nil) -> RoamReceivedStampAvailability {
        _ = stateRevision
        return RoamReceivedStampAvailability.resolve(reader: reader(for: tab ?? selectedTab))
    }

    public var activeAvailability: RoamReceivedStampAvailability {
        availability(for: selectedTab)
    }

    public var visibleStamps: [RoamAlbumStamp] {
        _ = stateRevision
        guard activeAvailability == .ready, let pager = activePager else { return [] }
        return pager.stamps
    }

    public var stampCards: [RoamReceivedStampCardPresentation] {
        visibleStamps.map(RoamReceivedStampCardPresentation.init)
    }

    public var totalCount: Int? {
        _ = stateRevision
        guard activeAvailability == .ready else { return nil }
        return activePager?.total
    }

    public var isLoading: Bool {
        _ = stateRevision
        return activePager?.loading ?? false
    }

    public var hasMore: Bool {
        _ = stateRevision
        guard activeAvailability == .ready, let pager = activePager else { return false }
        return pager.hasMore
    }

    public var error: Error? {
        _ = stateRevision
        return activePager?.error
    }

    public var isEmptyStateVisible: Bool {
        _ = stateRevision
        guard activeAvailability == .ready, let pager = activePager else { return false }
        return pager.loaded && pager.stamps.isEmpty && pager.error == nil
    }

    public func selectTab(_ tab: RoamReceivedStampTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
        stateRevision += 1
    }

    public func loadNextIfNeeded() async {
        stateRevision += 1
        guard let pager = activePager else { return }
        guard activeAvailability == .ready else {
            pager.reset()
            stateRevision += 1
            return
        }
        await pager.loadNext()
        if activeAvailability != .ready {
            pager.reset()
        }
        stateRevision += 1
    }

    public func refresh() async {
        stateRevision += 1
        guard let pager = activePager else { return }
        pager.reset()
        guard activeAvailability == .ready else {
            stateRevision += 1
            return
        }
        await pager.loadNext()
        if activeAvailability != .ready {
            pager.reset()
        }
        stateRevision += 1
    }

    public func cancelPending() {
        receivedPager?.cancelPending()
        collectedPager?.cancelPending()
        stateRevision += 1
    }
}
