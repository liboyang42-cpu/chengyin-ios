import XCTest
import UIKit
import Combine
import ImageIO
@testable import Questify

@MainActor final class RoamMedalShareCardTests: XCTestCase {
    private final class Reader: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var records: [RoamHistoryRecord] = []
        func history() throws -> [RoamHistoryRecord] { records }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
    }
    private final class Writer: RoamSharePhotoWriting {
        var status: RoamSharePhotoSaveState.Authorization = .authorized
        var image: UIImage?
        var writes = 0
        var permission: CheckedContinuation<RoamSharePhotoSaveState.Authorization, Never>?
        var requested: (() -> Void)?
        func authorizationStatus() -> RoamSharePhotoSaveState.Authorization { status }
        func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization {
            await withCheckedContinuation { permission = $0; requested?() }
        }
        func add(_ image: UIImage) async throws { self.image = image; writes += 1 }
    }
    private var subscriptions: Set<AnyCancellable> = []
    private func selection(name: String = "真实已得勋章", timestamp: Int64 = 1700000000000) throws -> RoamMedalShareSelection {
        let bytes = try JSONSerialization.data(withJSONObject: ["ts": timestamp, "medal": name])
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: bytes)
        return try XCTUnwrap(RoamMedalShareSelection(record: record, kind: .journey))
    }
    private func reader(_ selection: RoamMedalShareSelection) throws -> Reader {
        let reader = Reader()
        reader.identity = .init(scope: try .init(market: "cn", deployment: URL(string: "https://example.com/")!, accountID: 7), epoch: 1)
        reader.records = [selection.record]; return reader
    }
    private func completed(_ model: RoamSharePhotoSaveModel) -> XCTestExpectation {
        let done = expectation(description: "Synthetic photo save completed")
        model.$inFlight.dropFirst().filter { !$0 }.first().sink { _ in done.fulfill() }.store(in: &subscriptions)
        return done
    }
    func testRendererCreatesPortraitCardWithoutGPSMetadata() throws {
        let image = try XCTUnwrap(RoamMedalShareRenderer.render(selection().card))
        XCTAssertEqual(image.cgImage?.width, 750); XCTAssertEqual(image.cgImage?.height, 1000)
        let data = try XCTUnwrap(image.pngData())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
    }
    func testLongUnicodeNameAndUnknownDateStillRender() throws {
        let value = try selection(name: String(repeating: "城瘾 Café 🏅", count: 12), timestamp: 0)
        XCTAssertNil(value.card.recordedAt)
        let image = try XCTUnwrap(RoamMedalShareRenderer.render(value.card))
        XCTAssertEqual(image.cgImage?.height, 1000)
    }
    func testSaveUsesExactlyThePreviewImageAndDoesNotWriteTwice() async throws {
        let value = try selection(), reader = try reader(value), writer = Writer()
        let authority = try XCTUnwrap(RoamMedalShareAuthority(selection: value, reader: reader))
        let image = try XCTUnwrap(RoamMedalShareRenderer.render(value.card))
        let model = RoamSharePhotoSaveModel(writer: writer), done = completed(model)
        let source = RoamSharePhotoSaveState.Selection(record: value.record, includeRoute: false)
        model.save(image, selection: source) { authority.isCurrent(reader) }
        model.save(image, selection: source) { authority.isCurrent(reader) }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(writer.image === image); XCTAssertEqual(writer.writes, 1); XCTAssertEqual(model.state.phase, .saved)
    }
    func testAccountChangeWhilePermissionPendingPreventsSave() async throws {
        let value = try selection(), reader = try reader(value), writer = Writer()
        writer.status = .notDetermined
        let authority = try XCTUnwrap(RoamMedalShareAuthority(selection: value, reader: reader))
        let requested = expectation(description: "Synthetic permission requested")
        writer.requested = { requested.fulfill() }
        let model = RoamSharePhotoSaveModel(writer: writer), done = completed(model)
        model.save(UIImage(), selection: .init(record: value.record, includeRoute: false)) { authority.isCurrent(reader) }
        await fulfillment(of: [requested], timeout: 2)
        reader.identity = nil; writer.permission?.resume(returning: .authorized)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(writer.writes, 0); XCTAssertEqual(model.state.phase, .sourceChanged)
    }
    func testRemovedMedalWhilePermissionPendingPreventsSave() async throws {
        let value = try selection(), reader = try reader(value), writer = Writer()
        writer.status = .notDetermined
        let authority = try XCTUnwrap(RoamMedalShareAuthority(selection: value, reader: reader))
        let requested = expectation(description: "Synthetic permission requested")
        writer.requested = { requested.fulfill() }
        let model = RoamSharePhotoSaveModel(writer: writer), done = completed(model)
        model.save(UIImage(), selection: .init(record: value.record, includeRoute: false)) { authority.isCurrent(reader) }
        await fulfillment(of: [requested], timeout: 2)
        reader.records = []; writer.permission?.resume(returning: .authorized)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(writer.writes, 0); XCTAssertEqual(model.state.phase, .sourceChanged)
    }
}
