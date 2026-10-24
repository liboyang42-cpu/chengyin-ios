import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileIdentityShareFlowTests: XCTestCase {
    private final class Reader: SocialAccountReading {
        var identity = SocialAccountIdentity(accountID: 7, epoch: 1, role: "player")
        var presentationRevision: UInt64 = 0
        var isConfigured = true
        var isOfflineExample = false
        var reads = 0
        func publicProfile(memberID: Int) async throws -> SocialPublicProfile { reads += 1; throw APIError.invalidRequest }
        func informationList() async throws -> [SocialInformation] { reads += 1; throw APIError.invalidRequest }
        func information(id: Int) async throws -> SocialInformation { reads += 1; throw APIError.invalidRequest }
        func invitationHistory(page: Int) async throws -> SocialInviteHistory { reads += 1; throw APIError.invalidRequest }
    }
    private final class Scope { var current = true }
    private func profile(name: String = "Synthetic explorer") throws -> SocialPublicProfile {
        try JSONDecoder().decode(SocialPublicProfile.self, from: JSONSerialization.data(withJSONObject: ["id": 7, "nickname": name, "introduction": "City walks"]))
    }
    private func model(_ reader: Reader, _ scope: Scope = Scope()) throws -> ProfileIdentityShareModel {
        ProfileIdentityShareModel(profile: try profile(), reader: reader, isCurrent: { scope.current })
    }
    func testNormalSelfPreviewHandoffAndCloseNeedNoRead() throws {
        let r = Reader(), m = try model(r)
        m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        XCTAssertNil(m.handoff); m.beginHandoff(p); let h = try XCTUnwrap(m.handoff)
        XCTAssertEqual(h.text, p.text); XCTAssertEqual(h.previewID, p.id)
        m.finishHandoff(h); XCTAssertNil(m.handoff); XCTAssertEqual(m.preview?.id, p.id)
        m.close(p); XCTAssertNil(m.preview); XCTAssertEqual(r.reads, 0)
    }
    func testCancelPreviewDoesNotCreateSystemHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card")
        let p = try XCTUnwrap(m.preview); m.close(p); m.beginHandoff(p)
        XCTAssertNil(m.preview); XCTAssertNil(m.handoff); XCTAssertEqual(r.reads, 0)
    }
    func testRepeatedTapDoesNotReplacePreviewOrHandoff() throws {
        let m = try model(Reader()); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        m.open(title: "Other"); XCTAssertEqual(m.preview?.id, p.id)
        m.beginHandoff(p); let h = try XCTUnwrap(m.handoff); m.beginHandoff(p)
        XCTAssertEqual(m.handoff?.id, h.id)
    }
    func testAccountChangeBeforeConfirmationPreventsHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 8, epoch: 2, role: "player"); m.beginHandoff(p)
        XCTAssertFalse(m.canShare); XCTAssertNil(m.handoff)
    }
    func testSameAccountNewEpochPreventsHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 7, epoch: 2, role: "player"); m.beginHandoff(p)
        XCTAssertNil(m.handoff)
    }
    func testPresentationRevisionBlocksUnobservedABATransition() throws {
        let r = Reader(), m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.presentationRevision += 2; m.beginHandoff(p); m.activate()
        XCTAssertFalse(m.canShare); XCTAssertNil(m.handoff)
    }
    func testRawRoleBytesFenceCanonicallyEquivalentReplacement() throws {
        let r = Reader(); r.identity = .init(accountID: 7, epoch: 1, role: "caf\u{00e9}")
        let m = try model(r); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        r.identity = .init(accountID: 7, epoch: 1, role: "cafe\u{0301}"); m.beginHandoff(p)
        XCTAssertNil(m.handoff)
    }
    func testParentScopeRetirementPreventsHandoff() throws {
        let r = Reader(), scope = Scope(), m = try model(r, scope); m.open(title: "Card")
        let p = try XCTUnwrap(m.preview); scope.current = false; m.beginHandoff(p)
        XCTAssertNil(m.handoff); XCTAssertFalse(m.canShare)
    }
    func testRetiredCallbackCannotCloseLaterPreview() throws {
        let m = try model(Reader()); m.open(title: "Card"); let first = try XCTUnwrap(m.preview)
        m.beginHandoff(first); let old = try XCTUnwrap(m.handoff); m.retire(); m.activate()
        m.open(title: "Card"); let second = try XCTUnwrap(m.preview); m.beginHandoff(second)
        let current = try XCTUnwrap(m.handoff); m.finishHandoff(old); m.close(first)
        XCTAssertEqual(m.preview?.id, second.id); XCTAssertEqual(m.handoff?.id, current.id)
    }
    func testCloseAndReturnCanOpenFreshPreviewInSameScope() throws {
        let m = try model(Reader()); m.open(title: "Card"); let p = try XCTUnwrap(m.preview)
        m.retire(); XCTAssertNil(m.preview); m.activate(); m.open(title: "Card")
        XCTAssertNotEqual(m.preview?.id, p.id)
    }
    func testGuestOtherMemberAndUnconfiguredNeverOpen() throws {
        for member in [nil, 8] as [Int?] {
            let r = Reader(); r.identity = .init(accountID: member, epoch: 1)
            let m = try model(r); m.open(title: "Card"); XCTAssertNil(m.preview)
        }
        let r = Reader(); r.isConfigured = false; let m = try model(r); m.open(title: "Card"); XCTAssertNil(m.preview)
    }
    func testReplacementReaderAndChangedProfileHaveDistinctViewIdentity() throws {
        let a = Reader(), b = Reader(), p = try profile()
        XCTAssertNotEqual(ProfileIdentityShareViewIdentity(profile: p, reader: a), ProfileIdentityShareViewIdentity(profile: p, reader: b))
        XCTAssertNotEqual(ProfileIdentityShareViewIdentity(profile: p, reader: a), ProfileIdentityShareViewIdentity(profile: try profile(name: "New name"), reader: a))
    }
    func testNormalSectionConstructionDoesNotReadOrShare() throws {
        let r = Reader(); let _ = ProfileIdentityShareSection(profile: try profile(), reader: r, isCurrent: { true }, owner: ProfileIdentitySharePageOwner())
        XCTAssertEqual(r.reads, 0)
    }
}

