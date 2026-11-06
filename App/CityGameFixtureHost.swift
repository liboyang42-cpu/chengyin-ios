#if DEBUG
import SwiftUI
import Observation

/// Synthetic offline fixture for the W20 CITY business section. Every id, title, point
/// and number below is test data, not a CITY price, reward, budget or coordinate fact.
/// The real `CityPlayerView` reads through its reviewed routes from this in-memory wire.
@MainActor final class CityGameFixtureReadWire: HTTPTransport {
    var lifecycle = "OPEN"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let board: [String: Any] = ["gameId": "game-1", "boardId": "board-1", "regionId": "city-1", "seasonId": "season-1",
            "rulesReleaseId": "release-1", "rulesHash": String(repeating: "a", count: 64), "lifecycle": lifecycle,
            "title": "Synthetic official city", "revision": 1]
        var data: [String: Any] = ["contract": "CITY_PLAYER_READ_V1", "scope": "CITY", "status": "AVAILABLE", "board": board, "participationStatus": "JOINED"]
        if path.hasSuffix("/current") { data["regionId"] = "city-1"; data["pointsStatus"] = "AVAILABLE" }
        if path.hasSuffix("/participation") { data["participation"] = ["participationId": "participation-1", "membershipVersion": 1] }
        if path.hasSuffix("/points") {
            data["complete"] = true
            data["points"] = [
                ["pointId": "point-cafe", "title": "Synthetic cafe", "latitude": 10.0, "longitude": 20.0, "mine": false],
                ["pointId": "point-park", "title": "Synthetic park", "latitude": 10.001, "longitude": 20.001, "mine": false],
                ["pointId": "point-shop", "title": "Synthetic bookshop", "latitude": 10.002, "longitude": 20.002, "mine": false],
            ]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}

@MainActor @Observable final class CityGameFixtureService: CityGameServing {
    var points: Int64 = 5
    var actionsRemaining = 3
    var boardVersion: Int64 = 1
    var sequence: Int64 = 1
    var lifecycle: CityBoardLifecycle = .open
    var lostOnce = false
    var receiptMissingOnce = false
    var quoteChangedOnce = false
    var pausedShop = false
    private(set) var submissions: [CityActionIntent] = []
    private(set) var effects = 0
    private var receipts: [String: CityActionReceipt] = [:]
    private var cafeHeld = false
    private var shopChallenge: CityChallengeState?
    private var parkTaskKept = false

