import XCTest
@testable import Questify

/// NOT_RUN. Both real journal adapters over an in-memory primitive; no Security APIs or network.
/// Corrupt bytes below are injected synthetic cases, not observed production storage failures.
@MainActor final class PrivateHomeJournalEnvelopeRecoveryTests: XCTestCase {
    private actor Vault: PrivateHomeKeychainPrimitive {
        var items: [String: PrivateHomeKeychainItem] = [:]
        var removes = 0
        func read(key: String) throws -> PrivateHomeKeychainItem? { items[key] }
        func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
            guard items[key] == nil else { return false }; items[key] = item; return true
        }
        func remove(key: String, matchingTag: Data) throws -> Bool {
            removes += 1
            guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
        }
        func snapshot() -> [String: PrivateHomeKeychainItem] { items }
        func replace(_ key: String, _ item: PrivateHomeKeychainItem) { items[key] = item }
    }
    @MainActor private final class Fixture {
        let scope: RegionalSessionStorageScope, owner: PlayExperienceSession
        let vault: Vault
        let crud: PrivateHomeKeychainJournal, native: NativeHomeReturnKeychainJournal
        let mutation: PrivateHomeMutation, restore: NativeHomeRestoreRequest
        init() throws {
            let endpoint = "https://journal-envelope.example.test"
            let regional = try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]])
            let scope = try RegionalSessionStorageScope(configuration: regional, bundleIdentifier: "example.journalEnvelope", realm: "synthetic")
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: scope.service, token: "synthetic-token")
            let vault = Vault(); self.scope = scope; self.owner = owner; self.vault = vault
            mutation = try .init(requestId: "original-crud", expectedVersion: 3, label: "Synthetic", point: .init(latitude: 12, longitude: 45))
            restore = try JSONDecoder().decode(NativeHomeRestoreRequest.self,
                from: Data(#"{"requestId":"original-restore","proofId":"original-proof","homeVersion":3,"expectedAccountVersion":4,"scopeType":"RUN","scopeId":"42","resourceType":"sys.hp"}"#.utf8))
            crud = try .init(storageScope: scope, owner: owner, primitive: vault)
            native = try .init(storageScope: scope, owner: owner, primitive: vault)
        }
        func save(_ isNative: Bool) async throws {
            if isNative { try await native.save(restore) } else { try await crud.save(mutation) }
        }
        func read(_ isNative: Bool) async throws {
            if isNative { let value = try await native.read(); XCTAssertEqual(value, restore) }
            else { let value = try await crud.read(); XCTAssertEqual(value, mutation) }
        }
        func clear(_ isNative: Bool) async throws {
            if isNative { try await native.clear(matching: restore) } else { try await crud.clear(matching: mutation) }
        }
        func item() async throws -> (String, PrivateHomeKeychainItem) {
            let all = await vault.snapshot(); XCTAssertEqual(all.count, 1)
            let key = try XCTUnwrap(all.keys.first)
            return (key, try XCTUnwrap(all[key]))
        }
    }
    private func duplicate(_ bytes: Data, key: String, container: String? = nil, alias: String? = nil) throws -> Data {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let fields = try container.map { try XCTUnwrap(object[$0] as? [String: Any]) } ?? object
        let value = try XCTUnwrap(fields[key])
        let fragment = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8))
        var text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let marker = "\"\(key)\":"
        let range = try XCTUnwrap(text.range(of: marker))
        // alias is raw JSON key spelling, e.g. sche\u006da. It decodes to the same key.
        text.replaceSubrange(range, with: "\"\(alias ?? key)\":\(fragment)," + marker)
        return Data(text.utf8)
    }
    private func appendField(_ bytes: Data, _ rawField: String) throws -> Data {
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8)); XCTAssertEqual(text.last, "}")
        return Data((String(text.dropLast()) + "," + rawField + "}").utf8)
    }
    private func fixedStorageError(_ error: Error, native: Bool, file: StaticString = #filePath, line: UInt = #line) {
        if native { XCTAssertEqual(error as? NativeHomeReturnFailure, .storageUnavailable, file: file, line: line) }
        else { XCTAssertEqual(error as? PrivateHomeIssue, .storageUnavailable, file: file, line: line) }
    }
    private func unavailableWithoutMutation(_ f: Fixture, native: Bool, bytes: Data) async throws {
        let (key, original) = try await f.item(), beforeRemoves = await f.vault.removes
        await f.vault.replace(key, .init(bytes: bytes, tag: original.tag))
        do { try await f.read(native); XCTFail("Ambiguous record must not be adopted") } catch { fixedStorageError(error, native: native) }
        do { try await f.save(native); XCTFail("Duplicate save must not repair or overwrite") } catch { fixedStorageError(error, native: native) }
        do { try await f.clear(native); XCTFail("Ambiguous record must not authorize removal") } catch { fixedStorageError(error, native: native) }
        let (afterKey, after) = try await f.item(), afterRemoves = await f.vault.removes
        XCTAssertEqual(afterKey, key); XCTAssertEqual(after.bytes, bytes); XCTAssertEqual(after.tag, original.tag)
        XCTAssertEqual(afterRemoves, beforeRemoves)
    }

    func testOriginalSchemaOneBytesRoundTripDuplicateSaveAndConditionalClear() async throws {
        for native in [false, true] {
            let f = try Fixture(); try await f.save(native)
            let (_, first) = try await f.item(); try await f.read(native); try await f.save(native)
            let (_, same) = try await f.item(); XCTAssertEqual(same.bytes, first.bytes); XCTAssertEqual(same.tag, first.tag)
            try await f.clear(native); let empty = await f.vault.snapshot(); XCTAssertTrue(empty.isEmpty)
        }
    }

    func testDuplicateEnvelopeIdentityAndFingerprintKeysAreNotCollapsed() async throws {
        for native in [false, true] {
            for key in ["schema", "namespace", "accountID", "payloadFingerprint", "generationTag", native ? "request" : "mutation"] {
                let f = try Fixture(); try await f.save(native); let (_, item) = try await f.item()
                try await unavailableWithoutMutation(f, native: native, bytes: duplicate(item.bytes, key: key))
            }
        }
    }

    func testEscapedAliasesOfEnvelopeAndNestedIdentityKeysAreDuplicates() async throws {
        for native in [false, true] {
            for nested in [false, true] {
                let f = try Fixture(); try await f.save(native); let (_, item) = try await f.item()
                let bytes = try duplicate(item.bytes, key: nested ? "requestId" : "schema",
                    container: nested ? (native ? "request" : "mutation") : nil,
                    alias: nested ? "reque\\u0073tId" : "sche\\u006da")
                try await unavailableWithoutMutation(f, native: native, bytes: bytes)
            }
        }
    }

    func testNestedCrudMutationKeysCannotSelectOneOfMultipleInterpretations() async throws {
        for key in ["requestId", "expectedVersion", "label", "latitude", "longitude", "datum"] {
            let f = try Fixture(); try await f.save(false); let (_, item) = try await f.item()
            try await unavailableWithoutMutation(f, native: false, bytes: duplicate(item.bytes, key: key, container: "mutation"))
        }
    }

    func testNestedRestoreOriginalIdentityKeysCannotBeCollapsed() async throws {
        for key in ["requestId", "proofId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType"] {
            let f = try Fixture(); try await f.save(true); let (_, item) = try await f.item()
            try await unavailableWithoutMutation(f, native: true, bytes: duplicate(item.bytes, key: key, container: "request"))
        }
    }

    func testTrailingJsonInvalidUtf8AndNonObjectRecordsStayIntact() async throws {
        for native in [false, true] {
            for variant in 0..<5 {
                let f = try Fixture(); try await f.save(native); let (_, item) = try await f.item()
                let bytes: Data
                switch variant {
                case 0: bytes = item.bytes + Data(" {}".utf8)
                case 1: bytes = item.bytes + Data(" null".utf8)
                case 2: bytes = Data([0xFF]) + item.bytes
                case 3: bytes = Data("[]".utf8)
                default: bytes = Data("null".utf8)
                }
                try await unavailableWithoutMutation(f, native: native, bytes: bytes)
            }
        }
    }

    func testDuplicateUnknownFieldsAndExcessiveNestingDoNotBypassGrammarCheck() async throws {
        for native in [false, true] {
            for raw in [#""future":{"x":1,"x":1}"#, "\"future\":" + String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130)] {
                let f = try Fixture(); try await f.save(native); let (_, item) = try await f.item()
                try await unavailableWithoutMutation(f, native: native, bytes: appendField(item.bytes, raw))
            }
        }
    }

    func testWhitespaceAndUnambiguousUnknownFieldsRemainCompatibleWithoutReencodingStorage() async throws {
        for native in [false, true] {
            let f = try Fixture(); try await f.save(native); let (key, item) = try await f.item()
            let withUnknown = try appendField(item.bytes, #""future":{"values":[1,true,null,"synthetic"]}"#)
            let bytes = Data(" \n\t".utf8) + withUnknown + Data("\r\n ".utf8)
            await f.vault.replace(key, .init(bytes: bytes, tag: item.tag))
            try await f.read(native); try await f.save(native)
            let (_, unchanged) = try await f.item(); XCTAssertEqual(unchanged.bytes, bytes); XCTAssertEqual(unchanged.tag, item.tag)
            try await f.clear(native); let empty = await f.vault.snapshot(); XCTAssertTrue(empty.isEmpty)
        }
    }

    func testExisting8192ByteLimitIsPreservedRatherThanExpandedByParser() async throws {
        for native in [false, true] {
            let f = try Fixture(); try await f.save(native); let (key, item) = try await f.item()
            let exact = item.bytes + Data(repeating: 32, count: 8_192 - item.bytes.count)
            await f.vault.replace(key, .init(bytes: exact, tag: item.tag)); try await f.read(native)
            try await unavailableWithoutMutation(f, native: native, bytes: exact + Data([32]))
        }
    }

    @MainActor private final class CrudService: PrivateHomeServing {
        var reads = 0, writes = 0
        func load() throws -> PrivateHomeSnapshot {
            reads += 1
            return try JSONDecoder().decode(PrivateHomeSnapshot.self,
                from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
        }
        func mutate(_ mutation: PrivateHomeMutation) throws -> PrivateHomeReceipt { writes += 1; throw PrivateHomeIssue.unknownOutcome }
    }
    @MainActor private final class NativeService: NativeHomeReturnServing {
        var policies = 0, accounts = 0, verifies = 0, restores = 0
        func policy() -> NativeHomeReturnPolicy? {
            policies += 1
            return .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30, dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        }
        func account(for scope: NativeHomeResourceScope) -> NativeHomeResourceAccount {
            accounts += 1
            return .init(resourceType: "sys.hp", scopeType: "RUN", scopeId: "42", current: 2, maximum: 5, version: 4)
        }
        func verify(_ check: NativeHomeReturnCheck) throws -> NativeHomeReturnVerification { verifies += 1; throw NativeHomeReturnFailure.disabled }
        func restore(_ request: NativeHomeRestoreRequest) throws -> NativeHomeRestoreReceipt { restores += 1; throw NativeHomeReturnFailure.unknown }
        func restoreReceipt(for request: NativeHomeRestoreRequest) -> NativeHomeRestoreReceipt? { nil }
    }

    func testColdCrudRecoveryBlocksBeforeCurrentReadAndPreservesAmbiguousBytes() async throws {
        let f = try Fixture(), service = CrudService(); try await f.save(false)
        let (key, item) = try await f.item(), bytes = try duplicate(item.bytes, key: "requestId", container: "mutation")
        await f.vault.replace(key, .init(bytes: bytes, tag: item.tag))
        let model = PrivateHomeCoordinator(service: service, journal: f.crud, owner: f.owner, enabled: true, current: { f.owner })
        await model.load(); await model.retryExact(); await model.confirm()
        XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(service.reads, 0); XCTAssertEqual(service.writes, 0)
        let (_, preserved) = try await f.item(); XCTAssertEqual(preserved.bytes, bytes)
    }

    func testKnownCrudUnknownCannotAdoptCorruptReplacementOrReconstructIt() async throws {
        let f = try Fixture(), service = CrudService(); try await f.save(false)
        let model = PrivateHomeCoordinator(service: service, journal: f.crud, owner: f.owner, enabled: true, current: { f.owner })
        await model.load(); XCTAssertEqual(model.phase, .unknown)
        let (key, item) = try await f.item(), bytes = try duplicate(item.bytes, key: "label", container: "mutation")
        await f.vault.replace(key, .init(bytes: bytes, tag: item.tag))
        await model.load(); await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.writes, 0)
        let (_, preserved) = try await f.item(); XCTAssertEqual(preserved.bytes, bytes)
    }

    func testColdNativeRecoveryBlocksBeforePolicyAccountOrLocation() async throws {
        let f = try Fixture(), service = NativeService(); try await f.save(true)
        let (key, item) = try await f.item(), bytes = try duplicate(item.bytes, key: "proofId", container: "request")
        await f.vault.replace(key, .init(bytes: bytes, tag: item.tag)); var samples = 0
        let model = NativeHomeReturnCoordinator(scope: f.restore.scope, service: service, journal: f.native, owner: f.owner,
            enabled: true, location: { samples += 1; return .denied }, isCurrent: { true })
        await model.load(); await model.retryExact(); await model.readBack()
        XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.failure, .storageUnavailable); XCTAssertFalse(model.hasPendingRestore)
        XCTAssertEqual(service.policies, 0); XCTAssertEqual(service.accounts, 0); XCTAssertEqual(service.restores, 0); XCTAssertEqual(samples, 0)
        let (_, preserved) = try await f.item(); XCTAssertEqual(preserved.bytes, bytes)
    }

    func testKnownNativeUnknownAndRecreatedAdapterNeverDeleteAmbiguousOriginal() async throws {
        let f = try Fixture(), service = NativeService(); try await f.save(true)
        let model = NativeHomeReturnCoordinator(scope: f.restore.scope, service: service, journal: f.native, owner: f.owner,
            enabled: true, location: { .denied }, isCurrent: { true })
        await model.load(); XCTAssertEqual(model.phase, .unknown)
        let (key, item) = try await f.item(), bytes = try duplicate(item.bytes, key: "scopeId", container: "request")
        await f.vault.replace(key, .init(bytes: bytes, tag: item.tag)); await model.load(); await model.retryExact(); await model.readBack()
        XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.hasPendingRestore); XCTAssertEqual(service.restores, 0)
        XCTAssertEqual(service.policies, 1); XCTAssertEqual(service.accounts, 1)
        let reopened = try NativeHomeReturnKeychainJournal(storageScope: f.scope, owner: f.owner, primitive: f.vault)
        do { _ = try await reopened.read(); XCTFail() } catch { fixedStorageError(error, native: true) }
        let (_, preserved) = try await f.item(); XCTAssertEqual(preserved.bytes, bytes)
        let removes = await f.vault.removes; XCTAssertEqual(removes, 0)
    }
}
