import XCTest
@testable import Questify

@MainActor final class NativeChannelAppealCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/")!
    private func deployment(_ store: NativeChannelAppealPolicyStore? = nil) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.channel.appeal", realm: "synthetic", nativeChannelAppeals: store)
    }
    private func makeContext(_ deployment: ReviewedAppDeployment) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "player", session: try .init(accountID: 17, epoch: 3,
            namespace: deployment.storageScope.service, token: "synthetic-only"))
    }
    private var notice: NativeChannelGovernanceNotice {
        .init(messageID: 1, conversationID: 2, recipientID: 17, actionID: "51", guildKind: 1, guildID: "42")
    }
    private func makePolicy(_ context: RuntimeDependencyContext) throws -> NativeChannelAppealPolicyStore {
        NativeChannelAppealPolicyStore(try .init(baseURL: base, namespace: context.session.namespace,
            rights: [.moderationRead, .appealRead, .submit, .evidence, .withdraw, .originalReceipt]))
    }
    func testNormalReviewedCompositionFactorySubmitsWithUnpredictedUUID() async throws {
        let seed = try deployment(), context = try makeContext(seed), policies = try makePolicy(context), reviewed = try deployment(policies)
        let wire = CACompositionWire(), journal = CACompositionStore(), locators = CACompositionStore()
        let root = AppCompositionRoot(deployment: .reviewed(reviewed), makeTransport: { wire })
        let flow = try XCTUnwrap(root.makeNativeChannelAppealFlow(notice: notice, context: context, storage: journal,
            locatorStorage: locators, current: { true }, unauthorized: {}))
        await flow.activate(); XCTAssertTrue(flow.prepare(.submit, text: "appeal")); await flow.confirm()
        XCTAssertEqual(flow.state, .applied); XCTAssertEqual(wire.posts.count, 1); XCTAssertTrue(journal.rows.isEmpty)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(wire.posts.first?.httpBody)) as? [String: Any])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(body["submit_request_id"] as? String)))
        XCTAssertEqual(flow.appealDetails?.reason, "current, not receipt")
    }
    func testNoDeploymentCannotUseEvenAnOtherwiseValidPolicy() throws {
        let d = try deployment(), context = try makeContext(d), wire = CACompositionWire(), store = CACompositionStore()
        let root = AppCompositionRoot(deployment: .unconfigured, makeTransport: { wire })
        XCTAssertNil(root.makeNativeChannelAppealFlow(notice: notice, context: context, storage: store,
            locatorStorage: store, current: { true }, unauthorized: {})); XCTAssertTrue(wire.posts.isEmpty)
    }
    func testReviewedEndpointWithoutIndependentAppealPolicyDoesNotEnableJourney() throws {
        let d = try deployment(), context = try makeContext(d), wire = CACompositionWire(), store = CACompositionStore()
        let root = AppCompositionRoot(deployment: .reviewed(d), makeTransport: { wire })
        XCTAssertNil(root.makeNativeChannelAppealFlow(notice: notice, context: context, storage: store,
            locatorStorage: store, current: { true }, unauthorized: {})); XCTAssertTrue(wire.posts.isEmpty)
    }
    func testCompositionRejectsMismatchedRealmAndAccount() throws {
        let seed = try deployment(), context = try makeContext(seed), policies = try makePolicy(context), d = try deployment(policies)
        let wire = CACompositionWire(), store = CACompositionStore(), root = AppCompositionRoot(deployment: .reviewed(d), makeTransport: { wire })
        let wrong = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 17, epoch: 3, namespace: "other-realm", token: "synthetic-only"))
        XCTAssertNil(root.makeNativeChannelAppealFlow(notice: notice, context: wrong, storage: store, locatorStorage: store, current: { true }, unauthorized: {}))
        let wrongNotice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: 18, actionID: "51", guildKind: 1, guildID: "42")
        XCTAssertNil(root.makeNativeChannelAppealFlow(notice: wrongNotice, context: context, storage: store, locatorStorage: store, current: { true }, unauthorized: {}))
    }
    func testCompositionPolicyRevokedAfterPersistenceStopsFirstPost() async throws {
        let seed = try deployment(), context = try makeContext(seed), policies = try makePolicy(context), d = try deployment(policies)
        let wire = CACompositionWire(), journal = CACompositionStore(), locator = CACompositionStore()
        let root = AppCompositionRoot(deployment: .reviewed(d), makeTransport: { wire })
        let flow = try XCTUnwrap(root.makeNativeChannelAppealFlow(notice: notice, context: context, storage: journal,
            locatorStorage: locator, current: { true }, unauthorized: {}))
        await flow.activate(); XCTAssertTrue(flow.prepare(.submit, text: "original"))
        journal.afterWrite = { policies.replace(with: nil) }; await flow.confirm()
        XCTAssertTrue(flow.hasPending); XCTAssertFalse(journal.rows.isEmpty); XCTAssertTrue(wire.posts.isEmpty)
    }
}