    func snapshot(for read: CityReadSnapshot) async throws -> CityGameSnapshot {
        let cafe = CityPropertyState(propertyId: "prop-cafe", pointId: "point-cafe", role: .operable, status: cafeHeld ? .held : .available,
            stateVersion: boardVersion, heldByMyTeam: cafeHeld, protectedUntilMillis: nil,
            services: cafeHeld ? [CityServiceOffer(serviceId: "svc-cafe-clues", title: "Synthetic clue station", memberPointsFee: 0)] : [],
            challenge: nil, taskAttemptKept: false)
        let park = CityPropertyState(propertyId: "prop-park", pointId: "point-park", role: .neutral, status: .available, stateVersion: boardVersion,
            heldByMyTeam: false, protectedUntilMillis: nil, services: [], challenge: nil, taskAttemptKept: parkTaskKept)
        let shop = CityPropertyState(propertyId: "prop-shop", pointId: "point-shop", role: .operable, status: pausedShop ? .paused : .held,
            stateVersion: boardVersion, heldByMyTeam: false, protectedUntilMillis: nil,
            services: [CityServiceOffer(serviceId: "svc-shop-route", title: "Synthetic route tips", memberPointsFee: 2),
                       CityServiceOffer(serviceId: "svc-shop-pending", title: "Synthetic undisclosed service", memberPointsFee: nil)],
            challenge: shopChallenge, taskAttemptKept: false)
        let rules = CityRulesSummary(rulesReleaseId: "release-1", ruleVersion: "synthetic-rules-1", validFromMillis: 1_700_000_000_000,
            validUntilMillis: nil, actionsRemaining: actionsRemaining, actionsPerRound: 3, holdingLimit: 2)
        return CityGameSnapshot(contract: "CITY_GAME_SNAPSHOT_V1", scope: "CITY", boardId: "board-1", seasonId: "season-1",
            boardVersion: boardVersion, sequence: sequence, lifecycle: lifecycle, roundSeq: 1, rules: rules,
            properties: [cafe, park, shop], memberPoints: points, neutralTasksAvailable: true)
    }
    func deltas(after cursor: CityStreamCursor) async throws -> [CityDelta] { [] }
    func quote(_ kind: CityActionKind, targetId: String, read: CityReadSnapshot) async throws -> CityActionQuote {
        let cost: Int64 = targetId == "svc-shop-route" ? 2 : (kind == .acquireProperty ? 3 : 1)
        return CityActionQuote(quoteId: "quote-\(kind.rawValue)-\(targetId)", quoteVersion: 1, action: kind.rawValue, boardId: "board-1",
            targetId: targetId, payerMemberId: "member-12", ruleVersion: "synthetic-rules-1", memberPointsCost: cost, actionCost: 1,
            beneficiaryMemberIds: ["member-12"], expiresAtMillis: Int64((Date().timeIntervalSince1970 + 600) * 1000))
    }
    func submit(_ intent: CityActionIntent) async throws -> CityActionReceipt {
        submissions.append(intent)
        if let saved = receipts[intent.requestId] { return saved }
        if quoteChangedOnce, intent.consent != nil {
            quoteChangedOnce = false
            let receipt = CityActionReceipt(requestId: intent.requestId, boardId: intent.boardId, action: intent.kind.rawValue,
                decision: .quoteChanged, currentVersion: boardVersion, reasonCode: "QUOTE_CHANGED", taskAttemptKept: false)
            receipts[intent.requestId] = receipt; return receipt
        }
        apply(intent)
        let receipt = CityActionReceipt(requestId: intent.requestId, boardId: intent.boardId, action: intent.kind.rawValue,
            decision: .applied, currentVersion: boardVersion, reasonCode: nil, taskAttemptKept: false)
        receipts[intent.requestId] = receipt
        if lostOnce { lostOnce = false; throw URLError(.networkConnectionLost) }
        return receipt
    }
    func receipt(for intent: CityActionIntent) async throws -> CityActionReceipt? {
        if receiptMissingOnce { receiptMissingOnce = false; return nil }
        return receipts[intent.requestId]
    }
    private func apply(_ intent: CityActionIntent) {
        effects += 1; boardVersion += 1; sequence += 1; actionsRemaining = max(0, actionsRemaining - 1)
        switch intent.kind {
        case .acquireProperty: cafeHeld = true; points -= 3
        case .acceptServiceVisit: points -= intent.targetId == "svc-shop-route" ? 2 : 0
        case .startChallenge: shopChallenge = .offered; points -= 1
        case .acceptTask: if intent.targetId == "prop-park" { parkTaskKept = true }
        default: break
        }
    }
}

@MainActor struct CityGameFixtureHost: View {
    @State private var reader: CityPlayerReader
    @State private var service: CityGameFixtureService
    private let enabled: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        let wire = CityGameFixtureReadWire(); if args.contains("--city-game-frozen") { wire.lifecycle = "FROZEN" }
        let session = try! PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-city", token: "fixture-token")
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player", session: session)
        let approval = try? CityPlayerReadApproval(context: context, regionID: "city-1", expiresAt: Date().addingTimeInterval(3_600))
        _reader = State(initialValue: CityPlayerReader(approval: approval, transport: wire, isCurrent: { true }))
        let service = CityGameFixtureService()
        service.lostOnce = args.contains("--city-game-lost")
        service.receiptMissingOnce = args.contains("--city-game-receipt-missing")
        service.quoteChangedOnce = args.contains("--city-game-quote-changed")
        service.pausedShop = args.contains("--city-game-paused")
        if args.contains("--city-game-zero-points") { service.points = 0 }
        if args.contains("--city-game-frozen") { service.lifecycle = .frozen }
        _service = State(initialValue: service)
        enabled = !args.contains("--city-game-disabled")
    }
    private var gameFactory: (@MainActor (CityReadSnapshot) -> CityGameCoordinator?)? {
        guard enabled else { return nil }
        let service = service
        return { read in
            CityGameCoordinator(read: read, service: service, capabilities: .syntheticFixture([.cityActions]), memberId: "member-12", isCurrent: { true })
        }
    }
    var body: some View {
        NavigationStack {
            CityPlayerView(reader: reader, gameFactory: gameFactory)
        }
        .safeAreaInset(edge: .bottom) {
            // Payload-free recorder: proves review/cancel never send and retries never repeat an effect.
            HStack {
                Text(verbatim: String(service.submissions.count)).accessibilityIdentifier("cityGame.recorder.submissions")
                Text(verbatim: String(service.effects)).accessibilityIdentifier("cityGame.recorder.effects")
                Text(verbatim: String(Set(service.submissions.map(\.requestId)).count)).accessibilityIdentifier("cityGame.recorder.requestIds")
            }.font(.caption2)
        }
    }
}

