import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelManagementContractTests: XCTestCase {
    func testViewPermissionDoesNotBecomeChannelOrRoleManagement() throws {
        let channel = try fixtureChannel(names: ["VIEW_CHANNEL"])
        XCTAssertFalse(channel.canManage); XCTAssertFalse(channel.canManagePermissions); XCTAssertFalse(channel.canDelete)
        XCTAssertEqual(NativeChannelManagementCapability.manageChannel.bit, 1 << 10)
        XCTAssertEqual(NativeChannelManagementCapability.manageRole.bit, 1 << 11)
        XCTAssertEqual(NativeChannelManagementCapability.webhook.bit, 1 << 25)
    }
    func testActualStringIDsAndDistinctVersionsDoNotAcceptConversationProjection() throws {
        let channel = try fixtureChannel()
        XCTAssertEqual(channel.id.rawValue, "9012"); XCTAssertEqual(channel.scope.guildID.rawValue, "42")
        XCTAssertEqual(channel.version.value, 5); XCTAssertEqual(channel.permissionVersion?.value, 8)
        XCTAssertThrowsError(try NativeChannelManagementID("club_42"))
        XCTAssertThrowsError(try NativeChannelManagementID("09012"))
        XCTAssertThrowsError(try JSONDecoder().decode(NativeChannelManagementChannel.self,
            from: Data(#"{"conversation_id":9012,"counterparty":{"bizKey":"club_42"}}"#.utf8)))
    }
    func testDirectoryUsesCurrentServiceShapeWithoutDetailPermissionEpoch() async throws {
        let harness = try Harness()
        var row = channelObject(); row.removeValue(forKey: "perm_version")
        harness.transport.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/guilds/1/42/channels")
            return try envelope(["guild_kind": 1, "guild_id": "42", "groups": [], "ungrouped": [row]])
        }
        let result = try await harness.service().directory()
        XCTAssertEqual(result.channels.count, 1); XCTAssertNil(result.channels[0].permissionVersion)
        XCTAssertThrowsError(try result.channels[0].requireDetail(in: result.scope))
    }
    func testPatchPreservesExplicitNullAndOnlyChangedKeys() throws {
        let channel = try fixtureChannel()
        var draft = NativeChannelManagementDraft(channel: channel); draft.topic = ""
        let intent = try NativeChannelManagementIntent.edit(channel: channel, draft: draft, reason: "活动结束", requestID: "original-edit-001")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: intent.body()) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["topic", "expected_version", "reason", "request_id"])
        XCTAssertTrue(body["topic"] is NSNull); XCTAssertEqual(body["expected_version"] as? String, "5")
        XCTAssertEqual(try intent.body(), intent.body())
        let restored = try JSONDecoder().decode(NativeChannelManagementIntent.self, from: JSONEncoder().encode(intent))
        XCTAssertEqual(try restored.body(), intent.body())
    }
    func testDraftAndArchivedProtectedCommandsAreRejectedBeforeDispatch() throws {
        var draft = NativeChannelManagementDraft(); draft.name = "bad/name"
        XCTAssertThrowsError(try draft.validate()); draft.name = "频道"; draft.slowmodeSeconds = 21601
        XCTAssertThrowsError(try draft.validate())
        let defaultChannel = try fixtureChannel(isDefault: true)
        XCTAssertThrowsError(try NativeChannelManagementIntent.lifecycle(.delete, channel: defaultChannel, reason: "delete"))
        let systemArchive = try fixtureChannel(status: 1, archiveReason: "club_closed")
        XCTAssertThrowsError(try NativeChannelManagementIntent.lifecycle(.unarchive, channel: systemArchive, reason: "open"))
    }
    func testJournalPreservesOriginalAndSeparatesOwnerScopeDeployment() throws {
        let harness = try Harness(); let storage = MemoryStorage(); let source = try createIntent(harness.scope)
        let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        try journal.saveBeforeDispatch(source)
        let reopened = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        XCTAssertEqual(try reopened.restore(), source)
        let other = try NativeChannelManagementOwner(accountID: 12, namespace: "CN:test", baseURL: harness.api.baseURL)
        XCTAssertNil(try NativeChannelManagementJournal(owner: other, scope: harness.scope, storage: storage).restore())
        let otherScope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("43"))
        XCTAssertNil(try NativeChannelManagementJournal(owner: harness.owner(), scope: otherScope, storage: storage).restore())
        let changed = try createIntent(harness.scope, requestID: "another-request-001")
        XCTAssertThrowsError(try journal.saveBeforeDispatch(changed)); XCTAssertThrowsError(try journal.settle(changed))
        XCTAssertEqual(try journal.restore(), source)
        let lock = try XCTUnwrap(journal.beginOperation()); XCTAssertNil(reopened.beginOperation()); journal.endOperation(lock)
        let nextLock = try XCTUnwrap(reopened.beginOperation()); reopened.endOperation(nextLock)
    }
    func testJournalUnknownIdentityAtEveryRecordLayerCannotBeReadReplacedOrSettled() throws {
        let harness = try Harness(); let original = try createIntent(harness.scope)
        for location in ["record", "owner", "scope", "intent", "intentScope"] {
            let storage = MemoryStorage()
            let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
            try journal.saveBeforeDispatch(original)
            let key = try XCTUnwrap(storage.values.keys.first)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.values[key])) as? [String: Any])
            let unknown = "futureIdentityBinding"
            if location == "record" { raw[unknown] = "must-not-be-discarded" }
            else if location == "intentScope" {
                var intent = try XCTUnwrap(raw["intent"] as? [String: Any])
                var scope = try XCTUnwrap(intent["scope"] as? [String: Any])
                scope[unknown] = "must-not-be-discarded"; intent["scope"] = scope; raw["intent"] = intent
            } else {
                var value = try XCTUnwrap(raw[location] as? [String: Any])
                value[unknown] = "must-not-be-discarded"; raw[location] = value
            }
            let originalBytes = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            storage.values[key] = originalBytes
            XCTAssertThrowsError(try journal.restore(), location)
            XCTAssertThrowsError(try journal.saveBeforeDispatch(original), location)
            XCTAssertThrowsError(try journal.settle(original), location)
            XCTAssertEqual(storage.values[key], originalBytes, location)
        }
    }
    func testJournalLegacyKnownOptionalNullsRemainReadableWithoutByteMigration() throws {
        let harness = try Harness(); let storage = MemoryStorage(); let original = try createIntent(harness.scope)
        let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        try journal.saveBeforeDispatch(original)
        let key = try XCTUnwrap(storage.values.keys.first)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.values[key])) as? [String: Any])
        var intent = try XCTUnwrap(raw["intent"] as? [String: Any])
        for optional in ["channelID", "expectedVersion", "permissionVersion", "targetType", "targetID"] { intent[optional] = NSNull() }
        raw["intent"] = intent
        let originalBytes = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        storage.values[key] = originalBytes
        let reopened = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        XCTAssertEqual(try reopened.restore(), original)
        XCTAssertEqual(try reopened.restore()?.body(), original.body())
        try reopened.saveBeforeDispatch(original)
        XCTAssertEqual(storage.values[key], originalBytes)
        try reopened.settle(original); XCTAssertNil(storage.values[key])
    }
    func testJournalLegacyNumericVersionPreservesOriginalCommandAndRawBytes() throws {
        let harness = try Harness(); let storage = MemoryStorage(); let channel = try fixtureChannel()
        var draft = NativeChannelManagementDraft(channel: channel); draft.topic = "更新简介"
        let original = try NativeChannelManagementIntent.edit(channel: channel, draft: draft, reason: "更新", requestID: "legacy-numeric-version")
        let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        try journal.saveBeforeDispatch(original)
        let key = try XCTUnwrap(storage.values.keys.first)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.values[key])) as? [String: Any])
        var intent = try XCTUnwrap(raw["intent"] as? [String: Any]); intent["expectedVersion"] = 5; raw["intent"] = intent
        let originalBytes = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        storage.values[key] = originalBytes
        XCTAssertEqual(try journal.restore(), original)
        XCTAssertEqual(try journal.restore()?.body(), original.body())
        try journal.saveBeforeDispatch(original); XCTAssertEqual(storage.values[key], originalBytes)
        try journal.settle(original); XCTAssertNil(storage.values[key])
    }
    func testLostStorageWriteCannotDispatch() throws {
        let harness = try Harness(); let storage = MemoryStorage(); storage.dropWrites = true
        let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        XCTAssertThrowsError(try journal.saveBeforeDispatch(createIntent(harness.scope)))
        XCTAssertEqual(harness.transport.requests.count, 0)
    }
    func testAbsentLeaseAndRevokedABAStayClosed() async throws {
        let harness = try Harness(); harness.approval = nil
        let unavailable = try harness.service()
        do { _ = try await unavailable.directory(); XCTFail("Missing lease must not dispatch") } catch { }
        XCTAssertTrue(harness.transport.requests.isEmpty)
        let active = try Harness(); let service = try active.service(); active.live = nil
        XCTAssertFalse(service.isCurrent); active.live = active.context
        XCTAssertFalse(service.isCurrent); XCTAssertTrue(active.transport.requests.isEmpty)
    }
    func testIdentityChangeDuringResponseSuppressesOldPayloadAndUnauthorizedCallback() async throws {
        let harness = try Harness(); let service = try harness.service()
        harness.transport.handler = { _ in
            harness.live = nil
            return (Data(#"{"code":401,"errorCode":"LOGIN_REQUIRED"}"#.utf8), 401)
        }
        do { _ = try await service.detail(.init("9012")); XCTFail("Old identity response must be dropped") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .changedIdentity) }
        XCTAssertEqual(harness.unauthorizedCalls, 0)
    }
    func testRealChannelContextUsesClubAggregateAndCurrentEpochWithoutMintingWebhookGrant() async throws {
        let harness = try Harness(); harness.transport.handler = { _ in try envelope(channelObject()) }
        let service = try harness.service(); let context = try await service.currentChannelContext(channelID: .init("9012"))
        XCTAssertEqual(context.channelID.rawValue, "9012"); XCTAssertEqual(context.ownerID.rawValue, "42")
        XCTAssertEqual(context.ownerType, "CLUB"); XCTAssertEqual(context.identity.epoch, 1)
        XCTAssertFalse(context.serverPermissionNames.contains("MANAGE_WEBHOOKS")); XCTAssertTrue(service.contextIsCurrent(context))
        harness.approval?.revoke(); XCTAssertFalse(service.contextIsCurrent(context))
    }
    func testNotFoundRetainsOriginalAndDoesNotGenerateOrResendCommand() async throws {
        let harness = try Harness(); let storage = MemoryStorage(); let service = try harness.service()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try createIntent(service.scope, requestID: "lookup-original-001"); try journal.saveBeforeDispatch(intent)
        harness.transport.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/channel-platform/requests/lookup-original-001")
            return try envelope(["state": "NOT_FOUND", "request_id": intent.requestID, "retry_with_original_request": true])
        }
        let coordinator = try NativeChannelManagementCoordinator(service: service, journal: journal)
        coordinator.restoreOriginal(); await coordinator.recoverOriginal()
        XCTAssertEqual(coordinator.pending, intent); XCTAssertEqual(coordinator.outcome, .notFound)
        XCTAssertTrue(coordinator.canResendOriginal); XCTAssertEqual(try journal.restore(), intent)
        XCTAssertEqual(harness.transport.requests.count, 1)
        coordinator.retire()
        XCTAssertFalse(service.isCurrent); XCTAssertNil(coordinator.pending)
        XCTAssertEqual(try journal.restore(), intent, "Retiring the UI/final-forward lease must retain the exact durable original")
    }
    func testRedactedAppliedRestoresOutcomeWithoutHistoricalMetadataOrNewAuthority() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try createIntent(service.scope, requestID: "redacted-original-001"); try journal.saveBeforeDispatch(intent)
        harness.transport.handler = { _ in try envelope(["state": "APPLIED", "request_id": intent.requestID, "outcome_known": true, "result_redacted": true]) }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal); await model.recoverOriginal()
        XCTAssertEqual(model.outcome, .appliedRedacted); XCTAssertNil(model.detail); XCTAssertNil(model.pending)
        XCTAssertNil(try journal.restore()); XCTAssertFalse(model.canCreate)
    }
    func testWrongRequestReceiptCannotSettleOriginal() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try createIntent(service.scope, requestID: "bound-original-001"); try journal.saveBeforeDispatch(intent)
        harness.transport.handler = { _ in try envelope(["state": "APPLIED", "request_id": "different-request", "outcome_known": true, "result_redacted": true]) }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal); await model.recoverOriginal()
        XCTAssertEqual(try journal.restore(), intent); XCTAssertNil(model.outcome)
    }
    func testTimeoutKeepsSavedOriginalAndRecoversItsActualCreateResult() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try createIntent(service.scope, requestID: "timeout-create-original")
        var forwarded: Data?
        harness.transport.handler = { request in
            if request.url?.path.hasSuffix("/channels/manage") == true { return try envelope([]) }
            if request.httpMethod == "POST" {
                forwarded = request.httpBody
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Audit-Log-Reason"), intent.reason)
                throw URLError(.timedOut)
            }
            if request.url?.path.contains("/requests/") == true {
                return try envelope(["state": "APPLIED", "request_id": intent.requestID, "outcome_known": true,
                    "result": ["state": "APPLIED", "request_id": intent.requestID, "id": "9013", "guild_kind": 1,
                               "guild_id": "42", "version": "0", "status": 0, "name": "新频道"]])
            }
            return try envelope(["guild_kind": 1, "guild_id": "42", "groups": [], "ungrouped": []])
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await model.loadDirectory(); XCTAssertTrue(model.canCreate); try model.prepare(intent)
        await model.submitPrepared()
        XCTAssertEqual(forwarded, try intent.body()); XCTAssertEqual(try journal.restore(), intent)
        XCTAssertEqual(model.issue, .outcomeUnknown); XCTAssertFalse(model.canResendOriginal)
        await model.recoverOriginal()
        guard case .some(.applied(let result)) = model.outcome else { return XCTFail("Recover original APPLIED result") }
        XCTAssertEqual(result.id?.rawValue, "9013"); XCTAssertNil(try journal.restore()); XCTAssertNil(model.detail)
        XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testExplicitRetryQueriesAgainAndUsesByteIdenticalOriginal() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try createIntent(service.scope, requestID: "same-request-explicit-retry"); try journal.saveBeforeDispatch(intent)
        harness.transport.handler = { request in
            if request.url?.path.contains("/requests/") == true {
                return try envelope(["state": "NOT_FOUND", "request_id": intent.requestID])
            }
            if request.url?.path.hasSuffix("/channels/manage") == true { return try envelope([]) }
            XCTAssertEqual(request.httpBody, try intent.body())
            return try envelope(["state": "APPLIED", "request_id": intent.requestID, "id": "9013", "guild_kind": 1,
                                 "guild_id": "42", "version": "0", "status": 0, "name": "新频道"])
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await model.recoverOriginal(); await model.resendOriginal()
        XCTAssertEqual(harness.transport.requests.filter { $0.url?.path.contains("/requests/") == true }.count, 2)
        XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertNil(try journal.restore())
    }
    func testPermissionPreviewRejectsEscalationAndMetadataLeaseCannotGrantPermissionWrites() async throws {
        let harness = try Harness(); let channel = try fixtureChannel()
        let permissions = try JSONDecoder().decode(NativeChannelManagementPermissions.self, from: JSONSerialization.data(withJSONObject: [
            "channel_id": "9012", "version": "5", "perm_version": 8, "overrides": []]))
        let row = try NativeChannelManagementOverwrite(targetType: 1, targetID: "0", allowBits: "0x0", denyBits: "0x2", note: nil)
        let intent = try NativeChannelManagementIntent.overwrite(channel: channel, permissions: permissions, row: row, remove: false, reason: "review")
        do { _ = try await harness.service().execute(intent); XCTFail("Metadata command lease must not authorize permission writes") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .unavailable) }
        XCTAssertTrue(harness.transport.requests.isEmpty)
        XCTAssertThrowsError(try NativeChannelManagementOverwrite(targetType: 1, targetID: "0", allowBits: "0x400", denyBits: "0x0", note: nil))
        XCTAssertThrowsError(try NativeChannelManagementOverwrite(targetType: 1, targetID: "0", allowBits: "0x2", denyBits: "0x2", note: nil))
    }
    func testCanonicalWebhookAdapterRequiresIndependentUpstreamAndPreservesItsAuthorizationVersion() async throws {
        let harness = try Harness(); harness.transport.handler = { _ in
            try envelope(channelObject(names: ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"]))
        }
        let service = try harness.service()
        let closed = NativeChannelManagementWebhookScopeAdapter(channels: service, channelID: try .init("9012"))
        do { _ = try await closed.currentContext(); XCTFail("Channel fields cannot fill missing native/RBAC proof") }
        catch { guard let value = error as? NativeWebhookClientError, case .sourceUnavailable = value else { return XCTFail("Expected unavailable") } }
        let binding = try NativeWebhookBinding(accountID: "11", market: RegionalMarket.china.rawValue, namespace: "CN:test",
            origin: harness.api.baseURL, scope: .init(ownerID: NativeWebhookID(rawValue: "42")!, channelID: NativeWebhookID(rawValue: "9012")!),
            authorizationVersion: "fixture-upstream-authority-v9")
        let upstream = FixtureWebhookProvider(.init(binding: binding, eventCatalogue: .unavailable(code: "FIXTURE_NO_REGISTERED_EVENTS")))
        let adapter = NativeChannelManagementWebhookScopeAdapter(channels: service, channelID: try .init("9012"), upstream: upstream)
        let result = try await adapter.currentContext()
        XCTAssertEqual(result.binding, binding); XCTAssertEqual(result.binding.authorizationVersion, "fixture-upstream-authority-v9")
        XCTAssertEqual(result.eventCatalogue, .unavailable(code: "FIXTURE_NO_REGISTERED_EVENTS"))
        let revalidated = try await adapter.revalidate(binding); XCTAssertEqual(revalidated, result)
        harness.approval?.revoke()
        do { _ = try await adapter.currentContext(); XCTFail("Revoked channel lease must retire context") } catch { }
    }
    func testWebhookAdapterNeverPromotesViewPermissionOrAnEmptyCatalogue() async throws {
        let harness = try Harness(); harness.transport.handler = { _ in try envelope(channelObject(names: ["VIEW_CHANNEL"])) }
        let service = try harness.service()
        let binding = try NativeWebhookBinding(accountID: "11", market: RegionalMarket.china.rawValue, namespace: "CN:test",
            origin: harness.api.baseURL, scope: .init(ownerID: NativeWebhookID(rawValue: "42")!, channelID: NativeWebhookID(rawValue: "9012")!),
            authorizationVersion: "fixture-upstream-authority-v9")
        let upstream = FixtureWebhookProvider(.init(binding: binding, eventCatalogue: .available(revision: "fixture-catalogue-v1", options: [])))
        let noManagement = NativeChannelManagementWebhookScopeAdapter(channels: service, channelID: try .init("9012"), upstream: upstream)
        do { _ = try await noManagement.currentContext(); XCTFail("VIEW is not Webhook management") } catch { }
        XCTAssertEqual(upstream.calls, 0)
        harness.transport.handler = { _ in try envelope(channelObject(names: ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"])) }
        let emptyCatalogue = NativeChannelManagementWebhookScopeAdapter(channels: service, channelID: try .init("9012"), upstream: upstream)
        do { _ = try await emptyCatalogue.currentContext(); XCTFail("Empty available catalogue is not a complete source") } catch { }
    }
    func testOriginalResultVersionAndScopeMustMatchImmutableIntent() throws {
        let harness = try Harness(); let intent = try createIntent(harness.scope, requestID: "result-original-001")
        let wrong = try JSONDecoder().decode(NativeChannelManagementAppliedResult.self, from: JSONSerialization.data(withJSONObject: [
            "state": "APPLIED", "request_id": intent.requestID, "id": "9012", "guild_kind": 1, "guild_id": "43", "version": "0", "status": 0, "name": "新频道"]))
        XCTAssertThrowsError(try wrong.validate(for: intent))
        let correct = try JSONDecoder().decode(NativeChannelManagementAppliedResult.self, from: JSONSerialization.data(withJSONObject: [
            "state": "APPLIED", "request_id": intent.requestID, "id": "9012", "guild_kind": 1, "guild_id": "42", "version": "0", "status": 0, "name": "新频道"]))
        XCTAssertNoThrow(try correct.validate(for: intent))
    }
    func testSparseManagerInventoryRestoresWithoutInventingPermissionNames() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        harness.transport.handler = { request in
            if request.url?.path.hasSuffix("/channels/manage") == true { return try envelope([sparseRecoverableChannel()]) }
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/api/channels/9012/restore")
                let data = try XCTUnwrap(request.httpBody)
                let object = try JSONSerialization.jsonObject(with: data)
                let body = try XCTUnwrap(object as? [String: Any])
                XCTAssertEqual(body["expected_version"] as? String, "5")
                XCTAssertEqual(body["request_id"] as? String, "sparse-restore-original")
                return try envelope(restoredChannelResult("sparse-restore-original"))
            }
            return try envelope(["guild_kind": 1, "guild_id": "42", "groups": [], "ungrouped": []])
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await model.loadDirectory()
        let evidence = try XCTUnwrap(model.managementInventoryEvidence)
        let row = try XCTUnwrap(model.managementInventory.first)
        XCTAssertFalse(row.canManage); XCTAssertTrue(row.permissionNames.isEmpty)
        XCTAssertThrowsError(try NativeChannelManagementIntent.lifecycle(.restore, channel: row, reason: "恢复"), "Sparse row alone is not manager evidence")
        let intent = try NativeChannelManagementIntent.restore(channelID: row.id, inventory: evidence,
            reason: "恢复活动频道", requestID: "sparse-restore-original")
        try model.prepare(intent); await model.submitPrepared()
        guard case .some(.applied(let result)) = model.outcome else { return XCTFail("A real manager-inventory result must permit restore") }
        XCTAssertEqual(result.version?.value, 6); XCTAssertEqual(result.status, 1); XCTAssertNil(try journal.restore())
        XCTAssertTrue(row.permissionNames.isEmpty, "No permission is manufactured in the inventory DTO")
        XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertFalse(harness.transport.requests.contains { $0.url?.path == "/api/channels/9012" })
    }
    func testRestoreRequiresCurrentManagerEvidenceAndFreshServerAuthorization() async throws {
        let harness = try Harness(); let service = try harness.service()
        harness.transport.handler = { _ in try envelope([sparseRecoverableChannel()]) }
        let evidence = try await service.inventory()
        let intent = try NativeChannelManagementIntent.restore(channelID: .init("9012"), inventory: evidence, reason: "恢复")
        harness.transport.handler = { _ in (Data(#"{"code":403,"errorCode":"PERMISSION_DENIED"}"#.utf8), 403) }
        do { _ = try await service.execute(intent); XCTFail("An earlier inventory cannot replace a fresh server manager check") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .rejected("PERMISSION_DENIED")) }
        XCTAssertFalse(harness.transport.requests.contains { $0.httpMethod == "POST" })
        let storage = MemoryStorage(); let model = try NativeChannelManagementCoordinator(service: service,
            journal: NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage))
        XCTAssertThrowsError(try model.prepare(intent), "No inventory evidence was loaded by this coordinator")
        harness.approval?.revoke(); XCTAssertThrowsError(try model.prepare(intent)); XCTAssertFalse(model.managerInventoryConfirmed)
        let viewOnly = try Harness(operations: [.directory, .detail, .metadataCommand])
        do { _ = try await viewOnly.service().inventory(); XCTFail("A view endpoint lease is not inventory access") } catch { }
        XCTAssertTrue(viewOnly.transport.requests.isEmpty)
    }
    func testRestoreFreshInventoryVersionAndScopeConflictsCannotDispatch() async throws {
        let harness = try Harness(); let service = try harness.service()
        harness.transport.handler = { _ in try envelope([sparseRecoverableChannel()]) }
        let evidence = try await service.inventory()
        let intent = try NativeChannelManagementIntent.restore(channelID: .init("9012"), inventory: evidence, reason: "恢复")
        harness.transport.handler = { _ in try envelope([sparseRecoverableChannel(version: "6")]) }
        do { _ = try await service.execute(intent); XCTFail("Restore must retain the original metadata base version") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .versionConflict) }
        harness.transport.handler = { _ in
            var wrongScope = sparseRecoverableChannel(); wrongScope["guild_id"] = "43"; return try envelope([wrongScope])
        }
        do { _ = try await service.execute(intent); XCTFail("Inventory from a different guild cannot authorize restore") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .invalidSource) }
        XCTAssertFalse(harness.transport.requests.contains { $0.httpMethod == "POST" })
    }
    func testRestoreTimeoutResumesTheByteIdenticalOriginalAfterLookup() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        var forwarded: [Data] = []
        harness.transport.handler = { request in
            if request.url?.path.hasSuffix("/channels/manage") == true { return try envelope([sparseRecoverableChannel()]) }
            if request.httpMethod == "POST" {
                forwarded.append(try XCTUnwrap(request.httpBody))
                if forwarded.count == 1 { throw URLError(.timedOut) }
                return try envelope(restoredChannelResult("restore-timeout-original"))
            }
            if request.url?.path.contains("/requests/") == true { return try envelope(["state": "NOT_FOUND", "request_id": "restore-timeout-original"]) }
            return try envelope(["guild_kind": 1, "guild_id": "42", "groups": [], "ungrouped": []])
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal); await model.loadDirectory()
        let evidence = try XCTUnwrap(model.managementInventoryEvidence)
        let intent = try NativeChannelManagementIntent.restore(channelID: .init("9012"),
            inventory: evidence, reason: "恢复", requestID: "restore-timeout-original")
        try model.prepare(intent); await model.submitPrepared()
        XCTAssertEqual(try journal.restore(), intent); XCTAssertEqual(model.issue, .outcomeUnknown)
        await model.recoverOriginal(); await model.resendOriginal()
        XCTAssertEqual(forwarded, [try intent.body(), try intent.body()]); XCTAssertNil(try journal.restore())
        XCTAssertEqual(harness.transport.requests.filter { $0.url?.path.contains("/requests/") == true }.count, 2)
    }
    func testRestoreTimeoutCanRecoverTheOriginalAppliedResultWithoutAnotherWrite() async throws {
        let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        harness.transport.handler = { request in
            if request.url?.path.hasSuffix("/channels/manage") == true { return try envelope([sparseRecoverableChannel()]) }
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            if request.url?.path.contains("/requests/") == true {
                return try envelope(["state": "APPLIED", "request_id": "restore-applied-original", "outcome_known": true,
                    "result": restoredChannelResult("restore-applied-original")])
            }
            return try envelope(["guild_kind": 1, "guild_id": "42", "groups": [], "ungrouped": []])
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal); await model.loadDirectory()
        let evidence = try XCTUnwrap(model.managementInventoryEvidence)
        let intent = try NativeChannelManagementIntent.restore(channelID: .init("9012"),
            inventory: evidence, reason: "恢复", requestID: "restore-applied-original")
        try model.prepare(intent); await model.submitPrepared(); await model.recoverOriginal()
        guard case .some(.applied(let result)) = model.outcome else { return XCTFail("Read the original restore result") }
        XCTAssertEqual(result.requestID, intent.requestID); XCTAssertEqual(result.version?.value, 6)
        XCTAssertNil(try journal.restore()); XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testCurrentEmptyOrMalformedHTTP401RetiresProjectionAndPreservesOriginal() async throws {
        for body in [Data(), Data("<html>unauthorized</html>".utf8)] {
            let harness = try Harness(); let service = try harness.service(); let storage = MemoryStorage()
            let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
            let intent = try createIntent(service.scope); try journal.saveBeforeDispatch(intent)
            harness.transport.handler = { _ in try envelope(channelObject()) }
            let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
            model.restoreOriginal(); await model.loadDetail(try .init("9012")); XCTAssertNotNil(model.detail)
            harness.transport.handler = { _ in (body, 401) }
            await model.loadDirectory()
            XCTAssertEqual(harness.unauthorizedCalls, 1); XCTAssertFalse(service.isCurrent); XCTAssertTrue(model.retired)
            XCTAssertNil(model.directory); XCTAssertNil(model.detail); XCTAssertNil(model.pending)
            XCTAssertEqual(try journal.restore(), intent, "Body decoding must not lose an uncertain original")
            do { _ = try await service.directory(); XCTFail("Retired service cannot dispatch again") } catch { }
            XCTAssertEqual(harness.unauthorizedCalls, 1)
        }
    }
    func testEnvelope401StillRetiresButOtherMalformedStatusesDoNotExpireTheSession() async throws {
        let harness = try Harness(); let service = try harness.service()
        harness.transport.handler = { _ in (Data("not-json".utf8), 502) }
        do { _ = try await service.directory(); XCTFail("Bad gateway body is unknown") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .outcomeUnknown) }
        XCTAssertTrue(service.isCurrent); XCTAssertEqual(harness.unauthorizedCalls, 0)
        harness.transport.handler = { _ in (Data(#"{"code":400,"errorCode":"CHANNEL_NAME_INVALID"}"#.utf8), 400) }
        do { _ = try await service.directory(); XCTFail("Known business rejection remains a rejection") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .rejected("CHANNEL_NAME_INVALID")) }
        XCTAssertTrue(service.isCurrent); XCTAssertEqual(harness.unauthorizedCalls, 0)
        harness.transport.handler = { _ in (Data(#"{"code":401,"errorCode":"LOGIN_REQUIRED"}"#.utf8), 200) }
        do { _ = try await service.directory(); XCTFail("Envelope 401 must retire the current service") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .changedIdentity) }
        XCTAssertFalse(service.isCurrent); XCTAssertEqual(harness.unauthorizedCalls, 1)
    }
    func testLateOldEmptyHTTP401CannotExpireTheNewSession() async throws {
        let harness = try Harness(); let service = try harness.service()
        let newSession = try PlayExperienceSession(accountID: 12, epoch: 2, namespace: "CN:test", token: "new-test-token")
        let newContext = RuntimeDependencyContext(market: .china, baseURL: harness.api.baseURL, role: "player", session: newSession)
        harness.transport.handler = { _ in harness.live = newContext; return (Data(), 401) }
        do { _ = try await service.detail(.init("9012")); XCTFail("Old response must be dropped before unauthorized callback") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .changedIdentity) }
        XCTAssertEqual(harness.unauthorizedCalls, 0); XCTAssertEqual(harness.live, newContext)
    }
    func testOriginalWebhookAuthorityVersionChangeIsRevalidatedByTheOriginalProvider() async throws {
        let harness = try Harness(); harness.transport.handler = { _ in
            try envelope(channelObject(names: ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"]))
        }
        let service = try harness.service()
        let original = try NativeWebhookBinding(accountID: "11", market: RegionalMarket.china.rawValue, namespace: "CN:test",
            origin: harness.api.baseURL, scope: .init(ownerID: NativeWebhookID(rawValue: "42")!, channelID: NativeWebhookID(rawValue: "9012")!),
            authorizationVersion: "fixture-source-authority-v9")
        let upstream = FixtureWebhookProvider(.init(binding: original, eventCatalogue: .unavailable(code: "FIXTURE_NO_EVENTS")))
        let adapter = NativeChannelManagementWebhookScopeAdapter(channels: service, channelID: try .init("9012"), upstream: upstream)
        let first = try await adapter.currentContext(); XCTAssertEqual(first.binding, original)
        let changed = try NativeWebhookBinding(accountID: original.accountID, market: original.market, namespace: original.namespace,
            origin: original.origin, scope: original.scope, authorizationVersion: "fixture-source-authority-v10")
        upstream.context = .init(binding: changed, eventCatalogue: .unavailable(code: "FIXTURE_NO_EVENTS"))
        do { _ = try await adapter.revalidate(original); XCTFail("The original provider must reject its changed authority binding") }
        catch { guard let failure = error as? NativeWebhookClientError, case .scopeChanged = failure else { return XCTFail("Expected original scopeChanged") } }
        XCTAssertEqual(upstream.calls, 2); XCTAssertEqual(upstream.context.binding.authorizationVersion, changed.authorizationVersion)
    }
    func testPermissionCASV2BindsBothVersionsButLegacyOriginalBodyIsNotUpgraded() async throws {
        let intent = try permissionIntent()
        XCTAssertEqual(intent.schema, 2)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: intent.body()) as? [String: Any])
        XCTAssertEqual(body["expected_version"] as? String, "5")
        XCTAssertEqual(body["expected_perm_version"] as? String, "8")
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        raw["schema"] = 1
        let legacy = try JSONDecoder().decode(NativeChannelManagementIntent.self, from: JSONSerialization.data(withJSONObject: raw))
        let legacyBody = try legacy.body()
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyBody) as? [String: Any])
        XCTAssertNil(old["expected_version"]); XCTAssertNil(old["expected_perm_version"])
        let harness = try permissionHarness(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: try harness.owner(), scope: harness.scope, storage: storage)
        try journal.saveBeforeDispatch(legacy)
        let originalBytes = storage.values
        XCTAssertEqual(try journal.restore()?.body(), legacyBody)
        try journal.saveBeforeDispatch(legacy); XCTAssertEqual(storage.values, originalBytes)
        let model = try NativeChannelManagementCoordinator(service: harness.service(), journal: journal)
        model.restoreOriginal(); XCTAssertFalse(model.canResendOriginal)
        do { _ = try await harness.service().execute(legacy); XCTFail("Legacy permission bytes are lookup-only") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .permissionCASUnavailable) }
        XCTAssertTrue(harness.transport.requests.isEmpty)
        XCTAssertEqual(storage.values, originalBytes)
    }

    func testPermissionPutAndDeleteUseDedicatedLeaseAndExactOriginalCASBody() async throws {
        for remove in [false, true] {
            let harness = try permissionHarness(); let intent = try permissionIntent(remove: remove)
            harness.transport.handler = { request in
                if request.httpMethod == intent.method {
                    XCTAssertEqual(request.url?.path, "/" + intent.path)
                    XCTAssertEqual(request.httpBody, try intent.body())
                    return try envelope(permissionResult(intent))
                }
                return try permissionReadResponse(request)
            }
            let result = try await harness.service().execute(intent)
            XCTAssertEqual(result.version?.value, 6); XCTAssertEqual(result.permissionVersion?.value, 9)
            XCTAssertEqual(result.targetID, "0")
            XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == intent.method }.count, 1)
        }
    }

    func testPermissionCASStaleMetadataOrPermissionVersionNeverReachesMutation() async throws {
        for staleMetadata in [false, true] {
            let harness = try permissionHarness(); let intent = try permissionIntent()
            harness.transport.handler = { request in
                if request.url?.path.hasSuffix("/permissions") == true {
                    return try envelope(["channel_id": "9012", "version": staleMetadata ? "6" : "5",
                        "perm_version": staleMetadata ? 8 : 9, "overrides": []])
                }
                return try permissionReadResponse(request)
            }
            do { _ = try await harness.service().execute(intent); XCTFail("Both versions are fenced") }
            catch { XCTAssertEqual(error as? NativeChannelManagementError, .versionConflict) }
            XCTAssertFalse(harness.transport.requests.contains { $0.httpMethod == "PUT" })
        }
    }

    func testPermissionAppliedProofRejectsWrongTargetVersionsMasksAndAudit() throws {
        let intent = try permissionIntent()
        let mutations: [(String, Any)] = [("request_id", "another-original"), ("channel_id", "9013"),
            ("target_type", 2), ("target_id", "88"), ("version", "7"), ("perm_version", 8),
            ("allow_bits", "0x2"), ("deny_bits", "0x0"), ("inherited", true),
            ("note", "different"), ("audit_id", NSNull())]
        for (key, value) in mutations {
            var row = permissionResult(intent); row[key] = value
            let decoded = try JSONDecoder().decode(NativeChannelManagementAppliedResult.self,
                from: JSONSerialization.data(withJSONObject: row))
            XCTAssertThrowsError(try decoded.validate(for: intent), key)
        }
        let remove = try permissionIntent(remove: true)
        var row = permissionResult(remove); row["deleted"] = false
        let decoded = try JSONDecoder().decode(NativeChannelManagementAppliedResult.self,
            from: JSONSerialization.data(withJSONObject: row))
        XCTAssertThrowsError(try decoded.validate(for: remove))
    }

    func testPermissionEditorSubmitSettlesOnlyExactAppliedOriginal() async throws {
        let harness = try permissionHarness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try permissionIntent()
        harness.transport.handler = { request in
            if request.httpMethod == "PUT" {
                XCTAssertEqual(try journal.restore(), intent, "Persist before final forward")
                return try envelope(permissionResult(intent))
            }
            return try permissionReadResponse(request)
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await model.loadPermissions(try .init("9012")); try model.prepare(intent)
        XCTAssertTrue(model.canSubmitPrepared)
        await model.submitPrepared()
        guard case .some(.applied(let result)) = model.outcome else { return XCTFail("Expected actual command result") }
        XCTAssertEqual(result.requestID, intent.requestID); XCTAssertNil(try journal.restore())
        XCTAssertNil(model.pending); XCTAssertNil(model.permissions)
    }

    func testPermissionMalformedAppliedRetainsOriginalForRecovery() async throws {
        let harness = try permissionHarness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try permissionIntent()
        harness.transport.handler = { request in
            if request.httpMethod == "PUT" {
                var result = permissionResult(intent); result["perm_version"] = 10
                return try envelope(result)
            }
            return try permissionReadResponse(request)
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await model.loadPermissions(try .init("9012")); try model.prepare(intent); await model.submitPrepared()
        XCTAssertEqual(model.issue, .invalidSource); XCTAssertEqual(try journal.restore(), intent)
        XCTAssertEqual(model.pending, intent); XCTAssertNil(model.outcome)
    }

    func testPermissionTimeoutReopenedCoordinatorReadsOriginalWithoutSecondMutation() async throws {
        let harness = try permissionHarness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try permissionIntent()
        harness.transport.handler = { request in
            if request.httpMethod == "PUT" { throw URLError(.timedOut) }
            if request.url?.path.contains("/governance/requests/") == true {
                return try envelope(["state": "APPLIED", "request_id": intent.requestID,
                    "outcome_known": true, "result": permissionResult(intent)])
            }
            return try permissionReadResponse(request)
        }
        let first = try NativeChannelManagementCoordinator(service: service, journal: journal)
        await first.loadPermissions(try .init("9012")); try first.prepare(intent); await first.submitPrepared()
        XCTAssertEqual(try journal.restore(), intent)
        let reopened = try NativeChannelManagementCoordinator(service: harness.service(), journal:
            NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage))
        reopened.restoreOriginal(); await reopened.recoverOriginal()
        XCTAssertNil(try journal.restore()); XCTAssertNil(reopened.pending)
        XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "PUT" }.count, 1)
        // Recreating the coordinator verifies this source path, not disk/process persistence.
    }

    func testPermissionNotFoundRetryRequeriesAndReusesOriginalVersionsAndBody() async throws {
        let harness = try permissionHarness(); let service = try harness.service(); let storage = MemoryStorage()
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
        let intent = try permissionIntent(); try journal.saveBeforeDispatch(intent)
        harness.transport.handler = { request in
            if request.url?.path.contains("/governance/requests/") == true { return try envelope(["state": "NOT_FOUND"]) }
            if request.httpMethod == "PUT" {
                XCTAssertEqual(request.httpBody, try intent.body()); return try envelope(permissionResult(intent))
            }
            return try permissionReadResponse(request)
        }
        let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
        model.restoreOriginal(); await model.recoverOriginal()
        XCTAssertEqual(try journal.restore(), intent)
        XCTAssertFalse(harness.transport.requests.contains { $0.httpMethod == "PUT" })
        XCTAssertTrue(model.canResendOriginal); await model.resendOriginal()
        XCTAssertEqual(harness.transport.requests.filter { $0.url?.path.contains("/requests/") == true }.count, 2)
        XCTAssertEqual(harness.transport.requests.filter { $0.httpMethod == "PUT" }.count, 1)
        XCTAssertNil(try journal.restore())
    }

    func testPermissionRevocationDuringPreflightCannotForwardMutation() async throws {
        let harness = try permissionHarness(); let intent = try permissionIntent()
        harness.transport.handler = { request in
            let result = try permissionReadResponse(request); harness.approval?.revoke(); return result
        }
        do { _ = try await harness.service().execute(intent); XCTFail("Revoked permission lease must stop forward") }
        catch { XCTAssertEqual(error as? NativeChannelManagementError, .changedIdentity) }
        XCTAssertFalse(harness.transport.requests.contains { $0.httpMethod == "PUT" })
    }

    func testPermissionServerCASConflictClearsStaleEditorAndPreservesUncertainRetry() async throws {
        for retrying in [false, true] {
            let harness = try permissionHarness(); let service = try harness.service(); let storage = MemoryStorage()
            let journal = NativeChannelManagementJournal(owner: service.owner, scope: service.scope, storage: storage)
            let intent = try permissionIntent()
            harness.transport.handler = { request in
                if request.url?.path.contains("/requests/") == true { return try envelope(["state": "NOT_FOUND"]) }
                if request.httpMethod == "PUT" {
                    return (Data(#"{"code":409,"errorCode":"PERM_VERSION_CONFLICT","outcome_known":true}"#.utf8), 409)
                }
                return try permissionReadResponse(request)
            }
            let model = try NativeChannelManagementCoordinator(service: service, journal: journal)
            await model.loadPermissions(try .init("9012"))
            if retrying {
                try journal.saveBeforeDispatch(intent); model.restoreOriginal()
                await model.recoverOriginal(); await model.resendOriginal()
                XCTAssertEqual(try journal.restore(), intent, "Retry rejection does not settle earlier unknown outcome")
            } else {
                try model.prepare(intent); await model.submitPrepared(); XCTAssertNil(try journal.restore())
            }
            XCTAssertEqual(model.issue, .rejected("PERM_VERSION_CONFLICT"))
            XCTAssertNil(model.permissions); XCTAssertNil(model.detail); XCTAssertNil(model.prepared)
        }
    }

}

@MainActor private final class MemoryStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]; var dropWrites = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { if !dropWrites { values[key] = data } }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class FixtureTransport: NativeChannelManagementDispatching {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> (Data, Int) = { _ in throw NativeChannelManagementError.outcomeUnknown }
    func send(_ request: URLRequest, fence: NativeChannelManagementDispatchFence) async throws -> (Data, Int) {
        guard fence.isCurrent else { throw NativeChannelManagementError.changedIdentity }; requests.append(request); return try handler(request)
    }
}
@MainActor private final class FixtureWebhookProvider: NativeWebhookScopeProvider {
    var context: NativeWebhookContext
    var calls = 0
    init(_ context: NativeWebhookContext) { self.context = context }
    func currentContext() async throws -> NativeWebhookContext { calls += 1; return context }
    func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext {
        calls += 1; guard context.binding == binding else { throw NativeWebhookClientError.scopeChanged }; return context
    }
}
@MainActor private final class Harness {
    let api: APIConfiguration
    let context: RuntimeDependencyContext
    let scope: NativeChannelManagementScope
    var live: RuntimeDependencyContext?
    var approval: NativeChannelManagementApproval?
    var unauthorizedCalls = 0
    let transport = FixtureTransport()
    init(operations: Set<NativeChannelManagementAccess> = [.directory, .detail, .managementInventory, .metadataCommand, .metadataReceipt, .permissionsRead, .governanceReceipt]) throws {
        api = try .init(baseURL: URL(string: "https://example.com")!)
        let session = try PlayExperienceSession(accountID: 11, epoch: 1, namespace: "CN:test", token: "test-token")
        context = .init(market: .china, baseURL: api.baseURL, role: "player", session: session); live = context
        scope = try .init(guildKind: 1, guildID: .init("42"))
        approval = try .init(context: context, viewerRevision: 2, scope: scope,
            operations: operations, expiresAt: Date().addingTimeInterval(60))
    }
    func owner() throws -> NativeChannelManagementOwner { try .init(accountID: 11, namespace: "CN:test", baseURL: api.baseURL) }
    func service() throws -> NativeChannelManagementHTTPService {
        try .init(context: context, viewerRevision: 2, scope: scope, configuration: api, transport: transport,
            current: { self.live }, viewer: { 2 }, selectedApproval: { self.approval }, onUnauthorized: { _ in self.unauthorizedCalls += 1 })
    }
}
private func channelObject(names: [String] = ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_CHANNEL", "MANAGE_ROLE"],
                           isDefault: Bool = false, status: Int = 0, archiveReason: String? = nil) -> [String: Any] {
    ["id": "9012", "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1, "name": "活动频道",
     "topic": "原简介", "position": 0, "is_default": isDefault ? 1 : 0, "status": status,
     "version": "5", "perm_version": "8", "visibility": 1, "slowmode_sec": 30,
     "archive_reason": archiveReason as Any? ?? NSNull(), "my_permissions_list": names]
}
private func fixtureChannel(names: [String] = ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_CHANNEL", "MANAGE_ROLE"],
                            isDefault: Bool = false, status: Int = 0, archiveReason: String? = nil) throws -> NativeChannelManagementChannel {
    try JSONDecoder().decode(NativeChannelManagementChannel.self, from: JSONSerialization.data(withJSONObject:
        channelObject(names: names, isDefault: isDefault, status: status, archiveReason: archiveReason)))
}
private func createIntent(_ scope: NativeChannelManagementScope, requestID: String = "original-create-001") throws -> NativeChannelManagementIntent {
    var draft = NativeChannelManagementDraft(); draft.name = "新频道"
    return try .create(scope: scope, draft: draft, reason: "准备活动", requestID: requestID)
}
private func envelope(_ data: Any) throws -> (Data, Int) { (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200) }
private func sparseRecoverableChannel(version: String = "5") -> [String: Any] {
    ["id": "9012", "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1, "name": "待恢复频道",
     "position": 0, "is_default": 0, "status": 3, "version": version, "recoverable": true, "purge_at": "2030-01-01T00:00:00Z"]
}
private func restoredChannelResult(_ requestID: String) -> [String: Any] {
    ["id": "9012", "guild_kind": 1, "guild_id": "42", "version": "6", "name": "待恢复频道", "status": 1,
     "state": "APPLIED", "request_id": requestID, "replayed": false]
}

