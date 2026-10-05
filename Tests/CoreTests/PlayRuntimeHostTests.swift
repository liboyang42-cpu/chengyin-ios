import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayRuntimeHostTests: XCTestCase {
    private func api(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability> = [.mediaUpload]) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/source/")!), transport: transport, enabled: enabled)
    }
    func testUploadExactSourceMultipartAndTopLevelURL() async throws {
        let transport = PlayRuntimeHostTransport { _ in (Data(#"{"code":200,"url":"https://example.com/capture.png","data":{"url":"https://example.com/wrong.png"}}"#.utf8), 200) }
        let result = try await api(transport).uploadPhoto(Data([1,2,3]), mimeType: "image/png", token: "synthetic")
        XCTAssertEqual(result, "https://example.com/capture.png")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/source/api/common/uploadOSS"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"capture.png\""))
        for forbidden in ["bizType", "activityId", "topicId", "nodeId", "picUrl"] { XCTAssertFalse(body.contains(forbidden)) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUploadDoesNotFallbackToNestedURLOrRetry() async throws {
        let transport = PlayRuntimeHostTransport { _ in (Data(#"{"code":200,"data":{"url":"https://example.com/a.png"}}"#.utf8), 200) }
        do { _ = try await api(transport).uploadPhoto(Data([1]), mimeType: "image/png", token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .malformed) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testDormantUploadAndInvalidMediaNeverDispatch() async throws {
        let transport = PlayRuntimeHostTransport { _ in XCTFail("No network allowed"); return (Data(),200) }
        do { _ = try await api(transport, enabled: []).uploadPhoto(Data([1]), mimeType: "image/png", token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        do { _ = try await api(transport).uploadPhoto(Data(), mimeType: "image/png", token: "synthetic"); XCTFail() } catch {}
        do { _ = try await api(transport).uploadPhoto(Data([1]), mimeType: "video/mp4", token: "synthetic"); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testCapturedPhotoRequiresUploadThenReviewAndRejectsChangedIdentity() async throws {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        var context: PlayDeviceContext? = try .init(session: session, scope: .activity(4), nodeID: 9)
        var uploadCount = 0
        let model = PlayDeviceCaptureCoordinator(provider: PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1]), mimeType: "image/png") },
            upload: { bytes, mime, _ in XCTAssertEqual(bytes, Data([1])); XCTAssertEqual(mime, "image/png"); uploadCount += 1; return "https://example.com/selected.png" }, current: { context })
        await model.capture(.photo)
        XCTAssertNil(model.reviewedPhoto()); XCTAssertEqual(uploadCount, 0)
        await model.uploadPhoto()
        XCTAssertEqual(model.reviewedPhoto(), .photo(uploadedURL: "https://example.com/selected.png")); XCTAssertEqual(uploadCount, 1)
        context = nil; XCTAssertNil(model.reviewedPhoto()); XCTAssertFalse(model.canUpload)
        model.cancel(); XCTAssertNil(model.output); XCTAssertNil(model.uploadedPhoto)
    }
    func testLateUploadAfterCancelCannotBecomeEvidence() async throws {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let context = try PlayDeviceContext(session: session, scope: .topic(4), nodeID: 9)
        var resume: CheckedContinuation<String, Error>?
        let model = PlayDeviceCaptureCoordinator(provider: PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1]), mimeType: "image/png") },
            upload: { _, _, _ in try await withCheckedThrowingContinuation { resume = $0 } }, current: { context })
        await model.capture(.photo)
        let work = Task { await model.uploadPhoto() }
        while resume == nil { await Task.yield() }
        model.cancel(); resume?.resume(returning: "https://example.com/stale.png"); await work.value
        XCTAssertNil(model.reviewedPhoto()); XCTAssertNil(model.output); XCTAssertFalse(model.busy)
    }
    func testFilterBurnedBytesAreTheUploadInput() async throws {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let context = try PlayDeviceContext(session: session, scope: .topic(4), nodeID: 9)
        let model = PlayDeviceCaptureCoordinator(provider: PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1]), mimeType: "image/jpeg") },
            filter: { bytes, style in XCTAssertEqual(style, .nightVision); XCTAssertEqual(bytes, Data([1])); return Data([2]) },
            upload: { bytes, mime, _ in XCTAssertEqual(bytes, Data([2])); XCTAssertEqual(mime, "image/png"); return "https://example.com/filter.png" }, current: { context })
        await model.capture(.photo, photoFilter: .nightVision); await model.uploadPhoto()
        XCTAssertEqual(model.reviewedPhoto(), .photo(uploadedURL: "https://example.com/filter.png"))
        XCTAssertNil(PlayPhotoFilter(rawValue: "invented_ar"))
    }
}

private final class PlayRuntimeHostTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let response: (URLRequest) throws -> (Data, Int)
    init(_ response: @escaping (URLRequest) throws -> (Data, Int)) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try response(request) }
}
