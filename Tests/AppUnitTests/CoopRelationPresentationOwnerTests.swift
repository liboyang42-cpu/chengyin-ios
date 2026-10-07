import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Questify

#if DEBUG
@MainActor final class CoopRelationPresentationOwnerTests: XCTestCase {
    private final class Probe {
        var parentCovered = false
        var childVisible = false
    }
    private struct HostedDiscovery: View {
        @ObservedObject var reader: CoopRelationFixtureReader
        let model: CoopRelationDiscoveryModel
        let owner: CoopRelationPresentationOwner
        let probe: Probe
        var body: some View {
            let scope = CoopRelationPresentationOwnerTests.scope(reader)
            let current = { reader.session != nil && reader.scope == scope.merchantScope && reader.clubIdentity == scope.clubIdentity }
            let profiles = CoopRelationProfileContext(scope: scope, isCurrent: current, canOpen: { _ in current() }, destination: { route, selected in
                switch route {
                case .merchant(let member):
                    return AnyView(PublicMerchantHomeView(target: .ownerMemberID(member), context: .init(reader:
                        CoopRelationMerchantReader(base: reader, owner: member, isCurrent: { current() && selected() })))
                        .onAppear { probe.childVisible = true }
                        .onDisappear { probe.childVisible = false })
                case .club(let id):
                    return AnyView(CoopRelationClubProfileHost(id: id, base: reader, isCurrent: { current() && selected() }))
                }
            }, identityChanges: reader.objectWillChange.eraseToAnyPublisher())
            CoopRelationDiscoveryView(reader: reader, profiles: profiles, model: model, presentation: owner)
                .onAppear { probe.parentCovered = false }
                .onDisappear { probe.parentCovered = true }
        }
    }
    private static func scope(_ reader: CoopRelationFixtureReader) -> CoopRelationProfileScope {
        .init(merchantScope: reader.scope, clubIdentity: reader.clubIdentity,
              sessionRevision: reader.session?.epoch ?? 0, contentRevision: 1)
    }
    private func choice(_ reader: CoopRelationFixtureReader, _ model: CoopRelationDiscoveryModel,
                        kind: CoopRelationDiscoveryKind = .merchants) throws -> CoopRelationProfileSelection {
        let row = try XCTUnwrap(model.value?.rows(kind).first)
        return try XCTUnwrap(model.selection(row: row, reader: reader, scope: Self.scope(reader), context: .init()))
    }
    private func open(_ choice: CoopRelationProfileSelection, reader: CoopRelationFixtureReader,
                      model: CoopRelationDiscoveryModel, owner: CoopRelationPresentationOwner) {
        let captured = Self.scope(reader)
        XCTAssertTrue(owner.open(choice, isCurrent: {
            reader.scope == captured.merchantScope && reader.clubIdentity == captured.clubIdentity &&
                model.isCurrent(choice, reader: reader, scope: captured, context: .init())
        }))
    }
    private func wait(_ stage: String, _ condition: @escaping () -> Bool,
                      file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(stage, file: file, line: line)
        throw CancellationError()
    }

