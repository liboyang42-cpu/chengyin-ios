import XCTest
import CryptoKit
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class OwnedTopicCoverClientTests: XCTestCase {
    private final class Scope {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "author-cover-client")
        var approval: OwnedTopicCoverApproval?
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []; var bytes = Data(); var status = 200
        var hold = false; var began: XCTestExpectation?; var continuation: CheckedContinuation<(Data,Int),Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if hold { return try await withCheckedThrowingContinuation { continuation = $0; began?.fulfill() } }
            return (bytes, status)
        }
        func finish() { let c = continuation; continuation = nil; c?.resume(returning: (bytes,status)) }
        func reply(_ value: ProjectEditJSON) throws { bytes = try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": value]) }
    }
    private func asset(_ hash: String = String(repeating: "a", count: 64), owner: Int = 7) -> ProjectEditJSON {
        .object(["kind":.string("OWNED_TOPIC_COVER_V1"),"id":.string("11111111-1111-4111-8111-111111111111"),"assetId":.string("11111111-1111-4111-8111-111111111111"),"sourceVersion":.string("22222222-2222-4222-8222-222222222222"),"contentHash":.string(hash),"owner":.number(Decimal(owner)),"ownerMemberId":.number(Decimal(owner)),"policyVersion":.string("OWNED_TOPIC_COVER_V1")])
    }
    private func currentFields() -> ProjectEditJSON {
        .object(["topicId":.number(101),"topicConfigVersion":.number(4),"selectionVersion":.number(0),"contentSlotId":.number(51),"selectedAtConfigVersion":.null,"selectionState":.string("NONE"),"assetAvailability":.string("NONE"),"display":.null])
    }
    private func client(_ scope: Scope, wire: Wire, operations: Set<OwnedTopicCoverOperation>? = [.readCurrent,.readAsset,.upload,.select,.status]) throws -> OwnedTopicCoverClient {
        let configuration = try APIConfiguration(baseURL: URL(string:"https://example.com")!)
        scope.approval = try operations.map { try .init(baseURL:configuration.baseURL,namespace:scope.session.storageNamespace,accountID:7,operations:$0) }
        return .init(configuration:configuration,approval:scope.approval,jsonTransport:wire,imageTransport:wire,
                     currentCredentials:{ try? .init(session:scope.session,token:"synthetic-owner-token") },currentApproval:{scope.approval})
    }
    func testAbsentIndependentCapabilityHasZeroDispatchAndNativePickerIsSeparatelyOff() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire,operations:nil)
        do { _=try await source.current(topicID:101,session:scope.session);XCTFail() } catch { XCTAssertEqual(error as? OwnedTopicCoverFailure,.notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
        let readable=try client(scope,wire:wire);XCTAssertTrue(readable.permits(.upload,session:scope.session));XCTAssertFalse(readable.permitsNativePicker(session:scope.session))
    }
    func testRealCurrentWirePreservesExactCASAndDoesNotInventAssetForNone() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire);try wire.reply(currentFields())
        let current=try await source.current(topicID:101,session:scope.session)
        XCTAssertEqual(current.configVersion,4);XCTAssertEqual(current.contentSlotID,51);XCTAssertEqual(current.selectionVersion,0);XCTAssertNil(current.asset)
        let request=try XCTUnwrap(wire.requests.first);XCTAssertEqual(request.httpMethod,"GET");XCTAssertEqual(request.url?.path,"/api/topic/cover/selection/current");XCTAssertEqual(request.url?.query,"topicId=101")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"synthetic-owner-token");XCTAssertNil(request.httpBody)
    }
    func testUploadUsesOnlySanitizedSelectedBytesAndDoesNotTreatLocalHashAsServerOutput() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire);try wire.reply(asset())
        let local=try RetainedSelectedImage(jpeg:Data([255,216,255,1,2,3]),width:1,height:1)
        let result=try await source.upload(local,session:scope.session);XCTAssertEqual(result.contentHash,String(repeating:"a",count:64))
        let request=try XCTUnwrap(wire.requests.first),body=try XCTUnwrap(request.httpBody)
        XCTAssertEqual(request.url?.path,"/api/topic/cover/upload");XCTAssertEqual(request.httpMethod,"POST")
        XCTAssertNotNil(body.range(of:local.jpeg));XCTAssertTrue(String(decoding:body,as:UTF8.self).contains("name=\"file\"; filename=\"cover.jpg\""))
        XCTAssertFalse(String(decoding:body,as:UTF8.self).contains("ownerMemberId"));XCTAssertEqual(wire.requests.count,1)
    }
    func testBodyReadIsExactOwnerUUIDVersionAndDigestWithNoCallerURL() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire)
        wire.bytes=Data("synthetic fixed image body".utf8);let hash=SHA256.hash(data:wire.bytes).map {String(format:"%02x",$0)}.joined()
        let ref=try OwnedTopicCoverAsset.decode(asset(hash),owner:7)
        let received = try await source.content(ref,session:scope.session); XCTAssertEqual(received,wire.bytes)
        let request=try XCTUnwrap(wire.requests.first);XCTAssertEqual(request.url?.path,"/api/topic/cover/11111111-1111-4111-8111-111111111111/content")
        XCTAssertEqual(request.url?.query,"sourceVersion=22222222-2222-4222-8222-222222222222&contentHash=\(hash)")
        wire.bytes.append(0)
        do {_=try await source.content(ref,session:scope.session);XCTFail()}catch{XCTAssertEqual(error as? OwnedTopicCoverFailure,.invalidResponse)}
    }
    func testLateEmpty401AfterConfigurationABADoesNotBecomeCurrentUnauthorized() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire),captured=scope.session
        wire.hold=true;wire.began=expectation(description:"actual GET dispatched")
        let task=Task{try await source.current(topicID:101,session:captured)}
        await fulfillment(of:[try XCTUnwrap(wire.began)],timeout:1)
        scope.session=try .init(accountID:7,epoch:1,storageNamespace:captured.storageNamespace,configurationRevision:2)
        wire.bytes=Data();wire.status=401;wire.finish()
        do{_=try await task.value;XCTFail()}catch{XCTAssertEqual(error as? OwnedTopicCoverFailure,.changedContext)}
    }
    func testCurrentEmpty401StillRemainsUnauthorized() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire);wire.status=401;wire.bytes=Data()
        do{_=try await source.current(topicID:101,session:scope.session);XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}
    }
    func testSelectionAndStatusSendSameEightFieldsAndValidateMonotonicReceipt() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire)
        let current=try OwnedTopicCoverCurrent.decode(currentFields(),topicID:101,owner:7),ref=try OwnedTopicCoverAsset.decode(asset(),owner:7)
        let command=OwnedTopicCoverSelectionCommand(current:current,asset:ref)
        try wire.reply(.object(["topicId":.number(101),"topicConfigVersion":.number(5),"selectionVersion":.number(1),"contentSlotId":.number(51),"cover":asset()]))
        let receipt=try await source.select(command,session:scope.session),recovered=try await source.status(command,session:scope.session)
        XCTAssertEqual(receipt,recovered);XCTAssertEqual(receipt.selectionVersion,1)
        XCTAssertEqual(wire.requests[0].httpBody,wire.requests[1].httpBody)
        XCTAssertEqual(try JSONDecoder().decode([String:ProjectEditJSON].self,from:XCTUnwrap(wire.requests[0].httpBody)),command.fields)
        XCTAssertEqual(command.fields.count,8);wire.status=409
        do{_=try await source.status(command,session:scope.session);XCTFail()}catch{XCTAssertEqual(error as? OwnedTopicCoverFailure,.outcomeUnknown)}
    }
    func testImageFlowOwnsActualReadAndCloseRejectsLateUnauthorized() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire),ref=try OwnedTopicCoverAsset.decode(asset(),owner:7)
        let flow=OwnedTopicCoverImageFlow(asset:ref,session:scope.session,source:source,stillPresented:{true})
        wire.hold=true;wire.began=expectation(description:"actual body read held")
        let first=Task{await flow.load()};await fulfillment(of:[try XCTUnwrap(wire.began)],timeout:1)
        await flow.load();XCTAssertEqual(wire.requests.count,1);flow.close();wire.status=401;wire.finish();await first.value
        XCTAssertEqual(flow.state,.closed);XCTAssertEqual(wire.requests.count,1)
    }
    func testImageFlowRejectsReturnedBytesAfterParentPresentationChanges() async throws {
        let scope=Scope(),wire=Wire(),source=try client(scope,wire:wire)
        wire.bytes=Data("exact body".utf8);let hash=SHA256.hash(data:wire.bytes).map{String(format:"%02x",$0)}.joined()
        let ref=try OwnedTopicCoverAsset.decode(asset(hash),owner:7)
        var presented=true;let flow=OwnedTopicCoverImageFlow(asset:ref,session:scope.session,source:source,stillPresented:{presented})
        wire.hold=true;wire.began=expectation(description:"actual body read held")
        let task=Task{await flow.load()};await fulfillment(of:[try XCTUnwrap(wire.began)],timeout:1)
        presented=false;wire.finish();await task.value;XCTAssertEqual(flow.state,.closed)
    }

}
