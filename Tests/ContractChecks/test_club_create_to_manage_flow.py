"""Package 09 contract checks: Club Create Result & Jump to Management Closure (不扩 Club28)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ClubCreateToManageFlowContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.views = (ROOT / "App/ClubOperationsViews.swift").read_text(encoding="utf-8")
        cls.core_tests = (ROOT / "Tests/CoreTests/ClubCreateToManageFlowTests.swift").read_text(encoding="utf-8")

    def test_club28_scope_and_production_default_gate_remain_closed(self):
        self.assertIn("public struct ClubCreationGate: Equatable, Sendable", self.views)
        self.assertIn("public static let club28SubviewLimit = 28", self.views)
        self.assertIn("public static let productionDefault = ClubCreationGate(", self.views)
        self.assertIn("isConfigured: false", self.views)
        self.assertIn("writeAvailability: .unverified", self.views)
        self.assertIn("isConfigured && withinClub28Scope && (writeAvailability == .approved || writeAvailability == .syntheticOnly)", self.views)
        for forbidden in ["URLSession", "https://", "http://", "api/club/create"]:
            self.assertNotIn(forbidden, self.views)

    def test_workspace_tab_validates_requested_tab_and_falls_back_to_overview(self):
        self.assertIn("public enum ClubWorkspaceTab: String, CaseIterable, Equatable, Sendable", self.views)
        for case_name in ["case posts", "case events", "case overview", "case manage"]:
            self.assertIn(case_name, self.views)
        self.assertIn("public static let defaultFallback: ClubWorkspaceTab = .overview", self.views)
        self.assertIn("if validated == .manage && !canEnterManagement {\n            return .overview\n        }", self.views)

    def test_confirmed_receipt_same_account_readback_and_enter_management_action(self):
        for symbol in [
            "public struct ClubCreateToManageDestination: Equatable, Identifiable, Sendable",
            "public enum ClubCreateToManageBlockReason: String, Equatable, Sendable",
            "public struct ClubCreateToManageFlowState: Equatable, Sendable",
            'public static let enterManagementButtonTitle = "进入俱乐部管理 / Enter Club Management"',
            "public var hasConfirmedReceipt: Bool",
            "public var isSameAccountVerified: Bool",
            "public var isClubIdVerified: Bool",
            "public var isSameAccountReadbackVerified: Bool",
            "hasConfirmedReceipt && isSameAccountVerified && isClubIdVerified",
            "public mutating func enterClubManagement(requestedTab overrideTab: String? = nil) -> ClubCreateToManageDestination?",
        ]:
            self.assertIn(symbol, self.views)

        # Verify UI wiring in ClubOperationsWorkspaceView
        for wiring in [
            "var createToManageFlow: ClubCreateToManageFlowState",
            '.accessibilityIdentifier("clubCreateManage.status")',
            '.accessibilityIdentifier("clubCreateManage.enterManagement")',
            '.accessibilityIdentifier("clubCreateManage.destination")',
            ".disabled(loading || !flow.canEnterManagement)",
            "target: .club(destination.clubId)",
        ]:
            self.assertIn(wiring, self.views)

    def test_blocked_gate_readback_failure_and_account_mismatch_have_bilingual_copy(self):
        for copy_pair in [
            ("俱乐部创建门控未开启，暂不可进入俱乐部管理", "Club creation gate is closed; entering Club Management is blocked."),
            ("同账号回读校验未通过，暂不可进入俱乐部管理", "Same-account readback verification failed; entering Club Management is blocked."),
            ("账号已变更或不匹配，已拦截进入俱乐部管理", "Account mismatch detected; entering Club Management is blocked."),
            ("俱乐部 ID 回读不匹配，已拦截进入俱乐部管理", "Club ID readback mismatch; entering Club Management is blocked."),
            ("同账号回读已确认（俱乐部 #", "Same-account readback verified (Club #"),
        ]:
            self.assertIn(copy_pair[0], self.views)
            self.assertIn(copy_pair[1], self.views)

    def test_core_tests_cover_gate_receipt_readback_tab_and_mismatch_scenarios(self):
        test_methods = re.findall(r"func (test\w+)\(", self.core_tests)
        self.assertGreaterEqual(len(test_methods), 4)
        for expected in [
            "testProductionDefaultCreationGateRemainsClosedAndWithinClub28Scope",
            "testConfirmedReceiptAndSameAccountReadbackEnablesEnterManagementAndValidatesTab",
            "testWorkspaceTabValidationFallsBackSafelyToOverviewWhenNilInvalidOrBlocked",
            "testReadbackFailureOrClubIdMismatchBlocksEnteringManagement",
            "testAccountMismatchBlocksEnteringManagementEvenAfterReceipt",
        ]:
            self.assertIn(expected, test_methods)


if __name__ == "__main__":
    unittest.main()
