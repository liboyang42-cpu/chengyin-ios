import XCTest
import Combine
@testable import Questify

@MainActor final class TemplateMetadataSelectorLifecycleTests: XCTestCase {
    private final class Owner {
        var value: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession?) { self.value = value }
    }
    private func session(_ account: Int = 901, epoch: UInt64 = 1, role: String = "member") throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "metadata-fixture", epoch: epoch, authorizationRevision: role)
    }
    private func setup(_ seed: TemplateAuthoringDraft = .init(title: "Metadata")) throws -> (TemplateAuthoringModel, Owner, TemplateAuthoringLocalStore) {
        let owner = Owner(try session()), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        return (model, owner, store)
    }
    private func rows(_ ids: [Int]) throws -> [DiscoveryCategory] {
        try JSONDecoder().decode([DiscoveryCategory].self, from: JSONSerialization.data(withJSONObject:
            ids.map { ["id": $0, "categoryName": "Synthetic \($0)", "type": 4] as [String: Any] }))
    }
    func testLoadEmptyFailureRetryAndCloseDoNotMutateRawNilOrUnknownValues() async throws {
        for players in [nil, "", "  unknown legacy  "] as [String?] {
            var seed = TemplateAuthoringDraft(title: "Raw metadata")
            seed.players = players; seed.duration = 73; seed.activityCategoryids = " 99,4, 8 "; seed.categoryId = 888
            let (model, _, _) = try setup(seed), reader = MetadataSelectorFixtureReader()
            for field in TemplateMetadataField.allCases {
                let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: field)
                await editor.load(); XCTAssertEqual(editor.state, .empty); XCTAssertEqual(model.draft, seed)
                reader.failure = .httpStatus(503); await editor.load(); XCTAssertEqual(editor.state, .failed)
                reader.failure = nil; await editor.load(); XCTAssertEqual(editor.state, .empty)
                editor.close(); XCTAssertEqual(model.draft, seed); XCTAssertEqual(model.coordinator.draft, seed)
            }
            XCTAssertFalse(model.coordinator.canSubmit)
        }
    }
    func testPlayerSelectionCommitsExactValueThenSurvivesSaveAndRestoreWithoutWriterAuthority() async throws {
        let (model, owner, store) = try setup(), reader = MetadataSelectorFixtureReader()
        let option = TemplateMetadataOption(value: "  exact-key  ", label: "Visible label")
        reader.options = [option]
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
        await editor.load(); XCTAssertNil(model.draft.players)
        XCTAssertTrue(editor.select(option)); XCTAssertEqual(model.draft.players, "  exact-key  ")
        XCTAssertEqual(model.coordinator.draft.players, "  exact-key  "); XCTAssertFalse(editor.canRead)
        model.save(); model.leave()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        reopened.open(); reopened.restoreDraft()
        XCTAssertEqual(reopened.draft.players, "  exact-key  "); XCTAssertFalse(reopened.canSubmit)
    }
    func testDurationUnsupportedAndDuplicateValuesRemainVisibleButNonselectable() async throws {
        var seed = TemplateAuthoringDraft(title: "Duration"); seed.duration = 73
        let (model, _, _) = try setup(seed), reader = MetadataSelectorFixtureReader()
        let bad = ["1.5", "half-day", "2147483648", "045", " 45", "45m"].map { TemplateMetadataOption(value: $0, label: "Unsupported \($0)") }
        let valid = TemplateMetadataOption(value: "45", label: "45 minutes")
        reader.options = bad + [valid]
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .duration)
        await editor.load(); XCTAssertEqual(editor.visibleOptions, bad + [valid])
        for option in bad { XCTAssertFalse(editor.canSelect(option)); XCTAssertFalse(editor.select(option)); XCTAssertEqual(model.draft, seed) }
        XCTAssertTrue(editor.select(valid)); XCTAssertEqual(model.coordinator.draft.duration, 45)
        let duplicate = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
        reader.options = [.init(value: "same", label: "First"), .init(value: "same", label: "Second")]
        await duplicate.load(); XCTAssertEqual(duplicate.visibleOptions.count, 2)
        for option in duplicate.visibleOptions { XCTAssertFalse(duplicate.canSelect(option)); XCTAssertFalse(duplicate.select(option)) }
        XCTAssertNil(model.draft.players)
    }
    func testCategoriesPreserveUnknownIDsAppendInClickOrderAndRequireExplicitSave() async throws {
        var seed = TemplateAuthoringDraft(title: "Categories"); seed.activityCategoryids = " 99,4, 8 "; seed.categoryId = 777
        let (model, _, _) = try setup(seed), reader = MetadataSelectorFixtureReader()
        reader.categories = try rows([4] + Array(101...120))
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .categories)
        await editor.load(); XCTAssertEqual(reader.categoryTypes, [4]); XCTAssertEqual(editor.visibleSelectedIDs, [99, 4, 8])
        for id in (101...120).reversed() { editor.toggleCategory(id) }
        XCTAssertEqual(model.draft, seed)
        XCTAssertEqual(editor.visibleSelectedIDs, [99, 4, 8] + Array((101...120).reversed()))
        XCTAssertTrue(editor.saveCategories())
        XCTAssertEqual(model.coordinator.draft.activityCategoryids, ([99, 4, 8] + Array((101...120).reversed())).map(String.init).joined(separator: ","))
        XCTAssertEqual(model.coordinator.draft.categoryId, 777)
    }
    func testCategoryNoopSaveCancelAndMalformedLegacyReplacement() async throws {
        for raw in [" 99,4, 8 ", "4,4,unknown"] {
            var seed = TemplateAuthoringDraft(title: "Categories"); seed.activityCategoryids = raw; seed.categoryId = 99
            let (model, _, _) = try setup(seed), reader = MetadataSelectorFixtureReader(); reader.categories = try rows([4, 12])
            let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .categories)
            await editor.load()
            if editor.selection.isSupported {
                XCTAssertTrue(editor.saveCategories()); XCTAssertEqual(model.draft, seed)
                let cancelled = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .categories)
                await cancelled.load(); cancelled.toggleCategory(12); cancelled.close(); XCTAssertEqual(model.draft, seed)
            } else {
                XCTAssertFalse(editor.saveCategories()); editor.toggleCategory(12); XCTAssertEqual(model.draft, seed)
                editor.replaceUnsupportedCategories(); editor.toggleCategory(12); XCTAssertEqual(model.draft, seed)
                XCTAssertTrue(editor.saveCategories()); XCTAssertEqual(model.draft.activityCategoryids, "12"); XCTAssertEqual(model.draft.categoryId, 99)
            }
        }
    }
    func testNewestLoadWinsAndOldUnauthorizedCannotExpireCurrentPresentation() async throws {
        let (model, _, _) = try setup(), reader = MetadataSelectorFixtureReader()
        var pending: [CheckedContinuation<[TemplateMetadataOption], Error>] = []
        let firstStarted = expectation(description: "first started"), secondStarted = expectation(description: "second started")
        reader.dictionaryRead = { _ in
            try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                if pending.count == 1 { firstStarted.fulfill() } else { secondStarted.fulfill() }
            }
        }
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
        let first = Task { await editor.load() }; await fulfillment(of: [firstStarted], timeout: 1)
        let second = Task { await editor.load() }; await fulfillment(of: [secondStarted], timeout: 1)
        let latest = TemplateMetadataOption(value: "latest", label: "Latest")
        pending[1].resume(returning: [latest]); await second.value
        pending[0].resume(throwing: APIError.unauthorized); await first.value
        XCTAssertEqual(editor.visibleOptions, [latest]); XCTAssertEqual(reader.unauthorizedCount, 0)
        XCTAssertNil(model.draft.players)
    }
    func testCloseCancellationAndReaderIdentityChangeRejectLateSuccessAnd401() async throws {
        for action in ["close", "cancel", "reader"] {
            for fail in [false, true] {
                let (model, _, _) = try setup(), reader = MetadataSelectorFixtureReader()
                var pending: CheckedContinuation<[TemplateMetadataOption], Error>?
                let started = expectation(description: "read started")
                reader.dictionaryRead = { _ in try await withCheckedThrowingContinuation { pending = $0; started.fulfill() } }
                let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
                let task = Task { await editor.load() }; await fulfillment(of: [started], timeout: 1)
                if action == "close" { editor.close() }
                if action == "cancel" { task.cancel() }
                if action == "reader" { reader.identity = "replacement" }
                let option = TemplateMetadataOption(value: "stale", label: "Stale")
                if fail { pending?.resume(throwing: APIError.unauthorized) } else { pending?.resume(returning: [option]) }
                await task.value
                XCTAssertTrue(editor.visibleOptions.isEmpty); XCTAssertFalse(editor.select(option))
                XCTAssertEqual(reader.unauthorizedCount, 0); XCTAssertNil(model.draft.players)
            }
        }
    }
    func testAcceptedUnauthorizedHasOneCallbackAndRetryDoesNotInventDefaults() async throws {
        let (model, _, _) = try setup(), reader = MetadataSelectorFixtureReader(); reader.failure = .unauthorized
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
        await editor.load(); XCTAssertEqual(reader.unauthorizedCount, 1); XCTAssertEqual(editor.state, .failed)
        reader.failure = nil; reader.options = [.init(value: "first", label: "First")]
        await editor.load(); XCTAssertEqual(editor.state, .loaded); XCTAssertNil(model.draft.players)
    }
    func testDraftLifecycleAndSessionChangesRevokeResultsAndCommits() async throws {
        for action in ["reload", "leave", "discard", "replace", "account", "epoch", "role", "logout"] {
            let (model, owner, _) = try setup(), reader = MetadataSelectorFixtureReader()
            let option = TemplateMetadataOption(value: "new", label: "New"); reader.options = [option]
            let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .players)
            await editor.load(); XCTAssertTrue(editor.canSelect(option))
            switch action {
            case "reload": model.load()
            case "leave": model.leave()
            case "discard": model.discard()
            case "replace": model.draft.description = "replacement"; model.changed()
            case "account": owner.value = try session(902)
            case "epoch": owner.value = try session(epoch: 2)
            case "role": owner.value = try session(role: "merchant")
            default: owner.value = nil
            }
            let after = model.draft
            XCTAssertFalse(editor.canRead, action); XCTAssertNil(editor.savedRawValue); XCTAssertTrue(editor.visibleOptions.isEmpty)
            XCTAssertFalse(editor.select(option)); XCTAssertEqual(model.draft, after)
        }
    }
    func testRestoreAndPendingReviewRevokeOldSelectorsAndKeepPrimaryCategoryUntouched() async throws {
        let (model, owner, store) = try setup(), reader = MetadataSelectorFixtureReader()
        model.draft.players = "  old  "; model.draft.activityCategoryids = " 99,4 "; model.draft.categoryId = 777; model.changed(); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        let reopenedModel = TemplateAuthoringModel(coordinator: reopened); reopenedModel.load()
        let beforeRestore = TemplateAuthoringMetadataEditor(model: reopenedModel, reader: reader, field: .players)
        reopenedModel.restore(); XCTAssertFalse(beforeRestore.canRead)
        XCTAssertEqual(reopenedModel.draft.players, "  old  "); XCTAssertEqual(reopenedModel.draft.activityCategoryids, " 99,4 ")
        XCTAssertEqual(reopenedModel.draft.categoryId, 777)
        let editor = TemplateAuthoringMetadataEditor(model: reopenedModel, reader: reader, field: .players)
        reader.options = [.init(value: "new", label: "New")]; await editor.load()
        reopenedModel.prepare(.saveDraft); XCTAssertNotNil(reopenedModel.review)
        XCTAssertFalse(editor.select(reader.options[0])); XCTAssertEqual(reopenedModel.draft.players, "  old  ")
    }
    func testVenueOpenCancelPreservesNilEmptyAndHistoricalBytesWithoutWrites() throws {
        for raw in [nil, "", "  custom venue  ", "Cafe\u{301}", "博物馆 "] as [String?] {
            var seed = TemplateAuthoringDraft(title: "Venue"); seed.usageLocation = raw
            let (model, owner, store) = try setup(seed)
            let editor = TemplateAuthoringVenueEditor(model: model), generation = model.metadataGeneration
            XCTAssertTrue(editor.canEdit)
            XCTAssertEqual(editor.savedRawValue.map { Data($0.utf8) }, raw.map { Data($0.utf8) })
            XCTAssertNil(editor.selected)
            XCTAssertEqual(editor.hasHistoricalValue, raw?.isEmpty == false)
            editor.close()
            XCTAssertFalse(editor.select(.museum)); XCTAssertNil(editor.savedRawValue)
            XCTAssertEqual(model.metadataGeneration, generation)
            XCTAssertEqual(model.draft, seed); XCTAssertEqual(model.coordinator.draft, seed)
            XCTAssertEqual(model.draft.usageLocation.map { Data($0.utf8) }, raw.map { Data($0.utf8) })
            XCTAssertNil(try store.active(session: XCTUnwrap(owner.value)))
            XCTAssertFalse(model.coordinator.canSubmit)
        }
    }
    func testEveryVenueSelectionChangesOnlyItsFieldAndSurvivesLocalSaveRestore() throws {
        for preset in TemplateVenuePreset.allCases {
            var seed = TemplateAuthoringSyntheticFixtures.compoundDraft()
            seed.usageLocation = " Historical venue "; seed.players = " 3-5 "; seed.categoryId = 73
            let (model, owner, store) = try setup(seed)
            let editor = TemplateAuthoringVenueEditor(model: model)
            XCTAssertTrue(editor.select(preset)); XCTAssertFalse(editor.canRead)
            var expected = seed; expected.usageLocation = preset.storedValue
            XCTAssertEqual(model.draft, expected); XCTAssertEqual(model.coordinator.draft, expected)
            XCTAssertFalse(editor.select(.park)); XCTAssertEqual(model.draft, expected)
            model.save(); model.leave()
            let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
            reopened.open(); reopened.restoreDraft()
            XCTAssertEqual(reopened.draft, expected); XCTAssertFalse(reopened.canSubmit)
            XCTAssertNil(try store.pending(session: XCTUnwrap(owner.value), identity: reopened.identity))
        }
    }
    func testCurrentVenueSelectionIsNoopAndFreshPresentationCanSelectAgain() throws {
        var seed = TemplateAuthoringDraft(title: "Venue"); seed.usageLocation = "博物馆"
        let (model, _, _) = try setup(seed), generation = model.metadataGeneration
        let editor = TemplateAuthoringVenueEditor(model: model)
        XCTAssertEqual(editor.selected, .museum); XCTAssertFalse(editor.hasHistoricalValue)
        XCTAssertTrue(editor.select(.museum)); XCTAssertEqual(model.metadataGeneration, generation)
        XCTAssertEqual(model.draft, seed); XCTAssertEqual(model.coordinator.draft, seed)
        XCTAssertFalse(editor.select(.park))
        let fresh = TemplateAuthoringVenueEditor(model: model)
        XCTAssertTrue(fresh.select(.park)); XCTAssertEqual(model.coordinator.draft.usageLocation, "公园绿地")
    }
    func testVenueCallbacksRetireAcrossDraftAndSessionChanges() throws {
        for action in ["reload", "leave", "discard", "replace", "draftABA", "account", "epoch", "role", "logout", "sessionABA"] {
            var seed = TemplateAuthoringDraft(title: "Venue"); seed.usageLocation = "Historical"
            let (model, owner, _) = try setup(seed)
            let editor = TemplateAuthoringVenueEditor(model: model)
            switch action {
            case "reload": model.load()
            case "leave": model.leave()
            case "discard": model.discard()
            case "replace": model.draft.description = "Other draft bytes"
            case "draftABA": model.draft.usageLocation = "Other"; model.changed(); model.draft = seed; model.changed()
            case "account": owner.value = try session(902)
            case "epoch": owner.value = try session(epoch: 2)
            case "role": owner.value = try session(role: "merchant")
            case "sessionABA": owner.value = try session(902); model.load(); owner.value = try session(); model.load()
            default: owner.value = nil
            }
            let after = model.draft
            XCTAssertFalse(editor.canRead, action); XCTAssertNil(editor.savedRawValue, action)
            XCTAssertFalse(editor.select(.museum), action); XCTAssertEqual(model.draft, after, action)
        }
    }
    func testVenueStaleCanonicalEquivalentBytesAreRejectedBeforeParentChangeCallback() throws {
        var seed = TemplateAuthoringDraft(title: "Venue"); seed.usageLocation = "Cafe\u{301}"
        let (model, _, _) = try setup(seed), editor = TemplateAuthoringVenueEditor(model: model)
        model.draft.usageLocation = "Caf\u{e9}"
        XCTAssertEqual(model.draft, seed) // Swift String equality is canonical, the venue lease must be byte-exact.
        XCTAssertFalse(editor.canRead); XCTAssertFalse(editor.select(.museum))
        XCTAssertEqual(model.draft.usageLocation.map { Data($0.utf8) }, Data("Caf\u{e9}".utf8))
    }
    func testVenueRestoreAndReviewBlockOldSelectors() throws {
        var seed = TemplateAuthoringDraft(title: "Venue"); seed.usageLocation = "  saved venue  "
        let (model, owner, store) = try setup(seed); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        let restored = TemplateAuthoringModel(coordinator: reopened); restored.load()
        let old = TemplateAuthoringVenueEditor(model: restored)
        XCTAssertFalse(old.canEdit); restored.restore(); XCTAssertFalse(old.select(.museum))
        XCTAssertEqual(restored.draft.usageLocation, seed.usageLocation)
        let beforeReview = TemplateAuthoringVenueEditor(model: restored)
        restored.prepare(.saveDraft); XCTAssertNotNil(restored.review)
        XCTAssertFalse(beforeReview.select(.museum))
        let duringReview = TemplateAuthoringVenueEditor(model: restored)
        XCTAssertFalse(duringReview.select(.museum)); XCTAssertEqual(restored.draft.usageLocation, seed.usageLocation)
    }
    func testVenueBusyAndUnknownSubmissionKeepCurrentSavedTextReadOnly() async throws {
        let (model, _, _) = try setup(), editor = TemplateAuthoringVenueEditor(model: model)
        model.busy = true; XCTAssertFalse(editor.select(.museum)); XCTAssertNil(model.draft.usageLocation)
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport(scenario: .uncertain)),
            store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        var seed = TemplateAuthoringSyntheticFixtures.compoundDraft(); seed.usageLocation = "博物馆"
        coordinator.open(seed: seed)
        let locked = TemplateAuthoringModel(coordinator: coordinator); locked.load()
        locked.prepare(.publish); await locked.confirm(try XCTUnwrap(locked.review))
        XCTAssertTrue(coordinator.locked)
        let retained = TemplateAuthoringVenueEditor(model: locked)
        XCTAssertEqual(retained.savedRawValue, "博物馆"); XCTAssertFalse(retained.canEdit)
        XCTAssertFalse(retained.select(.park)); XCTAssertEqual(locked.draft.usageLocation, "博物馆")
    }

    func testLateCategory401AfterDiscardCannotExpireIdentity() async throws {
        let (model, _, _) = try setup(), reader = MetadataSelectorFixtureReader()
        var pending: CheckedContinuation<[DiscoveryCategory], Error>?
        let started = expectation(description: "categories started")
        reader.categoryRead = { try await withCheckedThrowingContinuation { pending = $0; started.fulfill() } }
        let editor = TemplateAuthoringMetadataEditor(model: model, reader: reader, field: .categories)
        let task = Task { await editor.load() }; await fulfillment(of: [started], timeout: 1)
        model.discard(); pending?.resume(throwing: APIError.unauthorized); await task.value
        XCTAssertEqual(reader.unauthorizedCount, 0); XCTAssertFalse(editor.saveCategories())
    }
}

