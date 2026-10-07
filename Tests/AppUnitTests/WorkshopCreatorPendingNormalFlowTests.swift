#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class WorkshopCreatorPendingNormalFlowTests: XCTestCase {
    typealias Harness = WorkshopCreatorPendingFixtureHarness
    func controller(_ h: Harness) throws -> WorkshopCreatorPendingController { try XCTUnwrap(h.session.makeWorkshopCreatorPendingController(sourceTemplateId: 901)) }
    func load(_ h: Harness, _ a: WorkshopCreatorPendingAppearance) async throws -> WorkshopCreatorPendingController {
        let c = try controller(h); await (try XCTUnwrap(c.appear(a)))(); return c
    }
    func testDefaultNormalLoginHasNoNewRouteAuthority() async throws {
        let h = Harness(); defer { h.clean() }; await h.login()
        XCTAssertNil(h.session.makeWorkshopCreatorPendingController(sourceTemplateId: 901)); XCTAssertTrue(h.wire.requests.allSatisfy { $0.url?.path.contains("/creator/") != true })
    }
    func testSeparateMissingListDetailAndAuthorGrantsNeverBorrowConsentGrant() async throws {
        for missing in 0..<3 {
            let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(authoring: missing != 0, listing: missing != 1, detailing: missing != 2)
            if missing == 0 { let c = try await load(h, .init()); h.fill(c); XCTAssertFalse(c.canSubmit); XCTAssertTrue(h.wire.authorBodies.isEmpty) }
            else { let c = try await load(h, .init()); XCTAssertNil(c.preview); XCTAssertTrue(c.items.isEmpty); XCTAssertTrue(h.wire.requests.allSatisfy { $0.url?.path.contains("/creator/") != true }) }
        }
    }
    func testOwnedSourceAuthorListDetailAndExplicitDeclarationNormalComposition() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let a = WorkshopCreatorPendingAppearance(), c = try await load(h, a); h.fill(c)
        let action = try XCTUnwrap(c.offerAuthor(a)); XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertNotNil(c.pending); await action()
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertEqual(c.items.count, 1); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
        await (try XCTUnwrap(c.offerReview(try XCTUnwrap(c.items.first), a)))(); let consent = try XCTUnwrap(c.declaration), review = WorkshopCreatorConsentAppearance()
        await (try XCTUnwrap(consent.appear(review)))(); consent.select(try XCTUnwrap(consent.targets.first), appearance: review)
        XCTAssertTrue(consent.acknowledgments.isEmpty); for i in 0..<3 { consent.acknowledge(i, value: true, appearance: review) }
        await (try XCTUnwrap(consent.offerConfirm(review)))(); XCTAssertEqual(consent.phase, .recorded); XCTAssertEqual(h.wire.declarationBodies.count, 1)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: h.wire.authorBodies[0]) as? [String: Any])?.count, 21)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: h.wire.declarationBodies[0]) as? [String: Any])?.count, 13)
    }
    func testUnknownAuthorOutcomeReopenRetriesByteIdenticalWithoutAuthorStatus() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let old = WorkshopCreatorPendingAppearance(), c = try await load(h, old); h.fill(c); h.wire.loseAuthorResponse = true
        await (try XCTUnwrap(c.offerAuthor(old)))(); c.close(old); let fresh = WorkshopCreatorPendingAppearance(); await (try XCTUnwrap(c.appear(fresh)))()
        h.wire.loseAuthorResponse = false; await (try XCTUnwrap(c.offerRetry(fresh)))()
        XCTAssertEqual(h.wire.authorBodies.count, 2); XCTAssertEqual(h.wire.authorBodies[0], h.wire.authorBodies[1]); XCTAssertNotNil(c.receipt)
        XCTAssertFalse(h.wire.requests.contains { $0.url?.path == "/native/api/workshop/creator/pending-packages/status" }); XCTAssertTrue(h.wire.declarationBodies.isEmpty)
    }
    func testHistoricalRetryAfterSourceRevocationDoesNotBecomeCurrentTarget() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let a = WorkshopCreatorPendingAppearance(), c = try await load(h, a); h.fill(c); h.wire.loseAuthorResponse = true
        await (try XCTUnwrap(c.offerAuthor(a)))(); h.wire.loseAuthorResponse = false; h.wire.rejectSource = true
        await (try XCTUnwrap(c.offerRetry(a)))(); XCTAssertNotNil(c.receipt); XCTAssertTrue(c.items.isEmpty); XCTAssertNil(c.preview); XCTAssertNil(c.declaration)
    }
    func testConfigurationABAInvalidatesQueuedAuthorAndLate401() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let a = WorkshopCreatorPendingAppearance(), c = try controller(h); h.wire.delay = true
        let action = try XCTUnwrap(c.appear(a)), task = Task { await action() }
        for _ in 0..<1000 { if h.wire.suspended != nil { break }; await Task.yield() }; XCTAssertNotNil(h.wire.suspended)
        let old = h.list; h.session.withWorkshopCreatorConsentConfigurationChange { h.list = nil; XCTAssertNil(h.session.makeWorkshopCreatorPendingController(sourceTemplateId: 901)) }
        h.session.withWorkshopCreatorConsentConfigurationChange { h.list = old }; let replacement = try controller(h)
        h.wire.resume401(); await task.value; XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(c.phase, .invalidated); XCTAssertEqual(replacement.phase, .idle)
    }
    func testCurrentRoleChangeRejectsOldQueuedAuthorAndRestoresBlankPresentation() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let a = WorkshopCreatorPendingAppearance(), c = try await load(h, a); h.fill(c); let action = try XCTUnwrap(c.offerAuthor(a))
        h.wire.role = "merchant"; await h.session.refreshOwnAccount(); await action(); XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertEqual(c.phase, .invalidated)
    }
    func testHostedBackAndFreshSelectionCannotReviveOldAuthorAction() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let c = try controller(h), a = WorkshopCreatorPendingAppearance()
        let root = UIViewController(), navigation = UINavigationController(rootViewController: root), window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; window.makeKeyAndVisible(); defer { window.isHidden = true }
        let host = UIHostingController(rootView: WorkshopCreatorPendingView(controller: c, appearance: a)); navigation.pushViewController(host, animated: false)
        try await waitUntil { c.phase == .editing }; h.fill(c); let old = try XCTUnwrap(c.offerAuthor(a)); navigation.popViewController(animated: false)
        try await waitUntil { c.phase == .idle }; let fresh = WorkshopCreatorPendingAppearance(); await (try XCTUnwrap(c.appear(fresh)))(); await old()
        XCTAssertTrue(h.wire.authorBodies.isEmpty); XCTAssertNotNil(c.pending); XCTAssertNil(c.appear(a))
    }
    func testHostedAuthorToReviewTransitionKeepsTheSameAppearanceLive() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); let c = try controller(h), a = WorkshopCreatorPendingAppearance()
        let root = UIViewController(), navigation = UINavigationController(rootViewController: root), window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation; window.makeKeyAndVisible(); defer { window.isHidden = true }
        let host = UIHostingController(rootView: WorkshopCreatorPendingView(controller: c, appearance: a)); navigation.pushViewController(host, animated: false)
        try await waitUntil { c.phase == .editing }; h.fill(c); await (try XCTUnwrap(c.offerAuthor(a)))()
        await (try XCTUnwrap(c.offerReview(try XCTUnwrap(c.items.first), a)))()
        try await waitUntil { c.phase == .reviewing && c.declaration?.phase == .reviewing }
        let consent = try XCTUnwrap(c.declaration); XCTAssertNotNil(consent.preview); XCTAssertTrue(consent.acknowledgments.isEmpty)
        await (try XCTUnwrap(c.offerBackToProposals(a)))(); try await waitUntil { c.phase == .editing }
        XCTAssertEqual(consent.phase, .invalidated); XCTAssertNotNil(c.preview)
        navigation.popViewController(animated: false); try await waitUntil { c.phase == .idle }; XCTAssertNil(c.appear(a))
    }
    private func recordDeclaration(_ h: Harness) async throws -> WorkshopCreatorPendingController {
        let a = WorkshopCreatorPendingAppearance(), c = try await load(h, a); h.fill(c); await (try XCTUnwrap(c.offerAuthor(a)))()
        await (try XCTUnwrap(c.offerReview(try XCTUnwrap(c.items.first), a)))(); let consent = try XCTUnwrap(c.declaration), review = WorkshopCreatorConsentAppearance()
        await (try XCTUnwrap(consent.appear(review)))(); consent.select(try XCTUnwrap(consent.targets.first), appearance: review)
        for i in 0..<3 { consent.acknowledge(i, value: true, appearance: review) }; await (try XCTUnwrap(consent.offerConfirm(review)))()
        XCTAssertEqual(consent.phase, .recorded); c.close(a); return c
    }
    func testReopenRecoversDeclarationWithOnlyConsentReadAndNoCurrentTarget() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); _ = try await recordDeclaration(h)
        try h.approve(authoring: false, listing: false, detailing: false, declaring: false); h.wire.rejectSource = true
        let count = h.wire.requests.count, c = try await load(h, .init())
        XCTAssertNotNil(c.declarationReceipt); XCTAssertNil(c.preview); XCTAssertNil(c.declaration); XCTAssertTrue(c.items.isEmpty)
        XCTAssertEqual(h.wire.requests.dropFirst(count).compactMap { $0.url?.lastPathComponent }, ["status"])
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertEqual(h.wire.declarationBodies.count, 1); XCTAssertFalse(c.canSubmit)
    }
    func testHistoricalDeclarationSurvivesRevokedSourcePreviewFailureOnReopen() async throws {
        let h = Harness(); defer { h.clean() }; await h.login(); try h.approve(); _ = try await recordDeclaration(h); h.wire.rejectSource = true
        let count = h.wire.requests.count, c = try await load(h, .init())
        XCTAssertNotNil(c.declarationReceipt); XCTAssertNil(c.preview); XCTAssertNil(c.declaration); XCTAssertEqual(c.phase, .failed)
        XCTAssertEqual(h.wire.requests.dropFirst(count).compactMap { $0.url?.lastPathComponent }, ["status", "preview"])
        XCTAssertEqual(h.wire.authorBodies.count, 1); XCTAssertEqual(h.wire.declarationBodies.count, 1)
    }
    func testEveryCreatorLabelUsesItsNamedCatalogAndSelectedLanguage() {
        let cases: [(String, String, String)] = [
            ("workshopCreator.another", "Finish this review and review another version", "完成本次核对，审阅另一版本"),
            ("workshopCreator.boundary", "Record explicit consent for your original text package, pending package review. Existing purchases keep their original terms.", "仅为本人原创文字包记录明确同意，等待包审核。现有购买条款保持原样。"),
            ("workshopCreator.changed", "Your account, permission, or presentation changed. Go back and open this page again.", "账号、权限或页面已变化，请返回后重新进入。"),
            ("workshopCreator.checkStatus", "Check the previous declaration", "核对此前声明结果"),
            ("workshopCreator.confirm.0", "I reviewed this version’s exact text, exclusions, and complete terms", "我已核对本版本全部原文、未包含资料和完整条款"),
            ("workshopCreator.confirm.1", "I explicitly allow buyers to use it in their own public themes within the displayed terms", "我明确允许买家在所展示条款范围内用于自己的公开主题"),
            ("workshopCreator.confirm.2", "This excludes resale or redistribution of the original package and does not expand past purchases", "此授权不含转售或再分发原包，不扩大旧购买授权"),
            ("workshopCreator.declare", "Confirm and record this declaration", "确认并记录本次声明"),
            ("workshopCreator.exactSource", "Exact text for this version", "本版本原文"),
            ("workshopCreator.failed", "The original text source or declaration could not be verified. Refresh to try again.", "无法核对该原创文字源或声明记录。请刷新后重试。"),
            ("workshopCreator.field.answerReveal", "Answer reveal", "答案揭示"),
            ("workshopCreator.field.description", "Description", "简介"),
            ("workshopCreator.field.hint1", "Hint 1", "提示一"),
            ("workshopCreator.field.hint2", "Hint 2", "提示二"),
            ("workshopCreator.field.merchantGuide", "Merchant guide", "商家指引原文"),
            ("workshopCreator.field.questionAnswer", "Answer", "答案原文"),
            ("workshopCreator.field.questionName", "Question", "问题原文"),
            ("workshopCreator.field.ruleInstructions", "Rules", "规则原文"),
            ("workshopCreator.field.title", "Title", "标题"),
            ("workshopCreator.fullTerms", "Complete terms for this version", "本版本完整条款"),
            ("workshopCreator.loading", "Checking…", "正在核对…"),
            ("workshopCreator.noTarget", "No package version with complete terms is available. You can review the source; confirmation requires complete terms.", "尚无可选择的包版本和完整条款。可以查看原文；完整条款可用后才能确认。"),
            ("workshopCreator.offerVersion", "Offer version reference", "报价版本标识"),
            ("workshopCreator.omitted", "Planning information excluded from this package", "本包未包含的规划资料"),
            ("workshopCreator.omitted.activityCategoryids", "Activity categories", "活动分类"),
            ("workshopCreator.omitted.categoryId", "Category", "分类"),
            ("workshopCreator.omitted.difficulty", "Difficulty", "难度"),
            ("workshopCreator.omitted.duration", "Duration", "时长"),
            ("workshopCreator.omitted.players", "Player count", "人数"),
            ("workshopCreator.omitted.requiredMaterials", "Materials", "所需材料"),
            ("workshopCreator.omitted.usageLocation", "Location", "适用地点"),
            ("workshopCreator.open", "Declare package use permission", "声明新包使用授权"),
            ("workshopCreator.package", "Package reference", "包标识"),
            ("workshopCreator.pendingReview", "Package review is still required. This is not a listing or an issued purchase license.", "仍需包审核，尚未上架或签发购买授权。"),
            ("workshopCreator.record", "Declaration record", "声明记录"),
            ("workshopCreator.recorded", "Declaration recorded", "声明已记录"),
            ("workshopCreator.refresh", "Refresh source review", "重新核对原文"),
            ("workshopCreator.request", "Request ID", "本次请求编号"),
            ("workshopCreator.scope", "Use in publicly operated themes", "公开主题使用范围"),
            ("workshopCreator.selectVersion", "Choose the intended version", "选择待声明版本"),
            ("workshopCreator.source", "Your template ID", "本人玩法编号"),
            ("workshopCreator.storage", "The local recovery record could not be safely read or saved. The declaration cannot continue.", "本机恢复记录无法安全读取或保存，声明未继续。"),
            ("workshopCreator.termsVersion", "Terms version", "条款版本"),
            ("workshopCreator.textOnly", "This version contains only the text below. Review every field.", "此版本只包含下列文字。请逐项核对原文。"),
            ("workshopCreator.title", "Creator use permission", "创作者使用授权"),
            ("workshopCreator.unavailable", "This service is not configured. Signing in does not enable declarations.", "此服务尚未配置。登录不会自动开启声明权限。"),
            ("workshopCreator.unknown", "The outcome is unconfirmed. The original request ID is retained. Check the record first; a missing record never causes an automatic resubmission.", "结果尚未确认。已保留原请求编号，请先核对记录。未找到记录也不会自动重新声明。"),
            ("workshopCreator.version", "Version", "版本"),
            ("workshopPending.adaptation", "Adaptation", "改编"),
            ("workshopPending.allowedRegions", "Allowed regions (comma-separated)", "允许地域（逗号分隔）"),
            ("workshopPending.another", "Start another proposal", "开始另一份提案"),
            ("workshopPending.author", "Save unreviewed proposal", "保存未审核提案"),
            ("workshopPending.back", "Back to proposals", "返回提案"),
            ("workshopPending.boundary", "Create an unreviewed proposal from your eligible original CMS source. Authoring does not consent, approve, list, charge or issue a buyer licence. Existing purchases keep their frozen rights.", "从符合条件的自有原创模板创建未审核提案。填写提案不会表示授权、审核通过、上架、收费或签发买家许可。已有购买保留冻结权利。"),
            ("workshopPending.buyerKinds", "Buyer kinds (comma-separated)", "购买主体类型（逗号分隔）"),
            ("workshopPending.choices", "Explicit proposed offer and restrictions", "明确的拟定报价与限制"),
            ("workshopPending.choose", "Choose explicitly", "请明确选择"),
            ("workshopPending.commercialUse", "Commercial use", "商业使用"),
            ("workshopPending.currency", "Currency (three uppercase letters)", "币种（三位大写字母）"),
            ("workshopPending.empty", "No current eligible proposal. Complete the form to create one.", "暂无符合当前条件的提案。请填写表单创建。"),
            ("workshopPending.expiresAt", "Proposal expiry (ISO-8601 UTC)", "提案到期时间（ISO-8601 UTC）"),
            ("workshopPending.expiryHelp", "Enter a future ISO-8601 instant, at most 30 days from creation and up to six fractional-second digits. Expiry is not review approval.", "请填写未来的ISO-8601时刻，距离创建时间不超过30天，小数秒最多6位。有效期不表示审核通过。"),
            ("workshopPending.fixedRestrictions", "One-time PAID acquisition. Perpetual use of the purchased version only. Updates limited to that exact version. Package redistribution prohibited. Copyright retained by the creator.", "一次性付费获取。仅永久使用已购买版本。更新权益限于该精确版本。禁止再分发原包。版权由创作者保留。"),
            ("workshopPending.historic", "This receipt may be historical. Current source eligibility and terms must be loaded again before a separate explicit declaration.", "此回执可能属于历史请求。必须重新读取当前来源资格和条款后，才能单独明确声明授权。"),
            ("workshopPending.invalid", "Complete every required choice and check the text, limits, price, currency and expiry. Nothing was sent.", "请明确填写全部必填选项，并检查条款、数量、价格、币种与到期时间。尚未发送。"),
            ("workshopPending.limitsHelp", "Each limit is required: -1 explicitly means unlimited, 0 means zero, and positive integers are maxima.", "每项均须填写：-1明确表示不限，0表示零，正整数表示上限。"),
            ("workshopPending.merchantLimit", "Merchant limit", "商家数量限制"),
            ("workshopPending.more", "Load more proposals", "加载更多提案"),
            ("workshopPending.option.ALLOWED", "Allowed", "允许"),
            ("workshopPending.option.BIND_RESOURCES_ONLY", "Bind resources only", "仅绑定资源"),
            ("workshopPending.option.LOCAL_ADAPTATION", "Local adaptation", "本地改编"),
            ("workshopPending.option.PROHIBITED", "Prohibited", "禁止"),
            ("workshopPending.priceHelp", "Enter an explicit positive integer price and currency. This unreviewed proposal supports a one-time PAID offer only; no payment occurs here.", "请明确填写正整数价格与币种。此未审核提案仅支持一次性付费报价；此处不会付款。"),
            ("workshopPending.priceMinor", "One-time price in minor units", "一次性价格（货币最小单位）"),
            ("workshopPending.priorDeclaration", "Previous declaration receipt", "既有授权声明回执"),
            ("workshopPending.priorDeclarationScope", "Historical receipt only. This does not prove current source eligibility, review approval, listing or buyer rights.", "仅显示历史回执。此回执不能证明当前来源资格、审核通过、已上架或买家权利。"),
            ("workshopPending.proposals", "Current owner proposals", "当前自有提案"),
            ("workshopPending.recorded", "Proposal receipt", "提案回执"),
            ("workshopPending.recovery", "This complete command was securely retained before sending. If the result is unknown, retry only this identical request. There is no separate author-status endpoint.", "完整指令已在发送前安全保存。结果不确定时仅可重试这一份完全相同的请求。没有独立的提案状态接口。"),
            ("workshopPending.refresh", "Reload current source and proposals", "重新读取当前来源与提案"),
            ("workshopPending.regionsHelp", "Region tokens: uppercase letters, digits, _ or -, up to 32 tokens. Buyer kinds: INDIVIDUAL, ORGANIZATION, MERCHANT. Enter only your intended choices, without duplicates.", "地域标记仅可包含大写字母、数字、_或-，最多32项。购买主体类型：INDIVIDUAL、ORGANIZATION、MERCHANT。只填写拟定选项，不可重复。"),
            ("workshopPending.required", "Required restrictions for this proposal", "本提案的固定限制"),
            ("workshopPending.retry", "Retry identical saved proposal", "重试已保存的相同提案"),
            ("workshopPending.reviewRequired", "The complete text, ownership, seller suitability and offer still need legal/content review. Public use in a buyer’s own themes requires the separate three explicit acknowledgements on the next review screen.", "完整条款、权属、卖家适格性与报价仍须法律及内容审核。买家在自己的主题中公开使用，须在下一审核页面单独完成三项明确确认。"),
            ("workshopPending.runLimit", "Run limit", "运行数量限制"),
            ("workshopPending.saved", "Saved exact request", "已保存的原始请求"),
            ("workshopPending.terms", "Complete intended licence text", "完整的拟定许可条款"),
            ("workshopPending.termsHelp", "Enter the entire licence document exactly as intended (up to 65,536 UTF-8 bytes). No legal text, price or choices are supplied for you.", "请原样填写完整许可文件（最多65,536个UTF-8字节）。系统不会代填法律条款、价格或可选条件。"),
            ("workshopPending.themeLimit", "Theme limit", "主题数量限制"),
            ("workshopPending.title", "Creator package proposal", "创作者包提案"),
            ("workshopPending.translation", "Translation", "翻译"),
            ("workshopPending.unknown", "The authoring result is uncertain. Keep this saved request and retry it unchanged; a receipt alone does not prove current eligibility.", "提案结果尚不确定。请保留原请求并完全一致地重试；回执本身不能证明当前资格。")
        ]
        for (key, english, chinese) in cases {
            XCTAssertEqual(workshopCreatorLocalized(key, locale: Locale(identifier: "en")), english, key)
            XCTAssertEqual(workshopCreatorLocalized(key, locale: Locale(identifier: "zh-Hans")), chinese, key)
        }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5); while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }; XCTAssertTrue(condition())
    }
}
#endif
