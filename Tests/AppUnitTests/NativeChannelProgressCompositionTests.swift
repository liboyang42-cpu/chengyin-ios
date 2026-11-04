import Foundation
import XCTest
import SwiftUI
@testable import Questify

@MainActor private final class ProgressProtectedStorageFixture: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var unavailable = false
    func read(_ key: String) throws -> Data? { if unavailable { throw NativeChannelProgressError.persistence }; return values[key] }
    func write(_ data: Data, key: String) throws { if unavailable { throw NativeChannelProgressError.persistence }; values[key] = data }
    func remove(_ key: String) throws { if unavailable { throw NativeChannelProgressError.persistence }; values.removeValue(forKey: key) }
}

@MainActor final class NativeChannelProgressCompositionTests: XCTestCase {
    func testProtectedAdapterPreservesExactOriginalKeyAndBytes() throws {
        let protected = ProgressProtectedStorageFixture(), storage = NativeChannelProgressSecureJournalStorage(storage: protected)
        let key = String(repeating: "a", count: 64), bytes = Data([0, 1, 128, 255])
        try storage.write(bytes, key: key)
        XCTAssertEqual(protected.values, [key: bytes]); XCTAssertEqual(try storage.read(key), bytes)
        try storage.remove(key); XCTAssertNil(try storage.read(key))
    }
    func testProtectedStorageFailureHasNoFallbackAndKeepsPendingBytes() throws {
        let protected = ProgressProtectedStorageFixture(), storage = NativeChannelProgressSecureJournalStorage(storage: protected)
        let key = String(repeating: "b", count: 64), original = Data("original-pending-command".utf8)
        try storage.write(original, key: key); protected.unavailable = true
        XCTAssertThrowsError(try storage.read(key)); XCTAssertThrowsError(try storage.write(Data(), key: key))
        XCTAssertThrowsError(try storage.remove(key)); XCTAssertEqual(protected.values[key], original)
    }
    func testUnconfiguredCompositionCannotSupplyTeamIndex() throws {
        let composition = AppCompositionRoot(), api = URL(string: "https://example.com")!
        let context = RuntimeDependencyContext(market: .china, baseURL: api, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:test", token: "test-token"))
        let data = Data(#"{"board_key":"distance","title":"Fixture","metric":"DISTANCE","period":"ALL","scope":"CHANNEL","subject_type":"MEMBER","row_limit":30,"visible":true,"revision":1,"topic_id":1,"activity_id":0,"filter_schema_json":{}}"#.utf8)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let board = try decoder.decode(NativeChannelProgressBoard.self, from: data)
        XCTAssertNil(composition.nativeChannelProgressTeamOptions(context, try .init("5"), board))
    }
    func testProgressSheetBindingCannotOutliveOrReviveAncestorVisit() {
        let ancestor = NativeChannelManagementRouteState(), progress = NativeChannelManagementRouteState()
        let parent = ancestor.binding
        parent.wrappedValue = true
        let child = NativeChannelManagementRouteState.child(progress.binding, parentCurrent: { parent.wrappedValue })
        child.wrappedValue = true; XCTAssertTrue(child.wrappedValue)
        ancestor.isPresented = false; ancestor.isPresented = true
        XCTAssertFalse(child.wrappedValue)
        child.wrappedValue = true; XCTAssertFalse(child.wrappedValue)
        XCTAssertTrue(ancestor.isPresented, "Stale progress cannot dismiss the new ancestor")
    }
}
