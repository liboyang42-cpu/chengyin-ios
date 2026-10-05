#if DEBUG
import SwiftUI

@MainActor final class ClubFeedFixtureReader: ObservableObject, ClubReading, ClubGovernanceAccess {
    let isClubConfigured = true
    let isConfigured = true
    let allowsOfflineWrites = false
    let storageNamespace = "synthetic-club-feed"
    let scenario: String
    @Published var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    @Published var viewerRevision: UInt64 = 1
    @Published var readCount = 0
    @Published var replaced = false
    var identity: ClubReadIdentity? { clubIdentity }
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--club-feed-scenario")
        scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
    }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        guard operation == .feed else { throw ClubGovernanceFailure.invalidRequest }
        guard try operation.fields(scope: scope, options: options) == ["limit": .integer(20)] else { throw ClubGovernanceFailure.invalidRequest }
        readCount += 1
        if scenario == "failure", readCount == 1 { throw ClubGovernanceFailure.rejected(code: 503, message: nil) }
        if clubIdentity.accountID != 701 { throw ClubGovernanceFailure.forbidden }
        let value: ClubGovernanceValue
        if scenario == "noClubs" || scenario == "empty" {
            value = .object(["clubCount": .integer(scenario == "noClubs" ? 0 : 2), "rows": .array([])])
        } else if scenario == "unknownCount" { value = .object(["rows": .array([])]) }
        else {
            var row: [String: ClubGovernanceValue] = ["id": .integer(191), "clubId": .integer(81),
                "clubName": .string("Fixture source club"), "nickname": .string(replaced ? "Replacement feed author" : "Fixture feed author"),
                "content": .string("合成俱乐部帖文。A source-attributed fixture post with deliberately long bilingual text for accessibility layout."),
                "createTime": .string("2026-10-04 18:30:00"), "avatar": .string("https://club-feed.invalid/avatar.jpg"),
                "images": .string("https://club-feed.invalid/one.jpg;https://club-feed.invalid/two.jpg,https://club-feed.invalid/three.jpg;https://club-feed.invalid/four.jpg"),
                "phone": .string("PRIVATE-CONTACT-MUST-NOT-APPEAR"), "authorMemberId": .integer(999)]
            if scenario == "invalidClub" { row["clubId"] = .integer(-1) }
            if replaced { row["clubId"] = .integer(82); row["clubName"] = .string("Replacement source club") }
            value = .object(["clubCount": .integer(2), "rows": .array([.object(row)])])
        }
        return .init(operation: operation, scope: scope, permissions: nil,
                     value: try ClubGovernanceValidation.validate(value, operation: operation, scope: scope))
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { throw ClubGovernanceFailure.notConfigured }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { [] }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { [] }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
    func clubDetail(id: Int) async throws -> ClubRecord {
        guard [81, 82].contains(id), clubIdentity.accountID == 701 else { throw ClubReadFailure.unauthorized(message: nil) }
        let value: [String: Any] = ["id": id, "name": "Actual source club \(id)", "description": "Synthetic club detail"]
        return try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

@MainActor struct ClubFeedFixtureHost: View {
    @StateObject private var reader = ClubFeedFixtureReader()
    @State private var images = NativePresentationImageReader()
    private var imageReader: any RetainedPublicImageReading {
        if reader.scenario == "disabled" { return RetainedPublicImageReader() }
        return images
    }
    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: String(reader.readCount)).accessibilityIdentifier("club.feed.fixture.reads")
            Text(verbatim: String(images.readCount)).accessibilityIdentifier("club.feed.fixture.imageReads")
            HStack {
                Button("Switch account") { reader.clubIdentity = .init(accountID: 702, epoch: 2) }
                    .accessibilityIdentifier("club.feed.fixture.switch")
                Button("Replace read scope") { reader.replaced = true; reader.viewerRevision &+= 1 }
                    .accessibilityIdentifier("club.feed.fixture.replace")
            }
            NavigationStack {
                List {
                    ClubGovernanceHomeEntries(feedContext: .init(viewerRevision: reader.viewerRevision,
                        readerIdentity: ObjectIdentifier(reader), destination: { id in
                            AnyView(ClubDetailView(id: id, reader: reader))
                        }, imageReader: imageReader), identity: reader.clubIdentity, access: reader,
                        coordinator: ClubGovernanceCoordinator(access: reader))
                }
            }
        }
    }
}
#endif