/// Synthetic W19 fixture: in-memory policy/account/verify/restore; no location provider.
@MainActor @Observable final class HomeReturnFixtureService: HomeReturnServing {
    var current: Int64 = 2
    var version: Int64 = 4
    var verifyDecision: HomeReturnVerification.Decision = .verified
    var lostOnce = false
    private(set) var restores: [HomeRestoreRequest] = []
    private(set) var effects = 0
    private var receipts: [String: HomeRestoreReceipt] = [:]
    func policy() async throws -> HomeReturnPolicy? { HomeReturnPolicy(policyVersion: "synthetic-policy", maxAccuracyMeters: 50, maxFixAgeSeconds: 60) }
    func account(for scope: HomeResourceScope) async throws -> HomeResourceAccount {
        HomeResourceAccount(resourceType: "stamina", scopeType: "GLOBAL", scopeId: nil, current: current, maximum: 5, version: version)
    }
    func verify(_ check: HomeReturnCheck) async throws -> HomeReturnVerification {
        let verified = verifyDecision == .verified
        return HomeReturnVerification(requestId: check.requestId, decision: verifyDecision, proofId: verified ? "proof-1" : nil,
            homeVersion: check.homeVersion, expiresAtMillis: verified ? Int64((Date().timeIntervalSince1970 + 120) * 1000) : nil,
            retryAfterSeconds: verifyDecision == .cooldown ? 600 : nil)
    }
    func restore(_ request: HomeRestoreRequest) async throws -> HomeRestoreReceipt {
        restores.append(request)
        if let saved = receipts[request.requestId] { return saved }
        effects += 1; current = 5; version += 1
        let receipt = HomeRestoreReceipt(requestId: request.requestId, proofId: request.proofId, decision: .restored, current: 5, maximum: 5,
            accountVersion: version, retryAfterSeconds: nil)
        receipts[request.requestId] = receipt
        if lostOnce { lostOnce = false; throw URLError(.networkConnectionLost) }
        return receipt
    }
    func restoreReceipt(for request: HomeRestoreRequest) async throws -> HomeRestoreReceipt? { receipts[request.requestId] }
}

@MainActor struct HomeReturnFixtureHost: View {
    @State private var home: PrivateHomeCoordinator
    @State private var restore: HomeReturnCoordinator
    @State private var service: HomeReturnFixtureService
    init() {
        let args = ProcessInfo.processInfo.arguments
        let owner = try! PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-private", token: "fixture-token")
        let homeService = PrivateHomeFixtureService(); homeService.active = !args.contains("--home-return-no-home"); homeService.version = 3
        _home = State(initialValue: PrivateHomeCoordinator(service: homeService, journal: PrivateHomeFixtureJournal(owner: owner), owner: owner,
            enabled: true, current: { owner }))
        let service = HomeReturnFixtureService(); service.lostOnce = args.contains("--home-return-lost")
        if args.contains("--home-return-out-of-radius") { service.verifyDecision = .outOfRadius }
        if args.contains("--home-return-cooldown") { service.verifyDecision = .cooldown }
        _service = State(initialValue: service)
        let denied = args.contains("--home-return-denied")
        let accuracy: Double = args.contains("--home-return-low-accuracy") ? 500 : 10
        let capabilities: ReformWorldCapabilities = args.contains("--home-return-disabled") ? .disabled : .syntheticFixture([.homeReturnRestore])
        _restore = State(initialValue: HomeReturnCoordinator(scope: .global(resourceType: "stamina"), service: service, capabilities: capabilities,
            location: { denied ? .denied : .fix(accuracyMeters: accuracy, capturedAt: Date()) }, isCurrent: { true }))
    }
    var body: some View {
        NavigationStack { PrivateHomeView(model: home).environment(\.homeReturnCoordinator, restore) }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(verbatim: String(service.restores.count)).accessibilityIdentifier("homeReturn.recorder.restores")
                    Text(verbatim: String(service.effects)).accessibilityIdentifier("homeReturn.recorder.effects")
                }.font(.caption2)
            }
    }
}
#endif