    /// The actual list is covered by a NavigationStack destination containing the real
    /// merchant profile View. Publication must reach the owner without list onChange.
    func testHostedCoveredListPopsVisibleProfileAfterAccountReplacement() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel(), probe = Probe()
        let owner = CoopRelationPresentationOwner(identityChanges: reader.objectWillChange.eraseToAnyPublisher())
        let host = UIHostingController(rootView: NavigationStack {
            HostedDiscovery(reader: reader, model: model, owner: owner, probe: probe)
        })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait("real list accepted") { model.isCurrent(reader: reader) }
        let old = try choice(reader, model)
        open(old, reader: reader, model: model, owner: owner)
        try await wait("real child visible while parent covered") { probe.childVisible && probe.parentCovered }
        XCTAssertNotNil(host.view.window)
        let oldReader = CoopRelationMerchantReader(base: reader, owner: PublicMerchantOwnerID(41)!, isCurrent: { owner.isCurrent(old) })
        reader.session = try .init(accountID: 102, epoch: 2, token: "synthetic-replacement")
        reader.scope = UUID()
        XCTAssertFalse(owner.isCurrent(old), "The live read fence must reject before the queued UI publication runs")
        let reads = reader.ownerReads
        do { _ = try await oldReader.home(.ownerMemberID(PublicMerchantOwnerID(41)!)); XCTFail("Retired selection dispatched") } catch {}
        XCTAssertEqual(reader.ownerReads, reads)
        do {
            try await wait("identity publication pops old child and returns to the actual list") {
                owner.selection == nil && !probe.childVisible && !probe.parentCovered && model.isCurrent(reader: reader)
            }
        } catch {
            // Synthetic booleans/counts only; distinguish pop failure from stale/loading
            // return state without changing the original predicate or wait budget.
            let diagnostic = "selected=\(owner.selection != nil) child=\(probe.childVisible) covered=\(probe.parentCovered) current=\(model.isCurrent(reader: reader)) loading=\(model.isLoading) failed=\(model.failed) signedIn=\(reader.session != nil) reads=\(reader.reads) ownerReads=\(reader.ownerReads) clubReads=\(reader.clubReads)"
            print("COOP_SYNTHETIC_OWNER " + diagnostic)
            let attachment = XCTAttachment(string: diagnostic)
            attachment.name = "Synthetic cooperation owner return state"; attachment.lifetime = .keepAlways
            add(attachment)
            throw error
        }
        let fresh = try choice(reader, model)
        XCTAssertNotEqual(fresh.id, old.id)
        open(fresh, reader: reader, model: model, owner: owner)
        try await wait("replacement account can open its own presentation") { probe.childVisible && probe.parentCovered }
        XCTAssertTrue(owner.isCurrent(fresh)); XCTAssertFalse(owner.isCurrent(old))
        reader.session = nil; reader.scope = UUID()
        try await wait("signout also removes the visible profile") { owner.selection == nil && !probe.childVisible }
        XCTAssertFalse(owner.isCurrent(fresh))
        // Duplicate initial-read count remains covered by the unchanged UI 1:0 assertion.
        // This test isolates account propagation and does not declare those two failures fixed.
    }

    func testIdentityPublicationRetiresExactSelectionWithoutAnyMountedList() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel()
        let owner = CoopRelationPresentationOwner(identityChanges: reader.objectWillChange.eraseToAnyPublisher())
        await model.load(reader: reader)
        let old = try choice(reader, model); open(old, reader: reader, model: model, owner: owner)
        reader.session = try .init(accountID: 102, epoch: 2, token: "synthetic")
        reader.scope = UUID()
        XCTAssertFalse(owner.isCurrent(old))
        try await wait("owner observes identity independently of the covered list") { owner.selection == nil }
        XCTAssertEqual(reader.ownerReads, 0); XCTAssertEqual(reader.clubReads, 0)
    }

    func testLateOldBackBindingAndQueuedIdentityCheckCannotCloseFreshPresentation() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel()
        let owner = CoopRelationPresentationOwner(identityChanges: reader.objectWillChange.eraseToAnyPublisher())
        await model.load(reader: reader)
        let old = try choice(reader, model); open(old, reader: reader, model: model, owner: owner)
        let oldBack = owner.binding
        reader.session = try .init(accountID: 102, epoch: 2, token: "synthetic"); reader.scope = UUID()
        await model.load(reader: reader)
        let fresh = try choice(reader, model); open(fresh, reader: reader, model: model, owner: owner)
        oldBack.wrappedValue = nil
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(owner.isCurrent(fresh)); XCTAssertEqual(owner.selection?.id, fresh.id)
        owner.binding.wrappedValue = nil
        XCTAssertNil(owner.selection); XCTAssertFalse(owner.isCurrent(fresh))
    }

    func testUnrelatedPublicationKeepsCurrentSelectionAndNeverReadsAProfile() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel()
        let owner = CoopRelationPresentationOwner(identityChanges: reader.objectWillChange.eraseToAnyPublisher())
        await model.load(reader: reader)
        let current = try choice(reader, model); open(current, reader: reader, model: model, owner: owner)
        reader.objectWillChange.send()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(owner.isCurrent(current)); XCTAssertEqual(reader.ownerReads, 0); XCTAssertEqual(reader.clubReads, 0)
    }

    func testRetiredClubSelectionSuppressesDelayedUnauthorizedButCurrentOneExpires() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed"), model = CoopRelationDiscoveryModel()
        let owner = CoopRelationPresentationOwner(identityChanges: reader.objectWillChange.eraseToAnyPublisher())
        await model.load(reader: reader)
        let old = try choice(reader, model, kind: .clubs); open(old, reader: reader, model: model, owner: owner)
        let wire = HeldUnauthorizedWire()
        let session = try ClubReadSession(accountID: 101, epoch: 1, token: "synthetic")
        var expired = 0
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let base = ClubSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let profile = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { owner.isCurrent(old) })
        let pending = Task { try await profile.clubDetail(id: 9) }
        try await wait("old request reaches the real session reader") { wire.pending != nil }
        reader.session = nil; reader.scope = UUID()
        wire.finish()
        do { _ = try await pending.value; XCTFail("Retired read returned") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
        let current = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { true })
        wire.hold = false
        do { _ = try await current.clubDetail(id: 9); XCTFail("Current 401 returned") } catch {}
        XCTAssertEqual(expired, 1)
    }
    private final class HeldUnauthorizedWire: HTTPTransport {
        var hold = true
        var pending: CheckedContinuation<Void, Never>?
        func finish() { let continuation = pending; pending = nil; continuation?.resume() }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if hold { await withCheckedContinuation { pending = $0 } }
            return (Data(#"{"code":401}"#.utf8), 401)
        }
    }
}
#endif
