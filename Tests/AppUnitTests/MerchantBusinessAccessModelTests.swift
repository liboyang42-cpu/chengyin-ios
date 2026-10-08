import Foundation
import XCTest
@testable import Questify

// App-hosted XCTest coverage. Authored in a workspace without Swift/Xcode:
// NOT_RUN here; this file is not evidence of a simulator or compiler pass.
@MainActor final class MerchantBusinessAccessModelTests: XCTestCase {
    private struct Load {
        let id: Int
        let task: Task<Void, Never>
        let request: MerchantBusinessAccessRequest
    }

    private var appearances: [ObjectIdentifier: MerchantBusinessAccessAppearance] = [:]
    private var appearanceKeys: [ObjectIdentifier: MerchantBusinessAccessLoadKey] = [:]

    private enum HarnessFailure: Error { case readDidNotSuspend }
    private enum SyntheticError: Error { case unavailable }

    // Cancellation handlers are nonisolated. A lock records actual cancellation
    // of the model-owned read task without an extra MainActor scheduling race.
    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func record() { lock.lock(); value = true; lock.unlock() }
        var wasCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://home-access", accountID: 99001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        private(set) var accessCalls = 0
        private(set) var snapshotCalls = 0
        private(set) var executionCalls = 0
        private(set) var executionCheckCalls = 0
        private(set) var redemptionCalls = 0
        private(set) var pending: [Int: CheckedContinuation<MerchantBusinessAccess, Error>] = [:]
        private(set) var probes: [Int: CancellationProbe] = [:]
        var nextStarted: XCTestExpectation?

