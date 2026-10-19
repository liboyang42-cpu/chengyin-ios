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
    def test_detail_source_sections_are_read_only_and_ordered(self):
        sections = read('App/ProfileOrderSourceDetailSections.swift')
        timeline = read('Core/ProfileOrderTimeline.swift')
        self.assertIn('ProfileOrderSourceDetailSections(order: order)', self.app)
        self.assertLess(self.app.index('Section(LocalizedStringKey(order.paymentSectionTitleKey))'), self.app.index('ProfileOrderSourceDetailSections(order: order)'))
        for marker in ['orderLifecycle.timeline.title', 'profile.orderParity.section.paymentInfo', 'profile.orderParity.section.registrant', 'profile.orderParity.section.voucher']:
            self.assertIn(marker, sections)
        self.assertLess(sections.index('orderLifecycle.timeline.title'), sections.index('profile.orderParity.section.paymentInfo'))
        self.assertLess(sections.index('profile.orderParity.section.paymentInfo'), sections.index('profile.orderParity.section.registrant'))
        self.assertLess(sections.index('profile.orderParity.section.registrant'), sections.index('profile.orderParity.section.voucher'))
        self.assertIn('if order.showsSourcePaymentInfo {', sections)
        self.assertIn('var showsSourcePaymentInfo: Bool { paymentStatus == 2 }', timeline)
        for forbidden in ['Task {', 'await ', 'transport', 'URLSession', 'Button(']:
            self.assertNotIn(forbidden, sections)
            self.assertNotIn(forbidden, timeline)

    def test_detail_facts_are_lenient_and_single_mount(self):
        profile = read('Core/ProfileContracts.swift')
        timeline = read('Core/ProfileOrderTimeline.swift')
        self.assertEqual(profile.count('detailFacts = try ProfileOrderDetailFacts(from: decoder)'), 1)
        self.assertEqual(profile.count('historyFacts = try ProfileOrderHistoryFacts(from: decoder)'), 1)
        facts = timeline.split('public struct ProfileOrderDetailFacts', 1)[1].split('public struct ProfileOrderTimelineStep', 1)[0]
        self.assertNotIn('try c.decode(', facts)
        self.assertNotIn('decodeIfPresent', facts)
        self.assertIn('?? Self.present(try? refund.decode(String.self, forKey: .updateTime))', facts)

    def test_timeline_follows_source_branches(self):
        timeline = read('Core/ProfileOrderTimeline.swift')
        for text in ['if paymentStatus == 2 {', '} else if state == .cancelled {', 'if state == .refunding || state == .refunded {',
                     'manualRefundCaseStatus == "NO_REFUND" || manualRefundCaseStatus == "MANUAL_REFUND_EVIDENCE_VERIFIED"',
                     'verificationStatus == 1 ? OrderLifecycleTime.display(verificationTime) : nil']:
            self.assertIn(text, timeline)
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        zh = lambda key: catalog[key]['localizations']['zh-Hans']['stringUnit']['value']
        expected = {'orderLifecycle.timeline.created': '订单已创建', 'orderLifecycle.timeline.paid': '支付已完成',
                    'orderLifecycle.timeline.cancelled': '订单已取消', 'orderLifecycle.timeline.awaitingPayment': '等待支付',
                    'orderLifecycle.timeline.verified': '权益已核销', 'orderLifecycle.timeline.refunding': '退款处理中',
                    'profile.orderParity.timeline.free': '免费报名成功', 'profile.orderParity.timeline.firstScan': '首次扫码成功',
                    'profile.orderParity.timeline.refunded': '已退款', 'profile.orderParity.timeline.awaitingStore': '等待到店核销',
                    'profile.orderParity.timeline.notVerified': '尚未核销', 'profile.orderParity.timeline.updatesLater': '完成后更新',
                    'profile.orderParity.transactionID': '微信交易单号', 'profile.orderParity.mobile': '手机'}
        for key, value in expected.items():
            self.assertEqual(zh(key), value, key)

if __name__ == '__main__':
    unittest.main()
