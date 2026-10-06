import XCTest
@testable import Questify

@MainActor final class MerchantPublicFactoryAppTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic NPC"}}}"#.utf8), 200)
        }
    }
    final class Journal: OperationPendingJournal {
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { nil }
        func write(_ record: OperationPendingRecord) throws {}
        func clear(_ record: OperationPendingRecord) throws {}
    }
    func testNormalDormantDependenciesAndAppHomeRemainUnconfigured() async throws {
        let d = NativeRuntimeDependencies.dormant, wire = Wire()
        XCTAssertNil(d.merchantPublicApproval); XCTAssertFalse(d.merchantNPCGrants.chatAllowed)
        let context = try MerchantPublicHostContext(market: .china, baseURL: URL(string: "https://example.com/")!, namespace: "fixture", epoch: 1)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: context.baseURL), journal: Journal(), current: { context }))
        let session = AppSession(runtimeDependencies: .init(transport: wire))
        let reader = session.publicMerchantHomeContext.reader
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalDependencyFactoryConstructsApprovedGuestReaderUsingInjectedHTTP() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/prod-api/")!
        let context = try MerchantPublicHostContext(market: .china, baseURL: url, namespace: "fixture", epoch: 1)
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        let home = try await factory.homeReader.home(.ownerMemberID(PublicMerchantOwnerID(77)!))
        XCTAssertEqual(home.id, 31); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertNil(wire.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(factory.chatGrants.chatAllowed)
    }
    func testNormalDependencyFactoryRejectsAccountMismatchAndRetainedContextChanges() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/")!
        var context: MerchantPublicHostContext? = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 9, epoch: 1, role: "user", token: "fixture-token")
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", accountID: 9, publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        context = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 10, epoch: 2, role: "user", token: "next-token")
        XCTAssertFalse(factory.homeReader.isConfigured)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: url), journal: Journal(), current: { context }))
        do { _ = try await factory.homeReader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
}

#if DEBUG
@MainActor final class MerchantOnboardingFixtureCounterTests: XCTestCase {
    func testReviewAndCancelCannotDispatchOrResetMonotonicCounters() async throws {
        for scenario in ["rejected", "submit-unknown"] {
            let fixture = MerchantOnboardingFixture(name: scenario)
            let coordinator = MerchantOnboardingCoordinator(server: fixture)
            let model = MerchantOnboardingModel(coordinator: coordinator)
            model.reset(); await model.load(); await model.checkIdentity()
            guard case .loaded(.application(let application)) = coordinator.loadState else {
                return XCTFail("Expected authoritative rejected fixture application")
            }
            model.reapply(application)
            model.prepare()
            XCTAssertNotNil(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.cancelConfirmation()
            XCTAssertNil(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.prepare()
            let approved = try XCTUnwrap(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            await coordinator.confirm(approved)
            XCTAssertEqual(fixture.submissionCount, 1)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.cancelConfirmation()
            model.reset(); await model.load()
            XCTAssertEqual(fixture.submissionCount, 1, "Cancel and readback must never erase a dispatch")
            XCTAssertEqual(fixture.uploadCount, 0)
            if scenario == "submit-unknown" {
                XCTAssertEqual(coordinator.submission, .outcomeUnknown)
            }
            fixture.replaceAccount()
            XCTAssertEqual(fixture.submissionCount, 1, "Counters remain monotonic even across account replacement")
        }
    }
    func testDiagnosticGateRejectsOrdinaryMissingAmbiguousAndOtherFixtureArguments() {
        let marker = "--uitesting-merchant-onboarding-fixture"
        let optIn = "--uitesting-merchant-onboarding-diagnostics"
        var emitted: [String] = []
        for arguments in [[], [optIn], [marker], [marker, "rejected"],
                          [marker, "identity-required", optIn], [marker, "unknown", optIn],
                          [marker, "rejected", marker, "submit-unknown", optIn],
                          [marker, "rejected", optIn, optIn]] {
            XCTAssertNil(MerchantOnboardingFixtureDiagnostics.make(arguments: arguments, emit: { emitted.append($0) }))
        }
        XCTAssertTrue(emitted.isEmpty)
        for scenario in ["rejected", "submit-unknown"] {
            XCTAssertNotNil(MerchantOnboardingFixtureDiagnostics.make(arguments: [marker, scenario, optIn], emit: { emitted.append($0) }))
        }
        XCTAssertTrue(emitted.isEmpty, "Creating a diagnostic sink must not emit an event")
    }
    func testDiagnosticEventsAreCappedAndReplaceOutOfRangeStepsWithAConstant() throws {
        var emitted: [String] = []
        let sink = try XCTUnwrap(MerchantOnboardingFixtureDiagnostics.make(arguments: [
            "--uitesting-merchant-onboarding-fixture", "rejected", "--uitesting-merchant-onboarding-diagnostics"
        ], emit: { emitted.append($0) }))
        sink.record(.reapplyEntered, busy: false, locked: false, editing: false, step: Int.max)
        for _ in 0..<40 { sink.record(.reapplyEdited, busy: false, locked: false, editing: true, step: 1) }
        XCTAssertEqual(emitted.count, 16)
        XCTAssertEqual(sink.evidence, emitted.joined(separator: " | "))
        XCTAssertLessThanOrEqual(sink.evidence.utf8.count, 3072)
        XCTAssertEqual(emitted.first, "MERCHANT_ONBOARDING_FIXTURE_DIAGNOSTIC event=reapplyEntered;busy=0;locked=0;editing=0;step=invalid")
        XCTAssertTrue(emitted.dropFirst().allSatisfy { $0 == "MERCHANT_ONBOARDING_FIXTURE_DIAGNOSTIC event=reapplyEdited;busy=0;locked=0;editing=1;step=1" })
        XCTAssertFalse(emitted.joined().contains(String(Int.max)))
    }
    func testDiagnosticReadsDoNotChangeRealDraftSubmissionOrFixtureCounters() async throws {
        let fixture = MerchantOnboardingFixture(name: "rejected")
        let coordinator = MerchantOnboardingCoordinator(server: fixture)
        let model = MerchantOnboardingModel(coordinator: coordinator)
        model.reset(); await model.load()
        guard case .loaded(.application(let application)) = coordinator.loadState else { return XCTFail("Expected original fixture application") }
        model.reapply(application)
        let originalDraft = model.draft, originalSubmission = coordinator.submission
        var emitted: [String] = []
        let sink = try XCTUnwrap(MerchantOnboardingFixtureDiagnostics.make(arguments: [
            "--uitesting-merchant-onboarding-fixture", "rejected", "--uitesting-merchant-onboarding-diagnostics"
        ], emit: { emitted.append($0) }))
        sink.record(.reapplyEdited, busy: model.isBusy, locked: coordinator.submission.isLocked, editing: model.isEditing, step: model.step)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(model.draft, originalDraft); XCTAssertEqual(model.step, 1); XCTAssertTrue(model.isEditing)
        XCTAssertEqual(coordinator.submission, originalSubmission)
        XCTAssertEqual(fixture.submissionCount, 0); XCTAssertEqual(fixture.uploadCount, 0)
    }
}
#endif