extension ProfileIdentityShareFlowTests {
    func testInitialNilPreviewBindingCannotAdoptLaterPreview() throws {
        let r = Reader(), m = try model(r)
        let empty = m.previewPresentation(for:nil)
        m.open(title:"Card"); let current = try XCTUnwrap(m.preview)
        XCTAssertNil(empty.wrappedValue)
        empty.wrappedValue = current; empty.wrappedValue = nil
        XCTAssertEqual(m.preview?.id,current.id); XCTAssertEqual(r.reads,0)
    }
    func testPreviewBindingAndLateDismissCannotReadOrCloseReopenedPreview() throws {
        let r = Reader(), m = try model(r); m.open(title:"First")
        let first = try XCTUnwrap(m.preview), old = m.previewPresentation(for:first)
        XCTAssertEqual(old.wrappedValue?.id,first.id); old.wrappedValue = nil
        m.open(title:"Second"); let second = try XCTUnwrap(m.preview)
        let fresh = m.previewPresentation(for:second)
        XCTAssertNil(old.wrappedValue); old.wrappedValue = second; old.wrappedValue = nil
        m.close(first)
        XCTAssertEqual(fresh.wrappedValue?.id,second.id); XCTAssertEqual(m.preview?.text,second.text)
        fresh.wrappedValue = nil; XCTAssertNil(m.preview); XCTAssertEqual(r.reads,0)
    }
    func testInitialNilSystemHandoffBindingNeverAdoptsLaterHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title:"Card"); let preview = try XCTUnwrap(m.preview)
        let empty = m.handoffPresentation(for:nil,previewID:preview.id)
        m.beginHandoff(preview); let current = try XCTUnwrap(m.handoff)
        XCTAssertNil(empty.wrappedValue); empty.wrappedValue = current; empty.wrappedValue = nil
        XCTAssertEqual(m.handoff?.id,current.id); XCTAssertEqual(r.reads,0)
    }
    func testCancelledSystemSheetOldBindingAndCompletionCannotClearNewHandoff() throws {
        let r = Reader(), m = try model(r); m.open(title:"Card"); let preview = try XCTUnwrap(m.preview)
        m.beginHandoff(preview); let first = try XCTUnwrap(m.handoff)
        let old = m.handoffPresentation(for:first,previewID:preview.id)
        let oldSystemCompletion = { m.finishHandoff(first) }
        XCTAssertEqual(old.wrappedValue?.id,first.id); old.wrappedValue = nil
        XCTAssertEqual(m.preview?.id,preview.id); m.beginHandoff(preview)
        let second = try XCTUnwrap(m.handoff), fresh = m.handoffPresentation(for:second,previewID:preview.id)
        XCTAssertNil(old.wrappedValue); XCTAssertFalse(m.handoffIsCurrent(first,previewID:preview.id))
        old.wrappedValue = second; old.wrappedValue = nil; oldSystemCompletion(); m.finishHandoff(first)
        XCTAssertEqual(fresh.wrappedValue?.id,second.id); XCTAssertEqual(m.handoff?.id,second.id)
        fresh.wrappedValue = nil; XCTAssertNil(m.handoff); XCTAssertEqual(m.preview?.id,preview.id); XCTAssertEqual(r.reads,0)
    }
    func testOldPreviewAndItsSystemCallbacksCannotTouchEntireReopenedFlow() throws {
        let r = Reader(), m = try model(r); m.open(title:"A"); let a = try XCTUnwrap(m.preview)
        let previewA = m.previewPresentation(for:a); m.beginHandoff(a); let handoffA = try XCTUnwrap(m.handoff)
        let systemA = m.handoffPresentation(for:handoffA,previewID:a.id)
        m.close(a); m.open(title:"B"); let b = try XCTUnwrap(m.preview); m.beginHandoff(b)
        let handoffB = try XCTUnwrap(m.handoff)
        XCTAssertNil(previewA.wrappedValue); XCTAssertNil(systemA.wrappedValue)
        previewA.wrappedValue = nil; systemA.wrappedValue = nil; m.close(a); m.finishHandoff(handoffA)
        XCTAssertEqual(m.preview?.id,b.id); XCTAssertEqual(m.handoff?.id,handoffB.id)
        XCTAssertFalse(m.handoffIsCurrent(handoffB,previewID:a.id)); XCTAssertTrue(m.handoffIsCurrent(handoffB,previewID:b.id))
        XCTAssertEqual(r.reads,0)
    }
    func testBothBindingGettersRejectCurrentAccountOrRevisionBeforeObserver() throws {
        for change in 0..<4 {
            let r = Reader(), m = try model(r); m.open(title:"Card"); let preview = try XCTUnwrap(m.preview)
            m.beginHandoff(preview); let handoff = try XCTUnwrap(m.handoff)
            let p = m.previewPresentation(for:preview), h = m.handoffPresentation(for:handoff,previewID:preview.id)
            switch change {
            case 0:r.identity = .init(accountID:8,epoch:2,role:"player")
            case 1:r.presentationRevision += 1
            case 2:r.isConfigured = false
            default:r.identity = .init(accountID:7,epoch:2,role:"player")
            }
            XCTAssertNil(p.wrappedValue); XCTAssertNil(h.wrappedValue)
            XCTAssertFalse(m.handoffIsCurrent(handoff,previewID:preview.id)); XCTAssertEqual(r.reads,0)
        }
    }
    func testHiddenOwnerBothGettersRemainEmptyUntilFreshExplicitFlow() throws {
        let r = Reader(), m = try model(r); m.open(title:"Card"); let preview = try XCTUnwrap(m.preview)
        m.beginHandoff(preview); let handoff = try XCTUnwrap(m.handoff)
        let p = m.previewPresentation(for:preview), h = m.handoffPresentation(for:handoff,previewID:preview.id)
        m.retire(); m.activate()
        XCTAssertNil(p.wrappedValue); XCTAssertNil(h.wrappedValue); XCTAssertNil(m.preview); XCTAssertNil(m.handoff)
        m.open(title:"Fresh"); let next = try XCTUnwrap(m.preview)
        XCTAssertNotEqual(next.id,preview.id); XCTAssertNil(p.wrappedValue); XCTAssertEqual(r.reads,0)
    }
    func testMatchingBindingCancellationReturnsToSamePreviewWithoutClaimingShare() throws {
        let r = Reader(), m = try model(r); m.open(title:"Card"); let preview = try XCTUnwrap(m.preview)
        m.beginHandoff(preview); let handoff = try XCTUnwrap(m.handoff)
        let binding = m.handoffPresentation(for:handoff,previewID:preview.id)
        XCTAssertEqual(binding.wrappedValue?.text,preview.text); binding.wrappedValue = nil
        XCTAssertNil(m.handoff); XCTAssertEqual(m.preview?.id,preview.id)
        XCTAssertEqual(m.preview?.text,preview.text); XCTAssertEqual(r.reads,0)
    }
}

