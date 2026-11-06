import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubBadgeResultAttributionTests: XCTestCase {
    private final class Wire: HTTPTransport {
        var handler: (URLRequest) throws -> (Data, Int) = { _ in (Data(), 503) }
        var paths: [String] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            paths.append(request.url!.path)
            return try handler(request)
        }
    }
    private final class Scenario {
        let source: ClubBadgeOriginalConsumerRecoveryTests.Fixture
        let wire = Wire()
        var owner = true
        var confirmMutation = false
        var confirmRecovery = false
        var onDetail: (() throws -> Void)?
        lazy var service = ClubBadgeManagementService(context: source.context, clubID: 7, transport: wire,
            current: { self.source.current }, approval: { _ in self.source.approval })
        lazy var flow = ClubBadgeManagementFlow(service: service, journal: source.journal)
        let prior: ClubBadgeOriginalReceipt
        init() throws {
            let fixture = try ClubBadgeOriginalConsumerRecoveryTests.Fixture()
            source = fixture
            let entry = try fixture.entry()
            try fixture.journal.reserve(entry, context: fixture.context)
            let original = try JSONDecoder().decode(ClubBadgeOriginalReceipt.self,
                from: JSONSerialization.data(withJSONObject: fixture.receipt(entry, terminal: true)))
            prior = original
            try fixture.journal.settle(entry, outcome: "CONFIRMED", receipt: original, context: fixture.context)
            wire.handler = { [unowned self] request in
                switch request.url!.path {
                case "/api/club/detail":
                    try self.onDetail?()
                    return (try self.source.envelope(data: ["id": 7, "isOwner": self.owner]), 200)
                case "/api/club/badge/list":
                    return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [["badgeCode": "CLUB7_1", "badgeName": "Trail", "clubId": 7]]]), 200)
                case "/api/club/badge/create", "/api/club/badge/original-receipt":
                    let recovery = request.url!.path.hasSuffix("original-receipt")
                    if !recovery && !self.confirmMutation { return (Data(), 503) }
                    guard let pending = try self.source.journal.read(self.source.context, clubID: 7).first(where: { $0.outcome == "UNKNOWN" }) else {
                        throw ClubBadgeManagementFailure.invalid
                    }
                    return (try self.source.envelope(data: self.source.receipt(pending,
                        terminal: recovery ? self.confirmRecovery : self.confirmMutation)), 200)
                default: throw ClubBadgeManagementFailure.invalid
                }
            }
        }
        var draft: ClubBadgeCreateDraft { var d = ClubBadgeCreateDraft(); d.name = "Second"; return d }
    }

    func testHistoricalReceiptCannotMasqueradeAsNewValidationResult() async throws {
        let s = try Scenario(); await s.flow.refresh()
        XCTAssertEqual(s.flow.resultPresentation, .historical(s.prior))
        await s.flow.create(.init())
        XCTAssertEqual(s.flow.resultPresentation, .needsReview)
        XCTAssertEqual(s.flow.receipt, s.prior)
        XCTAssertEqual(s.wire.paths.count, 2)
        XCTAssertEqual(try s.source.journal.read(s.source.context, clubID: 7).count, 1)
    }

    func testOwnerLossBeforeDispatchShowsCurrentFailureWithoutErasingHistory() async throws {
        let s = try Scenario(); await s.flow.refresh(); s.owner = false
        await s.flow.create(s.draft)
        XCTAssertEqual(s.flow.resultPresentation, .needsReview)
        XCTAssertEqual(s.flow.receipt, s.prior)
        XCTAssertFalse(s.flow.canCreate)
        XCTAssertFalse(s.wire.paths.contains("/api/club/badge/create"))
        XCTAssertEqual(try s.source.journal.read(s.source.context, clubID: 7).first?.receipt, s.prior)
    }

    func testUnreadableJournalTakesPriorityOverHistoricalSuccess() async throws {
        let s = try Scenario(); await s.flow.refresh()
        s.onDetail = {
            // Corrupt only this test's isolated synthetic file before reservation.
            let files = try FileManager.default.contentsOfDirectory(at: s.source.directory, includingPropertiesForKeys: nil)
            let file = try XCTUnwrap(files.first(where: { $0.pathExtension == "json" }))
            try Data("{}".utf8).write(to: file, options: .atomic)
        }
        await s.flow.create(s.draft)
        XCTAssertEqual(s.flow.resultPresentation, .storageUnavailable)
        XCTAssertEqual(s.flow.receipt, s.prior)
        XCTAssertFalse(s.flow.canCreate)
        XCTAssertFalse(s.wire.paths.contains("/api/club/badge/create"))
    }

    func testUnknownThenExactRecoveryReplacesOnlyCurrentResult() async throws {
        let s = try Scenario(); await s.flow.refresh()
        await s.flow.create(s.draft)
        XCTAssertEqual(s.flow.resultPresentation, .unknown)
        XCTAssertEqual(s.flow.receipt, s.prior)
        XCTAssertFalse(s.flow.canCreate)
        let pending = try XCTUnwrap(s.flow.unresolved.first)
        s.confirmRecovery = true
        await s.flow.refresh()
        guard case .confirmed(let recovered) = s.flow.resultPresentation else { return XCTFail("Exact receipt must be the current recovery result") }
        XCTAssertEqual(recovered.requestId, pending.requestID)
        XCTAssertNotEqual(recovered.requestId, s.prior.requestId)
        XCTAssertEqual(s.wire.paths.filter { $0 == "/api/club/badge/create" }.count, 1)
        XCTAssertEqual(try s.source.journal.read(s.source.context, clubID: 7).first?.receipt, s.prior)
        await s.flow.refresh()
        XCTAssertEqual(s.flow.resultPresentation, .historical(recovered))
        s.flow.invalidate()
        XCTAssertEqual(s.flow.resultPresentation, .none)
        XCTAssertEqual(try s.source.journal.read(s.source.context, clubID: 7).count, 2)
    }

    func testSuccessfulNewMutationUsesItsOwnReceiptIdentity() async throws {
        let s = try Scenario(); await s.flow.refresh(); s.confirmMutation = true
        await s.flow.create(s.draft)
        guard case .confirmed(let current) = s.flow.resultPresentation else { return XCTFail("Must expose current confirmed identity") }
        XCTAssertNotEqual(current.requestId, s.prior.requestId)
        XCTAssertEqual(s.flow.receipt, current)
        XCTAssertEqual(try s.source.journal.read(s.source.context, clubID: 7).first?.receipt, s.prior)
        XCTAssertEqual(s.wire.paths.filter { $0 == "/api/club/badge/create" }.count, 1)
    }
}