@MainActor private final class CACompositionStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var afterWrite: (() -> Void)?
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data; afterWrite?() }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class CACompositionWire: HTTPTransport {
    var posts: [URLRequest] = []
    func detail() -> [String: Any] {
        ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": "PENDING", "can_add_evidence": 1,
         "reason_text": "current, not receipt", "evidence_json": NSNull(), "supplements": [], "timeline": []]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = try XCTUnwrap(request.url).path; let result: [String: Any]
        if request.httpMethod == "POST" {
            posts.append(request); let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            var row = detail(); row["request_id"] = body["submit_request_id"]; row["state"] = "APPLIED"; row["reason_text"] = "receipt"
            result = row
        } else if path == "/api/im/moderation/me" {
            var row: [String: Any] = ["action_id": "51", "guild_kind": 1, "guild_id": "42", "target_member_id": "17", "appealable": posts.isEmpty ? 1 : 0]
            if !posts.isEmpty { row["existing_appeal_id"] = "61" }; result = ["list": [row]]
        } else if path == "/api/im/appeals/61" { result = detail() }
        else { XCTFail("Unexpected route \(path)"); throw APIError.invalidRequest }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": result]), 200)
    }
}


// Exercise the app's compiled feature table, not copied test-only translations.
@MainActor final class NativeChannelAppealEntryLocalizationTests: XCTestCase {
    private func text(_ key: String, _ language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "MISSING:" + key, table: "NativeChannelAppealDetails")
    }
    private let allKeys: [String] = [
        "facts",
        "reason",
        "submittedAt",
        "decidedAt",
        "withdrawnAt",
        "dueAt",
        "slaDueAt",
        "materials",
        "evidenceCount",
        "supplement",
        "originalEvidence",
        "unsupportedEvidence",
        "evidenceUnavailable",
        "noTextEvidence",
        "timeline",
        "eventAt",
        "timelineUnavailable",
        "noTimeline",
        "unknown",
        "messageReferences",
        "attachmentReferences",
        "attachmentsNotOpened",
        "recovery.pending",
        "recovery.requestID",
        "input.limit",
        "input.required",
        "input.tooLong",
        "progress.reading",
        "progress.submitting",
        "refresh.readOnly",
        "result.confirmed",
        "source.unavailable",
        "locator.unavailable",
        "status.PENDING",
        "status.REVIEWING",
        "status.UPHELD",
        "status.REVERSED",
        "status.WITHDRAWN",
        "status.closed",
        "channel.actionFacts.type",
        "channel.actionFacts.status",
        "channel.actionFacts.reasonCode",
        "channel.actionFacts.scopeType",
        "channel.actionFacts.scopeID",
        "channel.actionFacts.startsAt",
        "channel.actionFacts.expiresAt",
        "channel.actionFacts.durationSeconds",
        "channel.actionFacts.noTrustedCountdown",
        "channel.actionFacts.unavailable",
        "channel.actionFacts.title",
        "channel.actionFacts.unknown",
        "recovery.journalUnavailable",
        "recovery.explanation",
        "recovery.readOriginal",
        "recovery.reviewRetry",
        "recovery.title",
        "review.confirm",
        "action.cancel",
        "review.title",
        "input.placeholder",
        "input.explanation",
        "action.submit",
        "action.evidence",
        "action.withdraw",
        "input.title",
        "refresh.action",
        "session.unavailable",
        "entry.title",
        "retry.confirmation",
        "retry.confirm",
        "progress.serverStatus",
        "progress.actionID",
        "progress.deadline",
        "result.currentSeparate",
        "progress.currentReadFailed",
        "result.acceptedNotReversed",
        "progress.title",
        "operation.submit",
        "operation.evidence",
        "operation.withdraw",
        "operation.original",
        "status.unknown",
    ]
    private let newCopy: [(String, String, String)] = [
        ("recovery.journalUnavailable", "原请求记录暂不可用。请刷新重读；不会创建新的申诉或自动重发。", "The original request record is temporarily unavailable. Refresh to read it again; this will not create another appeal or resend automatically."),
        ("recovery.explanation", "结果尚待原回执确认，不创建另一条申诉。", "The outcome still needs confirmation from the original receipt. No new appeal will be created."),
        ("recovery.readOriginal", "回读原结果", "Check original result"),
        ("recovery.reviewRetry", "核对后重试原请求", "Review before retrying original request"),
        ("recovery.title", "原请求恢复", "Recover original request"),
        ("review.confirm", "确认提交", "Confirm submission"),
        ("action.cancel", "取消", "Cancel"),
        ("review.title", "确认原操作", "Confirm original action"),
        ("input.placeholder", "误判原因、补充说明或撤回原因", "Reason for appeal, additional statement, or reason for withdrawal"),
        ("input.explanation", "最多 500 个字符；补充说明不会另行上传媒体。", "Maximum 500 characters. Additional statements do not upload media."),
        ("action.submit", "我认为这是误判，申诉", "Appeal this moderation decision"),
        ("action.evidence", "追加一次说明", "Add one additional statement"),
        ("action.withdraw", "撤回申诉", "Withdraw appeal"),
        ("input.title", "说明", "Statement"),
        ("refresh.action", "刷新原处置和申诉进度", "Refresh original action and appeal progress"),
        ("session.unavailable", "当前会话或权限已失效，原待定请求仍保留。", "The current session or access is no longer valid. The original pending request is still saved."),
        ("entry.title", "频道处置申诉", "Channel moderation appeal"),
        ("retry.confirmation", "请先查看原结果；仅在原请求未被收到时，才以相同内容重试。", "Check the original result first. Only retry with the same content if the original request wasn't received."),
        ("retry.confirm", "核对并重试原请求", "Check and retry original request"),
        ("progress.serverStatus", "服务端原状态", "Original status"),
        ("progress.actionID", "处置编号", "Action ID"),
        ("progress.deadline", "原申诉截止", "Original appeal deadline"),
        ("result.currentSeparate", "原请求执行结果已确认；当前申诉状态另行读取，不以历史回执开放新的追加或撤回。", "The original request outcome is confirmed. Current appeal status is read separately; a past receipt does not enable a new statement or withdrawal."),
        ("progress.currentReadFailed", "暂未获取当前申诉进度，请刷新重试；不会重复提交申诉。", "We couldn't load your current appeal progress. Refresh to try again; your appeal won't be submitted twice."),
        ("result.acceptedNotReversed", "提交回执只表示申诉已受理，不代表撤销原处置。", "A submission receipt only confirms that the appeal was accepted for processing. It does not mean the original action was reversed."),
        ("progress.title", "原处置与申诉进度", "Original action and appeal progress"),
        ("operation.submit", "提交误判申诉", "Submit an appeal"),
        ("operation.evidence", "追加说明", "Add a statement"),
        ("operation.withdraw", "撤回原申诉", "Withdraw original appeal"),
        ("operation.original", "原操作", "Original action"),
        ("status.unknown", "申诉状态暂不可确认", "Appeal status cannot currently be confirmed"),
    ]
    func testEveryAppealKeyIsPackagedForChineseAndEnglish() throws {
        for language in ["zh-Hans", "en"] {
            for key in allKeys {
                let result = try text(key, language)
                XCTAssertFalse(result.isEmpty, key)
                XCTAssertNotEqual(result, key, language + ":" + key)
                XCTAssertFalse(result.hasPrefix("MISSING:"), language + ":" + key)
            }
        }
    }
    func testNewControlsAndSafetyMessagesResolveExactReviewedCopy() throws {
        for (key, chinese, english) in newCopy {
            XCTAssertEqual(try text(key, "zh-Hans"), chinese, key)
            XCTAssertEqual(try text(key, "en"), english, key)
        }
    }
    func testReviewOperationKeysKeepOriginalWireValues() throws {
        let rows: [(NativeChannelAppealFlow.Operation?, String, String, String)] = [
            (.submit, "operation.submit", "提交误判申诉", "Submit an appeal"),
            (.evidence, "operation.evidence", "追加说明", "Add a statement"),
            (.withdraw, "operation.withdraw", "撤回原申诉", "Withdraw original appeal"),
            (nil, "operation.original", "原操作", "Original action")
        ]
        for (operation, key, chinese, english) in rows {
            XCTAssertEqual(NativeChannelAppealPresentation.operationTitleKey(operation), key)
            XCTAssertEqual(try text(key, "zh-Hans"), chinese)
            XCTAssertEqual(try text(key, "en"), english)
        }
        XCTAssertEqual(NativeChannelAppealFlow.Operation.submit.rawValue, "submit")
        XCTAssertEqual(NativeChannelAppealFlow.Operation.evidence.rawValue, "evidence")
        XCTAssertEqual(NativeChannelAppealFlow.Operation.withdraw.rawValue, "withdraw")
    }
    func testKnownCurrentStatusesUseDedicatedLocalizedTitles() throws {
        let rows = [
            ("PENDING", "申诉待处理", "Appeal pending"),
            ("REVIEWING", "申诉处理中", "Appeal under review"),
            ("UPHELD", "维持原处置", "Original action upheld"),
            ("REVERSED", "原处置已撤销", "Original action reversed"),
            ("WITHDRAWN", "申诉已撤回", "Appeal withdrawn")
        ]
        for (status, chinese, english) in rows {
            let key = NativeChannelAppealPresentation.statusTitleKey(status)
            XCTAssertEqual(key, "status." + status)
            XCTAssertEqual(try text(key, "zh-Hans"), chinese)
            XCTAssertEqual(try text(key, "en"), english)
        }
    }
    func testUnrecognizedStatusNeverBecomesAnUntranslatedKeyOrSuccess() throws {
        for status in ["", "pending", "FUTURE_STATUS", "status.REVERSED", "%@", "未知"] {
            let key = NativeChannelAppealPresentation.statusTitleKey(status)
            XCTAssertEqual(key, "status.unknown")
            XCTAssertEqual(try text(key, "en"), "Appeal status cannot currently be confirmed")
            XCTAssertEqual(try text(key, "zh-Hans"), "申诉状态暂不可确认")
        }
    }
    func testLanguageSwitchResolvesTheOriginalRequestLabelWithoutCaching() throws {
        for (language, expected) in [("en", "Original request ID"), ("zh-Hans", "原请求编号"), ("en", "Original request ID")] {
            XCTAssertEqual(try text("recovery.requestID", language), expected)
        }
    }
    func testRealFlowRetains500UTF16BoundaryAndOriginalTextInEitherLanguage() async throws {
        for language in ["en", "zh-Hans"] {
            let base = URL(string: "https://example.test/")!
            let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
                session: try .init(accountID: 17, epoch: 3, namespace: "test.appeal.localization." + language, token: "synthetic-only"))
            let policies = NativeChannelAppealPolicyStore(try .init(baseURL: base, namespace: context.session.namespace,
                rights: [.moderationRead, .appealRead, .submit, .evidence, .withdraw, .originalReceipt]))
            let wire = CACompositionWire(), journal = CACompositionStore(), locator = CACompositionStore()
            let notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: 17, actionID: "51", guildKind: 1, guildID: "42")
            let flow = try XCTUnwrap(NativeChannelAppealRuntime.makeFlow(notice: notice, context: context, policyStore: policies,
                underlying: wire, storage: journal, locatorStorage: locator, current: { true }, unauthorized: {}))
            await flow.activate()
            XCTAssertFalse(flow.prepare(.submit, text: String(repeating: "a", count: 501)))
            let original = String(repeating: "🙂", count: 250)
            XCTAssertFalse(flow.prepare(.submit, text: original + "x"))
            XCTAssertTrue(flow.prepare(.submit, text: original))
            XCTAssertEqual(try text(NativeChannelAppealPresentation.operationTitleKey(flow.reviewedOperation), language),
                language == "en" ? "Submit an appeal" : "提交误判申诉")
            XCTAssertEqual(flow.reviewedText, original)
            XCTAssertTrue(wire.posts.isEmpty)
            XCTAssertTrue(journal.rows.isEmpty)
            await flow.confirm()
            XCTAssertEqual(wire.posts.count, 1)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(wire.posts.first?.httpBody)) as? [String: Any])
            XCTAssertEqual(body["reason_text"] as? String, original)
            XCTAssertEqual((body["reason_text"] as? String)?.utf16.count, 500)
            XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(body["submit_request_id"] as? String)))
            XCTAssertEqual(flow.state, .applied)
        }
    }
}
