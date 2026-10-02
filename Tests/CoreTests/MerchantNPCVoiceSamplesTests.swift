import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reserved .test endpoints are used only with the injected fake transports below.
@MainActor final class MerchantNPCVoiceSamplesTests: XCTestCase {
    @MainActor final class Fixture {
        let scope = MerchantNPCScope(accountID: 901, namespace: "synthetic.test", epoch: UUID(), merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
        func grants() -> MerchantNPCGrants { var g = MerchantNPCGrants(); g.server = true; g.provider = true; g.legal = true; g.resourceOwnership = true; g.voiceCloning = true; g.mediaTransmission = true; return g }
        func resource(_ http: MerchantNPCTests.HTTP, journal: any OperationPendingJournal) throws -> MerchantNPCResourcesCoordinator {
            let reader = MerchantOperationsFixtureReader()
            let voice = try JSONDecoder().decode(MerchantVoiceResource.self, from: Data(#"{"voiceStatus":0}"#.utf8))
            let avatar = try JSONDecoder().decode(MerchantAvatarResource.self, from: Data(#"{"available":true,"styles":["realistic"],"job":null}"#.utf8))
            reader.replace(.assets, with: .assets(.init(voice: voice, avatar: avatar)))
            return .init(scope: scope, client: .init(transport: http), reader: reader, journal: journal, currentScope: { self.scope }, grants: { self.grants() })
        }
    }
    final class Device: MerchantNPCVoiceDevice {
        var starts = 0; var plays = 0; var cancels = 0
        var next: MerchantNPCVoiceClip?
        var interruption: (() -> Void)?
        func start(configuration: MerchantNPCVoiceConfiguration, interrupted: @escaping () -> Void) async throws { starts += 1; interruption = interrupted }
        func finish() throws -> MerchantNPCVoiceClip? { next }
        func play(_ clip: MerchantNPCVoiceClip) throws { plays += 1 }
        func cancel() { cancels += 1 }
    }
    final class Upload: MerchantNPCVoiceUploading {
        var destination = "https://synthetic.test/api/common/uploadOSS"
        var calls: [Int] = []; var unknown = false
        func upload(_ clip: MerchantNPCVoiceClip, index: Int, scope: MerchantNPCScope) async throws -> MerchantNPCMediaReference {
            calls.append(index); if unknown { throw MerchantNPCFailure.unknownOutcome }
            return try .init(scope: scope, selectionID: clip.id, kind: .voiceSample(index: index), url: URL(string: "https://synthetic.test/\(index).m4a")!, approvedHosts: ["synthetic.test"])
        }
    }
    final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var json = #"{"code":200,"url":"https://synthetic.test/sample.m4a"}"#
        var after: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); after?(); return (Data(json.utf8), 200) }
    }
    func limits() throws -> MerchantNPCVoiceConfiguration { try .init(sampleRate: 16000, channels: 1, bitRate: 32000, minDuration: 1, maxDuration: 10, maxBytes: 1000, approvedHosts: ["synthetic.test"]) }
    func clip() -> MerchantNPCVoiceClip { .init(bytes: Data([0,0,0,12]) + Data("ftypM4A ".utf8), duration: 2) }
    func local() -> MerchantNPCVoiceLocalGrants { var g = MerchantNPCVoiceLocalGrants(); g.capture = true; g.playback = true; return g }
    func consumer(_ helper: Fixture, device: Device, upload: Upload, journal: MerchantNPCTests.Journal, localEnabled: Bool = true) async throws -> MerchantNPCVoiceSamplesCoordinator {
        let resources = try helper.resource(MerchantNPCTests.HTTP(), journal: journal); await resources.refresh()
        return .init(resources: resources, configuration: try limits(), device: device, uploader: upload, journal: journal, grants: { helper.grants() }, localGrants: { localEnabled ? self.local() : .init() })
    }
    func fill(_ c: MerchantNPCVoiceSamplesCoordinator, _ d: Device) async {
        c.attest(ownsVoice: true, consent: true)
        for index in 0..<5 { d.next = clip(); await c.record(index); c.finish() }
    }
    func testDefaultLocalGrantsBlockDevice() async throws {
        let h = Fixture(), d = Device(), u = Upload(), j = MerchantNPCTests.Journal()
        let c = try await consumer(h, device: d, upload: u, journal: j, localEnabled: false)
        c.attest(ownsVoice: true, consent: true); await c.record(0); c.play(0)
        XCTAssertEqual(d.starts, 0); XCTAssertEqual(d.plays, 0); XCTAssertTrue(u.calls.isEmpty)
    }
    func testConsentFirstAndNilPreservesPrior() async throws {
        let h = Fixture(), d = Device(), u = Upload(), j = MerchantNPCTests.Journal()
        let c = try await consumer(h, device: d, upload: u, journal: j)
        c.attest(ownsVoice: true, consent: true); await c.record(1); XCTAssertEqual(d.starts, 0)
        d.next = clip(); await c.record(0); c.finish(); let id = c.clips[0]?.id
        d.next = nil; await c.record(0); c.finish(); XCTAssertEqual(c.clips[0]?.id, id)
        await c.record(0); d.interruption?(); XCTAssertNil(c.recording); XCTAssertEqual(c.clips[0]?.id, id)
    }
    func testFiveSeparateReviewsAndEnrollmentUsesExistingReview() async throws {
        let h = Fixture(), d = Device(), u = Upload(), j = MerchantNPCTests.Journal()
        let c = try await consumer(h, device: d, upload: u, journal: j); await fill(c, d)
        await c.confirmUpload(UUID()); XCTAssertTrue(u.calls.isEmpty)
        for index in 0..<5 { c.prepareUpload(); let review = try XCTUnwrap(c.review); XCTAssertEqual(review.index, index); await c.confirmUpload(review.id); await c.confirmUpload(review.id) }
        XCTAssertEqual(u.calls, [0,1,2,3,4]); c.prepareEnrollment()
        guard case .enroll(let samples, _) = c.resources.review?.action else { return XCTFail() }
        XCTAssertEqual(samples.map(\.kind), (0..<5).map { .voiceSample(index: $0) })
        XCTAssertEqual(c.resources.outcome, .reviewed)
    }
    func testUnknownSurvivesRecreationAndOnlyMetadataPersists() async throws {
        let h = Fixture(), d = Device(), u = Upload(), j = MerchantNPCTests.Journal(); u.unknown = true
        let c = try await consumer(h, device: d, upload: u, journal: j); await fill(c, d); c.prepareUpload()
        await c.confirmUpload(try XCTUnwrap(c.review).id); XCTAssertTrue(c.unresolved); c.invalidate(); XCTAssertTrue(c.clips.isEmpty); XCTAssertTrue(c.uploaded.isEmpty)
        let next = try await consumer(h, device: Device(), upload: u, journal: j); XCTAssertTrue(next.unresolved); XCTAssertTrue(next.resources.hasUnresolvedWrite)
        let json = String(decoding: try JSONEncoder().encode(XCTUnwrap(j.records.values.first)), as: UTF8.self)
        XCTAssertFalse(json.contains("ftyp")); XCTAssertFalse(json.contains("m4a")); XCTAssertFalse(json.contains("url")); XCTAssertEqual(u.calls, [0])
    }
    func testRevokingAttestationDropsMediaAndReview() async throws {
        let h = Fixture(), d = Device(), u = Upload(), j = MerchantNPCTests.Journal()
        let c = try await consumer(h, device: d, upload: u, journal: j); await fill(c, d); c.prepareUpload()
        c.attest(ownsVoice: false, consent: false); XCTAssertTrue(c.clips.isEmpty); XCTAssertNil(c.review); XCTAssertFalse(c.ready)
    }
    func adapter(_ h: Fixture, _ http: HTTP, enabled: Bool, scope: @escaping () -> MerchantNPCScope?) throws -> MerchantNPCVoiceUpload {
        let config = try APIConfiguration(baseURL: URL(string: "https://synthetic.test")!)
        return .init(configuration: config, limits: try limits(), transport: http, enabled: enabled, approval: try .init(baseURL: config.baseURL, namespace: h.scope.namespace, accountID: h.scope.accountID, paths: ["api/common/uploadOSS"]), currentScope: scope, token: { "synthetic-token" }, grants: { h.grants() })
    }
    func testUploadDisabledWithoutCallingHTTP() async throws {
        let h = Fixture(), http = HTTP(); let a = try adapter(h, http, enabled: false, scope: { h.scope })
        do { _ = try await a.upload(clip(), index: 0, scope: h.scope); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }; XCTAssertTrue(http.requests.isEmpty)
    }
    func testExactMultipartAndTopLevelURL() async throws {
        let h = Fixture(), http = HTTP(); let a = try adapter(h, http, enabled: true, scope: { h.scope })
        let sample = clip(); let ref = try await a.upload(sample, index: 0, scope: h.scope)
        XCTAssertEqual(ref.selectionID, sample.id); let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"sample-1.m4a\"")); XCTAssertTrue(body.contains("name=\"fileType\"\r\n\r\nm4a")); XCTAssertFalse(body.contains("bizId"))
    }
    func testNestedURLAndStaleScopeAreUnknown() async throws {
        let h = Fixture(), http = HTTP(); var current: MerchantNPCScope? = h.scope
        let a = try adapter(h, http, enabled: true, scope: { current })
        http.json = #"{"code":200,"data":{"url":"https://synthetic.test/a.m4a"}}"#
        do { _ = try await a.upload(clip(), index: 0, scope: h.scope); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .unknownOutcome) }
        http.after = { current = nil }
        do { _ = try await a.upload(clip(), index: 0, scope: h.scope); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .unknownOutcome) }
    }
    func testValidationRequiresContainerAndConfiguredBounds() throws {
        XCTAssertThrowsError(try limits().validate(.init(bytes: Data("arbitrary".utf8), duration: 2)))
        XCTAssertThrowsError(try limits().validate(.init(bytes: clip().bytes, duration: 11)))
    }
}