@MainActor private func permissionHarness() throws -> Harness {
    try Harness(operations: [.detail, .permissionsRead, .permissionCommand, .governanceReceipt])
}
private func permissionIntent(remove: Bool = false) throws -> NativeChannelManagementIntent {
    let permissions = try JSONDecoder().decode(NativeChannelManagementPermissions.self, from:
        JSONSerialization.data(withJSONObject: ["channel_id": "9012", "version": "5", "perm_version": 8, "overrides": []]))
    return try .overwrite(channel: fixtureChannel(), permissions: permissions,
        row: .init(targetType: 1, targetID: "0", allowBits: "0x0", denyBits: "0x2", note: "review note"),
        remove: remove, reason: "permission review", requestID: remove ? "permission-delete-001" : "permission-put-001")
}
private func permissionResult(_ intent: NativeChannelManagementIntent) -> [String: Any] {
    var row: [String: Any] = ["request_id": intent.requestID, "state": "APPLIED", "channel_id": "9012",
        "target_type": 1, "target_id": "0", "version": "6", "perm_version": 9, "audit_id": "120", "replayed": false]
    if intent.operation == .deleteOverwrite { row["deleted"] = true; row["inherited"] = true }
    else { row["allow_bits"] = "0x0"; row["deny_bits"] = "0x2"; row["note"] = "review note"; row["inherited"] = false }
    return row
}
private func permissionReadResponse(_ request: URLRequest) throws -> (Data, Int) {
    guard request.httpMethod == "GET" else { throw NativeChannelManagementError.invalidSource }
    if request.url?.path.hasSuffix("/permissions") == true {
        return try envelope(["channel_id": "9012", "version": "5", "perm_version": 8, "overrides": []])
    }
    if request.url?.path == "/api/im/roles" { return try envelope(["list": [], "has_more": false]) }
    if request.url?.path.contains("/effective/") == true {
        return try envelope(["channel_id": "9012", "member_id": "11", "permissions": "0xc21",
            "permissions_list": ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_CHANNEL", "MANAGE_ROLE"], "version": "5"])
    }
    return try envelope(channelObject())
}
