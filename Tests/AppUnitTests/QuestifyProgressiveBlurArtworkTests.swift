import XCTest
import UIKit
@testable import Questify

private actor BlurImageFixture: ObjectCardImageLoading {
    let data: Data
    private(set) var calls = 0
    init(_ data: Data) { self.data = data }
    func image(url: String) async throws -> Data { calls += 1; return data }
}
private actor DelayedBlurImageFixture: ObjectCardImageLoading {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<Data, Error>?
    private(set) var observedCancellation = false
    init(started: XCTestExpectation) { self.started = started }
    func image(url: String) async throws -> Data {
        let data: Data = try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started.fulfill() }
        observedCancellation = Task.isCancelled
        return data
    }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}

@MainActor final class QuestifyProgressiveBlurArtworkTests: XCTestCase {
    private func source() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { context in
            for x in 0..<64 {
                (x.isMultiple(of: 2) ? UIColor.white : UIColor.black).setFill()
                context.cgContext.fill(CGRect(x: CGFloat(x * 2), y: 0, width: 2, height: 128))
            }
        }
        return try XCTUnwrap(image.pngData())
    }
    private func pixels(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }
    private func request(version: String = "one", width: Double = 128, radius: Double = 16, enabled: Bool = true) throws -> ProgressiveArtworkRequest {
        .init(url: try XCTUnwrap(URL(string: "https://example.test/cover.png")),
              identity: .init(owner: "synthetic-owner", content: "cover", version: version),
              output: try XCTUnwrap(.init(pointWidth: width, pointHeight: 128, scale: 1)),
              parameters: try XCTUnwrap(.init(start: 0.3, end: 0.9, maxRadius: radius)),
              appearance: "light", increasedContrast: false, usesBlur: enabled)
    }
    func testHotDerivedCacheReturnsSamePixelsAndSeparateVersionNeverAliases() async throws {
        let renderer = ProgressiveArtworkRenderer(), data = try source(), first = try request()
        let a = try await renderer.render(data, request: first), b = try await renderer.render(data, request: first)
        XCTAssertTrue(a.image === b.image)
        let c = try await renderer.render(data, request: request(version: "replacement"))
        XCTAssertFalse(a.image === c.image)
        await renderer.clear()
        let afterClear = try await renderer.render(data, request: first)
        XCTAssertFalse(a.image === afterClear.image)
    }
    func testZeroRadiusAndTransparencyPerformanceFallbackUseTheSameSharpPixels() async throws {
        let renderer = ProgressiveArtworkRenderer(), data = try source()
        let zero = try await renderer.render(data, request: request(radius: 0))
        let fallback = try await renderer.render(data, request: request(enabled: false))
        XCTAssertEqual(zero.image.width, 128); XCTAssertEqual(zero.image.height, 128)
        XCTAssertEqual(try pixels(zero.image), try pixels(fallback.image))
    }
    func testSpatialFilterChangesLowerDetailWhileKeepingTopClearAndEdgesOpaque() async throws {
        let renderer = ProgressiveArtworkRenderer(), data = try source()
        let sharp = try await renderer.render(data, request: request(radius: 0)).image
        let blur = try await renderer.render(data, request: request()).image
        let a = try pixels(sharp), b = try pixels(blur)
        func detail(_ bytes: Data, row: Int, stride: Int) -> Int {
            (4..<124).reduce(0) { sum, x in sum + abs(Int(bytes[row * stride + x * 4]) - Int(bytes[row * stride + (x - 1) * 4])) }
        }
        XCTAssertEqual(Double(detail(a, row: 8, stride: sharp.bytesPerRow)), Double(detail(b, row: 8, stride: blur.bytesPerRow)), accuracy: 20)
        XCTAssertLessThan(detail(b, row: 116, stride: blur.bytesPerRow), detail(a, row: 116, stride: sharp.bytesPerRow) / 2)
        for y in [0, 127] { for x in [0, 127] { XCTAssertEqual(b[y * blur.bytesPerRow + x * 4 + 3], 255) } }
    }
    func testParameterAndSizeChangesReuseSingleOwnedDownload() async throws {
        let model = ProgressiveArtworkModel(), reader = BlurImageFixture(try source())
        await model.load(try request(), reader: reader)
        await model.load(try request(width: 96, radius: 8), reader: reader)
        let count = await reader.calls
        XCTAssertEqual(count, 1); XCTAssertNotNil(model.image)
        await model.load(try request(version: "new-source"), reader: reader)
        let replacementCount = await reader.calls
        XCTAssertEqual(replacementCount, 2)
    }
    func testPageRetirementAndMemoryPressureDiscardLateImageResult() async throws {
        for memory in [false, true] {
            let started = expectation(description: "owned image read started"), model = ProgressiveArtworkModel()
            let reader = DelayedBlurImageFixture(started: started), value = try request(), bytes = try source()
            let task = Task { await model.load(value, reader: reader) }
            await fulfillment(of: [started], timeout: 2)
            model.retire(memoryPressure: memory)
            await reader.finish(bytes); await task.value
            let cancelled = await reader.observedCancellation
            XCTAssertTrue(cancelled)
            XCTAssertNil(model.image); XCTAssertNil(model.loaded)
        }
    }
    func testSwiftUITaskCancellationReachesOwnedWorkerAndCannotPublishPixels() async throws {
        let started = expectation(description: "owned worker started"), model = ProgressiveArtworkModel()
        let reader = DelayedBlurImageFixture(started: started), value = try request(), bytes = try source()
        let task = Task { await model.load(value, reader: reader) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await reader.finish(bytes); await task.value
        let cancelled = await reader.observedCancellation
        XCTAssertTrue(cancelled); XCTAssertNil(model.image); XCTAssertNil(model.loaded)
    }

    func testRetiredLeaseRejectsUncancelledQueuedRenderAfterCacheClear() async throws {
        let renderer = ProgressiveArtworkRenderer(), data = try source(), value = try request()
        let lease = ProgressiveArtworkLease()
        let prior = try await renderer.render(data, request: value, lease: lease)
        lease.invalidate()
        await renderer.clear()
        XCTAssertFalse(Task.isCancelled)
        do {
            _ = try await renderer.render(data, request: value, lease: lease)
            XCTFail("A retired generation must not refill the cleared cache")
        } catch is CancellationError { }
        let current = try await renderer.render(data, request: value)
        XCTAssertFalse(prior.image === current.image)
    }

}
