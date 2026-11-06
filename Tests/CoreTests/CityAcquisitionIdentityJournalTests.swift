import Foundation
import XCTest
@testable import QuestifyCore

/// Authored synthetic persistence checks. Each fixture uses its own disposable UUID suite.
/// Swift/XCTest execution is NOT_RUN in the authoring environment (Swift unavailable).
@MainActor final class CityAcquisitionIdentityJournalTests: XCTestCase {
    private let owner = "city-acquisition:test-deployment:42"
    private let target = "region-81"
    private let metadata = ["nativeWebhook", "merchantNPCSave", "themeItemUse", "sideQuestPlayer", "merchantSideQuestPublishing"]

    private func isolated(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "CityAcquisitionIdentityJournalTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
    private func key(_ owner: String, _ target: String, original: Bool = false) -> String {
        (original ? "questify.city.acquisition.original.v1." : "questify.operations.pending.v1.") +
        Data("\(owner.utf8.count):\(owner):\(target)".utf8).base64EncodedString()
    }
    private func journal(_ defaults: UserDefaults) -> CityAcquisitionIdentityJournal {
        CityAcquisitionIdentityJournal(defaults: defaults, ownerKey: owner, targetKey: target)
    }
    private func record() -> OperationPendingRecord { OperationPendingRecord(ownerKey: owner, targetKey: target) }
    private func fields(_ record: OperationPendingRecord) -> [String: Any] {
        ["operationID": record.operationID.uuidString, "ownerKey": record.ownerKey,
         "targetKey": record.targetKey, "acknowledgedSteps": record.acknowledgedSteps]
    }
    private func data(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    func testFreshJournalFindsExactLegacyKeyAndDoesNotWriteOnReads() throws {
        try isolated { defaults in
            let store = journal(defaults)
            XCTAssertNil(try store.pending(ownerKey: owner, targetKey: target))
            XCTAssertNil(try store.original(ownerKey: owner, targetKey: target))
            let original = record()
            try OperationDefaultsJournal(defaults: defaults).write(original)
            let bytes = defaults.data(forKey: key(owner, target))
            XCTAssertEqual(try journal(defaults).pending(ownerKey: owner, targetKey: target), original)
            XCTAssertEqual(defaults.data(forKey: key(owner, target)), bytes)
            XCTAssertNil(defaults.object(forKey: key(owner, target, original: true)))
        }
    }

    func testQuoteThenConfirmAdvanceOriginalIdentityButLeavePendingEmpty() throws {
        try isolated { defaults in
            let quote = record(), confirm = record()
            for request in [quote, confirm] {
                let store = journal(defaults)
                try store.write(request)
                XCTAssertEqual(try journal(defaults).pending(ownerKey: owner, targetKey: target), request)
                try store.clear(request)
                let reopened = journal(defaults)
                XCTAssertNil(try reopened.pending(ownerKey: owner, targetKey: target))
                XCTAssertEqual(try reopened.original(ownerKey: owner, targetKey: target), request)
                let stored = try XCTUnwrap(defaults.data(forKey: key(owner, target, original: true)))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
                XCTAssertEqual(Set(object.keys), Set(["operationID", "ownerKey", "targetKey", "acknowledgedSteps"]))
            }
        }
    }

    func testUnknownPendingCannotBeReplacedByDifferentIDOrClearedByStaleID() throws {
        try isolated { defaults in
            let first = record(), next = record(), store = journal(defaults)
            try store.write(first)
            let before = defaults.dictionaryRepresentation() as NSDictionary
            XCTAssertThrowsError(try store.write(next))
            XCTAssertThrowsError(try store.clear(next))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            XCTAssertEqual(try journal(defaults).pending(ownerKey: owner, targetKey: target), first)
        }
    }

    func testRecognizedNullFieldsRemainByteExactOnSameIDWriteAndOriginalRead() throws {
        try isolated { defaults in
            let original = record()
            var object = fields(original)
            for name in metadata { object[name] = NSNull() }
            let raw = try data(object), store = journal(defaults)
            defaults.set(raw, forKey: key(owner, target))
            defaults.set(raw, forKey: key(owner, target, original: true))
            XCTAssertEqual(try store.pending(ownerKey: owner, targetKey: target), original)
            try store.write(original)
            XCTAssertEqual(defaults.data(forKey: key(owner, target)), raw)
            try store.clear(original)
            XCTAssertEqual(defaults.data(forKey: key(owner, target, original: true)), raw)
            XCTAssertEqual(try journal(defaults).original(ownerKey: owner, targetKey: target), original)
        }
    }

    func testMalformedAndFutureRawInEitherSlotIsPreserved() throws {
        let original = record()
        var invalid: [Any] = ["not data", Data("{broken".utf8), try data([:])]
        for name in metadata + ["futureMetadata"] {
            var object = fields(original)
            object[name] = ["future": true]
            invalid.append(try data(object))
        }
        var unknownNull = fields(original)
        unknownNull["futureMetadata"] = NSNull()
        invalid.append(try data(unknownNull))
        for missing in ["operationID", "ownerKey", "targetKey", "acknowledgedSteps"] {
            var object = fields(original)
            object.removeValue(forKey: missing)
            invalid.append(try data(object))
        }
        for steps in [-1, 1, 2] {
            var object = fields(original)
            object["acknowledgedSteps"] = steps
            invalid.append(try data(object))
        }
        var wrongScope = fields(original)
        wrongScope["targetKey"] = "other-region"
        invalid.append(try data(wrongScope))
        for originalSlot in [false, true] {
            for raw in invalid {
                try isolated { defaults in
                    let store = journal(defaults)
                    try store.write(original)
                    defaults.set(raw, forKey: key(owner, target, original: originalSlot))
                    let before = defaults.dictionaryRepresentation() as NSDictionary
                    if originalSlot {
                        XCTAssertThrowsError(try store.original(ownerKey: owner, targetKey: target))
                    } else {
                        XCTAssertThrowsError(try store.pending(ownerKey: owner, targetKey: target))
                    }
                    XCTAssertThrowsError(try store.write(original))
                    XCTAssertThrowsError(try store.clear(original))
                    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
                }
            }
        }
    }

    func testRawChangeAfterReadPreventsClearEvenWhenDecodedIdentityMatches() throws {
        try isolated { defaults in
            let original = record(), store = journal(defaults)
            try store.write(original)
            _ = try store.pending(ownerKey: owner, targetKey: target)
            var object = fields(original)
            object["merchantNPCSave"] = NSNull()
            let changed = try data(object)
            defaults.set(changed, forKey: key(owner, target))
            XCTAssertThrowsError(try store.clear(original))
            XCTAssertEqual(defaults.data(forKey: key(owner, target)), changed)
            XCTAssertNil(defaults.object(forKey: key(owner, target, original: true)))
        }
    }

    func testUTF8ExactScopeRejectsCanonicallyEquivalentStrings() throws {
        try isolated { defaults in
            let composedOwner = "city-acquisition:caf\u{00E9}:42"
            let decomposedOwner = "city-acquisition:cafe\u{0301}:42"
            let composedTarget = "r\u{00E9}gion"
            let decomposedTarget = "re\u{0301}gion"
            XCTAssertEqual(composedOwner, decomposedOwner)
            XCTAssertEqual(composedTarget, decomposedTarget)
            let store = CityAcquisitionIdentityJournal(defaults: defaults, ownerKey: composedOwner, targetKey: composedTarget)
            let original = OperationPendingRecord(ownerKey: composedOwner, targetKey: composedTarget)
            try store.write(original)
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let originalBytes = try XCTUnwrap(defaults.data(forKey: key(composedOwner, composedTarget)))
            XCTAssertThrowsError(try store.pending(ownerKey: decomposedOwner, targetKey: composedTarget))
            XCTAssertThrowsError(try store.original(ownerKey: composedOwner, targetKey: decomposedTarget))
            XCTAssertThrowsError(try store.write(OperationPendingRecord(ownerKey: decomposedOwner, targetKey: composedTarget)))
            var changed = fields(original)
            changed["ownerKey"] = decomposedOwner
            defaults.set(try data(changed), forKey: key(composedOwner, composedTarget))
            XCTAssertThrowsError(try store.pending(ownerKey: composedOwner, targetKey: composedTarget))
            defaults.set(originalBytes, forKey: key(composedOwner, composedTarget))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }

    func testUnrelatedSlotsAndOtherDomainsRemainUntouched() throws {
        try isolated { defaults in
            let foreign = [key("city-team:scope:42", target), key("city-budget:scope:42", target),
                           key(owner, "other-region"), key("city-acquisition:other:42", target, original: true)]
            for name in foreign { defaults.set(Data("unknown bytes".utf8), forKey: name) }
            let original = record(), store = journal(defaults)
            try store.write(original)
            try store.clear(original)
            for name in foreign { XCTAssertEqual(defaults.data(forKey: name), Data("unknown bytes".utf8)) }
            let nonAcquisition = CityAcquisitionIdentityJournal(defaults: defaults, ownerKey: "city-team:scope:42", targetKey: target)
            XCTAssertThrowsError(try nonAcquisition.pending(ownerKey: "city-team:scope:42", targetKey: target))
            XCTAssertThrowsError(try nonAcquisition.write(OperationPendingRecord(ownerKey: "city-team:scope:42", targetKey: target)))
        }
    }
    func testMarkerWriteFailureRetainsPendingAndPreviousOriginal() throws {
        let suite = "CityAcquisitionIdentityJournalTests." + UUID().uuidString
        let defaults = try XCTUnwrap(AcquisitionFaultDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = record(), next = record(), store = journal(defaults)
        try store.write(previous)
        try store.clear(previous)
        try store.write(next)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        defaults.dropMarkerWrite = true
        XCTAssertThrowsError(try store.clear(next))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertEqual(try journal(defaults).pending(ownerKey: owner, targetKey: target), next)
        XCTAssertEqual(try journal(defaults).original(ownerKey: owner, targetKey: target), previous)
    }

    func testClearWritesOriginalBeforeRemovingPendingAndCanRecoverInterruptedClear() throws {
        let suite = "CityAcquisitionIdentityJournalTests." + UUID().uuidString
        let defaults = try XCTUnwrap(AcquisitionFaultDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = record(), store = journal(defaults)
        try store.write(original)
        defaults.dropPendingRemoval = true
        XCTAssertThrowsError(try store.clear(original))
        let backedUp = try XCTUnwrap(defaults.markerAtPendingRemoval)
        XCTAssertEqual(try JSONDecoder().decode(OperationPendingRecord.self, from: backedUp), original)
        let reopened = journal(defaults)
        XCTAssertEqual(try reopened.pending(ownerKey: owner, targetKey: target), original)
        XCTAssertEqual(try reopened.original(ownerKey: owner, targetKey: target), original)
        defaults.dropPendingRemoval = false
        try reopened.clear(original)
        XCTAssertNil(try journal(defaults).pending(ownerKey: owner, targetKey: target))
        XCTAssertEqual(try journal(defaults).original(ownerKey: owner, targetKey: target), original)
    }

    func testPendingWriteFailureDoesNotCreateOriginal() throws {
        let suite = "CityAcquisitionIdentityJournalTests." + UUID().uuidString
        let defaults = try XCTUnwrap(AcquisitionFaultDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.dropPendingWrite = true
        XCTAssertThrowsError(try journal(defaults).write(record()))
        XCTAssertNil(defaults.object(forKey: key(owner, target)))
        XCTAssertNil(defaults.object(forKey: key(owner, target, original: true)))
    }

}


/// Deterministic, isolated write/read-back fault simulation; no production defaults are used.
private final class AcquisitionFaultDefaults: UserDefaults {
    var dropMarkerWrite = false
    var dropPendingWrite = false
    var dropPendingRemoval = false
    var markerAtPendingRemoval: Data?

    override func set(_ value: Any?, forKey defaultName: String) {
        if dropMarkerWrite && defaultName.hasPrefix("questify.city.acquisition.original.v1.") { return }
        if dropPendingWrite && defaultName.hasPrefix("questify.operations.pending.v1.") { return }
        super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        let prefix = "questify.operations.pending.v1."
        if defaultName.hasPrefix(prefix) {
            let scope = String(defaultName.dropFirst(prefix.count))
            markerAtPendingRemoval = data(forKey: "questify.city.acquisition.original.v1." + scope)
            if dropPendingRemoval { return }
        }
        super.removeObject(forKey: defaultName)
    }
}
