import XCTest
@testable import Questify

/// These fixture-only tests never perform networking. Apple execution remains required.
@MainActor final class TemplateOptionMediaReadbackTests: XCTestCase {
    private func owner(_ account: Int = 909, epoch: UInt64 = 1, role: String = "member") throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "option-media-readback", epoch: epoch, authorizationRevision: role)
    }
    private func seed() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Local option media")
        draft.validationMethod = .choice
        draft.questionOptionMediaJson = #" {"A":{"img":"  inert-image-A  "},"B":{"audio":"inert-audio-B"}} "#
        return draft
    }
    func testCurrentOwnerReadbacksRemainExactDuringSubmittingAndEveryTerminalLock() async throws {
        let cases: [(TemplateAuthoringAuthority, Bool, TemplateAuthoringCoordinator.State)] = [
            (.synthetic, false, .simulated), (.synthetic, true, .uncertain), (.injectedHTTP, false, .acknowledged)
        ]
        for (authority, uncertain, expectedState) in cases {
            let session = try owner(), transport = OptionMediaReadbackFixtureTransport(authority: authority, uncertain: uncertain)
            let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
            coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
            let image = model.optionMedia(.a, .image), audio = model.optionMedia(.b, .audio), original = model.draft
            func verifyLockedReadback() {
                XCTAssertTrue(coordinator.locked); XCTAssertFalse(model.canEdit)
                XCTAssertEqual(image.wrappedValue, "  inert-image-A  "); XCTAssertEqual(audio.wrappedValue, "inert-audio-B")
                XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, "  inert-image-A  ")
                XCTAssertEqual(model.optionMedia(.b, .audio).wrappedValue, "inert-audio-B")
                image.wrappedValue = "late image"; audio.wrappedValue = "late audio"
                model.optionMedia(.a, .image).wrappedValue = "new locked image"
                model.optionMedia(.b, .audio).wrappedValue = "new locked audio"
                XCTAssertEqual(model.draft, original); XCTAssertEqual(coordinator.draft, original)
            }
            transport.onSend = { XCTAssertEqual(coordinator.state, .submitting); verifyLockedReadback() }
            model.prepare(.saveDraft); await model.confirm(try XCTUnwrap(model.review))
            XCTAssertEqual(coordinator.state, expectedState); XCTAssertEqual(transport.requests, 1)
            verifyLockedReadback()
        }
    }
    func testRetainedAndFreshBindingsBlankAcrossAccountEpochRoleAndLogoutBeforeReload() throws {
        let replacements: [TemplateAuthoringSession?] = [try owner(910), try owner(epoch: 2), try owner(role: "merchant"), nil]
        for replacement in replacements {
            var session: TemplateAuthoringSession? = try owner()
            let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
            coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
            let oldImage = model.optionMedia(.a, .image), oldAudio = model.optionMedia(.b, .audio), original = model.draft
            session = replacement
            XCTAssertEqual(oldImage.wrappedValue, ""); XCTAssertEqual(oldAudio.wrappedValue, "")
            XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, ""); XCTAssertEqual(model.optionMedia(.b, .audio).wrappedValue, "")
            oldImage.wrappedValue = "late"; model.optionMedia(.b, .audio).wrappedValue = "fresh stale"
            XCTAssertEqual(model.draft, original)
            model.load(); let cleared = model.draft
            XCTAssertEqual(oldImage.wrappedValue, ""); XCTAssertEqual(oldAudio.wrappedValue, "")
            XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, ""); XCTAssertEqual(model.optionMedia(.b, .audio).wrappedValue, "")
            oldImage.wrappedValue = "late after load"; oldAudio.wrappedValue = "late after load"
            XCTAssertEqual(model.draft, cleared)
            if replacement != nil {
                model.draft = seed(); model.changed()
                XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, "  inert-image-A  ")
                XCTAssertEqual(oldImage.wrappedValue, ""); XCTAssertEqual(oldAudio.wrappedValue, "")
            }
        }
    }
    func testCoordinatorIdentityReplacementBlanksNewBindingsBeforeModelReload() throws {
        let originalSession = try owner(); var session: TemplateAuthoringSession? = originalSession
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let oldImage = model.optionMedia(.a, .image), oldIdentity = coordinator.identity
        session = nil; coordinator.synchronizeSession(); session = originalSession; coordinator.synchronizeSession()
        XCTAssertNotEqual(coordinator.identity, oldIdentity)
        XCTAssertEqual(oldImage.wrappedValue, ""); XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, "")
        let original = model.draft; model.optionMedia(.a, .image).wrappedValue = "wrong identity"
        XCTAssertEqual(model.draft, original)
        model.load(); model.draft = seed(); model.changed()
        XCTAssertEqual(oldImage.wrappedValue, ""); XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, "  inert-image-A  ")
    }
    func testRestoreAndDiscardStillRevokeOptionMediaGeneration() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let saved = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        saved.open(seed: seed()); saved.saveLocal()
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let preRestore = model.optionMedia(.a, .image); model.restore()
        XCTAssertEqual(preRestore.wrappedValue, ""); preRestore.wrappedValue = "stale restore"
        XCTAssertEqual(model.draft, seed())
        let preDiscard = model.optionMedia(.a, .image); model.discard(); model.draft = seed(); model.changed()
        XCTAssertEqual(preDiscard.wrappedValue, ""); preDiscard.wrappedValue = "stale discard"
        XCTAssertEqual(model.draft, seed()); XCTAssertEqual(model.optionMedia(.a, .image).wrappedValue, "  inert-image-A  ")
    }
}

/// Injected authority exercises acknowledgment semantics with an in-memory response only.
@MainActor private final class OptionMediaReadbackFixtureTransport: TemplateAuthoringTransport {
    let authority: TemplateAuthoringAuthority
    let uncertain: Bool
    var onSend: (() -> Void)?
    private(set) var requests = 0
    init(authority: TemplateAuthoringAuthority, uncertain: Bool) { self.authority = authority; self.uncertain = uncertain }
    func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
        requests += 1; onSend?()
        if uncertain { throw TemplateAuthoringError.uncertain }
        return (Data(#"{"code":200,"msg":"fixture only"}"#.utf8), 200)
    }
}
