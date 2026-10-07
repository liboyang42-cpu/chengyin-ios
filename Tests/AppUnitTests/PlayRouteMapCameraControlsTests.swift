import XCTest
import SwiftUI
@testable import Questify

@MainActor final class PlayRouteMapCameraControlsTests: XCTestCase {
    private let raw = #"{"mode":1,"playable":true,"nodes":[{"nodeId":1,"name":"A long visible stop with the complete destination name · 完整地点名称必须保留到最后，不能省略重要信息","address":"A long address with entrance details exactly as supplied · 来源提供的完整地址与入口说明必须保留","done":false,"latitude":31,"longitude":121}]}"#
    private func presentation() throws -> PlayRouteMapPresentation {
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
        return try XCTUnwrap(PlayRouteMapPresentation(snapshot: PlaySnapshot(scope: .activity(41), result: result)))
    }
    func testCameraControlsAndFullPreviewGrowAtMaximumTextInBothLanguages() throws {
        let value = try presentation()
        func height(_ locale: String, _ size: DynamicTypeSize) -> CGFloat {
            let view = PlayRouteMapCameraControls(presentation: value, preview: value.stops.first, issue: .missingCoordinates,
                request: { _ in nil }, onFocus: { _ in XCTFail("Rendering must not invoke a camera command") },
                onOpen: { _ in XCTFail("Rendering must not navigate") })
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(size)
                .fixedSize(horizontal: false, vertical: true)
            return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000)).height
        }
        for locale in ["en", "zh-Hans"] {
            let normal = height(locale, .large), maximum = height(locale, .accessibility5)
            XCTAssertGreaterThan(normal, 0); XCTAssertGreaterThan(maximum, normal)
            XCTAssertTrue(maximum.isFinite); XCTAssertLessThan(maximum, 15_000)
        }
    }
    func testRenderingCameraControlsCannotStartReadsOrAlterTaskProgress() async throws {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/controls/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw), 200)
        let session = try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic")
        let model = PlayExperienceCoordinator(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/controls")!), transport: wire, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await model.load(); let before = try XCTUnwrap(model.snapshot), context = model.interactionContext
        let read = try XCTUnwrap(PlayRouteMapCamera.Read(snapshot: before, context: context))
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let view = PlayRouteMapCameraControls(presentation: read.presentation, preview: nil, issue: nil,
            request: { gate.request($0, read: read) }, onFocus: { _ in XCTFail("Rendering must not focus") }, onOpen: { _ in XCTFail("Rendering must not open a task") })
        _ = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 320, height: 10_000))
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.interactionContext, context); XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.canWrite); XCTAssertFalse(model.canManageRun)
    }
}
