import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor enum WorkshopProfessionalAppFixture {
    static let instant = "2026-10-06T00:00:00Z"
    static func data(_ value: [String: Any]) throws -> Data { try WorkshopPaidTextAppFixture.data(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T { try WorkshopPaidTextAppFixture.decode(type, value) }
    static var target: [String: Any] { ["topicId":501,"name":"Synthetic city target","productType":1,"mode":"CITY_ORIENTATION","routeConfigVersion":4,"ownerModeFingerprint":String(repeating:"d",count:64),"fingerprintProfile":"W18_CONTENT_OWNER_MODE_V1","materializationStatus":"PROTECTED_TEMPLATE_ADAPTER_REQUIRED"] }
    static var draft: [String: Any] { ["targetDraftId":91,"targetRevision":2,"businessType":"TOPIC","targetPayloadHash":String(repeating:"e",count:64),"mode":"UNRESOLVED","destinationKind":"W18_PRIVATE_COMPONENT_ONLY"] }
    static func command() throws -> WorkshopPaidProfessionalCommand {
        try .init(reference: WorkshopPaidTextAppFixture.reference(), body: decode(WorkshopPaidInstalledText.self, WorkshopPaidTextAppFixture.body()),
                  currentDraft: decode(WorkshopPaidInstallTarget.self, draft), target: decode(WorkshopPaidProfessionalTarget.self, target), confirmedMode: .city,
                  requestID: UUID(uuidString:"00000000-0000-4000-8000-000000000002")!)
    }
    static func operation(_ command: WorkshopPaidProfessionalCommand, state: String) -> [String: Any] {
        var v: [String: Any] = ["schema":"w18-paid-professional-operation-v1","scope":"OWNER_OPERATION_METADATA_ONLY","requestId":command.requestId,"state":state,"safeToReplace":["REJECTED","CANCELLED"].contains(state)]
        if state == "NOT_FOUND" { return v }
        v["commandHash"] = command.commandHash; v["createdAt"] = instant; v["updatedAt"] = instant
        v["rejectionCode"] = state == "REJECTED" ? "CURRENT_SOURCE_OR_TARGET_UNAVAILABLE" as Any : NSNull(); v["creation"] = NSNull()
        if state == "CREATED" {
            v["creation"] = ["schema":"w18-paid-professional-materialization-status-v1","scope":"OWNER_HISTORICAL_CREATION_REFERENCE_ONLY","requestId":command.requestId,"state":"CREATION_COMMITTED","templateId":700,"targetTopicId":command.targetTopicId,"ownedDraftId":command.ownedDraftId,"confirmedMode":command.confirmedMode.rawValue,"licenseId":command.licenseId,"purchasedVersionId":command.purchasedVersionId,"templateContentHash":String(repeating:"f",count:64),"createdAt":instant,"currentTemplateState":"NOT_CHECKED","currentUseAuthority":"NOT_GRANTED_BY_HISTORY"] as [String: Any]
        }
        return v
    }
    static func record(_ c: WorkshopPaidProfessionalCommand) throws -> [String: Any] { ["operationKey":String(repeating:"a",count:64),"commandHash":c.commandHash,"createdAt":instant,"command":try JSONSerialization.jsonObject(with:c.wireData())] }
}
@MainActor final class WorkshopPaidProfessionalNormalFlowTests: XCTestCase {
    typealias F = WorkshopProfessionalAppFixture
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = [], delay = false, state = "NOT_FOUND"
        var command: WorkshopPaidProfessionalCommand?, suspended: CheckedContinuation<(Data, Int), Never>?
        var operations: [URLRequest] { requests.filter { $0.url!.path.contains("professional-") } }
        var writes: [URLRequest] { operations.filter { ["submit","cancel"].contains($0.url!.lastPathComponent) } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            func response(_ value: [String: Any]) throws -> (Data, Int) { (try F.data(["code":200,"data":value]),200) }
            if path.contains("professional-") && delay { delay = false; return await withCheckedContinuation { suspended = $0 } }
            if path.hasSuffix("/installed-text/detail") { return (try WorkshopPaidTextAppFixture.envelope(),200) }
            if path.hasSuffix("/install/targets") { return try response(["schema":"w18-paid-install-targets-v1","scope":"OWNER_DRAFT_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":F.instant,"items":[F.draft],"hasMore":false,"nextBeforeDraftId":NSNull()]) }
            if path.hasSuffix("/professional-targets/list") { return try response(["schema":"w18-owned-professional-topic-targets-v1","scope":"INDIVIDUAL_CONTENT_OWNER_AND_PUBLISHER_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":F.instant,"items":[F.target],"hasMore":false,"nextBeforeTopicId":NSNull()]) }
            if path.hasSuffix("/professional-targets/detail") { return try response(F.target) }
            if path.hasSuffix("/professional-operations/history") { return try response(["schema":"w18-paid-professional-operation-history-v1","scope":"OWNER_OPERATION_INTENT_REFERENCES_ONLY","licenseId":"w18-paid-11","items":command.map { [try! F.record($0)] } ?? [],"scannedCount":command == nil ? 0 : 1,"hasMore":false,"nextBeforeOperationKey":NSNull()]) }
            if path.hasSuffix("/professional-operations/status") {
                if let command { return try response(F.operation(command,state:state)) }
                let input = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
                return try response(["schema":"w18-paid-professional-operation-v1","scope":"OWNER_OPERATION_METADATA_ONLY","requestId":input["requestId"]!,"state":"NOT_FOUND","safeToReplace":false])
            }
            if path.hasSuffix("/professional-operations/submit") || path.hasSuffix("/professional-operations/cancel") {
                command = try WorkshopPaidInstallWire.decode(WorkshopPaidProfessionalCommand.self,data:request.httpBody!)
                state = path.hasSuffix("/cancel") && state != "CREATED" ? "CANCELLED" : "CREATED"
                return try response(F.operation(command!,state:state))
            }
            switch request.url!.lastPathComponent {
            case "phone": return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8),200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200)
            case "logout": return (Data(#"{"code":200}"#.utf8),200)
            default: throw APIError.invalidRequest
            }
        }
        func wait() async { for _ in 0..<1000 { if suspended != nil { return }; await Task.yield() }; XCTFail("Expected suspended normal request") }
        func resume401() { let old = suspended; suspended = nil; old?.resume(returning:(Data(),401)) }
    }
    @MainActor private final class Harness {
        let wire = Wire(), vault = Vault(), base = URL(string:"https://example.com/native")!, suite = "professional-" + UUID().uuidString
        let deployment: ReviewedAppDeployment
        var session: AppSession!, root: AppCompositionRoot!
        var read: WorkshopPaidProfessionalReadApproval?, write: WorkshopPaidProfessionalWriteApproval?
        var body: WorkshopPaidInstalledTextApproval?, install: WorkshopPaidInstallApproval?, seen = 0
        init() throws {
            deployment = try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.workshop.professional",realm:"synthetic-"+UUID().uuidString.lowercased())
            root = AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:suite)!,tokenStore:{[vault] _ in vault}),makeTransport:{[wire] in wire},
                workshopPaidProfessionalReadApproval:{[weak self] c in guard let self, self.valid(c) else { return nil }; return self.read },
                workshopPaidProfessionalWriteApproval:{[weak self] c in guard let self, self.valid(c) else { return nil }; return self.write },
                workshopPaidInstalledTextApproval:{[weak self] c in guard let self, self.valid(c) else { return nil }; return self.body },
                workshopPaidInstallApproval:{[weak self] c in guard let self, let expected = try? self.context(canonical:false) else { return nil }; XCTAssertEqual(c,expected); return c == expected ? self.install : nil })
            session = root.makeSession()
        }
        func valid(_ c: RuntimeDependencyContext) -> Bool { guard let expected = try? context() else { return false }; seen += 1; XCTAssertEqual(c,expected); XCTAssertEqual(c.role,c.session.role); return c == expected }
        func context(canonical: Bool = true) throws -> RuntimeDependencyContext { .init(market:.china,baseURL:base,role:wire.role,session:try .init(accountID:7,epoch:session.sessionRevision,namespace:deployment.storageScope.service,token:"synthetic-7",role:canonical ? wire.role : "player")) }
        func login() async { await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456") }
        func approve(write enabled: Bool = true, prepare: Bool = true) throws {
            let r = try WorkshopPaidProfessionalReadApproval(context:context(),expiresAt:.distantFuture)
            let w = enabled ? try WorkshopPaidProfessionalWriteApproval(context:context(),expiresAt:.distantFuture) : nil
            let b = prepare ? try WorkshopPaidInstalledTextApproval(context:context(),expiresAt:.distantFuture) : nil
            let i = prepare ? try WorkshopPaidInstallApproval(context:context(canonical:false),expiresAt:.distantFuture) : nil
            session.withWorkshopReadConfigurationChange { read = r; write = w; body = b; install = i }
        }
        func controller() throws -> WorkshopPaidProfessionalController { try XCTUnwrap(session.makeWorkshopPaidProfessionalController(reference:WorkshopPaidTextAppFixture.reference())) }
        func review(_ c: WorkshopPaidProfessionalController, _ a: WorkshopPaidProfessionalAppearance) async throws {
            await (try XCTUnwrap(c.appear(a)))(); await (try XCTUnwrap(c.offerNewReview(a)))()
            await (try XCTUnwrap(c.offerSelect(XCTUnwrap(c.targets.first),displayed:a)))(); XCTAssertEqual(c.phase,.review)
        }
        func clean() { UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
    }
    func testDefaultFactoryIsUnavailableWithZeroProfessionalRequests() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        XCTAssertNil(h.session.makeWorkshopPaidProfessionalController(reference:try WorkshopPaidTextAppFixture.reference())); XCTAssertTrue(h.wire.operations.isEmpty)
    }
    func testActualNormalPlayerMerchantClubContextReviewAndDedicatedCreate() async throws {
        for role in ["player","merchant","club"] {
            let h = try Harness(); defer { h.clean() }; h.wire.role = role; await h.login(); try h.approve()
            let c = try h.controller(), a = WorkshopPaidProfessionalAppearance(); XCTAssertTrue(c === h.session.makeWorkshopPaidProfessionalController(reference:try WorkshopPaidTextAppFixture.reference()))
            try await h.review(c,a); await (try XCTUnwrap(c.offerSubmit(a,confirmedMode:.city)))()
            XCTAssertEqual(c.operation?.state,.created); XCTAssertEqual(h.wire.writes.count,1); XCTAssertGreaterThan(h.seen,8)
            XCTAssertEqual(h.wire.writes.first?.value(forHTTPHeaderField:"Authorization"),"synthetic-7")
        }
    }
    func testHistoryRecoveryWorksWithoutBodyOrWriteApproval() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(write:false,prepare:false); h.wire.command = try F.command(); h.wire.state = "CREATED"
        let c = try h.controller(), a = WorkshopPaidProfessionalAppearance(); await (try XCTUnwrap(c.appear(a)))()
        await (try XCTUnwrap(c.offerInspect(XCTUnwrap(c.operations.first),displayed:a)))()
        XCTAssertEqual(c.operation?.state,.created); XCTAssertTrue(h.wire.writes.isEmpty); XCTAssertFalse(h.wire.requests.contains { $0.url!.path.contains("installed-text") })
    }
    func testNormalReadGrantDoesNotBorrowCreatePermission() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(write:false)
        let c = try h.controller(), a = WorkshopPaidProfessionalAppearance(); try await h.review(c,a)
        XCTAssertNil(c.offerSubmit(a,confirmedMode:.city)); XCTAssertEqual(c.issue,.disabled); XCTAssertTrue(h.wire.writes.isEmpty)
    }
    func testConfigurationABARemovesOldBodyAndQueuedCreateBeforeChange() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let c = try h.controller(), a = WorkshopPaidProfessionalAppearance(); try await h.review(c,a)
        let queued = try XCTUnwrap(c.offerSubmit(a,confirmedMode:.city)), old = h.write
        h.session.withWorkshopReadConfigurationChange {
            h.write = nil; XCTAssertEqual(c.phase,.invalidated)
            XCTAssertNil(h.session.makeWorkshopPaidProfessionalController(reference:try! WorkshopPaidTextAppFixture.reference())); h.write = old
        }
        await queued(); XCTAssertTrue(h.wire.writes.isEmpty); XCTAssertNil(c.body)
        let fresh = try h.controller(); XCTAssertFalse(c === fresh)
    }
    func testSuspendedOldRead401CannotLogoutAfterPresentationDismissAndReopen() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(); let p = WorkshopPaidProfessionalPresentation()
        let reference = try WorkshopPaidTextAppFixture.reference(), factory: WorkshopPaidProfessionalControllerFactory = { h.session.makeWorkshopPaidProfessionalController(reference:$0) }
        p.open(makeReference:{reference},makeController:factory); let old = try XCTUnwrap(p.selection); h.wire.delay = true
        let action = try XCTUnwrap(old.controller.appear(old.appearance)); let task = Task { await action() }; await h.wire.wait()
        p.dismiss(old); p.open(makeReference:{reference},makeController:factory); let fresh = try XCTUnwrap(p.selection)
        await (try XCTUnwrap(fresh.controller.appear(fresh.appearance)))(); p.dismiss(old); h.wire.resume401(); await task.value
        XCTAssertTrue(p.selection === fresh); XCTAssertEqual(fresh.controller.phase,.history); XCTAssertEqual(h.vault.token,"synthetic-7")
    }
    func testNormalGenericTransportRejectsSubmitAndCancelEvenWithWriteGrant() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let transport = h.root.transport(); transport.current = { .init(epoch:h.session.sessionRevision,accountID:7,role:h.wire.role,token:"synthetic-7") }
        for route in [WorkshopPaidProfessionalRequest.Route.submit,.cancel] {
            let data = try F.command().wireData(); var request = URLRequest(url:h.base.appendingPathComponent(route.path)); request.httpMethod = "POST"; request.httpBody = data
            request.setValue("synthetic-7",forHTTPHeaderField:"Authorization"); request.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type"); request.setValue(String(data.count),forHTTPHeaderField:"Content-Length")
            request.setValue("no-store",forHTTPHeaderField:"Cache-Control"); request.setValue("no-cache",forHTTPHeaderField:"Pragma"); request.cachePolicy = .reloadIgnoringLocalCacheData
            XCTAssertEqual(WorkshopPaidProfessionalRequest.accepts(request,baseURL:h.base),route)
            do { _ = try await transport.send(request); XCTFail("Generic send must reject mutation") } catch { }
        }
        XCTAssertTrue(h.wire.writes.isEmpty)
    }
    func testHostedActualSheetCloseQueuedActionAndReopenKeepsFreshAppearance() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let p = WorkshopPaidProfessionalPresentation(), reference = try WorkshopPaidTextAppFixture.reference()
        let factory: WorkshopPaidProfessionalControllerFactory = { h.session.makeWorkshopPaidProfessionalController(reference:$0) }
        let host = UIHostingController(rootView:NavigationStack { Form { WorkshopPaidProfessionalEntry(makeReference:{reference},makeController:factory,presentation:p) } })
        let window = UIWindow(frame:UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible(); defer { window.isHidden = true }; host.view.layoutIfNeeded()
        p.open(makeReference:{reference},makeController:factory); let old = try XCTUnwrap(p.selection)
        for _ in 0..<1000 { if old.controller.phase == .history { break }; await Task.yield() }
        XCTAssertEqual(old.controller.phase,.history); XCTAssertNotNil(host.presentedViewController)
        let queued = try XCTUnwrap(old.controller.offerNewReview(old.appearance)); p.dismiss(old); await queued()
        XCTAssertNil(old.controller.body); XCTAssertTrue(h.wire.writes.isEmpty)
        p.open(makeReference:{reference},makeController:factory); let fresh = try XCTUnwrap(p.selection)
        p.replace(nil,expected:old.id); p.dismiss(old); XCTAssertTrue(p.selection === fresh)
    }
}
