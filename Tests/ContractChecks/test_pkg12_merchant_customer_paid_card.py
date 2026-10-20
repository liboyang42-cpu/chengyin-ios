"""Contract checks for Package 12 — Merchant Customer Detail Paid Card & Sensitive State Split."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "App/MerchantCustomerDetailSections.swift"
TESTS = ROOT / "Tests/AppUnitTests/MerchantCustomerDetailSectionsTests.swift"
CATALOG = ROOT / "Resources/MerchantReviewAndCustomerDetail.xcstrings"
FRAGMENT = ROOT / "Resources/MerchantCustomerDetailLocalizations.fragment.json"


class MerchantCustomerPaidCardContracts(unittest.TestCase):
    def test_paid_card_state_enum_and_computed_property(self):
        source = APP.read_text(encoding="utf-8")
        self.assertIn("enum PaidCardState: Equatable {", source)
        self.assertIn("case permissionHidden, unknown, amount(String)", source)
        self.assertIn("var paidCardState: PaidCardState {", source)
        self.assertIn(
            'guard canRead, access.allows("merchant:crm:sensitive:read") else { return .permissionHidden }',
            source,
        )
        self.assertIn("if let paidAmount { return .amount(paidAmount) }", source)
        self.assertIn("return .unknown", source)

    def test_paid_card_is_dedicated_section_before_participation_with_bilingual_localization(self):
        source = APP.read_text(encoding="utf-8")
        identity_section = source.split('Section("merchant.customerDetail.identity")', 1)[1].split(
            "Section {", 1
        )[0]
        self.assertNotIn('LabeledContent("merchant.business.field.paidAmount")', identity_section)

        card_idx = source.index('.accessibilityIdentifier("merchant.customerDetail.paidCard")')
        participation_idx = source.index('Section("merchant.customerDetail.participation")')
        self.assertLess(card_idx, participation_idx)

        self.assertNotIn("未记录", source)
        self.assertNotIn("累计已付不含退款记录", source)

        for token in [
            'LabeledContent("merchant.business.field.paidAmount")',
            "switch paidCardState {",
            "case .amount(let text):",
            "Text(verbatim: text).monospacedDigit()",
            "case .unknown:",
            'Text("merchant.customerDetail.paidAmountUnrecorded", tableName: Self.paidCardLocalizationTableName)',
            "case .permissionHidden:",
            'Text("merchant.business.sensitiveUnavailable").foregroundStyle(.secondary)',
            'Text("merchant.customerDetail.paidAmountExcludesRefunds", tableName: Self.paidCardLocalizationTableName)',
            '.accessibilityIdentifier("merchant.customerDetail.paidCard")',
        ]:
            self.assertIn(token, source)

        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
        fragment = json.loads(FRAGMENT.read_text(encoding="utf-8"))
        for key in [
            "merchant.customerDetail.paidAmountUnrecorded",
            "merchant.customerDetail.paidAmountExcludesRefunds",
        ]:
            self.assertIn(key, catalog)
            self.assertEqual(set(catalog[key]["localizations"].keys()), {"en", "zh-Hans"})
            self.assertIn(key, fragment)
            self.assertEqual(set(fragment[key]["localizations"].keys()), {"en", "zh-Hans"})

    def test_unit_tests_cover_paid_card_states(self):
        tests = TESTS.read_text(encoding="utf-8")
        self.assertIn("XCTAssertEqual(view.paidCardState, .permissionHidden)", tests)
        self.assertIn('XCTAssertEqual(populated.paidCardState, .amount("CNY 42.00"))', tests)
        self.assertIn("XCTAssertEqual(absent.paidCardState, .unknown)", tests)
        self.assertIn('XCTAssertEqual(absent.paidCardState.localizedStatusKey, "merchant.customerDetail.paidAmountUnrecorded")', tests)
        self.assertIn('XCTAssertEqual(zero.paidCardState, .amount("CNY 0.00"))', tests)


if __name__ == "__main__":
    unittest.main()
