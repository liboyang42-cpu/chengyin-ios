import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class SettingsTestSoundStore: SettingsSoundStoring {
    var value = SettingsSoundPreferences.defaults
    var readFailure = false
    var writeFailure = false
    var suspendReads = false
    var suspendWrites = false
    private(set) var reads = 0
    private(set) var writes = 0
    var pendingRead: CheckedContinuation<SettingsSoundPreferences, Error>?
    var pendingWrite: CheckedContinuation<Void, Error>?
    func read() async throws -> SettingsSoundPreferences {
        reads += 1
        if readFailure { throw SettingsSoundStoreError.invalidStoredValue }
        if suspendReads { return try await withCheckedThrowingContinuation { pendingRead = $0 } }
        return value
    }
    func write(_ value: SettingsSoundPreferences) async throws {
        writes += 1
        if writeFailure { throw SettingsSoundStoreError.writeFailed }
        if suspendWrites { try await withCheckedThrowingContinuation { pendingWrite = $0 } }
        self.value = value
    }
}
@MainActor private final class SettingsTestLegalReader: SettingsLegalReading {
    var fail = false
    var suspend = false
    var requests: [CheckedContinuation<SettingsLegalAvailability, Error>] = []
    func document(type: SettingsLegalType, market: RegionalMarket?) async throws -> SettingsLegalAvailability {
        if fail { throw SettingsSoundStoreError.invalidStoredValue }
        if suspend { return try await withCheckedThrowingContinuation { requests.append($0) } }
        return SettingsSourceLegalCatalog.document(type: type, market: market)
    }
}

