import XCTest
import Combine
import UIKit
@testable import Questify

@MainActor final class RoamShareAlbumGuideFlowTests: XCTestCase {
    private final class Writer: RoamSharePhotoWriting {
        var status: RoamSharePhotoSaveState.Authorization = .authorized
        var writes = 0
        var image: UIImage?
        var started: (() -> Void)?
        var result: CheckedContinuation<Void, Error>?
        func authorizationStatus() -> RoamSharePhotoSaveState.Authorization { status }
        func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization { .denied }
        func add(_ image: UIImage) async throws {
            writes += 1; self.image = image
            try await withCheckedThrowingContinuation { result = $0; started?() }
        }
    }
    private var subscriptions: Set<AnyCancellable> = []
    private func selection(_ fields: [String: Any] = [:]) throws -> RoamSharePhotoSaveState.Selection {
        let fields = ["ts": 1700000000000 as Any].merging(fields) { _, new in new }
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        return .init(record: record, includeRoute: false)
    }
    private func completed(_ model: RoamSharePhotoSaveModel) -> XCTestExpectation {
        let done = expectation(description: "Synthetic Photos completion")
        model.$inFlight.dropFirst().filter { !$0 }.first().sink { _ in done.fulfill() }.store(in: &subscriptions)
        return done
    }
    func testGuideWaitsForWriteCompletionAndUsesSameImage() async throws {
        let writer = Writer(), image = UIImage(), selection = try selection(["shops": 2])
        let model = RoamSharePhotoSaveModel(writer: writer)
        var guide = RoamShareAlbumGuideState()
        let request = try XCTUnwrap(guide.begin(destination: .moments, selection: selection, saveInFlight: model.inFlight))
        let started = expectation(description: "Synthetic write submitted"), done = completed(model)
        writer.started = { started.fulfill() }
        model.save(image, selection: selection) { guide.accepts(request) }
        await fulfillment(of: [started], timeout: 2)
        guide.receive(request, phase: model.state.phase, current: selection, sourceIsCurrent: true)
        XCTAssertNil(guide.guide); XCTAssertTrue(writer.image === image)
        writer.result?.resume(); await fulfillment(of: [done], timeout: 2)
        guide.receive(request, phase: model.state.phase, current: selection, sourceIsCurrent: true)
        XCTAssertEqual(guide.guide?.destination, .moments); XCTAssertEqual(writer.writes, 1)
        guide.dismissGuide()
        // Mirrors the existing-saved receipt branch; another guide needs no duplicate write.
        let next = try XCTUnwrap(guide.begin(destination: .xiaohongshu, selection: selection, saveInFlight: model.inFlight))
        XCTAssertEqual(model.state.selection, selection)
        guide.receive(next, phase: model.state.phase, current: selection, sourceIsCurrent: true)
        XCTAssertEqual(guide.guide?.destination, .xiaohongshu); XCTAssertEqual(writer.writes, 1)
    }
    func testWriteFailureNeverShowsSavedOrPostedGuide() async throws {
        let writer = Writer(), selection = try selection(), model = RoamSharePhotoSaveModel(writer: writer)
        var guide = RoamShareAlbumGuideState()
        let request = try XCTUnwrap(guide.begin(destination: .moments, selection: selection, saveInFlight: false))
        let started = expectation(description: "Synthetic write submitted"), done = completed(model)
        writer.started = { started.fulfill() }
        model.save(UIImage(), selection: selection) { guide.accepts(request) }
        await fulfillment(of: [started], timeout: 2)
        writer.result?.resume(throwing: NSError(domain: "synthetic", code: 1))
        await fulfillment(of: [done], timeout: 2)
        guide.receive(request, phase: model.state.phase, current: selection, sourceIsCurrent: true)
        XCTAssertEqual(model.state.phase, .failed); XCTAssertNil(guide.guide)
    }
    func testInvalidationWhileWritingCannotShowLateGuide() async throws {
        let writer = Writer(), selection = try selection(), model = RoamSharePhotoSaveModel(writer: writer)
        var guide = RoamShareAlbumGuideState()
        let request = try XCTUnwrap(guide.begin(destination: .moments, selection: selection, saveInFlight: false))
        let started = expectation(description: "Synthetic write submitted"), done = completed(model)
        writer.started = { started.fulfill() }
        model.save(UIImage(), selection: selection) { guide.accepts(request) }
        await fulfillment(of: [started], timeout: 2)
        guide.invalidate(); model.invalidate(); writer.result?.resume()
        await fulfillment(of: [done], timeout: 2)
        guide.receive(request, phase: .saved, current: selection, sourceIsCurrent: true)
        XCTAssertNil(guide.guide)
    }
    func testCopyOmitsUnknownsAndPrivateRecordFields() throws {
        let selection = try selection(["ts": 0, "zone": "SECRET-ZONE", "photos": ["https://example.com/secret.jpg"], "medal": "SECRET-MEDAL"])
        let text = RoamShareAlbumGuideCopy.text(.init(record: selection.record), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(text, "#城瘾CityFog")
    }
    func testCopyFormatsKnownZeroAndLocaleDecimal() throws {
        let selection = try selection(["ts": 0, "shops": 0, "distance": 1.5, "explorePct": 0])
        let text = RoamShareAlbumGuideCopy.text(.init(record: selection.record), locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(text.contains("1,5 km")); XCTAssertTrue(text.contains("0%")); XCTAssertTrue(text.hasSuffix("#城瘾CityFog"))
    }
}
