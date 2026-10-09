import XCTest
@testable import Questify

@MainActor private final class GuideTemplateReader: DiscoveryReading {
    var isConfigured = true
    var discoveryPresentationIdentity = "account-a:epoch-1"
    var home: DiscoveryTemplateHome?
    var error: Error = APIError.httpStatus(503)
    var held = false
    private(set) var homeReads = 0
    private(set) var otherReads = 0
    private var pending: [Int: CheckedContinuation<DiscoveryTemplateHome, Error>] = [:]
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome {
        homeReads += 1
        if held { let index = homeReads; return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        if let home { return home }; throw error
    }
    func waitForRead(_ count: Int) async {
        for _ in 0..<200 where pending[count] == nil { await Task.yield() }
        XCTAssertNotNil(pending[count])
    }
    func finish(_ count: Int, with home: DiscoveryTemplateHome) { pending.removeValue(forKey: count)?.resume(returning: home) }
    func fail(_ count: Int) { pending.removeValue(forKey: count)?.resume(throwing: error) }
    func discoveryBanners() async throws -> [DiscoveryBanner] { otherReads += 1; return [] }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] { otherReads += 1; return [] }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { otherReads += 1; return [] }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { otherReads += 1; return [] }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { otherReads += 1; throw APIError.notConfigured }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { otherReads += 1; throw APIError.notConfigured }
}

