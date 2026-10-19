"""Source contracts only for w2-04 order parity: not compiled Swift or UI execution."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class W204OrderParityChecks(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/ProfileOrderSourcePresentation.swift')
        self.app = read('App/ProfileOrdersView.swift')
        self.ui = read('App/ProfileOrderFilterSection.swift')
        self.screen = read('App/ProfileReadScreen.swift')

    def test_chip_row_replaces_menu_without_requests(self):
        self.assertNotIn('.pickerStyle(.menu)', self.ui)
        self.assertIn('ScrollView(.horizontal, showsIndicators: false)', self.ui)
        self.assertIn('ForEach(ProfileOrderHistoryFilter.allCases)', self.ui)
        self.assertIn('.accessibilityIdentifier("profile.orderFilter.chip.\\(filter.rawValue)")', self.ui)
        self.assertIn('.accessibilityIdentifier("profile.orderFilter.picker")', self.ui)
        self.assertIn('Text("profile.orderParity.filterEmptyHint")', self.ui)
        for banned in ['Task {', '.profileOrders(', '.profileOrder(', '.refreshable', 'await ']:
            self.assertNotIn(banned, self.ui)

    def test_only_all_and_refunding_chip_labels_change(self):
        self.assertIn('case .all: return "profile.orderParity.chip.all"', self.core)
        self.assertIn('case .refunding: return "profile.orderParity.chip.refunding"', self.core)
        self.assertIn('default: return titleKey', self.core)

    def test_issue_copy_is_opt_in_and_defaults_unchanged(self):
        self.assertIn('issueCopy: ProfileReadIssueCopy? = nil,', self.screen)
        self.assertIn('issue = issueCopy.map { ProfileLoadIssue(error, copy: $0) } ?? ProfileLoadIssue(error)', self.screen)
        self.assertIn('issueCopy?.signInTitleKey ?? "profile.signInRequired"', self.screen)
        self.assertIn('issueCopy?.signInDetailKey ?? "auth.expired"', self.screen)
        self.assertEqual(self.app.count('issueCopy: .orders'), 1)
        self.assertEqual(self.app.count('issueCopy: .orderDetail'), 1)
        self.assertEqual(self.app.count('issueCopy:'), 2)

    def test_time_range_has_no_time_zone_conversion(self):
        block = self.core.split('public enum ProfileOrderTimeRangeText')[1].split('private extension Character')[0]
        for banned in ['TimeZone', 'DateFormatter', 'Calendar', 'Date(']:
            self.assertNotIn(banned, block)
        self.assertIn('ProfileOrderTimeRangeText.text(start: order.startDate, end: order.endDate)', self.app)

    def test_discover_cta_is_inert_without_host(self):
        self.assertIn('var discoverRoutes: (@MainActor () -> Void)? = nil', self.app)
        self.assertIn('if let discoverRoutes {', self.app)

    def test_detail_state_card_and_sections(self):
        self.assertIn('ProfileOrderStateNoticeSection(order: order)', self.app)
        self.assertIn('Section(LocalizedStringKey("profile.orderParity.section.order"))', self.app)
        self.assertIn('Section(LocalizedStringKey(order.paymentSectionTitleKey))', self.app)
        self.assertIn('guard state != .unknown else { return nil }', self.core)
        for removed in ['"profile.orders.paymentCode"', '"profile.orders.refundCode"', '"profile.orders.refundApplicationCode"']:
            self.assertNotIn(removed, self.app)
        self.assertIn('case .raw(let code): Text("profile.orderParity.rawCode \\(String(code))")', self.app)

    def test_core_is_display_only(self):
        for banned in ['URLSession', 'transport.send', 'Task {', 'UserDefaults', 'func pay(', 'func refund(', 'func cancel(', 'func submit(']:
            self.assertNotIn(banned, self.core)

    def test_fragment_is_bilingual_and_merged(self):
        fragment = json.loads(read('Resources/W204OrdersLocalizations.fragment.json'))['strings']
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertGreaterEqual(len(fragment), 30)
        for key, entry in fragment.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
            self.assertEqual(catalog.get(key), entry, key)
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in fragment.items()}
        self.assertEqual(zh['profile.orderParity.chip.refunding'], '退款中')
        self.assertEqual(zh['profile.orderParity.error.title'], '订单暂时没有加载出来')
        self.assertEqual(zh['profile.orderParity.signIn.title'], '登录后查看订单')
        self.assertEqual(zh['profile.orderParity.forbidden.title'], '当前账号无法查看订单')
        self.assertEqual(zh['profile.orderParity.notice.free'], '免费报名成功')

    def test_native_tests_exist(self):
        core = read('Tests/CoreTests/ProfileOrderSourcePresentationTests.swift')
        for name in ['testTimeRangeRequiresBothValidEnds', 'testStateNoticeUsesSourceTitlesAndUnknownHasNoCard',
                     'testOrdersIssueCopyClassifiesSignInForbiddenMalformedAndFailure']:
            self.assertIn(name, core)
        ui = read('Tests/AppUITests/ProfileOrderFilterFlowTests.swift')
        self.assertIn('profile.orderFilter.chip.', ui)
        self.assertIn('profile.orderFilter.emptyHint', ui)

    def test_detail_uses_source_detail_copy_and_default_loading_elsewhere(self):
        self.assertIn('accessibilityPrefix: "profile.order.detail", issueCopy: .orderDetail, load:', self.app)
        self.assertIn('ProgressView(LocalizedStringKey(issueCopy?.loadingKey ?? "profile.loading"))', self.screen)
        self.assertIn('loadingKey: "profile.orderParity.detail.loading"', self.core)
        self.assertIn('forbiddenTitleKey: "profile.orderParity.detail.unavailable"', self.core)
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(catalog['profile.orderParity.detail.unavailable']['localizations']['zh-Hans']['stringUnit']['value'], '订单暂不可查看')
        self.assertEqual(catalog['profile.orderParity.detail.loading']['localizations']['zh-Hans']['stringUnit']['value'], '订单详情加载中')

if __name__ == '__main__':
    unittest.main()