extension ProfileIdentityShareFlowTests {
    private func pageContext(_ r: Reader) -> ProfileIdentitySharePageContext {
        .init(memberID: 7, reader: r, isCurrent: true)
    }
    private func register(_ owner: ProfileIdentitySharePageOwner, _ reader: Reader, _ profile: SocialPublicProfile) {
        let context = pageContext(reader), read = owner.beginSourceRead(pageContext(reader))
        owner.acceptSource(profile, reader: reader, expected: context, readID: read, isCurrent: true)
    }
    func testPageDepartureRetiresPreviewAndOldCallbacksCannotTouchReturn() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), context = pageContext(r), p = try profile()
        owner.appear(context, active: true)
        register(owner, r, try profile())
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "A", isCurrent: { true })
        let a = try XCTUnwrap(owner.model), previewA = try XCTUnwrap(a.preview)
        a.beginHandoff(previewA); let handoffA = try XCTUnwrap(a.handoff)
        let oldPreview = a.previewPresentation(for: previewA)
        owner.disappear(context)
        XCTAssertNil(owner.model); XCTAssertNil(a.preview); XCTAssertNil(a.handoff); XCTAssertFalse(a.canShare)
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "Hidden", isCurrent: { true })
        XCTAssertNil(owner.model)
        owner.appear(context, active: true); XCTAssertNil(owner.model)
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "B", isCurrent: { true })
        let b = try XCTUnwrap(owner.model), previewB = try XCTUnwrap(b.preview)
        oldPreview.wrappedValue = nil; a.close(previewA); a.finishHandoff(handoffA)
        XCTAssertNil(oldPreview.wrappedValue); XCTAssertEqual(b.preview?.id, previewB.id)
        XCTAssertEqual(r.reads, 0)
    }
    func testPageBackgroundClearsButSystemShareInactiveDoesNotRetire() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), context = pageContext(r)
        owner.appear(context, active: true)
        register(owner, r, try profile())
        owner.open(profile: try profile(), reader: r, expected: context, source: owner.sourceTicket, title: "Card", isCurrent: { true })
        let m = try XCTUnwrap(owner.model), p = try XCTUnwrap(m.preview)
        m.beginHandoff(p); let h = try XCTUnwrap(m.handoff)
        owner.sceneChanged(context, active: true)
        XCTAssertEqual(m.handoff?.id, h.id)
        owner.sceneChanged(context, active: false)
        XCTAssertNil(owner.model); XCTAssertNil(m.preview); XCTAssertNil(m.handoff)
        owner.sceneChanged(context, active: true)
        XCTAssertNil(owner.model); XCTAssertTrue(owner.permits(context)); XCTAssertEqual(r.reads, 0)
    }
    func testPageContextChangeRejectsOldRowActionBeforeObserverAndOldSheetAfterObserver() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), old = pageContext(r), p = try profile()
        owner.appear(old, active: true)
        register(owner, r, p)
        owner.open(profile: p, reader: r, expected: old, source: owner.sourceTicket, title: "A", isCurrent: { true })
        let a = try XCTUnwrap(owner.model), previewA = try XCTUnwrap(a.preview)
        r.presentationRevision += 1
        XCTAssertNil(a.previewPresentation(for: previewA).wrappedValue)
        owner.open(profile: p, reader: r, expected: old, source: owner.sourceTicket, title: "Late", isCurrent: { true })
        XCTAssertTrue(owner.model === a)
        let fresh = pageContext(r); owner.update(fresh)
        XCTAssertNil(owner.model); XCTAssertNil(a.preview)
        register(owner, r, p)
        owner.open(profile: p, reader: r, expected: fresh, source: owner.sourceTicket, title: "B", isCurrent: { true })
        let b = try XCTUnwrap(owner.model), previewB = try XCTUnwrap(b.preview)
        owner.disappear(old); a.close(previewA)
        XCTAssertEqual(b.preview?.id, previewB.id); XCTAssertTrue(owner.visible)
        r.identity = .init(accountID: 8, epoch: 2, role: "player")
        XCTAssertFalse(b.canShare); owner.update(pageContext(r)); XCTAssertNil(owner.model)
        XCTAssertEqual(r.reads, 0)
    }
    func testInvalidOrUnloadedParentNeverCreatesPreviewOrDispatches() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), context = pageContext(r), p = try profile()
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "Not mounted", isCurrent: { true })
        XCTAssertNil(owner.model)
        owner.appear(context, active: true)
        register(owner, r, try profile())
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "Retired parent", isCurrent: { false })
        XCTAssertNil(owner.model); r.isConfigured = false
        owner.open(profile: p, reader: r, expected: context, source: owner.sourceTicket, title: "Unconfigured", isCurrent: { true })
        XCTAssertNil(owner.model); XCTAssertEqual(r.reads, 0)
    }

    @MainActor private final class PageFixture: ObservableObject {
        @Published var showRow = true
        let owner = ProfileIdentitySharePageOwner()
        let reader = Reader()
        let profile: SocialPublicProfile
        init(profile: SocialPublicProfile) { self.profile = profile }
    }
    @MainActor private struct MountedPage: View {
        @ObservedObject var fixture: PageFixture
        var body: some View {
            ProfileIdentitySharePageHost(owner: fixture.owner,
                context: .init(memberID: 7, reader: fixture.reader, isCurrent: true)) {
                List {
                    if fixture.showRow {
                        ProfileIdentityShareSection(profile: fixture.profile, reader: fixture.reader,
                            isCurrent: { true }, owner: fixture.owner)
                    }
                    Text("Synthetic profile content")
                }
            }
        }
    }
    func testMountedPageRowRemovalKeepsPreviewAndRealNavigationDepartureRetiresOwner() async throws {
        let fixture = PageFixture(profile: try profile())
        let page = UIHostingController(rootView: MountedPage(fixture: fixture))
        let navigation = UINavigationController(rootViewController: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(fixture.owner.visible)
        let context = pageContext(fixture.reader)
        register(fixture.owner, fixture.reader, fixture.profile)
        fixture.owner.open(profile: fixture.profile, reader: fixture.reader, expected: context, source: fixture.owner.sourceTicket,
                           title: "Synthetic card", isCurrent: { true })
        let model = try XCTUnwrap(fixture.owner.model), preview = try XCTUnwrap(model.preview)
        fixture.showRow = false
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(fixture.owner.model === model); XCTAssertEqual(model.preview?.id, preview.id)
        XCTAssertTrue(fixture.owner.visible)
        model.close(preview)
        try await Task.sleep(nanoseconds: 150_000_000)
        navigation.pushViewController(UIViewController(), animated: false)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(fixture.owner.visible); XCTAssertNil(fixture.owner.model); XCTAssertFalse(model.canShare)
        navigation.popViewController(animated: false)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(fixture.owner.visible); XCTAssertNil(fixture.owner.model)
        fixture.showRow = true
        fixture.owner.open(profile: fixture.profile, reader: fixture.reader, expected: context, source: fixture.owner.sourceTicket,
                           title: "New explicit preview", isCurrent: { true })
        let next = try XCTUnwrap(fixture.owner.model), nextPreview = try XCTUnwrap(next.preview)
        model.close(preview)
        XCTAssertEqual(next.preview?.id, nextPreview.id); XCTAssertEqual(fixture.reader.reads, 0)
        next.close(nextPreview)
    }
}