@MainActor final class SocialGuideTemplateTests: XCTestCase {
    private func row(_ id: Int, title: String? = nil, uses: Int? = nil) -> [String: Any] {
        var value: [String: Any] = ["id": id, "title": title ?? "Game \(id)"]
        value["useNum"] = uses; return value
    }
    private func home(hot: [[String: Any]] = [], recommended: [[String: Any]] = [], mustPlay: [[String: Any]] = []) throws -> DiscoveryTemplateHome {
        try JSONDecoder().decode(DiscoveryTemplateHome.self, from: JSONSerialization.data(withJSONObject:
            ["hotList": hot, "recommendList": recommended, "mustPlayList": mustPlay]))
    }
    private func loaded() async throws -> (SocialGuideTemplateModel, GuideTemplateReader) {
        let reader = GuideTemplateReader(); reader.home = try home(hot: [row(7), row(9)])
        let model = SocialGuideTemplateModel(); await model.load(reader: reader)
        return (model, reader)
    }
    func testHotPrecedesRecommendedAndMustPlay() throws {
        XCTAssertEqual(SocialGuideTemplateRows.select(try home(hot: [row(9)], recommended: [row(3)], mustPlay: [row(4)])).map(\.id), [9])
    }
    func testEmptyHotFallsBackToRecommendedThenMustPlay() throws {
        XCTAssertEqual(SocialGuideTemplateRows.select(try home(recommended: [row(3)], mustPlay: [row(4)])).map(\.id), [3])
        XCTAssertEqual(SocialGuideTemplateRows.select(try home(mustPlay: [row(4)])).map(\.id), [4])
    }
    func testChosenPoolFiltersBeforeSixRowLimitAndRetainsOrderAndDuplicates() throws {
        let rows = [row(1, title: " \n"), row(8), row(8), row(2), row(3), row(4), row(5), row(6), row(7)]
        XCTAssertEqual(SocialGuideTemplateRows.select(try home(hot: rows)).map(\.id), [8, 8, 2, 3, 4, 5])
    }
    func testMalformedNonemptyPoolDoesNotFallThroughToAnotherPool() throws {
        XCTAssertTrue(SocialGuideTemplateRows.select(try home(hot: [row(1, title: "\u{FEFF}")], recommended: [row(2)])).isEmpty)
    }
    func testAllEmptyIsTrueEmpty() throws { XCTAssertTrue(SocialGuideTemplateRows.select(try home()).isEmpty) }
    func testCardTextMatchesJavaScriptWhitespaceWithoutInventedPlaceholder() {
        XCTAssertEqual(SocialGuideTemplateRows.text("\u{FEFF} \n游玩\t"), "游玩")
        XCTAssertEqual(SocialGuideTemplateRows.text("\u{0085}name\u{0085}"), "\u{0085}name\u{0085}")
        XCTAssertEqual(SocialGuideTemplateRows.text(nil), "")
    }
    func testOnlyPositiveKnownUseCountsAreDisplayed() throws {
        let rows = SocialGuideTemplateRows.select(try home(hot: [row(1), row(2, uses: 0), row(3, uses: 4)]))
        XCTAssertNil(SocialGuideTemplateRows.useCount(rows[0])); XCTAssertNil(SocialGuideTemplateRows.useCount(rows[1]))
        XCTAssertEqual(SocialGuideTemplateRows.useCount(rows[2]), 4)
    }
    func testLoadUsesOnlyExistingHomeReadAndStartsWithNoDestination() async throws {
        let (model, reader) = try await loaded()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.visibleSnapshot(reader: reader)?.rows.map(\.id), [7, 9])
        XCTAssertEqual(reader.homeReads, 1); XCTAssertEqual(reader.otherReads, 0); XCTAssertNil(model.selection)
    }
    func testExplicitDetailUsesExactSnapshotRowWithoutReadingOrAuthoring() async throws {
        let (model, reader) = try await loaded(); let snapshot = try XCTUnwrap(model.visibleSnapshot(reader: reader))
        model.openDetail(index: 1, snapshotID: snapshot.id, reader: reader)
        XCTAssertEqual(model.destination(reader: reader)?.target, .detail(9))
        XCTAssertEqual(reader.homeReads, 1); XCTAssertEqual(reader.otherReads, 0)
    }
    func testStaleRowSnapshotAndOutOfRangeActionsCannotNavigate() async throws {
        let (model, reader) = try await loaded(); let snapshot = try XCTUnwrap(model.snapshot)
        for index in [-1, 2, Int.max] { model.openDetail(index: index, snapshotID: snapshot.id, reader: reader) }
        model.openDetail(index: 0, snapshotID: UUID(), reader: reader); XCTAssertNil(model.selection)
        await model.load(reader: reader)
        model.openDetail(index: 0, snapshotID: snapshot.id, reader: reader); XCTAssertNil(model.selection)
    }
    func testRepeatedActionCannotReplacePresentedDetail() async throws {
        let (model, reader) = try await loaded(); let snapshot = try XCTUnwrap(model.snapshot)
        model.openDetail(index: 0, snapshotID: snapshot.id, reader: reader); let id = model.selection?.id
        model.openDetail(index: 1, snapshotID: snapshot.id, reader: reader); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        XCTAssertEqual(model.selection?.id, id); XCTAssertEqual(model.selection?.target, .detail(7))
    }
    func testCatalogRemainsAvailableAfterFailureAndPerformsNoReadUntilPresented() async {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); await model.load(reader: reader)
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.snapshot)
        model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader)); XCTAssertEqual(model.destination(reader: reader)?.target, .catalog)
        XCTAssertEqual(reader.homeReads, 1); XCTAssertEqual(reader.otherReads, 0)
    }
    func testEmptyReadyStateCanStillOpenCatalog() async throws {
        let reader = GuideTemplateReader(); reader.home = try home(); let model = SocialGuideTemplateModel()
        await model.load(reader: reader); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.snapshot?.rows.count, 0)
        model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader)); XCTAssertEqual(model.destination(reader: reader)?.target, .catalog)
    }
    func testUnconfiguredReaderNeverReadsOrOpensCatalog() async {
        let reader = GuideTemplateReader(); reader.isConfigured = false; let model = SocialGuideTemplateModel()
        await model.load(reader: reader); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        XCTAssertEqual(model.phase, .unavailable); XCTAssertEqual(reader.homeReads, 0); XCTAssertNil(model.selection)
    }
    func testScopeChangeImmediatelyHidesRowsAndDestinationBeforeViewNotification() async throws {
        let (model, reader) = try await loaded(); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        reader.discoveryPresentationIdentity = "account-b:epoch-2"
        XCTAssertNil(model.visibleSnapshot(reader: reader)); XCTAssertNil(model.destination(reader: reader))
    }
    func testDifferentReaderCannotAdoptSameScopeSnapshot() async throws {
        let (model, reader) = try await loaded(); let other = GuideTemplateReader(); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        XCTAssertNil(model.visibleSnapshot(reader: other)); XCTAssertNil(model.destination(reader: other))
    }
    func testConfigurationLossImmediatelyHidesRowsAndDestination() async throws {
        let (model, reader) = try await loaded(); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader)); reader.isConfigured = false
        XCTAssertNil(model.visibleSnapshot(reader: reader)); XCTAssertNil(model.destination(reader: reader))
    }
    func testLateSuccessFromOldScopeCannotPublish() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let task = Task { await model.load(reader: reader) }; await reader.waitForRead(1)
        reader.discoveryPresentationIdentity = "replacement"; reader.finish(1, with: try home(hot: [row(1)])); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(model.destination(reader: reader))
    }
    func testLateFailureCannotReplaceNewerSuccessfulLoad() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let old = Task { await model.load(reader: reader) }; await reader.waitForRead(1)
        let newer = Task { await model.load(reader: reader) }; await reader.waitForRead(2)
        reader.finish(2, with: try home(hot: [row(2)])); await newer.value
        reader.fail(1); await old.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.snapshot?.rows.map(\.id), [2])
    }
    func testLateOlderSuccessCannotReplaceNewerLoad() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let old = Task { await model.load(reader: reader) }; await reader.waitForRead(1)
        let newer = Task { await model.load(reader: reader) }; await reader.waitForRead(2)
        reader.finish(2, with: try home(hot: [row(2)])); await newer.value
        reader.finish(1, with: try home(hot: [row(1)])); await old.value
        XCTAssertEqual(model.snapshot?.rows.map(\.id), [2])
    }
    func testDepartureOrBackgroundInvalidationRetiresLateCompletionAndSelection() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let task = Task { await model.load(reader: reader) }; await reader.waitForRead(1)
        model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader)); model.invalidate()
        reader.finish(1, with: try home(hot: [row(1)])); await task.value
        XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.snapshot); XCTAssertNil(model.selection)
    }
    func testPresentedSheetSuspensionKeepsExactScopeSelectionAndRows() async throws {
        let (model, reader) = try await loaded(); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        let snapshot = model.snapshot?.id, destination = model.selection?.id; model.suspend()
        XCTAssertEqual(model.visibleSnapshot(reader: reader)?.id, snapshot)
        XCTAssertEqual(model.destination(reader: reader)?.id, destination)
    }
    func testSuspensionInvalidatesOutstandingRead() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let task = Task { await model.load(reader: reader) }; await reader.waitForRead(1); model.suspend()
        reader.finish(1, with: try home(hot: [row(1)])); await task.value
        XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.snapshot)
    }
    func testOldDismissalCannotCloseNewerDestination() {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        let old = model.selection!.id; model.closeDestination(id: old); model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        let newer = model.selection!.id; model.closeDestination(id: old)
        XCTAssertEqual(model.selection?.id, newer); model.closeDestination(id: newer); XCTAssertNil(model.selection)
    }
    func testQueuedRetryCannotReadAfterRetirement() async {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); let permit = model.reloadPermit(reader: reader)
        model.invalidate(); await model.reload(reader: reader, permit: permit)
        XCTAssertEqual(reader.homeReads, 0); XCTAssertEqual(model.phase, .idle)
    }
    func testQueuedRetryCannotReadDifferentReaderOrScope() async {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); let permit = model.reloadPermit(reader: reader)
        await model.reload(reader: GuideTemplateReader(), permit: permit)
        reader.discoveryPresentationIdentity = "changed"; await model.reload(reader: reader, permit: permit)
        XCTAssertEqual(reader.homeReads, 0)
    }
    func testOldRenderedCatalogActionCannotNavigateInReplacementScope() {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader()
        let permit = model.catalogPermit(reader: reader)
        reader.discoveryPresentationIdentity = "changed"
        model.openCatalog(reader: reader, permit: permit); XCTAssertNil(model.selection)
    }
    func testOldRenderedCatalogActionCannotReviveAfterSameReaderRetirementAndReturn() {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader()
        let old = model.catalogPermit(reader: reader)
        model.invalidate() // Background or departure; same account/reader on return.
        model.openCatalog(reader: reader, permit: old); XCTAssertNil(model.selection)
        model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        XCTAssertEqual(model.destination(reader: reader)?.target, .catalog)
    }
    func testCoveringSheetSuspensionRetiresOldCatalogPermitWithoutClosingSelection() throws {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader()
        let old = model.catalogPermit(reader: reader); model.openCatalog(reader: reader, permit: old)
        let selection = try XCTUnwrap(model.selection); model.suspend()
        XCTAssertEqual(model.destination(reader: reader)?.id, selection.id)
        model.closeDestination(id: selection.id)
        model.openCatalog(reader: reader, permit: old); XCTAssertNil(model.selection)
        model.openCatalog(reader: reader, permit: model.catalogPermit(reader: reader))
        XCTAssertEqual(model.destination(reader: reader)?.target, .catalog)
    }
    func testCancelledSuspendedReadCannotPublishEvenWithoutViewRetirement() async throws {
        let reader = GuideTemplateReader(); reader.held = true; let model = SocialGuideTemplateModel()
        let task = Task { await model.load(reader: reader) }; await reader.waitForRead(1); task.cancel()
        reader.finish(1, with: try home(hot: [row(1)])); await task.value
        XCTAssertNil(model.snapshot)
    }
    func testCancelledBeforeLoadNeverReads() async {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader()
        let task = Task { await model.load(reader: reader) }; task.cancel(); await task.value
        XCTAssertEqual(reader.homeReads, 0)
    }
    func testCancellationErrorIsNotShownAsNetworkFailure() async {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); reader.error = CancellationError()
        await model.load(reader: reader); XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.snapshot)
    }
    func testExplicitRetryReadsAgainAndCanRecover() async throws {
        let model = SocialGuideTemplateModel(), reader = GuideTemplateReader(); await model.load(reader: reader)
        reader.home = try home(hot: [row(5)])
        await model.reload(reader: reader, permit: model.reloadPermit(reader: reader))
        XCTAssertEqual(reader.homeReads, 2); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.snapshot?.rows.map(\.id), [5])
    }
}