        func access() async throws -> MerchantBusinessAccess {
            let id = accessCalls
            accessCalls += 1
            let probe = CancellationProbe()
            probes[id] = probe
            let started = nextStarted
            nextStarted = nil
            // Intentionally ignore cancellation until the test releases the read.
            // A transport that completes late must not restore stale permissions.
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    pending[id] = continuation
                    started?.fulfill()
                }
            }, onCancel: { probe.record() })
        }

        func resolve(_ id: Int, with result: Result<MerchantBusinessAccess, Error>,
                     file: StaticString = #filePath, line: UInt = #line) {
            guard let continuation = pending.removeValue(forKey: id) else {
                return XCTFail("No suspended synthetic access read \(id)", file: file, line: line)
            }
            continuation.resume(with: result)
        }

        func finishAll() {
            let continuations = Array(pending.values)
            pending.removeAll()
            for continuation in continuations { continuation.resume(throwing: CancellationError()) }
        }

        func restore(_ key: MerchantBusinessAccessLoadKey) {
            scope = key.scope
            authorizationGeneration = key.authorizationGeneration
            isConfigured = key.configured
        }

        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            snapshotCalls += 1
            XCTFail("Home access must not load business documents")
            throw MerchantBusinessFailure.disabled
        }

        func canExecute(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool {
            executionCheckCalls += 1
            XCTFail("Home access must not prepare a mutation")
            return false
        }

        func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator {
            redemptionCalls += 1
            XCTFail("Home access must not create a redemption coordinator")
            return .init(service: nil, journal: journal, currentSession: { nil })
        }

        func execute(_ mutation: MerchantBusinessMutation, requestID: String,
                     scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            executionCalls += 1
            XCTFail("Home access must not dispatch a mutation")
            throw MerchantBusinessFailure.disabled
        }

        func execute(_ review: MerchantBusinessConfirmation,
                     check: () throws -> Void) async throws -> MerchantBusinessReceipt {
            executionCalls += 1
            XCTFail("Home access must not execute a confirmation")
            throw MerchantBusinessFailure.disabled
        }

        func execute(_ review: MerchantBusinessConfirmation,
                     authorization: MerchantBusinessDispatchAuthorization,
                     check: () throws -> Void) async throws -> MerchantBusinessReceipt {
            executionCalls += 1
            XCTFail("Home access must not consume dispatch authorization")
            throw MerchantBusinessFailure.disabled
        }
    }

    @MainActor private enum ContextChange: CaseIterable {
        case authorization, account, epoch, realm, signOut, disabled
        func apply(to reader: Reader) {
            switch self {
            case .authorization: reader.authorizationGeneration = UUID()
            case .account: reader.scope = .init(realm: "synthetic://home-access", accountID: 99002, epoch: 1)
            case .epoch: reader.scope = .init(realm: "synthetic://home-access", accountID: 99001, epoch: 2)
            case .realm: reader.scope = .init(realm: "synthetic://replacement-access", accountID: 99001, epoch: 1)
            case .signOut: reader.scope = nil
            case .disabled: reader.isConfigured = false
            }
        }
    }

    private func makeSystem() -> (MerchantBusinessAccessModel, Reader) {
        (MerchantBusinessAccessModel(), Reader())
    }

    @discardableResult
    private func present(_ model: MerchantBusinessAccessModel, reader: Reader) -> MerchantBusinessAccessAppearance {
        let appearance = MerchantBusinessAccessAppearance()
        appearances[ObjectIdentifier(model)] = appearance
        appearanceKeys[ObjectIdentifier(model)] = .init(reader: reader)
        model.begin(reader: reader, appearance: appearance)
        addTeardownBlock {
            await MainActor.run {
                model.end(appearance: appearance)
                reader.finishAll()
            }
        }
        return appearance
    }

    private func retire(_ model: MerchantBusinessAccessModel) {
        if let appearance = appearances[ObjectIdentifier(model)] { model.end(appearance: appearance) }
    }

    private func grant(merchantID: Int = 610, restricted: Bool = false) throws -> MerchantBusinessAccess {
        var object = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        object["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic access workshop \(merchantID)")])
        if restricted {
            object["roleCode"] = .string("MERCHANT_CHECKIN")
            object["permissions"] = .array([.string("merchant:basic:read")])
            object["canManageOperators"] = .bool(false)
        }
        return try MerchantBusinessAccess(object)
    }

    // Existing lifecycle scenarios use synchronous admission, then consume the
    // resulting ticket. Regression tests below also invoke each API directly.
    private func startFreshRead(_ model: MerchantBusinessAccessModel, reader: Reader) async throws -> Load {
        let key = MerchantBusinessAccessLoadKey(reader: reader), identity = ObjectIdentifier(model)
        if let appearance = appearances[identity], model.isActive(appearance: appearance), appearanceKeys[identity] == key {
            model.refresh(reader: reader, appearance: appearance, context: key)
        } else {
            present(model, reader: reader)
        }
        return try await consume(model, reader: reader, request: XCTUnwrap(model.request))
    }

    private func consume(_ model: MerchantBusinessAccessModel, reader: Reader,
                         request: MerchantBusinessAccessRequest) async throws -> Load {
        let id = reader.accessCalls
        let started = expectation(description: "Synthetic access read \(id) suspended")
        reader.nextStarted = started
        let task = Task { await model.load(reader: reader, request: request) }
        await fulfillment(of: [started], timeout: 2)
        guard reader.pending[id] != nil else {
            task.cancel()
            retire(model)
            reader.finishAll()
            throw HarnessFailure.readDidNotSuspend
        }
        return Load(id: id, task: task, request: request)
    }

    private func finish(_ load: Load, reader: Reader, with result: Result<MerchantBusinessAccess, Error>) async {
        reader.resolve(load.id, with: result)
        await load.task.value
    }

    private func assertEmpty(_ model: MerchantBusinessAccessModel, reader: Reader,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(model.access(for: reader), file: file, line: line)
        XCTAssertNil(model.issue(for: reader), file: file, line: line)
        XCTAssertFalse(model.isLoading(for: reader), file: file, line: line)
    }

    private func assertReadOnly(_ reader: Reader, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reader.snapshotCalls, 0, file: file, line: line)
        XCTAssertEqual(reader.executionCalls, 0, file: file, line: line)
        XCTAssertEqual(reader.executionCheckCalls, 0, file: file, line: line)
        XCTAssertEqual(reader.redemptionCalls, 0, file: file, line: line)
    }

    func testLoadKeyIncludesReaderIdentityScopeAuthorizationAndConfiguration() {
        let reader = Reader(), replacement = Reader()
        let original = MerchantBusinessAccessLoadKey(reader: reader)
        replacement.restore(original)
        XCTAssertEqual(original, MerchantBusinessAccessLoadKey(reader: reader))
        XCTAssertNotEqual(original, MerchantBusinessAccessLoadKey(reader: replacement))
        for change in ContextChange.allCases {
            reader.restore(original)
            change.apply(to: reader)
            XCTAssertNotEqual(original, MerchantBusinessAccessLoadKey(reader: reader), "\(change)")
        }
        reader.restore(original)
        reader.authorizationGeneration = nil
        XCTAssertNotEqual(original, MerchantBusinessAccessLoadKey(reader: reader))
    }

    func testSuccessfulReadPublishesOnlyDecodedAccessForItsReader() async throws {
        let (model, reader) = makeSystem(), expected = try grant()
        assertEmpty(model, reader: reader)
        let load = try await startFreshRead(model, reader: reader)
        XCTAssertTrue(model.isLoading(for: reader))
        XCTAssertNil(model.access(for: reader))
        XCTAssertNil(model.issue(for: reader))
        await finish(load, reader: reader, with: .success(expected))
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertTrue(model.access(for: reader)?.allows("merchant:verify") == true)
        XCTAssertNil(model.issue(for: reader))
        XCTAssertFalse(model.isLoading(for: reader))
        XCTAssertEqual(reader.accessCalls, 1)
        XCTAssertFalse(try XCTUnwrap(reader.probes[load.id]).wasCancelled)
        assertReadOnly(reader)
    }

    func testSameScopeRefreshHidesCachedPermissionsUntilFreshReadCompletes() async throws {
        let (model, reader) = makeSystem()
        let first = try await startFreshRead(model, reader: reader)
        await finish(first, reader: reader, with: .success(try grant()))
        let key = MerchantBusinessAccessLoadKey(reader: reader)
        let refresh = try await startFreshRead(model, reader: reader)
        XCTAssertEqual(key, MerchantBusinessAccessLoadKey(reader: reader))
        XCTAssertNil(model.access(for: reader))
        XCTAssertNil(model.issue(for: reader))
        XCTAssertTrue(model.isLoading(for: reader))
        let restricted = try grant(restricted: true)
        await finish(refresh, reader: reader, with: .success(restricted))
        XCTAssertEqual(model.access(for: reader), restricted)
        XCTAssertFalse(model.access(for: reader)?.allows("merchant:verify") ?? true)
        XCTAssertEqual(reader.accessCalls, 2)
        assertReadOnly(reader)
    }

    func testOlderSuccessAndErrorCannotClearConcurrentReplacementLoading() async throws {
        let staleResults: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in staleResults {
            let (model, reader) = makeSystem()
            let older = try await startFreshRead(model, reader: reader)
            let newer = try await startFreshRead(model, reader: reader)
            await finish(older, reader: reader, with: result)
            XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
            XCTAssertFalse(try XCTUnwrap(reader.probes[newer.id]).wasCancelled)
            XCTAssertTrue(model.isLoading(for: reader), "Old cleanup must not finish a newer read")
            XCTAssertNil(model.access(for: reader))
            XCTAssertNil(model.issue(for: reader))
            let expected = try grant(merchantID: 611, restricted: true)
            await finish(newer, reader: reader, with: .success(expected))
            XCTAssertEqual(model.access(for: reader), expected)
            XCTAssertFalse(model.isLoading(for: reader))
            assertReadOnly(reader)
        }
    }

    func testOlderSuccessAndErrorCannotOverwriteCompletedReplacement() async throws {
        let staleResults: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in staleResults {
            let (model, reader) = makeSystem()
            let older = try await startFreshRead(model, reader: reader)
            let newer = try await startFreshRead(model, reader: reader)
            let expected = try grant(merchantID: 611, restricted: true)
            await finish(newer, reader: reader, with: .success(expected))
            await finish(older, reader: reader, with: result)
            XCTAssertEqual(model.access(for: reader), expected)
            XCTAssertNil(model.issue(for: reader))
            XCTAssertFalse(model.isLoading(for: reader))
            assertReadOnly(reader)
        }
    }

    func testOlderSuccessCannotEraseReplacementFailure() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        let newer = try await startFreshRead(model, reader: reader)
        await finish(newer, reader: reader, with: .failure(MerchantBusinessFailure.denied))
        await finish(older, reader: reader, with: .success(try grant()))
        XCTAssertNil(model.access(for: reader))
        XCTAssertEqual(model.issue(for: reader), "merchant.business.denied")
        XCTAssertFalse(model.isLoading(for: reader))
    }

    func testFailedRefreshClearsOldAccessAndUsesTypedOrGenericIssue() async throws {
        let errors: [(Error, String)] = [(MerchantBusinessFailure.denied, "merchant.business.denied"),
                                        (SyntheticError.unavailable, "merchant.business.loadFailed")]
        for (error, expectedIssue) in errors {
            let (model, reader) = makeSystem()
            let initial = try await startFreshRead(model, reader: reader)
            await finish(initial, reader: reader, with: .success(try grant()))
            let refresh = try await startFreshRead(model, reader: reader)
            await finish(refresh, reader: reader, with: .failure(error))
            XCTAssertNil(model.access(for: reader))
            XCTAssertEqual(model.issue(for: reader), expectedIssue)
            XCTAssertFalse(model.isLoading(for: reader))
            let retry = try await startFreshRead(model, reader: reader)
            XCTAssertNil(model.issue(for: reader))
            await finish(retry, reader: reader, with: .success(try grant(restricted: true)))
            XCTAssertNil(model.issue(for: reader))
            assertReadOnly(reader)
        }
    }

    func testEveryContextChangeHidesCachedPermissionsBeforeNewTaskOrAppearanceEvent() async throws {
        for change in ContextChange.allCases {
            let (model, reader) = makeSystem()
            let initial = try await startFreshRead(model, reader: reader)
            await finish(initial, reader: reader, with: .success(try grant()))
            change.apply(to: reader)
            assertEmpty(model, reader: reader)
            XCTAssertEqual(reader.accessCalls, 1, "\(change) must not need a second read to hide access")
            retire(model)
            assertEmpty(model, reader: reader)
            assertReadOnly(reader)
        }
    }

    func testEveryContextChangeHidesCachedIssueBeforeNewTaskOrAppearanceEvent() async throws {
        for change in ContextChange.allCases {
            let (model, reader) = makeSystem()
            let initial = try await startFreshRead(model, reader: reader)
            await finish(initial, reader: reader, with: .failure(MerchantBusinessFailure.denied))
            XCTAssertEqual(model.issue(for: reader), "merchant.business.denied")
            change.apply(to: reader)
            assertEmpty(model, reader: reader)
            XCTAssertEqual(reader.accessCalls, 1)
        }
    }

    func testContextDriftDiscardsSuspendedSuccessAndErrorBeforeAppearanceEvent() async throws {
        let results: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for change in ContextChange.allCases {
            for result in results {
                let (model, reader) = makeSystem()
                let oldKey = MerchantBusinessAccessLoadKey(reader: reader)
                let load = try await startFreshRead(model, reader: reader)
                let appearance = try XCTUnwrap(appearances[ObjectIdentifier(model)])
                change.apply(to: reader)
                assertEmpty(model, reader: reader)
                await finish(load, reader: reader, with: result)
                assertEmpty(model, reader: reader)
                XCTAssertTrue(model.isActive(appearance: appearance), "A late response must not retire the visible appearance before onChange")
                XCTAssertNil(model.request)
                reader.restore(oldKey)
                assertEmpty(model, reader: reader)
            }
        }
    }

    func testContextChangeResponseBeforeOnChangeKeepsAppearanceReplaceableAndNewReadSucceeds() async throws {
        let results: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in results {
            let (model, reader) = makeSystem()
            let originalAppearance = present(model, reader: reader)
            let older = try await consume(model, reader: reader, request: XCTUnwrap(model.request))
            reader.authorizationGeneration = UUID()
            await finish(older, reader: reader, with: result) // Completes before Home's onChange.
            assertEmpty(model, reader: reader)
            XCTAssertNil(model.request)
            XCTAssertTrue(model.isActive(appearance: originalAppearance))
            // Match Home's guard and transition, rather than rescuing a retired token.
            guard model.isActive(appearance: originalAppearance) else {
                XCTFail("Home onChange would be blocked by a prematurely retired appearance")
                continue
            }
            model.end(appearance: originalAppearance)
            let replacementAppearance = present(model, reader: reader)
            let newer = try await consume(model, reader: reader, request: XCTUnwrap(model.request))
            XCTAssertFalse(model.isActive(appearance: originalAppearance))
            XCTAssertTrue(model.isActive(appearance: replacementAppearance))
            let expected = try grant(restricted: true)
            await finish(newer, reader: reader, with: .success(expected))
            XCTAssertEqual(model.access(for: reader), expected)
            XCTAssertFalse(model.access(for: reader)?.allows("merchant:verify") ?? true)
            XCTAssertNil(model.issue(for: reader))
            XCTAssertFalse(model.isLoading(for: reader))
            XCTAssertEqual(reader.accessCalls, 2)
            assertReadOnly(reader)
        }
    }

    func testObservedContextABACannotRestoreCachedAccess() async throws {
        for change in ContextChange.allCases {
            let (model, reader) = makeSystem()
            let original = MerchantBusinessAccessLoadKey(reader: reader)
            let initial = try await startFreshRead(model, reader: reader)
            await finish(initial, reader: reader, with: .success(try grant()))
            change.apply(to: reader)
            retire(model) // Observe B before returning to A.
            reader.restore(original)
            retire(model)
            XCTAssertEqual(original, MerchantBusinessAccessLoadKey(reader: reader))
            assertEmpty(model, reader: reader)
            let reopened = try await startFreshRead(model, reader: reader)
            let expected = try grant(restricted: true)
            await finish(reopened, reader: reader, with: .success(expected))
            XCTAssertEqual(model.access(for: reader), expected)
        }
    }

    func testObservedContextABAFencesOldReadWhenOriginalKeyReturns() async throws {
        for change in ContextChange.allCases {
            let (model, reader) = makeSystem()
            let original = MerchantBusinessAccessLoadKey(reader: reader)
            let older = try await startFreshRead(model, reader: reader)
            change.apply(to: reader)
            retire(model)
            reader.restore(original)
            retire(model)
            XCTAssertEqual(original, MerchantBusinessAccessLoadKey(reader: reader))
            let newer = try await startFreshRead(model, reader: reader)
            await finish(older, reader: reader, with: .success(try grant()))
            XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
            XCTAssertNil(model.access(for: reader))
            XCTAssertTrue(model.isLoading(for: reader))
            let expected = try grant(restricted: true)
            await finish(newer, reader: reader, with: .success(expected))
            XCTAssertEqual(model.access(for: reader), expected)
        }
    }

    func testAuthorizationChangeAtSameScopeLoadsOnlyNewPermissions() async throws {
        let (model, reader) = makeSystem()
        let originalScope = reader.scope
        let older = try await startFreshRead(model, reader: reader)
        reader.authorizationGeneration = UUID()
        assertEmpty(model, reader: reader)
        retire(model)
        let newer = try await startFreshRead(model, reader: reader)
        let expected = try grant(restricted: true)
        await finish(newer, reader: reader, with: .success(expected))
        await finish(older, reader: reader, with: .failure(MerchantBusinessFailure.denied))
        XCTAssertEqual(reader.scope, originalScope)
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertNil(model.issue(for: reader))
    }

    func testAccountChangeCannotRestoreOldMerchantOrItsPermissions() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        ContextChange.account.apply(to: reader)
        assertEmpty(model, reader: reader)
        let newer = try await startFreshRead(model, reader: reader)
        let expected = try grant(merchantID: 611, restricted: true)
        await finish(newer, reader: reader, with: .success(expected))
        await finish(older, reader: reader, with: .success(try grant()))
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertEqual(reader.scope?.accountID, 99002)
        XCTAssertNil(model.issue(for: reader))
        assertReadOnly(reader)
    }

    func testReplacementReaderAtIdenticalScopeCannotSeeOldAccessOrIssue() async throws {
        let results: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in results {
            let (model, reader) = makeSystem(), replacement = Reader()
            defer { replacement.finishAll() }
            replacement.restore(MerchantBusinessAccessLoadKey(reader: reader))
            let original = try await startFreshRead(model, reader: reader)
            await finish(original, reader: reader, with: result)
            assertEmpty(model, reader: replacement)
            XCTAssertEqual(replacement.accessCalls, 0)
            retire(model)
            assertEmpty(model, reader: reader)
            let next = try await startFreshRead(model, reader: replacement)
            let expected = try grant(merchantID: 611, restricted: true)
            await finish(next, reader: replacement, with: .success(expected))
            XCTAssertEqual(model.access(for: replacement), expected)
            assertEmpty(model, reader: reader)
            assertReadOnly(replacement)
        }
    }

    func testReplacementReaderCancelsOldReadDespiteIdenticalScopeAndAuthorization() async throws {
        let (model, reader) = makeSystem(), replacement = Reader()
        defer { replacement.finishAll() }
        replacement.restore(MerchantBusinessAccessLoadKey(reader: reader))
        let older = try await startFreshRead(model, reader: reader)
        assertEmpty(model, reader: replacement)
        let newer = try await startFreshRead(model, reader: replacement)
        await finish(older, reader: reader, with: .failure(MerchantBusinessFailure.denied))
        XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
        XCTAssertTrue(model.isLoading(for: replacement))
        XCTAssertNil(model.issue(for: replacement))
        assertEmpty(model, reader: reader)
        let expected = try grant(merchantID: 611, restricted: true)
        await finish(newer, reader: replacement, with: .success(expected))
        XCTAssertEqual(model.access(for: replacement), expected)
        assertReadOnly(reader)
        assertReadOnly(replacement)
    }

    func testSignOutSkipsAccessReadAndLateSuccessCannotEraseSignInIssue() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        reader.scope = nil
        assertEmpty(model, reader: reader)
        present(model, reader: reader)
        XCTAssertEqual(reader.accessCalls, 1)
        XCTAssertEqual(model.issue(for: reader), "merchant.signIn")
        await finish(older, reader: reader, with: .success(try grant()))
        XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
        XCTAssertNil(model.access(for: reader))
        XCTAssertEqual(model.issue(for: reader), "merchant.signIn")
        XCTAssertFalse(model.isLoading(for: reader))
        assertReadOnly(reader)
    }

    func testDisabledConfigurationSkipsReadAndLateErrorCannotEraseConfigurationIssue() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        reader.isConfigured = false
        assertEmpty(model, reader: reader)
        present(model, reader: reader)
        XCTAssertEqual(reader.accessCalls, 1)
        XCTAssertEqual(model.issue(for: reader), "auth.notConfigured")
        await finish(older, reader: reader, with: .failure(MerchantBusinessFailure.denied))
        XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
        XCTAssertNil(model.access(for: reader))
        XCTAssertEqual(model.issue(for: reader), "auth.notConfigured")
        XCTAssertFalse(model.isLoading(for: reader))
        assertReadOnly(reader)
    }

    func testInitiallySignedOutOrDisabledNeverInvokesReaderAndCanRecover() async throws {
        let (model, reader) = makeSystem()
        let original = MerchantBusinessAccessLoadKey(reader: reader)
        reader.scope = nil
        present(model, reader: reader)
        XCTAssertEqual(model.issue(for: reader), "merchant.signIn")
        reader.isConfigured = false
        present(model, reader: reader)
        XCTAssertEqual(model.issue(for: reader), "auth.notConfigured")
        XCTAssertEqual(reader.accessCalls, 0)
        XCTAssertFalse(model.isLoading(for: reader))
        reader.restore(original)
        assertEmpty(model, reader: reader)
        let recovered = try await startFreshRead(model, reader: reader)
        await finish(recovered, reader: reader, with: .success(try grant(restricted: true)))
        XCTAssertNotNil(model.access(for: reader))
        XCTAssertNil(model.issue(for: reader))
        assertReadOnly(reader)
    }

    func testRepeatedBeginForCurrentAppearanceCannotCancelItsClaimedRequest() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        reader.authorizationGeneration = UUID()
        let newer = try await startFreshRead(model, reader: reader)
        let current = try XCTUnwrap(appearances[ObjectIdentifier(model)])
        model.begin(reader: reader, appearance: current)
        model.begin(reader: reader, appearance: current)
        XCTAssertEqual(model.request, newer.request)
        XCTAssertTrue(model.isLoading(for: reader))
        XCTAssertFalse(try XCTUnwrap(reader.probes[newer.id]).wasCancelled)
        await finish(older, reader: reader, with: .success(try grant()))
        XCTAssertTrue(model.isLoading(for: reader))
        let expected = try grant(restricted: true)
        await finish(newer, reader: reader, with: .success(expected))
        model.begin(reader: reader, appearance: current)
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertFalse(try XCTUnwrap(reader.probes[newer.id]).wasCancelled)
    }

    func testLeavingClearsCachedPermissionsAndReopeningRequiresFreshRead() async throws {
        let (model, reader) = makeSystem()
        let first = try await startFreshRead(model, reader: reader)
        await finish(first, reader: reader, with: .success(try grant()))
        retire(model) // HomeView.onDisappear.
        retire(model)
        assertEmpty(model, reader: reader)
        retire(model)
        assertEmpty(model, reader: reader)
        let reopened = try await startFreshRead(model, reader: reader)
        XCTAssertNil(model.access(for: reader))
        XCTAssertTrue(model.isLoading(for: reader))
        let expected = try grant(restricted: true)
        await finish(reopened, reader: reader, with: .success(expected))
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertEqual(reader.accessCalls, 2)
    }

    func testLeavingCancelsPendingReadAndLateCompletionCannotRepopulateClosedHome() async throws {
        let results: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in results {
            let (model, reader) = makeSystem()
            let pending = try await startFreshRead(model, reader: reader)
            retire(model)
            assertEmpty(model, reader: reader)
            await finish(pending, reader: reader, with: result)
            XCTAssertTrue(try XCTUnwrap(reader.probes[pending.id]).wasCancelled)
            assertEmpty(model, reader: reader)
        }
    }

    func testReopeningWhileDismissedReadIsPendingFencesOldCompletion() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        retire(model)
        let reopened = try await startFreshRead(model, reader: reader)
        await finish(older, reader: reader, with: .success(try grant()))
        XCTAssertTrue(model.isLoading(for: reader))
        XCTAssertNil(model.access(for: reader))
        XCTAssertNil(model.issue(for: reader))
        let expected = try grant(restricted: true)
        await finish(reopened, reader: reader, with: .success(expected))
        XCTAssertEqual(model.access(for: reader), expected)
        assertReadOnly(reader)
    }

    func testCallerCancellationPropagatesToOwnedTaskAndDiscardsLateSuccessOrError() async throws {
        let results: [Result<MerchantBusinessAccess, Error>] = [.success(try grant()), .failure(MerchantBusinessFailure.denied)]
        for result in results {
            let (model, reader) = makeSystem()
            let pending = try await startFreshRead(model, reader: reader)
            pending.task.cancel()
            await finish(pending, reader: reader, with: result)
            XCTAssertTrue(try XCTUnwrap(reader.probes[pending.id]).wasCancelled)
            assertEmpty(model, reader: reader)
            let retry = try await startFreshRead(model, reader: reader)
            await finish(retry, reader: reader, with: .success(try grant(restricted: true)))
            XCTAssertNotNil(model.access(for: reader))
            assertReadOnly(reader)
        }
    }

    func testCancellingOlderCallerAfterReplacementDoesNotCancelNewRead() async throws {
        let (model, reader) = makeSystem()
        let older = try await startFreshRead(model, reader: reader)
        let newer = try await startFreshRead(model, reader: reader)
        older.task.cancel()
        await finish(older, reader: reader, with: .failure(CancellationError()))
        XCTAssertTrue(try XCTUnwrap(reader.probes[older.id]).wasCancelled)
        XCTAssertFalse(try XCTUnwrap(reader.probes[newer.id]).wasCancelled)
        XCTAssertTrue(model.isLoading(for: reader))
        let expected = try grant(restricted: true)
        await finish(newer, reader: reader, with: .success(expected))
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertNil(model.issue(for: reader))
    }

    func testCancelledOldLoadEnteringAfterReplacementCannotClearNewRequestLoadingOrCache() async throws {
        let (model, oldReader) = makeSystem(), replacement = Reader()
        let oldAppearance = present(model, reader: oldReader)
        let oldTicket = try XCTUnwrap(model.request)
        replacement.restore(oldTicket.context)
        let queued = expectation(description: "Old ticket consumer queued before entering model")
        var gate: CheckedContinuation<Void, Never>?
        defer { gate?.resume() }
        let lateOldCaller = Task {
            await withCheckedContinuation { gate = $0; queued.fulfill() }
            await model.load(reader: oldReader, request: oldTicket)
        }
        await fulfillment(of: [queued], timeout: 2)
        lateOldCaller.cancel()
        let currentAppearance = present(model, reader: replacement)
        let current = try await consume(model, reader: replacement, request: XCTUnwrap(model.request))
        gate?.resume(); gate = nil
        await lateOldCaller.value
        XCTAssertFalse(model.isActive(appearance: oldAppearance))
        XCTAssertTrue(model.isActive(appearance: currentAppearance))
        XCTAssertEqual(model.request, current.request)
        XCTAssertTrue(model.isLoading(for: replacement))
        XCTAssertFalse(try XCTUnwrap(replacement.probes[current.id]).wasCancelled)
        XCTAssertNil(model.access(for: replacement))
        XCTAssertEqual(oldReader.accessCalls, 0)
        let expected = try grant(merchantID: 611, restricted: true)
        await finish(current, reader: replacement, with: .success(expected))
        let cancelledAgain = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(reader: oldReader, request: oldTicket)
        }
        await cancelledAgain.value
        await model.load(reader: oldReader, request: oldTicket) // Also reject an uncancelled obsolete ticket.
        XCTAssertEqual(model.request, current.request)
        XCTAssertEqual(model.access(for: replacement), expected)
        XCTAssertNil(model.issue(for: replacement))
        XCTAssertFalse(model.isLoading(for: replacement))
        XCTAssertEqual(oldReader.accessCalls, 0)
        XCTAssertEqual(replacement.accessCalls, 1)
        assertReadOnly(oldReader)
        assertReadOnly(replacement)
    }

    func testQueuedOldRefreshCannotReenterAfterLeavingReplacementOrObservedABA() async throws {
        for scenario in ["reentry", "replacement", "authorizationABA", "accountABA"] {
            let (model, originalReader) = makeSystem()
            let oldAppearance = present(model, reader: originalReader)
            let oldKey = MerchantBusinessAccessLoadKey(reader: originalReader)
            let oldTicket = try XCTUnwrap(model.request)
            let queued = expectation(description: "Old refresh queued: \(scenario)")
            var gate: CheckedContinuation<Void, Never>?
            defer { gate?.resume() }
            let oldRefresh = Task {
                await withCheckedContinuation { gate = $0; queued.fulfill() }
                model.refresh(reader: originalReader, appearance: oldAppearance, context: oldKey)
            }
            await fulfillment(of: [queued], timeout: 2)
            model.end(appearance: oldAppearance)
            model.refresh(reader: originalReader, appearance: oldAppearance, context: oldKey)
            XCTAssertNil(model.request)
            XCTAssertFalse(model.isActive(appearance: oldAppearance))
            let currentReader: Reader
            if scenario == "replacement" {
                currentReader = Reader()
                currentReader.restore(oldKey)
            } else {
                currentReader = originalReader
                if scenario.hasSuffix("ABA") {
                    if scenario == "authorizationABA" { ContextChange.authorization.apply(to: originalReader) }
                    else { ContextChange.account.apply(to: originalReader) }
                    let intermediate = present(model, reader: originalReader)
                    model.end(appearance: intermediate)
                    originalReader.restore(oldKey)
                }
            }
            let currentAppearance = present(model, reader: currentReader)
            let current = try await consume(model, reader: currentReader, request: XCTUnwrap(model.request))
            gate?.resume(); gate = nil
            await oldRefresh.value
            model.begin(reader: originalReader, appearance: oldAppearance)
            model.end(appearance: oldAppearance)
            XCTAssertTrue(model.isActive(appearance: currentAppearance), scenario)
            XCTAssertEqual(model.request, current.request, scenario)
            XCTAssertTrue(model.isLoading(for: currentReader), scenario)
            XCTAssertFalse(try XCTUnwrap(currentReader.probes[current.id]).wasCancelled, scenario)
            let expected = try grant(merchantID: 611, restricted: true)
            await finish(current, reader: currentReader, with: .success(expected))
            model.refresh(reader: originalReader, appearance: oldAppearance, context: oldKey)
            await model.load(reader: originalReader, request: oldTicket)
            XCTAssertEqual(model.access(for: currentReader), expected, scenario)
            XCTAssertEqual(model.request, current.request, scenario)
            XCTAssertEqual(currentReader.accessCalls, 1, scenario)
            if currentReader !== originalReader { XCTAssertEqual(originalReader.accessCalls, 0) }
            assertReadOnly(originalReader)
            assertReadOnly(currentReader)
        }
    }

    func testStaleRefreshKeyAndWrongReaderCannotReplaceCurrentRequest() async throws {
        let (model, reader) = makeSystem(), replacement = Reader()
        let oldKey = MerchantBusinessAccessLoadKey(reader: reader)
        reader.authorizationGeneration = UUID()
        let appearance = present(model, reader: reader)
        let current = try await consume(model, reader: reader, request: XCTUnwrap(model.request))
        replacement.restore(MerchantBusinessAccessLoadKey(reader: reader))
        model.refresh(reader: reader, appearance: appearance, context: oldKey)
        model.refresh(reader: replacement, appearance: appearance, context: .init(reader: replacement))
        await model.load(reader: replacement, request: current.request)
        XCTAssertEqual(model.request, current.request)
        XCTAssertTrue(model.isLoading(for: reader))
        XCTAssertFalse(try XCTUnwrap(reader.probes[current.id]).wasCancelled)
        XCTAssertEqual(replacement.accessCalls, 0)
        await finish(current, reader: reader, with: .success(try grant(restricted: true)))
    }

    func testTicketCanBeConsumedOnlyOnceAndSupersededUnclaimedTicketCannotRead() async throws {
        let (model, reader) = makeSystem()
        let appearance = present(model, reader: reader)
        let obsolete = try XCTUnwrap(model.request)
        model.refresh(reader: reader, appearance: appearance, context: .init(reader: reader))
        let ticket = try XCTUnwrap(model.request)
        XCTAssertNotEqual(obsolete, ticket)
        await model.load(reader: reader, request: obsolete)
        XCTAssertEqual(reader.accessCalls, 0)
        XCTAssertEqual(model.request, ticket)
        let first = try await consume(model, reader: reader, request: ticket)
        await model.load(reader: reader, request: ticket)
        XCTAssertEqual(reader.accessCalls, 1)
        XCTAssertTrue(model.isLoading(for: reader))
        XCTAssertFalse(try XCTUnwrap(reader.probes[first.id]).wasCancelled)
        let expected = try grant()
        await finish(first, reader: reader, with: .success(expected))
        await model.load(reader: reader, request: ticket)
        XCTAssertEqual(reader.accessCalls, 1)
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertEqual(model.request, ticket)
        assertReadOnly(reader)
    }

    func testCancelledCurrentTicketConsumerCannotClearExistingCache() async throws {
        let (model, reader) = makeSystem()
        let completed = try await startFreshRead(model, reader: reader)
        let expected = try grant()
        await finish(completed, reader: reader, with: .success(expected))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(reader: reader, request: completed.request)
        }
        await cancelled.value
        XCTAssertEqual(model.access(for: reader), expected)
        XCTAssertEqual(model.request, completed.request)
        XCTAssertEqual(reader.accessCalls, 1)
    }

    func testAllHomeRouteTargetsSurviveAccessCleanupWithOriginalDependencies() async throws {
        let targets: [MerchantBusinessHomeRoute.Target] = [.query(.overview), .scan, .cityNode]
        for target in targets {
            let (model, reader) = makeSystem(), journal = MerchantBusinessMemoryIntentStore()
            let loaded = try await startFreshRead(model, reader: reader)
            await finish(loaded, reader: reader, with: .success(try grant()))
            let route = MerchantBusinessHomeRoute(target: target, reader: reader, journal: journal)
            let equalRoute = MerchantBusinessHomeRoute(target: target, reader: reader, journal: journal)
            XCTAssertEqual(route, equalRoute)
            XCTAssertEqual(Set([route, equalRoute]).count, 1)
            retire(model) // Pushing a destination removes Home's access rows.
            assertEmpty(model, reader: reader)
            XCTAssertTrue(route.isCurrent(reader: reader, journal: journal))
            XCTAssertTrue(route.reader === reader)
            XCTAssertTrue(route.journal === journal)
            XCTAssertEqual(route.target, target)
            assertReadOnly(reader)
        }
    }

    func testHomeRouteRejectsChangedReaderScopeAuthorizationConfigurationOrJournal() {
        let targets: [MerchantBusinessHomeRoute.Target] = [.query(.overview), .scan, .cityNode]
        for target in targets {
            let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
            let route = MerchantBusinessHomeRoute(target: target, reader: reader, journal: journal)
            let original = MerchantBusinessAccessLoadKey(reader: reader)
            for change in ContextChange.allCases {
                reader.restore(original)
                change.apply(to: reader)
                XCTAssertFalse(route.isCurrent(reader: reader, journal: journal), "\(target), \(change)")
                XCTAssertNotEqual(route, MerchantBusinessHomeRoute(target: target, reader: reader, journal: journal))
            }
            reader.restore(original)
            let replacement = Reader(), replacementJournal = MerchantBusinessMemoryIntentStore()
            replacement.restore(original)
            XCTAssertFalse(route.isCurrent(reader: replacement, journal: journal))
            XCTAssertFalse(route.isCurrent(reader: reader, journal: replacementJournal))
            XCTAssertNotEqual(route, MerchantBusinessHomeRoute(target: target, reader: replacement, journal: journal))
            XCTAssertNotEqual(route, MerchantBusinessHomeRoute(target: target, reader: reader, journal: replacementJournal))
            XCTAssertTrue(route.reader === reader)
            XCTAssertTrue(route.journal === journal)
            assertReadOnly(reader)
            assertReadOnly(replacement)
        }
    }

    func testAccessLifecycleNeverDispatchesMutationOrChangesExistingIntent() async throws {
        let (model, reader) = makeSystem(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610,
                                            target: "review:63001", requestID: "synthetic-home-existing-intent")
        try journal.reserve(intent)
        let initial = try await startFreshRead(model, reader: reader)
        await finish(initial, reader: reader, with: .success(try grant()))
        let refresh = try await startFreshRead(model, reader: reader)
        await finish(refresh, reader: reader, with: .failure(MerchantBusinessFailure.denied))
        reader.authorizationGeneration = UUID()
        retire(model)
        let replacement = try await startFreshRead(model, reader: reader)
        await finish(replacement, reader: reader, with: .success(try grant(restricted: true)))
        retire(model)
        reader.scope = nil
        present(model, reader: reader)
        reader.isConfigured = false
        present(model, reader: reader)
        XCTAssertEqual(reader.accessCalls, 3)
        assertReadOnly(reader)
        XCTAssertEqual(try journal.intents(), [intent])
    }
}
