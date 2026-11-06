import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private final class PresentationStampTransport: HTTPTransport {
    var response: String
    var status = 200
    var requests: [URLRequest] = []

    init(_ response: String) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(response.utf8), status)
    }
}

@MainActor final class RoamReceivedStampPresentationTests: XCTestCase {
    private let base = URL(string: "https://album.example/native")!

    private func pageJSON(
        _ list: String = #"[{"id":71,"picUrl":"https://cdn.example/stamp71.jpg","caption":" 街角留念 ","checkState":1,"createTime":"2026-10-19T14:30:00"},{"id":72,"picUrl":"http://insecure.example/stamp72.jpg","caption":"   ","checkState":0},{"id":73,"picUrl":"https://cdn.example/stamp73.jpg","caption":"withheld","checkState":2}]"#,
        total: Int = 3,
        pageNum: Int = 1,
        pageSize: Int = 20
    ) -> String {
        #"{"code":200,"data":{"list":\#(list),"total":\#(total),"pageNum":\#(pageNum),"pageSize":\#(pageSize)}}"#
    }

    private func makeContext(account: Int = 81, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(
            market: .china,
            baseURL: base,
            role: "player",
            session: try .init(
                accountID: account,
                epoch: epoch,
                namespace: "synthetic",
                token: "synthetic-received-token"
            )
        )
    }

    private func makeReceivedAccess(_ context: RuntimeDependencyContext) throws -> RoamReceivedStampReadAccess {
        try RoamReceivedStampReadAccess(
            context: context,
            approval: OperationEndpointApproval(
                baseURL: base,
                namespace: context.session.namespace,
                accountID: context.session.accountID,
                paths: [RoamReceivedStampReadRoute.path]
            )
        )
    }

    func testTabDescriptorsAndRouteBindingsMatchSourceCopy() {
        XCTAssertEqual(RoamReceivedStampTab.allCases, [.collected, .received])
        XCTAssertEqual(RoamReceivedStampTab.collected.title, "集章册")
        XCTAssertEqual(RoamReceivedStampTab.received.title, "收到的章")
        XCTAssertEqual(RoamReceivedStampTab.collected.routePath, "api/roam/stamp/list")
        XCTAssertEqual(RoamReceivedStampTab.received.routePath, "api/roam/stamp/received")
        XCTAssertEqual(RoamReceivedStampTab.collected.accessibilityID, "roam.receivedStamp.tab.collected")
        XCTAssertEqual(RoamReceivedStampTab.received.accessibilityID, "roam.receivedStamp.tab.received")
        XCTAssertFalse(RoamReceivedStampTab.collected.emptyTitle.isEmpty)
        XCTAssertFalse(RoamReceivedStampTab.received.emptyTitle.isEmpty)
    }

    func testAvailabilityDistinguishesSignInRequiredNotConfiguredAndReadyWithoutDispatch() async throws {
        let nilModel = RoamReceivedStampPresentation(reader: nil)
        XCTAssertEqual(nilModel.activeAvailability, .notConfigured)
        XCTAssertFalse(nilModel.activeAvailability.canLoad)
        XCTAssertEqual(nilModel.activeAvailability.statusTitle, "暂未开放")
        await nilModel.loadNextIfNeeded()
        XCTAssertTrue(nilModel.visibleStamps.isEmpty)

        let transport = PresentationStampTransport(pageJSON())
        let service = RoamReceivedStampService(
            configuration: try APIConfiguration(baseURL: base),
            transport: transport
        )
        var currentContext: RuntimeDependencyContext? = nil
        var activeGrant: RoamReceivedStampReadAccess? = nil
        let reader = RoamReceivedStampReader(
            service: service,
            current: { currentContext },
            viewerRevision: { 0 },
            access: { _ in activeGrant }
        )

        let model = RoamReceivedStampPresentation(
            receivedReader: reader,
            collectedReader: nil,
            initialTab: .received
        )
        XCTAssertEqual(model.activeAvailability, .signInRequired)
        XCTAssertEqual(model.activeAvailability.statusTitle, "请先登录")
        await model.loadNextIfNeeded()
        XCTAssertTrue(transport.requests.isEmpty)

        currentContext = try makeContext()
        XCTAssertEqual(model.activeAvailability, .notConfigured)
        await model.loadNextIfNeeded()
        XCTAssertTrue(transport.requests.isEmpty)

        activeGrant = try makeReceivedAccess(try XCTUnwrap(currentContext))
        XCTAssertEqual(model.activeAvailability, .ready)
        XCTAssertEqual(model.availability(for: .collected), .notConfigured)
    }

    func testPresentationPagesReceivedStampsFiltersModerationAndClearsOnRevokeOrSignOut() async throws {
        let transport = PresentationStampTransport(pageJSON())
        let service = RoamReceivedStampService(
            configuration: try APIConfiguration(baseURL: base),
            transport: transport
        )
        var currentContext: RuntimeDependencyContext? = try makeContext()
        let grant = try makeReceivedAccess(try XCTUnwrap(currentContext))
        var activeGrant: RoamReceivedStampReadAccess? = grant
        let reader = RoamReceivedStampReader(
            service: service,
            current: { currentContext },
            viewerRevision: { 0 },
            access: { _ in activeGrant }
        )

        let model = RoamReceivedStampPresentation(
            receivedReader: reader,
            collectedReader: nil,
            initialTab: .received
        )
        await model.loadNextIfNeeded()

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.path, "/native/api/roam/stamp/received")
        XCTAssertEqual(model.visibleStamps.map(\.id), [71, 72])
        XCTAssertEqual(model.totalCount, 3)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isEmptyStateVisible)

        let cards = model.stampCards
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].serialText, "NO. 0071")
        XCTAssertEqual(cards[0].captionText, " 街角留念 ")
        XCTAssertTrue(cards[0].hasCaption)
        XCTAssertEqual(cards[0].dateText, "2026-10-19 14:30:00")
        XCTAssertEqual(cards[0].approvedImageURL, "https://cdn.example/stamp71.jpg")

        XCTAssertEqual(cards[1].serialText, "NO. 0072")
        XCTAssertEqual(cards[1].captionText, "未留寄语")
        XCTAssertFalse(cards[1].hasCaption)
        XCTAssertNil(cards[1].approvedImageURL)

        model.selectTab(.collected)
        XCTAssertEqual(model.selectedTab, .collected)
        XCTAssertEqual(model.activeAvailability, .notConfigured)
        XCTAssertTrue(model.visibleStamps.isEmpty)

        model.selectTab(.received)
        XCTAssertEqual(model.visibleStamps.map(\.id), [71, 72])

        grant.revoke()
        XCTAssertEqual(model.activeAvailability, .notConfigured)
        XCTAssertTrue(model.visibleStamps.isEmpty)
        XCTAssertNil(model.totalCount)

        currentContext = nil
        activeGrant = nil
        XCTAssertEqual(model.activeAvailability, .signInRequired)
        XCTAssertTrue(model.visibleStamps.isEmpty)
    }
}
