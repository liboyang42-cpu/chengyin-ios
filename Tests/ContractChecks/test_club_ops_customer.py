"""Source contracts for the mini-program parity of club customers, customer detail and settlement.

These read Swift and catalog sources only; they do not compile or run Swift.
"""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TABLE = "ClubOpsCustomer"


def read(path):
    return (ROOT / path).read_text()


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


class ClubOpsCustomerCatalog(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(read("Resources/ClubOpsCustomer.xcstrings"))
        cls.strings = cls.catalog["strings"]

    def zh(self, key):
        return self.strings[key]["localizations"]["zh-Hans"]["stringUnit"]["value"]

    def test_catalog_shape_is_bilingual(self):
        self.assertEqual(self.catalog["sourceLanguage"], "en")
        self.assertEqual(self.catalog["version"], "1.0")
        for key, row in self.strings.items():
            for lang in ["en", "zh-Hans"]:
                unit = row["localizations"][lang]["stringUnit"]
                self.assertEqual(unit["state"], "translated", key)
                self.assertTrue(unit["value"].strip(), key)

    def test_every_table_key_used_in_swift_exists(self):
        import re
        sources = "".join(read(p) for p in ["App/ClubOpsCustomerViews.swift", "App/ClubOpsSettlementViews.swift",
                                            "App/ClubGovernanceViews.swift", "App/ClubSettlementDetail.swift",
                                            "App/ClubOwnerFundsView.swift", "Core/ClubOpsCustomerPresentation.swift",
                                            "Core/ClubOpsSettlementPresentation.swift"])
        used = set()
        for literal in re.findall(r'(?<!accessibilityIdentifier\()"(clubOps\.[A-Za-z.]+)[^"]*"', sources):
            used.add(literal)
        prefixes = {"clubOps.customer.status.", "clubOps.customer.issue.", "clubOps.settlement.withdraw."}
        keys = {k.split(" ", 1)[0] for k in self.strings}
        for key in used:
            if key in prefixes:
                continue
            self.assertIn(key, keys, key)
        for code in ["VERIFIED", "PENDING", "CONTACTED", "REFUNDED", "CANCELLED", "REGISTERED"]:
            self.assertIn("clubOps.customer.status." + code, self.strings)
        for issue in ["remarkTooLong", "tagTooLong", "tooManyTags"]:
            self.assertIn("clubOps.customer.issue." + issue, self.strings)
        for hint in ["zero", "unknown", "ownerOnly"]:
            self.assertIn("clubOps.settlement.withdraw." + hint, self.strings)

    def test_exact_mini_program_copy(self):
        expected = {
            "clubOps.customers.count %lld %lld": "%1$lld 位 · 本月新增 %2$lld",
            "clubOps.customers.noName": "未留姓名",
            "clubOps.customers.metaPendingTopic %lld %@": "待核销 %1$lld 张 · 最近参加「%2$@」",
            "clubOps.customers.metaVerifiedDay %lld %@": "核销 %1$lld 次 · 最近 %2$@",
            "clubOps.customers.empty": "还没有客户",
            "clubOps.customers.emptyDetail": "有人买过本俱乐部的票之后，这里会按人汇总他的到店与退款。",
            "clubOps.customers.filteredEmpty": "没有符合条件的客户",
            "clubOps.customers.filteredEmptyDetail": "换个筛选或关键词试试",
            "clubOps.customers.failed": "客户名单加载失败",
            "clubOps.customers.retry": "重试加载",
            "clubOps.customers.forbidden": "当前岗位没有客户查看权限",
            "clubOps.customers.forbiddenDetail": "请联系主理人调整角色权限",
            "clubOps.customer.noInteraction": "尚未发生互动",
            "clubOps.customer.interactionRemark %lld %lld %@": "最近互动 %1$lld月%2$lld日 · %3$@",
            "clubOps.customer.paidAmount": "累计实付",
            "clubOps.customer.amountHidden": "无查看权限",
            "clubOps.customer.overview": "客户概览",
            "clubOps.customer.records": "参与记录",
            "clubOps.customer.recordsEmpty": "暂无参与记录",
            "clubOps.customer.recordsEmptyDetail": "该客户还没有报名或核销过",
            "clubOps.customer.noRemark": "还没有备注",
            "clubOps.customer.remark %@": "备注：%@",
            "clubOps.customer.tagPlaceholder": "加个标签，例如：常客",
            "clubOps.customer.remarkPlaceholder": "备注：口味偏好、常带谁、下次要留意什么",
            "clubOps.customer.issue.remarkTooLong": "备注最多 200 字",
            "clubOps.customer.issue.tagTooLong": "单个标签最多 12 字",
            "clubOps.customer.issue.tooManyTags": "标签最多 8 个",
            "clubOps.customer.status.CANCELLED": "已取消",
            "clubOps.customer.viewTopic": " · 查看活动",
            "clubOps.settlement.settledLabel": "已入账分润",
            "clubOps.settlement.amountUnverified": "金额待核验",
            "clubOps.settlement.unverifiedCount %lld": "%lld 笔已结算记录缺少入账证据，合计待核验",
            "clubOps.settlement.topicsHeader": "各主题结算",
            "clubOps.settlement.rowUnverified": "待核验",
            "clubOps.settlement.footnote": "已入账以账户打款记录为准；核算净额包含已执行调整，后续调整不代表已到账。作废记录保留历史金额，不再打款。",
            "clubOps.settlement.empty": "还没有平台分润记录",
            "clubOps.settlement.failed": "结算数据暂不可用",
            "clubOps.settlement.retry": "重新加载",
            "clubOps.settlement.withdraw.zero": "可提现为 0：分润到账并客诉期结束后才能提现",
            "clubOps.settlement.withdraw.unknown": "可提现余额待确认",
            "clubOps.settlement.withdraw.ownerOnly": "仅主理人可发起提现",
        }
        for key, value in expected.items():
            self.assertEqual(self.zh(key), value, key)

    def test_shared_catalogs_are_untouched_by_this_table(self):
        self.assertNotIn("clubOps.customers.count %lld %lld", read("Resources/Localizable.xcstrings"))


class ClubOpsCustomerWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.view = read("App/ClubGovernanceViews.swift")
        cls.content = span(cls.view, "@ViewBuilder private func content(_ snapshot: ClubGovernanceSnapshot)", "@ViewBuilder private func dataRows(")

    def test_validation_accepts_backend_cancelled_records(self):
        validation = read("Core/ClubGovernanceValidation.swift")
        self.assertIn('["VERIFIED", "PENDING", "CONTACTED", "REFUNDED", "CANCELLED", "REGISTERED"].contains(row["statusCode"].string ?? "")', validation)
        mapper = Path("/home/user/hengyin/chengyinhub-system/src/main/resources/mapper/business/ClubCrmMapper.xml")
        if mapper.exists():
            self.assertIn("then 'CANCELLED'", mapper.read_text())
        core = read("Core/ClubOpsCustomerPresentation.swift")
        self.assertIn('cancelled = "CANCELLED"', core)

    def test_list_uses_presentation_and_keeps_customer_route(self):
        branch = span(self.content, "if operation == .customers {\n                if let list", "} else {\n                ClubGovernanceFactRows")
        for token in ["try? ClubOpsCustomerListPresentation(value: value)", "snapshotCustomerFilters?.isFiltered == true",
                      "ClubGovernanceReadView(operation: .customer, scope: .init(clubID: scope.clubID, memberID: id)"]:
            self.assertIn(token, branch)
        rows = read("App/ClubOpsCustomerViews.swift")
        self.assertIn('.accessibilityIdentifier("club.gov.route.customer")', rows)
        self.assertIn('.accessibilityIdentifier("club.gov.fact.displayName")', rows)
        self.assertNotIn("phone\"]", rows)
        # Existing clear-filters action remains the only reset path.
        self.assertIn('.accessibilityIdentifier("club.gov.customers.clearFilters")', self.content)
        self.assertEqual(self.view.count("clearCustomerFilters(source: snapshot"), 1)

    def test_detail_keeps_topic_route_edit_gate_and_hidden_amount(self):
        branch = span(self.content, "} else if operation == .customer {", "} else {\n            if operation == .customers {")
        for token in ["ClubOpsCustomerDetailPresentation(value: value, memberID: scope.memberID)",
                      "customerTopicRoute(record.source)", "selectCustomerTopic(target)",
                      "detail.canEdit ? AnyView(edit(.saveCustomer"]:
            self.assertIn(token, branch)
        views = read("App/ClubOpsCustomerViews.swift")
        self.assertIn('accessibilityIdentifier("club.gov.customer.topic.\\(action.id)")', views)
        self.assertIn('"clubOps.customer.amountHidden"', views)
        core = read("Core/ClubOpsCustomerPresentation.swift")
        self.assertIn('if paid == .null || paid == .string("") { paidAmountText = nil }', core)
        self.assertNotIn('"phone"', core)

    def test_editor_rereads_detail_after_dismissal_inside_existing_fences(self):
        self.assertIn(".sheet(item: $editor, onDismiss: { rereadCustomerAfterEditor() })", self.view)
        body = span(self.view, "private func rereadCustomerAfterEditor()", "private func current(_ target: ClubLeaderboardMemberRoute)")
        for token in ["operation == .customer", "scenePhase == .active", "snapshotContext == readContext",
                      "identity == access.identity", "!loading", "await load()"]:
            self.assertIn(token, body)
        # The helper must stay outside the pinned clear-filters span.
        clear = span(self.view, "private func clearCustomerFilters(", "private func loadCustomersNow()")
        self.assertNotIn("rereadCustomerAfterEditor", clear)

    def test_chip_editor_reuses_the_reviewed_command_form(self):
        form = read("App/ClubGovernanceCommandForm.swift")
        self.assertIn('ClubOpsCustomerTagRemarkEditor(tagsText: textBinding("tags"), remark: textBinding("remark"))', form)
        self.assertIn('(route.operation != .saveCustomer || !["tags", "remark"].contains(key))', form)
        self.assertIn("}.disabled(busy || locked || review != nil)", form)
        editor = span(read("App/ClubOpsCustomerViews.swift"), "struct ClubOpsCustomerTagRemarkEditor", "private func add()")
        self.assertIn('.accessibilityIdentifier("club.gov.input.tags")', editor)
        self.assertNotIn("requestID", editor)
        core = read("Core/ClubOpsCustomerPresentation.swift")
        for token in ["maxTags = 8, maxTagLength = 12, maxRemarkLength = 200", "utf16.count > maxRemarkLength",
                      "utf16.count > maxTagLength", "seen.count > maxTags"]:
            self.assertIn(token, core)
        commands = read("Core/ClubGovernanceCommands.swift")
        self.assertIn("tags.count <= 8", commands)
        self.assertIn("s.utf16.count <= 12", commands)
        self.assertIn("remark.utf16.count <= 200", commands)

    def test_customer_write_permission_matches_directory_rule(self):
        commands = read("Core/ClubGovernanceCommands.swift")
        self.assertIn('case .saveCustomer: return "CUSTOMER_DIRECTORY"', commands)
        self.assertNotIn('case .saveCustomer: return "club:member:list:read"', commands)
        contracts = read("Core/ClubGovernanceContracts.swift")
        self.assertIn('if permission == "CUSTOMER_DIRECTORY" { return allowsCustomerDirectory(scope: scope) }', contracts)

    def test_failure_copy_is_added_without_replacing_generic_error(self):
        nav = span(self.view, "private var bodyNavigation: some View {", ".navigationTitle(title)")
        self.assertIn("if let failure, let copy = ClubOpsFailureCopy(operation: operation, failure: failure) {", nav)
        self.assertIn('accessibilityIdentifier("club.gov.error")', nav)
        self.assertLess(nav.index("ClubOpsFailureCopy("), nav.index('accessibilityIdentifier("club.gov.error")'))

    def test_authored_core_tests_exist(self):
        tests = read("Tests/CoreTests/ClubOpsCustomerPresentationTests.swift")
        for name in ["testValidationAcceptsCancelledRecordsEmittedByBackend", "testListMetaFollowsMiniProgramPendingFirstRule",
                     "testPaidAmountIsHiddenNotZeroAndUsesTrimMoney", "testTagDraftMirrorsMiniProgramLimitsAndDedupes",
                     "testDraftTextStillProducesTheSameCommandFields", "testCustomerWriteUsesDirectoryGovernanceRuleAndFailsClosed"]:
            self.assertIn("func " + name + "(", tests)
        settlement = read("Tests/CoreTests/ClubOpsSettlementPresentationTests.swift")
        for name in ["testUnverifiedTotalNeverInventsAnAmount", "testWithdrawHintMatchesMiniProgramStates"]:
            self.assertIn("func " + name + "(", settlement)


class ClubOpsSettlementWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        view = read("App/ClubGovernanceViews.swift")
        cls.branch = span(view, "} else if operation == .settlement {", "} else if operation == .feed {")

    def test_card_owner_gate_and_rows(self):
        b = self.branch
        self.assertIn("try? ClubOpsSettlementSummary(value: value, scope: scope)", b)
        self.assertIn("ClubOpsSettlementSummaryCard(summary: settlementSummary)", b)
        self.assertIn("if let target = ClubOwnerFundsTarget(snapshot: snapshot, context: readContext) {", b)
        self.assertIn("} else if let settlementSummary, !settlementSummary.isOwner, settlementSummary.hasTopics {", b)
        self.assertIn("ClubOpsSettlementOwnerOnlyWithdraw()", b)
        self.assertIn('Text("club.gov.financialGate")', b)
        self.assertIn('"clubOps.settlement.topicsHeader"', b)
        self.assertIn("ClubOpsSettlementFootnote()", b)
        self.assertIn(".disabled(ownerFundsParent.retainsContact || ownerFundsParent.workflow.loading)", b)
        self.assertLess(b.index("ClubOpsSettlementSummaryCard"), b.index("ClubOwnerFundsSection("))

    def test_non_owner_withdraw_is_disabled_and_has_no_money_path(self):
        views = read("App/ClubOpsSettlementViews.swift")
        owner_only = span(views, "struct ClubOpsSettlementOwnerOnlyWithdraw", "struct ClubOpsSettlementFootnote")
        self.assertIn("Button {} label:", owner_only)
        self.assertIn(".disabled(true)", owner_only)
        for forbidden in ["openContact", "withdraw(", "api/", "URLSession", "reader"]:
            self.assertNotIn(forbidden, views)
        summary = read("Core/ClubOpsSettlementPresentation.swift")
        self.assertIn('isOwner = accepted["isOwner"] == .bool(true)', summary)
        self.assertIn("ClubGovernanceValidation.validate(value, operation: .settlement, scope: scope)", summary)

    def test_owner_hint_copy_and_contact_gate_unchanged(self):
        funds = read("App/ClubOwnerFundsView.swift")
        self.assertIn("ClubOpsWithdrawHint(isOwner: true, availability: workflow.availability)", funds)
        self.assertIn(".disabled(offered == nil || workflow.loading || workflow.availability != .positive || context.support == nil)", funds)

    def test_rows_show_pending_verification_and_empty_copy(self):
        rows = span(read("App/ClubSettlementDetail.swift"), "struct ClubSettlementRows:", "struct ClubSettlementDetail:")
        self.assertIn('"clubOps.settlement.rowUnverified"', rows)
        self.assertIn('"clubOps.settlement.empty"', rows)
        self.assertIn("if row.status == .void || row.status == .unverified { Text(verbatim: row.paidText) }", rows)
        status = read("Core/ClubSettlementDetailPresentation.swift")
        self.assertIn('case "settled": status = row["amountStatus"] == .string("unverified") ? .unverified : .credited', status)

    def test_ledger_read_is_not_added(self):
        contracts = read("Core/ClubGovernanceContracts.swift")
        self.assertNotIn("club-direct-merchant", contracts)


if __name__ == "__main__":
    unittest.main()


class ClubOpsCustomerRecordIdentityChecks(unittest.TestCase):
    def test_duplicate_record_keys_fail_closed(self):
        core = (ROOT / 'Core/ClubOpsCustomerPresentation.swift').read_text()
        self.assertIn('guard Set(records.map(\\.id)).count == records.count else { throw ClubGovernanceFailure.malformed }', core)
