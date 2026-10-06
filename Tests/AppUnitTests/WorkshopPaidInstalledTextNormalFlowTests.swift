import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor enum WorkshopPaidTextAppFixture {
    static let requestID = "00000000-0000-4000-8000-000000000001"
    static let source = #"{"schema":"w18-member-text-v1","title":" 原文🙂 ","merchantGuide":" 保密说明 ","questionName":" Q? ","questionAnswer":" A ","hint1":"一","hint2":"二","answerReveal":"答案","bindings":{}}"#
    static let terms = Data("opaque synthetic frozen terms".utf8)
    static func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .sortedKeys) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T { try WorkshopPaidInstallWire.decode(type, data: data(value), maximum: 2_097_152) }
    static func item() throws -> WorkshopPurchasedItem { var value = WorkshopPurchasedAppFixture.item; value["contentHash"] = ContentDraftRecord.hash(source); return try decode(WorkshopPurchasedItem.self, value) }
    static func command() throws -> WorkshopPaidInstallCommand {
        try .init(requestId: requestID, licenseId: "w18-paid-11", moduleId: item().moduleId, purchasedVersionId: item().purchasedVersionId,
            contentHash: ContentDraftRecord.hash(source), termsHash: item().termsHash, targetDraftId: 91, targetRevision: 1,
            businessType: "TOPIC", targetPayloadHash: String(repeating: "c", count: 64), planningRegion: "synthetic-region", commercialUse: false)
    }
    static func receipt() throws -> WorkshopPaidInstallOutcome {
        var value = try JSONSerialization.jsonObject(with: command().wireData()) as! [String: Any]
        value["schema"] = "w18-paid-install-outcome-v1"; value["state"] = "INSTALLED_PRIVATE_DRAFT"; value["mode"] = "UNRESOLVED"
        value["holdDeadline"] = "2026-10-05T00:05:00Z"; value["ownedDraftId"] = 101; value["installedAt"] = "2026-10-05T00:00:01Z"
        value["professionalTemplateStatus"] = "MATERIALIZATION_REQUIRED"; value["published"] = false; value["executable"] = false
        return try decode(WorkshopPaidInstallOutcome.self, value)
    }
    static func reference() throws -> WorkshopPaidInstalledTextReference { try .init(item: item(), receipt: receipt()) }
    static func body() throws -> [String: Any] {
        let item = try item(), c = try command(); var component = try JSONSerialization.jsonObject(with: Data(source.utf8)) as! [String: Any]
        component["validationMethod"] = 1; let componentJSON = String(data: try data(component), encoding: .utf8)!
        let policy = WorkshopPurchasedAppFixture.item
        var rights: [String: Any] = ["useDuration":"PERPETUAL_PURCHASED_VERSION", "updates":"EXACT_PURCHASED_VERSION", "redistribution":"PROHIBITED"]
        for key in ["commercialUse","adaptation","translation","allowedRegions","themeLimit","merchantLimit","runLimit"] { rights[key] = policy[key] }
        return ["schema":"w18-paid-installed-text-v1", "scope":"OWNER_PAID_INSTALLED_TEXT_PROTECTED_READ_ONLY", "requestId":requestID,
            "licenseId":item.licenseId,"moduleId":item.moduleId,"purchasedVersionId":item.purchasedVersionId,"version":"v1", "contentHash":item.contentHash,
            "componentHash":ContentDraftRecord.hash(componentJSON),"ownedDraftId":101,"ownedDraftRevision":1,"installedAt":"2026-10-05T00:00:01Z","checkedAt":"2026-10-05T00:00:02Z",
            "originalTargetDraftId":91,"originalTargetRevision":1,"originalTargetPayloadHash":c.targetPayloadHash,"originalBusinessType":"TOPIC","mode":"UNRESOLVED",
            "sourceJson":source,"componentJson":componentJSON,"termsVersion":item.termsVersion,"termsHash":item.termsHash,"termsDocumentHash":ContentDraftRecord.hash(String(data:terms,encoding:.utf8)!),"termsDocumentBase64":terms.base64EncodedString(),
            "rights":rights,"professionalTemplateStatus":"MATERIALIZATION_REQUIRED","published":false,"executable":false]
    }
    static func envelope() throws -> Data { try data(["code":200,"data":body()]) }
}
@MainActor final class WorkshopPaidInstalledTextNormalFlowTests: XCTestCase {
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = [], delay = false
        var response: (Data,Int)
        var suspended: CheckedContinuation<(Data,Int),Never>?
        var bodyRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/purchased/installed-text/") == true } }
        init() throws { response = (try WorkshopPaidTextAppFixture.envelope(),200) }
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request)
            if request.url?.path.contains("/purchased/installed-text/") == true {
                if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }; return response
            }
            if request.url?.path.contains("/purchased/install/") == true {
                let value: [String: Any]
                if request.url?.lastPathComponent == "history" {
                    var receipt = try JSONSerialization.jsonObject(with: WorkshopPaidTextAppFixture.command().wireData()) as! [String: Any]
                    receipt["schema"] = "w18-paid-install-outcome-v1"; receipt["state"] = "INSTALLED_PRIVATE_DRAFT"; receipt["mode"] = "UNRESOLVED"; receipt["holdDeadline"] = "2026-10-05T00:05:00Z"; receipt["ownedDraftId"] = 101; receipt["installedAt"] = "2026-10-05T00:00:01Z"; receipt["professionalTemplateStatus"] = "MATERIALIZATION_REQUIRED"; receipt["published"] = false; receipt["executable"] = false
                    value = ["schema":"w18-paid-install-history-v1","scope":"OWNER_COMMAND_RECEIPTS_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":[receipt],"hasMore":false,"nextBeforeCommandKey":NSNull()]
                } else if request.url?.lastPathComponent == "targets" {
                    value = ["schema":"w18-paid-install-targets-v1","scope":"OWNER_DRAFT_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":[],"hasMore":false,"nextBeforeDraftId":NSNull()]
                } else { throw APIError.invalidRequest }
                return (try WorkshopPaidTextAppFixture.data(["code":200,"data":value]),200)
            }
            let value: String
            switch request.url?.lastPathComponent {
            case "phone": value = "{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}"
            case "userInfo": value = "{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}"
            case "logout": value = #"{"code":200}"#
            default: throw APIError.invalidRequest
            }
            return (Data(value.utf8),200)
        }
        func wait() async { for _ in 0..<1000 { if suspended != nil { return }; await Task.yield() }; XCTFail("Expected suspended actual normal transport") }
        func resume(_ response: (Data,Int)) { let old = suspended; suspended = nil; old?.resume(returning: response) }
    }
    @MainActor private final class Harness {
        let wire: Wire, vault = Vault(), base = URL(string:"https://example.com/native")!, suite = "paid-body-" + UUID().uuidString
        let deployment: ReviewedAppDeployment
        var session: AppSession!, approval: WorkshopPaidInstalledTextApproval?, installApproval: WorkshopPaidInstallApproval?, seen = 0
        init() throws {
            wire = try Wire()
            deployment = try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.workshop.paidbody",realm:"synthetic-"+UUID().uuidString.lowercased())
            session = AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:suite)!,tokenStore:{[vault] _ in vault}),makeTransport:{[wire] in wire},workshopPaidInstalledTextApproval:{[weak self] context in
                guard let self,let expected=try? self.context() else{return nil}; self.seen += 1
                XCTAssertEqual(context,expected); XCTAssertEqual(context.role,context.session.role)
                return context==expected ? self.approval:nil
            },workshopPaidInstallApproval:{[weak self] context in guard let self,let grant=self.installApproval,grant.matches(context) else{return nil};return grant}).makeSession()
        }
        func context(canonical: Bool = true) throws -> RuntimeDependencyContext {
            .init(market:.china,baseURL:base,role:wire.role,session:try .init(accountID:7,epoch:session.sessionRevision,namespace:deployment.storageScope.service,token:"synthetic-7",role:canonical ? wire.role:"player"))
        }
        func login() async { await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456") }
        func approve() throws { let body = try WorkshopPaidInstalledTextApproval(context:context(),expiresAt:.distantFuture), install = try WorkshopPaidInstallApproval(context:context(canonical:false),expiresAt:.distantFuture); session.withWorkshopReadConfigurationChange { approval = body; installApproval = install } }
        func controller() throws -> WorkshopPaidInstalledTextController { try XCTUnwrap(session.makeWorkshopPaidInstalledTextController(reference:WorkshopPaidTextAppFixture.reference())) }
        func clean() { UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
    }
    func testNormalDefaultAndInstallApprovalCannotOpenProtectedBody() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        h.installApproval = try .init(context:h.context(canonical:false),expiresAt:.distantFuture)
        XCTAssertNil(h.session.makeWorkshopPaidInstalledTextController(reference:try WorkshopPaidTextAppFixture.reference())); XCTAssertTrue(h.wire.bodyRequests.isEmpty)
    }
    func testNormalPlayerMerchantClubSelectorsSeeConsistentFullCanonicalContext() async throws {
        for role in ["player","merchant","club"] { let h = try Harness(); defer { h.clean() }; h.wire.role = role; await h.login(); try h.approve()
            let c = try h.controller(); XCTAssertTrue(c === h.session.makeWorkshopPaidInstalledTextController(reference:try WorkshopPaidTextAppFixture.reference()))
            await (try XCTUnwrap(c.appear(.init())))(); XCTAssertEqual(c.phase,.loaded); XCTAssertEqual(h.wire.bodyRequests.count,1); XCTAssertGreaterThanOrEqual(h.seen,5)
            XCTAssertEqual(h.wire.bodyRequests.first?.value(forHTTPHeaderField:"Authorization"),"synthetic-7")
        }
    }
    func testConfigurationABAInvalidatesBeforeChangeAndOld401CannotLogout() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(); let c = try h.controller(), old = h.approval, a = WorkshopPaidInstalledTextAppearance(); h.wire.delay = true
        let offered = try XCTUnwrap(c.appear(a)), task = Task { await offered() }; await h.wire.wait()
        h.session.withWorkshopReadConfigurationChange { XCTAssertEqual(c.phase,.invalidated); h.approval = nil; XCTAssertNil(h.session.makeWorkshopPaidInstalledTextController(reference:try! WorkshopPaidTextAppFixture.reference())) }
        h.session.withWorkshopReadConfigurationChange { h.approval = old }; let fresh = try h.controller(); XCTAssertFalse(c === fresh)
        h.wire.resume((Data(),401)); await task.value; XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(fresh.phase,.idle); XCTAssertNil(c.content)
    }
    func testNormalRoleABAAndRootReplacementClearProtectedDataAndQueuedOffers() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(); let c = try h.controller(), a = WorkshopPaidInstalledTextAppearance(), queued = try XCTUnwrap(c.appear(a))
        h.wire.role = "merchant"; await h.session.refreshOwnAccount(); h.wire.role = "player"; await h.session.refreshOwnAccount(); await queued()
        XCTAssertEqual(c.phase,.invalidated); XCTAssertTrue(h.wire.bodyRequests.isEmpty)
        let fresh = try h.controller(); await (try XCTUnwrap(fresh.appear(.init())))(); XCTAssertNotNil(fresh.content)
        h.session.setWorkshopOwnedPresentationActive(false); XCTAssertEqual(fresh.phase,.invalidated); XCTAssertNil(fresh.content)
    }
    func testCurrentNormal401StillExpiresAuthenticatedSession() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(); h.wire.response = (Data(),401)
        let c = try h.controller(); await (try XCTUnwrap(c.appear(.init())))(); XCTAssertFalse(h.session.isSignedIn); XCTAssertNil(c.content)
    }
    func testLiveInstallHistoryEntryCapturesActualReceiptAndClosedParentCannotReopenIt() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let parent = try XCTUnwrap(h.session.makeWorkshopPaidInstallController(item:WorkshopPaidTextAppFixture.item())), a = WorkshopPaidInstallAppearance()
        await (try XCTUnwrap(parent.appear(a)))(); let receipt = try XCTUnwrap(parent.history.first)
        XCTAssertNotNil(parent.installedTextReference(receipt,appearance:a)); parent.close(a)
        let presentation = WorkshopPaidInstalledTextPresentation(); var factories = 0
        presentation.open(makeReference:{parent.installedTextReference(receipt,appearance:a)},makeController:{ _ in factories += 1; return nil })
        XCTAssertNil(presentation.selection); XCTAssertEqual(factories,0); XCTAssertTrue(h.wire.bodyRequests.isEmpty)
    }
    func testActualHostedSheetOpensFromSharedEntryAndBackClearsBodyBeforeReopen() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let parent = try XCTUnwrap(h.session.makeWorkshopPaidInstallController(item:WorkshopPaidTextAppFixture.item())), a = WorkshopPaidInstallAppearance()
        await (try XCTUnwrap(parent.appear(a)))(); let receipt = try XCTUnwrap(parent.history.first), p = WorkshopPaidInstalledTextPresentation()
        let reference = { parent.installedTextReference(receipt,appearance:a) }, factory: WorkshopPaidInstalledTextControllerFactory = { h.session.makeWorkshopPaidInstalledTextController(reference:$0) }
        let host = UIHostingController(rootView:NavigationStack { Form { WorkshopPaidInstalledTextEntry(makeReference:reference,makeController:factory,presentation:p) } })
        let window = UIWindow(frame:UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible(); defer { window.isHidden = true }; host.view.layoutIfNeeded()
        p.open(makeReference:reference,makeController:factory); let old = try XCTUnwrap(p.selection)
        for _ in 0..<1000 { if old.controller.phase == .loaded { break }; await Task.yield() }
        XCTAssertEqual(old.controller.phase,.loaded); XCTAssertNotNil(host.presentedViewController)
        let queued = try XCTUnwrap(old.controller.offerReload(old.appearance)); p.dismiss(old); XCTAssertNil(old.controller.content)
        for _ in 0..<1000 { if host.presentedViewController == nil { break }; await Task.yield() }
        p.open(makeReference:reference,makeController:factory); let fresh = try XCTUnwrap(p.selection)
        for _ in 0..<1000 { if fresh.controller.phase == .loaded { break }; await Task.yield() }
        let count = h.wire.bodyRequests.count; await queued(); p.replace(nil,expected:old.id); p.dismiss(old)
        XCTAssertTrue(p.selection === fresh); XCTAssertEqual(fresh.controller.phase,.loaded); XCTAssertEqual(h.wire.bodyRequests.count,count)
        p.dismiss(fresh)
    }
    func testTransportClonePreservesIndependentBodyApprovalAndRejectsWriteRoute() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(); let c = try h.controller(); await (try XCTUnwrap(c.appear(.init())))()
        let request = try XCTUnwrap(h.wire.bodyRequests.first), context = try h.context(), grant = try XCTUnwrap(h.approval)
        let transport = CompositionHTTPTransport(deployment:h.deployment,underlying:h.wire,workshopPaidInstalledTextApproval:{ actual in XCTAssertEqual(actual,context); return actual==context ? grant:nil })
        transport.current = { .init(epoch:context.session.epoch,accountID:7,role:context.role,token:"synthetic-7") }; let copy = transport.replacingUnderlying(h.wire)
        _ = try await copy.send(request); let before = h.wire.bodyRequests.count
        var bad = request; bad.url = h.base.appendingPathComponent("api/workshop/purchased/installed-text/publish")
        do { _ = try await copy.send(bad); XCTFail("Body grant admitted publish") } catch {}
        XCTAssertEqual(h.wire.bodyRequests.count,before)
    }
}