final class SettingsNativeTests: XCTestCase {
    func testSixSourceDefaults() {
        XCTAssertEqual(SettingsSoundKey.allCases.map { SettingsSoundPreferences.defaults[$0] }, [true, true, true, false, false, false])
        XCTAssertEqual(SettingsSoundPreferences.storageKey, "scene_sound_haptics")
        XCTAssertEqual(SettingsSoundKey.allCases.count, 6)
    }
    func testSoundRoundTripKeepsIndependentFlags() throws {
        var preferences = SettingsSoundPreferences.defaults
        preferences[.sound] = false; preferences[.ocean] = true
        let decoded = try SettingsSoundPreferences.decodeStored(JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        XCTAssertTrue(decoded.haptics); XCTAssertTrue(decoded.airplane)
    }
    func testPartialStoredValueUsesDefaultsAndIgnoresUnknownFields() throws {
        let value = try SettingsSoundPreferences.decodeStored(Data(#"{"ocean":true,"future":42}"#.utf8))
        XCTAssertTrue(value.sound); XCTAssertTrue(value.haptics); XCTAssertTrue(value.airplane); XCTAssertTrue(value.ocean)
        XCTAssertFalse(value.raindrop); XCTAssertFalse(value.forest)
        XCTAssertEqual(try SettingsSoundPreferences.decodeStored(nil), .defaults)
    }
    func testCorruptTypesAreNotTreatedAsMissingPreferences() {
        for json in ["null", "[]", "true", "broken", #"{"sound":null}"#, #"{"sound":1}"#, #"{"haptics":"true"}"#] {
            XCTAssertThrowsError(try SettingsSoundPreferences.decodeStored(Data(json.utf8)), json)
        }
    }
    @MainActor func testLocalStorePersistsWithoutChangingLanguageOrMarket() async throws {
        let name = "SettingsNativeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("en", forKey: "preferences.language")
        defaults.set("US", forKey: "QuestifyMarket")
        let store = SettingsLocalSoundStore(defaults: defaults)
        let initial = try await store.read()
        XCTAssertEqual(initial, .defaults)
        var value = initial; value[.forest] = true
        try await store.write(value)
        let restored = try await SettingsLocalSoundStore(defaults: defaults).read()
        XCTAssertEqual(restored, value)
        XCTAssertEqual(defaults.string(forKey: "preferences.language"), "en")
        XCTAssertEqual(defaults.string(forKey: "QuestifyMarket"), "US")
    }
    @MainActor func testLocalStoreDoesNotReplaceCorruptPayload() async throws {
        let name = "SettingsNativeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let corrupt = Data("corrupt".utf8)
        defaults.set(corrupt, forKey: SettingsSoundPreferences.storageKey)
        do { _ = try await SettingsLocalSoundStore(defaults: defaults).read(); XCTFail("Expected corruption") }
        catch { }
        XCTAssertEqual(defaults.data(forKey: SettingsSoundPreferences.storageKey), corrupt)
    }
    @MainActor func testFailedReadHasRetryStateAndNeverWritesDefaults() async {
        let store = SettingsTestSoundStore(); store.readFailure = true
        let model = SettingsSoundCoordinator(store: store)
        await model.load()
        XCTAssertNil(model.state.preferences); XCTAssertEqual(model.state.messageKey, "settingsNative.sound.loadFailed")
        await model.set(.sound, to: false)
        XCTAssertEqual(store.writes, 0)
        store.readFailure = false
        await model.load()
        XCTAssertEqual(model.state.preferences, .defaults); XCTAssertNil(model.state.messageKey)
    }
    @MainActor func testFailedWritePreservesPreviousValueAndCanRetry() async {
        let store = SettingsTestSoundStore(); let model = SettingsSoundCoordinator(store: store)
        await model.load(); store.writeFailure = true
        await model.set(.sound, to: false)
        XCTAssertEqual(model.state.preferences?.sound, true)
        XCTAssertEqual(model.state.messageKey, "settingsNative.sound.saveFailed")
        store.writeFailure = false
        await model.set(.sound, to: false)
        XCTAssertEqual(model.state.preferences?.sound, false); XCTAssertNil(model.state.messageKey)
    }
    @MainActor func testNoOpToggleDoesNotWrite() async {
        let store = SettingsTestSoundStore(); let model = SettingsSoundCoordinator(store: store)
        await model.load(); await model.set(.sound, to: true)
        XCTAssertEqual(store.writes, 0)
    }
    @MainActor func testOverlappingTogglesCannotOverwriteAnInFlightWrite() async {
        let store = SettingsTestSoundStore(); let model = SettingsSoundCoordinator(store: store)
        await model.load(); store.suspendWrites = true
        let first = Task { await model.set(.ocean, to: true) }
        while store.pendingWrite == nil { await Task.yield() }
        XCTAssertTrue(model.state.isBusy)
        await model.set(.forest, to: true)
        XCTAssertEqual(store.writes, 1)
        store.pendingWrite?.resume(); store.pendingWrite = nil
        await first.value
        XCTAssertEqual(model.state.preferences?.ocean, true)
        XCTAssertEqual(model.state.preferences?.forest, false)
        XCTAssertFalse(model.state.isBusy)
    }
    @MainActor func testCancelledLoadDoesNotPublishLatePreferences() async {
        let store = SettingsTestSoundStore(); store.suspendReads = true
        let model = SettingsSoundCoordinator(store: store)
        let task = Task { await model.load() }
        while store.pendingRead == nil { await Task.yield() }
        task.cancel(); store.pendingRead?.resume(returning: .defaults); store.pendingRead = nil
        await task.value
        XCTAssertNil(model.state.preferences); XCTAssertNil(model.state.messageKey); XCTAssertFalse(model.state.isBusy)
    }
    func testSourceLegalMetadataAndSectionCountsArePreserved() {
        let agreement = SettingsSourceLegalCatalog.userAgreement
        XCTAssertEqual(agreement.version, "v2.2"); XCTAssertEqual(agreement.effectiveDate, "2026-08-12")
        XCTAssertEqual(agreement.sections.count, 13); XCTAssertEqual(agreement.languageCode, "zh-Hans")
        XCTAssertFalse(agreement.isReleaseApproved)
        let cancellation = SettingsSourceLegalCatalog.cancellationNotice
        XCTAssertEqual(cancellation.version, "v2.1"); XCTAssertEqual(cancellation.sections.count, 5)
        XCTAssertTrue(cancellation.sections[0].body.contains("2. 存在在途提现；"))
        XCTAssertFalse(cancellation.isReleaseApproved)
    }
    func testPrivacyMissingStateIsNotACompleteDocument() {
        XCTAssertEqual(SettingsSourceLegalCatalog.document(type: .privacyPolicy, market: .china), .missing(.pendingSourceText))
    }
    func testUSNeverFallsBackToCNSourcedTerms() {
        for type in SettingsLegalType.allCases {
            XCTAssertEqual(SettingsSourceLegalCatalog.document(type: type, market: .unitedStates), .missing(.regionalTextNotProvided))
        }
    }
    func testMissingMarketFailsClosedForEveryDocument() {
        for type in SettingsLegalType.allCases {
            XCTAssertEqual(SettingsSourceLegalCatalog.document(type: type, market: nil), .missing(.missingMarket))
        }
    }
    func testUnknownRouteMatchesSourceFallbackButStillHonorsMarket() {
        XCTAssertEqual(SettingsLegalType.resolve("unexpected"), .userAgreement)
        XCTAssertEqual(SettingsLegalType.resolve("privacy_policy"), .privacyPolicy)
        XCTAssertEqual(SettingsSourceLegalCatalog.document(type: .resolve("unexpected"), market: .unitedStates), .missing(.regionalTextNotProvided))
    }
    func testLanguageChoiceDoesNotAffectMarketLegalSelection() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(RegionalMarket.china.language(storedValue: language.rawValue), language)
            XCTAssertEqual(SettingsSourceLegalCatalog.document(type: .privacyPolicy, market: .china), .missing(.pendingSourceText))
        }
    }
    func testParagraphListMarkersReconstructExactSourceText() {
        let body = SettingsSourceLegalCatalog.cancellationNotice.sections[0].body
        let lines = SettingsLegalLine.lines(in: body)
        XCTAssertNil(lines[0].marker); XCTAssertEqual(lines[1].marker, "1. ")
        XCTAssertEqual(lines.map { ($0.marker ?? "") + $0.text }.joined(separator: "\n"), body)
        XCTAssertEqual(SettingsLegalLine.lines(in: "普通段落").first?.text, "普通段落")
    }
    @MainActor func testDocumentFailureAndRetry() async {
        let reader = SettingsTestLegalReader(); let model = SettingsLegalCoordinator(reader: reader)
        reader.fail = true; await model.load(type: .userAgreement, market: .china)
        XCTAssertEqual(model.state, .failed)
        reader.fail = false; await model.load(type: .privacyPolicy, market: .china)
        XCTAssertEqual(model.state, .loaded(.missing(.pendingSourceText)))
    }
    @MainActor func testOlderDocumentResultCannotOverwriteNewSelection() async {
        let reader = SettingsTestLegalReader(); reader.suspend = true
        let model = SettingsLegalCoordinator(reader: reader)
        let first = Task { await model.load(type: .userAgreement, market: .china) }
        while reader.requests.count < 1 { await Task.yield() }
        let second = Task { await model.load(type: .privacyPolicy, market: .unitedStates) }
        while reader.requests.count < 2 { await Task.yield() }
        reader.requests[1].resume(returning: .missing(.regionalTextNotProvided)); await second.value
        reader.requests[0].resume(returning: .sourceDocument(SettingsSourceLegalCatalog.userAgreement)); await first.value
        XCTAssertEqual(model.state, .loaded(.missing(.regionalTextNotProvided)))
    }
    @MainActor func testDismissedDocumentCannotBeRepopulatedByLateResponse() async {
        let reader = SettingsTestLegalReader(); reader.suspend = true
        let model = SettingsLegalCoordinator(reader: reader)
        let task = Task { await model.load(type: .userAgreement, market: .china) }
        while reader.requests.isEmpty { await Task.yield() }
        model.invalidate()
        reader.requests[0].resume(returning: .sourceDocument(SettingsSourceLegalCatalog.userAgreement)); await task.value
        XCTAssertEqual(model.state, .idle)
    }
    func testAppInformationUsesBundleMetadataAndDoesNotInventFlutterVersion() {
        let info = SettingsAppInformation(info: ["CFBundleDisplayName":" Questify ", "CFBundleShortVersionString":"0.1.0", "CFBundleVersion":"1"])
        XCTAssertEqual(info.displayName, "Questify"); XCTAssertEqual(info.version, "0.1.0"); XCTAssertEqual(info.build, "1")
        XCTAssertNil(SettingsAppInformation(info: [:]).version)
        XCTAssertNil(SettingsAppInformation(info: ["CFBundleVersion":"$(CURRENT_PROJECT_VERSION)"]).build)
        XCTAssertEqual(SettingsAppInformation(info: ["CFBundleName":"Fallback"]).displayName, "Fallback")
    }
    func testContactIsMarketScoped() {
        XCTAssertEqual(SettingsSourceContact.phone(market: .china), "15229020419")
        XCTAssertNil(SettingsSourceContact.phone(market: .unitedStates)); XCTAssertNil(SettingsSourceContact.phone(market: nil))
    }
    func testSourceCreditsAreOfflineAndUnmodified() {
        XCTAssertEqual(SettingsSourceAttribution.all.count, 2)
        XCTAssertEqual(SettingsSourceAttribution.all[0].sourceURL, "https://game-icons.net/")
        XCTAssertEqual(SettingsSourceAttribution.all[1].title, "像素城市场景 · Luis Zuno（ansimuz）· CC0 1.0")
    }
    func testPlayerCodeRequiresActualSafeServerImageURL() throws {
        let good = try JSONDecoder().decode(SettingsPlayerCode.self, from: Data(#"{"qr":" https://example.com/code.png "}"#.utf8))
        XCTAssertEqual(good.imageURL.absoluteString, "https://example.com/code.png")
        for raw in ["", "javascript:alert(1)", "file:///tmp/a", "http://example.com/code.png", "https://user:password@example.com/code.png", "https://example.com/code.png#fragment"] {
            let data = try JSONSerialization.data(withJSONObject: ["qr":raw])
            XCTAssertThrowsError(try JSONDecoder().decode(SettingsPlayerCode.self, from: data))
        }
        for json in ["{}", #"{"qr":null}"#, #"{"qr":123}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(SettingsPlayerCode.self, from: Data(json.utf8)))
        }
    }
}
