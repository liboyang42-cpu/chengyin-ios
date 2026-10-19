"""Static wiring for the club detail tabs (mini-program pages/club/detail). Not Swift compiler or runtime evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path): return (ROOT / path).read_text()


class ClubDetailTabContracts(unittest.TestCase):
    def test_policy_matches_mini_program_tab_contract(self):
        core = read('Core/ClubDetailTabs.swift')
        self.assertIn('case posts, events, overview, manage', core)
        self.assertIn('publicTabs: [ClubDetailTab] = [.posts, .events, .overview]', core)
        self.assertIn('isOwner || isJoined ? .posts : .overview', core)
        self.assertIn('canGovern || grant?.allowsManage == true', core)
        for permission in ['club:write', 'club:member:approve', 'club:member:manage', 'club:content:manage', 'club:role:manage',
                           'club:notify:send', 'club:activity:manage', 'club:event:operate', 'club:event:checkin', 'club:finance:read']:
            self.assertIn(f'"{permission}"', core)
        self.assertIn('grant?.clubID == clubID ? grant : nil', core)

    def test_detail_view_gates_every_tab_section(self):
        view = read('App/ClubDetailView.swift')
        self.assertEqual(view.count('ClubDetailTabBar(tabs: tabs.tabs, selection: tab)'), 1)
        self.assertIn('tabs.resolve(selectedTab ?? tabs.initialTab(requested: requestedTab))', view)
        # Header and join/quit stay above the tabs; each moved section is behind its tab.
        self.assertLess(view.index('ClubActionPanel('), view.index('ClubDetailTabBar('))
        for marker, tab in [('club.chat.entry', '.posts'), ('ClubCommunityEntry(', '.posts'), ('club.calendar.open', '.events'),
                            ('club.openManagement', '.manage'), ('club.statsOverview.open', '.manage'), ('club.openMembers', '.overview'),
                            ('ClubMerchantDiscoveryView(', '.manage'), ('club.projectLaunch.entry', '.manage')]:
            head = view[:view.index(marker)]
            self.assertIn(f'tab == {tab}', head[head.rindex('\n                if '):], marker)
        # The manage grant is the existing access/me read and revokes on account change.
        self.assertIn('governance.access.read(.access, scope: .init(clubID: id), options: [:])', view)
        self.assertIn('manageGrant = nil; selectedTab = nil', view)
        self.assertNotRegex(view, r'\b(send|dispatch|URLSession)\s*\(')

    def test_tab_copy_is_bilingual_in_catalog(self):
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        fragment = json.loads(read('Resources/ClubDetailTabsLocalizations.fragment.json'))['strings']
        expected = {'club.detail.tab.posts': '帖子', 'club.detail.tab.events': '活动', 'club.detail.tab.overview': '概览', 'club.detail.tab.manage': '管理'}
        for key, zh in expected.items():
            self.assertEqual(catalog[key]['localizations']['zh-Hans']['stringUnit']['value'], zh)
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value)
            self.assertTrue(value['localizations']['en']['stringUnit']['value'])

    def test_authored_tests_exist(self):
        core = read('Tests/CoreTests/ClubDetailTabTests.swift')
        ui = read('Tests/AppUITests/ClubDetailTabsFlowTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test\w+', core)), 6)
        self.assertGreaterEqual(len(re.findall(r'func test\w+', ui)), 2)


if __name__ == '__main__':
    unittest.main()
