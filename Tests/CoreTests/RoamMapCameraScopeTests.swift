import XCTest
@testable import QuestifyCore

/// Identity-policy tests only. Keeping the actual MapKit camera alive requires UI acceptance.
final class RoamMapCameraScopeTests: XCTestCase {
    private final class ReaderMarker {}
    private let firstReader = ReaderMarker()
    private let secondReader = ReaderMarker()
    private let approval = UUID()
    private var area: RoamSearchArea {
        .init(coordinate: .init(latitude: 31, longitude: 121)!, label: "Manual area")
    }
    private var identity: RoamReadIdentity {
        .init(accountID: 7, epoch: 10, role: "player", viewerRevision: 2,
              areaRevision: 3, manualMapApprovalRevision: approval)
    }
    private func scope(identity: RoamReadIdentity? = nil, area: RoamSearchArea? = nil) -> RoamMapCameraScope? {
        .init(readerID: ObjectIdentifier(firstReader), identity: identity ?? self.identity,
              area: area ?? self.area, isConfigured: true)
    }

    func testSameReaderFullIdentityAndAreaKeepOnePresentation() throws {
        let initial = try XCTUnwrap(scope())
        // Repeated loads and data-only filtering do not participate in the camera key.
        for _ in 0..<20 {
            XCTAssertEqual(initial, scope())
        }
        XCTAssertEqual(Set([initial, try XCTUnwrap(scope())]).count, 1)
    }

    func testMissingAuthorizationConfigurationOrAreaHasNoCameraScope() {
        let readerID = ObjectIdentifier(firstReader)
        XCTAssertNil(RoamMapCameraScope(readerID: readerID, identity: nil, area: area, isConfigured: true))
        XCTAssertNil(RoamMapCameraScope(readerID: readerID, identity: identity, area: nil, isConfigured: true))
        XCTAssertNil(RoamMapCameraScope(readerID: readerID, identity: identity, area: area, isConfigured: false))
        XCTAssertNil(RoamMapCameraScope(readerID: readerID, identity: .init(accountID: 0, epoch: 10), area: area, isConfigured: true))
    }

    func testReplacingRegionBoundReaderResetsEvenWithSameAccountAndArea() {
        let otherRegion = RoamMapCameraScope(readerID: ObjectIdentifier(secondReader), identity: identity,
                                             area: area, isConfigured: true)
        XCTAssertNotEqual(scope(), otherRegion)
    }

    func testAccountSessionRoleViewerAreaAndApprovalChangesReset() {
        let initial = scope()
        let changes: [RoamReadIdentity] = [
            .init(accountID: 8, epoch: 10, role: "player", viewerRevision: 2, areaRevision: 3, manualMapApprovalRevision: approval),
            .init(accountID: 7, epoch: 11, role: "player", viewerRevision: 2, areaRevision: 3, manualMapApprovalRevision: approval),
            .init(accountID: 7, epoch: 10, role: "merchant", viewerRevision: 2, areaRevision: 3, manualMapApprovalRevision: approval),
            .init(accountID: 7, epoch: 10, role: "player", viewerRevision: 3, areaRevision: 3, manualMapApprovalRevision: approval),
            .init(accountID: 7, epoch: 10, role: "player", viewerRevision: 2, areaRevision: 4, manualMapApprovalRevision: approval),
            .init(accountID: 7, epoch: 10, role: "player", viewerRevision: 2, areaRevision: 3, manualMapApprovalRevision: UUID()),
            .init(accountID: 7, epoch: 10, role: "player", viewerRevision: 2, areaRevision: 3, manualMapApprovalRevision: nil)
        ]
        for changed in changes { XCTAssertNotEqual(initial, scope(identity: changed)) }
    }

    func testChosenAreaChangeResetsAndAreaRevisionPreventsReturningToOldScope() {
        let changed = RoamSearchArea(coordinate: .init(latitude: 32, longitude: 120)!, label: "Other area")
        XCTAssertNotEqual(scope(), scope(area: changed))
        let returnedToSameCoordinates = RoamReadIdentity(accountID: 7, epoch: 10, role: "player",
            viewerRevision: 2, areaRevision: 5, manualMapApprovalRevision: approval)
        XCTAssertNotEqual(scope(), scope(identity: returnedToSameCoordinates, area: area))
    }

    func testScopeContainsNoPinsSelectionOrCredential() throws {
        let labels = Mirror(reflecting: try XCTUnwrap(scope())).children.compactMap(\.label)
        XCTAssertEqual(labels, ["readerID", "identity", "area"])
    }
}
