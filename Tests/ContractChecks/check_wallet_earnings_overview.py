"""Source contracts for inline funds stages and the organizer-share tab.

This is not Swift compilation, XCTest, or a simulator run.
"""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class WalletEarningsOverviewContracts(unittest.TestCase):
    def test_home_mounts_stages_and_income_keeps_the_product_search_fix(self):
        views = read("App/WalletCommerceViews.swift")
        home = views.split("@MainActor struct WalletCommerceHomeView", 1)[1].split("@MainActor struct WalletAssetsView", 1)[0]
        self.assertIn("WalletFundsStagesInline(reader: reader, funds: funds)", home)
        self.assertIn('accessibilityIdentifier("wallet.earnings.stages.home")', home)
        self.assertIn("organizerFinance: organizerFinance", home)
        self.assertIn("guard visibility.assets, isVisible, scenePhase == .active else { return }", home)
        self.assertIn("try await $0.stages(token: $1)", home)
        self.assertNotIn("navigationDestination", home)
        products = views.split("@MainActor struct WalletProductsView: View {", 1)[1].split("@MainActor struct WalletProductView: View {", 1)[0]
        for token in ["pendingLoad", "scheduleLoad()", "model.loading = true",
                      "guard value.isEmpty, !submittedKeyword.isEmpty else { return }",
                      "An interrupted read is retryable"]:
            self.assertIn(token, products)
        screen = views.split("@MainActor final class WalletScreen<Value>", 1)[1].split("extension WalletScreen where Value == WithdrawalBalance", 1)[0]
        self.assertIn("guard stamp == generation else { return }", screen)
        self.assertNotIn("String(localized:", views)

    def test_account_host_reuses_finance_view_without_a_detour_or_ungranted_read(self):
        host = read("App/SessionWalletCommerceView.swift").split("@MainActor struct SessionWalletCommerceView", 1)[1].split("@MainActor struct WalletInvitationHistoryAccess", 1)[0]
        self.assertIn("CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: \"coopflow.finance\")", host)
        self.assertIn("allowsRead: { false }", host)
        self.assertNotIn("navigationDestination", host)
        self.assertNotIn("value.points = true", host)
        self.assertNotIn("value.mall = true", host)
        self.assertIn("showsCooperationFinance: false", read("App/SessionWalletCommerceView.swift"))
        pane = read("App/WalletEarningsOverview.swift")
        self.assertLess(pane.find("func showReader"), pane.find("access.makeContent()"))
        self.assertIn("allowsRead && hasSession && mounted", pane)
        self.assertNotIn("struct WalletOrganizerFinanceSummary", pane)
        self.assertNotIn("try await reader.read(.finance)", pane)
        self.assertIn("@MainActor enum WalletFundsStageClassifier", pane)
        self.assertIn("if !input.configured || input.unavailable { return .unconfigured }", pane)
        self.assertNotIn(".noPermission", pane)
        self.assertNotIn("wallet.earnings.finance.noPermission", pane)
        self.assertIn('accessibilityIdentifier("wallet.earnings.finance.unconfigured")', pane)
        self.assertLess(pane.find("#if DEBUG"), pane.find("class WalletEarningsSyntheticFinanceReader"))
        self.assertNotIn('record["pendingReason"]', pane)
        self.assertNotIn("pendingReason:", pane)
        self.assertNotIn("withdrawable.value +", pane)
        self.assertNotIn("creditedIncome +", pane)
        self.assertNotIn("exchangeRate", pane)

    def test_summary_type_is_reused_unchanged_and_strings_stay_in_their_own_table(self):
        import hashlib
        swift = "\n".join(path.read_text() for path in ROOT.rglob("*.swift"))
        self.assertEqual(swift.count("struct CoopFinanceSummarySection"), 1)
        workbench = read("App/CooperationFlowWorkbench.swift")
        finance = workbench.split("case .finance:", 1)[1].split("case .myBusiness:", 1)[0]
        self.assertEqual(finance.count("CoopFinanceSummarySection(summary: CoopFinanceSummary(value))"), 1)
        self.assertIn('settlementRows(value["topics"].rows ?? [], source: .finance)', finance)
        self.assertLess(finance.index("CoopFinanceSummarySection"), finance.index("settlementRows"))
        expected = {
            "App/CoopFinanceSummarySection.swift": "e532d492b42aa0dd659030a16b84ec3da8ef37495bb84b4f4e275c4e45f4fbd0",
            "Core/CoopFinanceSummary.swift": "fd9dec440f790682eb76c5817f822556178eaae16bb55361042ad94943596363",
            "Tests/CoreTests/CoopFinanceSummaryTests.swift": "58783c02e8c24689252ec26ca1c30ba014fd7789057a09006735a6e96f0f44c2",
            "Tests/AppUITests/CoopFinanceSummaryFlowTests.swift": "0bb5523b08c5e5cc2be95170d4915dffb9d26965cae55ca29b00a7afe7569493",
        }
        for path, digest in expected.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)
        settlement = read("Core/CooperationFlowContracts.swift").split("public struct CoopFlowSettlement", 1)[1].split("public struct CoopFlowNearbyPartner", 1)[0]
        self.assertNotIn("pendingReason", settlement)
        self.assertIn("struct CoopFlowReadView", swift)
        self.assertIn("struct CoopFlowSettlementDetail", swift)
        catalog = json.loads(read("Resources/WalletEarningsOverview.xcstrings"))
        strings = catalog["strings"]
        self.assertEqual(strings["wallet.earnings.stages.unknown"]["localizations"]["zh-Hans"]["stringUnit"]["value"], "未知")
        self.assertEqual(strings["wallet.earnings.stages.unknown"]["localizations"]["en"]["stringUnit"]["value"], "Unknown")
        self.assertEqual(strings["wallet.earnings.tab.organizer"]["localizations"]["zh-Hans"]["stringUnit"]["value"], "主办分润")
        self.assertEqual(strings["wallet.earnings.tab.income"]["localizations"]["zh-Hans"]["stringUnit"]["value"], "收入")
        for key in ("wallet.earnings.stages.unconfigured", "wallet.earnings.finance.unconfigured"):
            self.assertEqual(strings[key]["localizations"]["zh-Hans"]["stringUnit"]["value"], "未配置/暂不可用")
            self.assertEqual(strings[key]["localizations"]["en"]["stringUnit"]["value"], "Not configured / unavailable")
        self.assertNotIn("wallet.earnings.stages.noPermission", strings)
        self.assertNotIn("wallet.earnings.finance.noPermission", strings)
        main = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        for key in strings:
            self.assertNotIn(key, main)
        balance = read("Core/WithdrawalSupport.swift")
        self.assertIn("if !c.contains(.balance) { balance = WalletAmount(0) }", balance)

    def test_authored_checks_name_the_entry_and_the_independent_states(self):
        unit = read("Tests/AppUnitTests/WalletEarningsOverviewTests.swift")
        ui = read("Tests/AppUITests/WalletEarningsOverviewUITests.swift")
        for name in ["testUnknownDoesNotBecomeZeroAndLegalZeroIsNotAFailure",
                     "testDeniedOrganizerFinanceDoesNotReadAndAGrantReadsOncePerCall",
                     "testClearedStageReadDropsTheLateResultAndABalanceSurvivesStageFailure",
                     "testTabHoldDoesNotRemountOnSwitchAndDropsOnBackground"]:
            self.assertIn(name, unit)
        for name in ["testOrganizerTabReadsSummaryOnceAndReturnsFromSettlementDetail",
                     "testClosedOrganizerTabShowsUnconfiguredAndDoesNotRead",
                     "testUnconfiguredStagesHaveNoRetryAndATransientFailureRetriesAlone",
                     "testChineseLabelsAndLargeTextKeepTheRealValues"]:
            self.assertIn(name, ui)
        self.assertIn("coopflow.settlement.finance.8", ui)
        self.assertIn("wallet.income.detail.open.4", ui)
        self.assertIn('XCTAssertEqual(settlement.status, "inTransit")', unit)

    def test_summary_requires_an_actual_topics_array_not_a_default_empty_list(self):
        workbench = read("App/CooperationFlowWorkbench.swift")
        finance = workbench.split("case .finance:", 1)[1].split("case .myBusiness:", 1)[0]
        expected = '''if value["topics"].rows != nil {
                CoopFinanceSummarySection(summary: CoopFinanceSummary(value))
            } else {
                Text("coopflow.amount.unknown")
                    .accessibilityIdentifier("coopflow.summary.unknown")
            }'''
        self.assertIn(expected, finance)
        self.assertNotIn("rows?.isEmpty", finance)
        self.assertNotIn("rows ?? []).isEmpty", finance)
        # CoopFlowJSON.rows distinguishes [] (valid zero) from missing/null/non-array.
        contract = read("Core/CooperationFlowContracts.swift")
        self.assertIn("if case .array(let v) = self { return v }; return nil", contract)
        self.assertIn('return v[key] ?? .null', contract)


if __name__ == "__main__":
    unittest.main()
