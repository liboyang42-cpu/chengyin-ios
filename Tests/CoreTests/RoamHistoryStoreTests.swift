import XCTest
@testable import QuestifyCore

@MainActor private final class RoamMemoryStorage: RoamHistoryDataStoring {
    var values: [String: Data] = [:]
    var failRead = false
    var failWrite = false
    var writes = 0
    func read(key: String) throws -> Data? {
        if failRead { throw RoamExperienceFailure.historyUnreadable }; return values[key]
    }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw RoamExperienceFailure.historyWriteFailed }
        values[key] = data; writes += 1
    }
}
@MainActor final class RoamHistoryStoreTests: XCTestCase {
    private func scope(account: Int = 1, market: String = "cn", path: String = "a") throws -> RoamHistoryScope {
        try RoamHistoryScope(market: market, deployment: URL(string: "https://example.com/\(path)")!, accountID: account)
    }
    private func record(_ id: Int = 901, timestamp: Int? = nil) throws -> RoamHistoryRecord {
        try JSONDecoder().decode(RoamHistoryRecord.self, from: Data("{\"ts\":\(timestamp ?? id),\"serverSessionID\":\(id),\"shops\":2}".utf8))
    }
    private func fact(_ id: Int = 901) throws -> RoamSessionFact {
        try JSONDecoder().decode(RoamSessionFact.self, from: Data(RoamExperienceSyntheticFixtures.settled.replacingOccurrences(of: "\"901\"", with: "\"\(id)\"").utf8))
    }
    func testMissingStorageIsEmptyButLockedAndCorruptStorageAreErrors() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        XCTAssertTrue(try store.readAll().isEmpty)
        storage.failRead = true; XCTAssertThrowsError(try store.readAll())
        storage.failRead = false; storage.values[scope.storageKey] = Data("{broken}".utf8)
        XCTAssertThrowsError(try store.readAll()); XCTAssertEqual(storage.writes, 0)
    }
    func testPrependDeduplicatesAndKeeps50Newest() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        for id in 1...52 { try store.prependSettled(record(id, timestamp: id), fact: fact(id)) }
        XCTAssertEqual(try store.readAll().count, 50)
        XCTAssertEqual(try store.readAll().first?.serverSessionID, 52)
        XCTAssertEqual(try store.readAll().last?.serverSessionID, 3)
        try store.prependSettled(record(50, timestamp: 999), fact: fact(50))
        XCTAssertEqual(try store.readAll().filter { $0.serverSessionID == 50 }.count, 1)
    }
    func testUnsettledMismatchedAndInconsistentRecordsCannotWrite() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        let active = try JSONDecoder().decode(RoamSessionFact.self, from: Data(RoamExperienceSyntheticFixtures.active.utf8))
        XCTAssertThrowsError(try store.prependSettled(record(), fact: active))
        XCTAssertThrowsError(try store.prependSettled(record(902), fact: fact()))
        let inflated = try JSONDecoder().decode(RoamHistoryRecord.self, from: Data(#"{"ts":1,"serverSessionID":901,"shops":999,"medal":"fabricated"}"#.utf8))
        XCTAssertThrowsError(try store.prependSettled(inflated, fact: fact()))
        XCTAssertEqual(storage.writes, 0)
    }
    func testWriteFailurePreservesOldBytesAndAllowsRetry() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        try store.prependSettled(record(), fact: fact())
        let previous = storage.values[scope.storageKey]
        storage.failWrite = true
        XCTAssertThrowsError(try store.prependSettled(record(902), fact: fact(902)))
        XCTAssertEqual(storage.values[scope.storageKey], previous)
        storage.failWrite = false; try store.prependSettled(record(902), fact: fact(902))
        XCTAssertEqual(try store.readAll().count, 2)
    }
    func testAccountMarketAndDeploymentNeverShareHistory() throws {
        var current: RoamHistoryScope? = try scope()
        let original = try XCTUnwrap(current), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { current })
        try store.prependSettled(record(), fact: fact())
        for next in [try scope(account: 2), try scope(market: "us"), try scope(path: "b")] {
            current = next; XCTAssertTrue(try store.readAll().isEmpty)
        }
        current = nil; XCTAssertThrowsError(try store.readAll())
        current = original; XCTAssertEqual(try store.readAll().count, 1)
    }
    func testEnvelopeScopeCannotBeReboundByCopyingBytes() throws {
        let a = try scope(), b = try scope(account: 2), storage = RoamMemoryStorage()
        let first = RoamHistoryStore(storage: storage, currentScope: { a })
        try first.prependSettled(record(), fact: fact())
        storage.values[b.storageKey] = storage.values[a.storageKey]
        let second = RoamHistoryStore(storage: storage, currentScope: { b })
        XCTAssertThrowsError(try second.readAll())
    }
    func testRecordNotFoundIsNotReadFailure() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        XCTAssertNil(try store.find(timestamp: 123))
        storage.failRead = true; XCTAssertThrowsError(try store.find(timestamp: 123))
    }
    func testCorruptReadBlocksPrependWithoutOverwriting() throws {
        let scope = try scope(), storage = RoamMemoryStorage()
        storage.values[scope.storageKey] = Data("[]".utf8)
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        XCTAssertThrowsError(try store.prependSettled(record(), fact: fact()))
        XCTAssertEqual(storage.values[scope.storageKey], Data("[]".utf8)); XCTAssertEqual(storage.writes, 0)
    }
    func testScopeRejectsAccountlessAndUnapprovedURLShapes() {
        XCTAssertThrowsError(try scope(account: 0))
        XCTAssertThrowsError(try scope(market: "unknown"))
        XCTAssertThrowsError(try RoamHistoryScope(market: "cn", deployment: URL(string: "http://example.com")!, accountID: 1))
    }
}
