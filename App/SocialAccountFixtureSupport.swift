#if DEBUG
import SwiftUI

@MainActor final class SocialAccountFixtureReader: SocialAccountReading {
    enum Scenario: String { case content, guest, empty, partial, failure, delayed, unknown, rejected, disabled, removed, unconfigured }
    let scenario: Scenario
    var identity: SocialAccountIdentity
    var isConfigured: Bool { scenario != .unconfigured }
    let isOfflineExample = true
    init(_ scenario: Scenario) {
        self.scenario = scenario
        identity = .init(accountID: scenario == .guest ? nil : 81, epoch: 1, role: scenario == .guest ? nil : "player")
    }
    func switchAccount() { identity = .init(accountID: identity.accountID == 81 ? 83 : 81, epoch: identity.epoch + 1, role: "player") }
    private func check() async throws {
        if scenario == .delayed { try await Task.sleep(nanoseconds: 650_000_000) }
        if scenario == .failure { throw APIError.httpStatus(503) }
        if !isConfigured { throw APIError.notConfigured }
    }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile {
        try await check(); return try SocialAccountSyntheticFixtures.profile(id: memberID, relationshipKnown: identity.accountID != nil)
    }
    func informationList() async throws -> [SocialInformation] {
        try await check(); return scenario == .empty ? [] : try SocialAccountSyntheticFixtures.information().filter(\.isUsable)
    }
    func information(id: Int) async throws -> SocialInformation {
        try await check()
        if scenario == .removed { return try JSONDecoder().decode(SocialInformation.self, from: Data("{}".utf8)) }
        guard let value = try SocialAccountSyntheticFixtures.information().first(where: { $0.id == id }) else { throw APIError.invalidRequest }; return value
    }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory {
        guard identity.accountID != nil else { throw APIError.unauthorized }
        try await check()
        let all = try SocialAccountSyntheticFixtures.members()
        let rows = scenario == .empty ? [] : (page == 1 ? Array(all.prefix(2)) : Array(all.suffix(2)))
        return try .init(page: .init(members: rows, total: scenario == .empty ? 0 : 4, pageNumber: page, pageSize: 2), rewardScan: SocialAccountSyntheticFixtures.rewards(partial: scenario == .partial))
    }
}
@MainActor final class SocialActionFixtureAccess: SocialActionAccess {
    let account: SocialAccountFixtureReader
    var identity: SocialAccountIdentity { account.identity }
    var availability: SocialActionAvailability { account.scenario == .disabled ? .disabled : .syntheticOnly }
    init(account: SocialAccountFixtureReader) { self.account = account }
    func snapshot(target: SocialActionTarget) async throws -> SocialActionSnapshot {
        if account.scenario == .delayed { try await Task.sleep(nanoseconds: 600_000_000) }
        if let id = target.memberID { return try .init(target: target, profile: SocialAccountSyntheticFixtures.profile(id: id)) }
        guard let postID = target.postID else { return .init(target: target) }
        let comment = try target.commentID.flatMap { id in try SquareSyntheticFixtures.comments().first { $0.id == id } }
        return try .init(target: target, post: SquareSyntheticFixtures.post(id: postID), comment: comment)
    }
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReceipt {
        guard expectedIdentity == identity else { throw SocialActionWriteFailure.notSent }
        if account.scenario == .unknown { throw SocialActionWriteFailure.outcomeUnknown }
        if account.scenario == .rejected { throw SocialActionWriteFailure.rejected }
        if account.scenario == .disabled { throw SocialActionWriteFailure.notSent }
        try await Task.sleep(nanoseconds: 200_000_000)
        return .init(synthetic: true)
    }
}
@MainActor private final class SocialMediaFixtureReader: SocialMessageMediaReading {
    let account: SocialAccountFixtureReader
    var identity: MessagingReadIdentity? { account.identity.accountID.map { .init(accountID: $0, epoch: account.identity.epoch) } }
    var isConfigured: Bool { account.scenario != .disabled }
    let isOfflineExample = true
    init(account: SocialAccountFixtureReader) { self.account = account }
    func image(_ media: SocialMessageMedia, expectedIdentity: MessagingReadIdentity) async throws -> Data {
        guard identity == expectedIdentity else { throw APIError.unauthorized }
        if account.scenario == .failure { throw SocialMediaFailure.unavailable }
        // Locally generated synthetic bitmap; never contacts the example host.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320))
        return renderer.pngData { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
            UIColor.white.setFill(); context.fill(CGRect(x: 80, y: 80, width: 320, height: 160))
        }
    }
}
@MainActor struct SocialAccountFixtureHostView: View {
    private let reader: SocialAccountFixtureReader
    private let square = SquareFixtureReader()
    private let actions: SocialActionCoordinator
    private let media: SocialMediaFixtureReader
    private let destination: String
    @State private var revision = 0
    @State private var selectedGuideDestination: SocialGuideDestination?
    init() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        let reader = SocialAccountFixtureReader(value("--uitesting-social-scenario").flatMap(SocialAccountFixtureReader.Scenario.init(rawValue:)) ?? .content)
        self.reader = reader; actions = SocialActionCoordinator(access: SocialActionFixtureAccess(account: reader)); media = SocialMediaFixtureReader(account: reader)
        destination = value("--uitesting-social-destination") ?? "profile"
    }
    var body: some View {
        VStack(spacing: 0) {
            Button("social.fixtureSwitchAccount") { reader.switchAccount(); actions.synchronizeSession(); revision += 1 }.accessibilityIdentifier("social.fixture.switch")
            NavigationStack {
                Group {
                    switch destination {
                    case "guide": SocialPlayGuideView(reader: reader, onOpenDestination: { selectedGuideDestination = $0 })
                    case "invites": SocialInviteHistoryView(reader: reader, squareReader: square, actions: actions)
                    case "editor": SocialActionEditorView(purpose: .createPost, target: .newPost, coordinator: actions)
                    case "square": SquareDetailView(id: 701, reader: square, accountReader: reader, actions: actions)
                    case "media":
                        if let message = try? SocialAccountSyntheticFixtures.imageMessage(), let identity = media.identity {
                            SocialMessageMediaView(message: message, reader: media, expectedIdentity: identity)
                        }
                    default: SocialPublicProfileView(memberID: 82, reader: reader, squareReader: square, actions: actions)
                    }
                }.id(revision)
                .overlay(alignment: .bottom) {
                    if let selectedGuideDestination { Text(verbatim: "Fixture destination: \(selectedGuideDestination.rawValue)").accessibilityIdentifier("social.fixture.destination") }
                }
            }
        }
    }
}
#endif