@MainActor private final class MetadataSelectorFixtureReader: DiscoveryReading {
    var isConfigured = true
    var identity = "fixture"
    var discoveryPresentationIdentity: String { identity }
    var options: [TemplateMetadataOption] = []
    var categories: [DiscoveryCategory] = []
    var failure: APIError?
    var categoryTypes: [Int?] = []
    var unauthorizedCount = 0
    var dictionaryRead: ((TemplateMetadataKind) async throws -> [TemplateMetadataOption])?
    var categoryRead: (() async throws -> [DiscoveryCategory])?
    func templateMetadataDictionary(kind: TemplateMetadataKind) async throws -> [TemplateMetadataOption] {
        if let dictionaryRead { return try await dictionaryRead(kind) }
        if let failure { throw failure }; return options
    }
    func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]> {
        .init(read: { try await self.templateMetadataDictionary(kind: kind) }, onUnauthorized: { self.unauthorizedCount += 1 })
    }
    func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
        .init(read: { try await self.discoveryCategories(type: 4) }, onUnauthorized: { self.unauthorizedCount += 1 })
    }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] {
        categoryTypes.append(type)
        if let categoryRead { return try await categoryRead() }
        if let failure { throw failure }; return categories
    }
    func discoveryBanners() async throws -> [DiscoveryBanner] { throw APIError.notConfigured }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { throw APIError.notConfigured }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { throw APIError.notConfigured }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { throw APIError.notConfigured }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { throw APIError.notConfigured }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { throw APIError.notConfigured }
}