extension ProfileIdentityShareFlowTests {
    func testSameReaderRevisionNewLoadedSourceRejectsOldRowActionAndAcceptsNewTicket() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), context = pageContext(r)
        let a = try profile(name: "A"), b = try profile(name: "B")
        owner.appear(context, active: true); register(owner, r, a)
        let old = try XCTUnwrap(owner.ticket(profile: a, expected: context))
        let oldAction = { owner.open(profile: a, reader: r, expected: context, source: old, title: "Old", isCurrent: { true }) }
        oldAction(); let oldModel = try XCTUnwrap(owner.model), oldPreview = try XCTUnwrap(oldModel.preview)
        register(owner, r, b)
        XCTAssertEqual(pageContext(r), context); XCTAssertNil(owner.model); XCTAssertNil(oldModel.preview)
        oldAction(); XCTAssertNil(owner.model)
        XCTAssertNil(owner.ticket(profile: a, expected: context))
        let fresh = try XCTUnwrap(owner.ticket(profile: b, expected: context))
        XCTAssertNotEqual(fresh.id, old.id)
        owner.open(profile: b, reader: r, expected: context, source: fresh, title: "New", isCurrent: { true })
        let model = try XCTUnwrap(owner.model), preview = try XCTUnwrap(model.preview)
        XCTAssertTrue(preview.text.contains("B")); oldModel.close(oldPreview); oldAction()
        XCTAssertEqual(model.preview?.id, preview.id); XCTAssertEqual(r.reads, 0)
    }
    func testReplacedReadAndPageDepartureCannotRegisterLateSource() throws {
        let r = Reader(), owner = ProfileIdentitySharePageOwner(), context = pageContext(r)
        let a = try profile(name: "A"), b = try profile(name: "B")
        owner.appear(context, active: true)
        let first = owner.beginSourceRead(context), second = owner.beginSourceRead(context)
        owner.acceptSource(b, reader: r, expected: context, readID: second, isCurrent: true)
        let fresh = try XCTUnwrap(owner.sourceTicket)
        owner.acceptSource(a, reader: r, expected: context, readID: first, isCurrent: true)
        XCTAssertEqual(owner.sourceTicket, fresh)
        let late = owner.beginSourceRead(context); XCTAssertNil(owner.sourceTicket)
        owner.disappear(context); owner.appear(context, active: true)
        owner.acceptSource(a, reader: r, expected: context, readID: late, isCurrent: true)
        XCTAssertNil(owner.sourceTicket); XCTAssertNil(owner.model); XCTAssertEqual(r.reads, 0)
    }
}
