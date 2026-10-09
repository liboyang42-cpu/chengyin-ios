"""Focused P029 source contracts; no Swift compiler, UI or accessibility execution."""
from pathlib import Path
import hashlib
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ObjectBadgeWallLayoutContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/ObjectBadgeViews.swift').read_text()
        self.wall, self.detail = self.source.split('@MainActor struct ObjectBadgeDetailView:', 1)
    def test_existing_detail_and_route_lifetimes_are_byte_identical(self):
        value = ('@MainActor struct ObjectBadgeDetailView:' + self.detail).encode()
        self.assertEqual(hashlib.sha256(value).hexdigest(), '50dadbb49766a082c13bae8be710bd91a5e03226a3f578c6e9a424506ea07345')
        self.assertIn('let capturedIdentity = reader.identity', self.wall)
        self.assertIn('ObjectBadgeDetailView(badge: badge, reader: reader, expectedIdentity: capturedIdentity, media: media)', self.wall)
    def test_default_list_and_current_owner_selection_are_local(self):
        self.assertIn('private var layout: ObjectBadgeWallLayout = .list', self.wall)
        self.assertIn('owner == current && current.identity != nil && current.isConfigured ? layout : .list', self.wall)
        self.assertIn('guard rendered == current, current.identity != nil, current.isConfigured else { return }', self.wall)
        self.assertIn('layoutSelection.choose($0, rendered: owner, current: layoutOwner)', self.wall)
        self.assertIn('.onChange(of: layoutOwner) { _, _ in layoutSelection.retire() }', self.wall)
        self.assertIn('readerID: ObjectIdentifier(reader), identity: reader.identity, isConfigured: reader.isConfigured', self.wall)
    def test_switch_does_not_add_reads_or_reload_the_read_screen(self):
        self.assertEqual(self.wall.count('try await reader.profileBadges()'), 1)
        self.assertNotIn('.id(layout', self.wall)
        for forbidden in ['.task(', '.onAppear', 'UserDefaults', 'URLSession', 'request(', 'unlock(', 'AsyncImage(', 'Task {']:
            self.assertNotIn(forbidden, self.wall)
        selection = self.wall.split('struct ObjectBadgeWallLayoutSelection {', 1)[1].split('/// Additive replacement', 1)[0]
        for forbidden in ['reader.', 'await ', 'NavigationLink', 'save(', 'publish(']:
            self.assertNotIn(forbidden, selection)
    def test_control_is_separate_from_detail_navigation(self):
        control = self.wall.split('struct ObjectBadgeWallLayoutControl: View {', 1)[1].split('struct ObjectBadgeWallBadgeLabel:', 1)[0]
        self.assertIn('Picker("objects.badgeLayout.title", selection: $selection)', control)
        self.assertIn('.pickerStyle(.menu).frame(minHeight: 44)', control)
        self.assertNotIn('NavigationLink', control)
        self.assertIn('Section {\n                    ObjectBadgeWallLayoutControl', self.wall)
        self.assertIn('.accessibilityIdentifier("objects.badge.layout")', control)
    def test_same_rows_group_order_and_partial_results_are_retained(self):
        groups = ['Section("profile.badges.identities")', 'Section("profile.badges.medals")', 'Section("profile.badges.achievements")']
        self.assertEqual([self.wall.index(g) for g in groups], sorted(self.wall.index(g) for g in groups))
        for token in ['if wall.isPartial', 'Text("profile.badges.partial")', 'wall.medalFailureMessage', 'Text("profile.badges.partialHint")',
                      'if wall.isEmpty { Text("profile.badges.empty") }', 'if let medals = wall.medals',
                      'let city = medals.filter { !$0.isAchievement }', 'let achievements = medals.filter(\\.isAchievement)',
                      'wall.identities.map { .identity($0) }', 'city.map { .medal($0) }', 'achievements.map { .medal($0) }']:
            self.assertIn(token, self.wall)
        self.assertEqual(self.wall.count('ForEach(Array(badges.enumerated()), id: \\.offset)'), 2)
    def test_static_grid_is_readable_and_uses_existing_badge_facts(self):
        for token in ['dynamicTypeSize.isAccessibilitySize', '[GridItem(.flexible(), alignment: .topLeading)]',
                      'GridItem(.adaptive(minimum: 160)', 'description.fixedSize(horizontal: false, vertical: true)',
                      '.accessibilityElement(children: .combine)', 'Text(verbatim: badge.name)',
                      'badge.isLocked ? "profile.badges.locked" : "profile.badges.unlocked"',
                      'Text("objects.badgeLayout.staticOnly")']:
            self.assertIn(token, self.wall)
        self.assertIn('layout: layout).buttonStyle(.plain)', self.wall)
        self.assertNotIn('.lineLimit(', self.wall)
        self.assertNotIn('SceneKit', self.wall)
        self.assertNotIn('RealityKit', self.wall)
    def test_additive_bilingual_labels_accept_exact_central_merge(self):
        fragment = json.loads((ROOT / 'Resources/ObjectBadgeWallLayoutLocalizations.fragment.json').read_text())
        expected = {'objects.badgeLayout.' + k for k in ['title', 'list', 'wall', 'staticOnly']}
        self.assertEqual(set(fragment), expected)
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        present = expected & set(catalog)
        if present:
            self.assertEqual(present, expected)
            for key in expected: self.assertEqual(fragment[key], catalog[key])
        for row in fragment.values():
            self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
            for locale in row['localizations'].values(): self.assertTrue(locale['stringUnit']['value'])
        self.assertEqual(fragment['objects.badgeLayout.wall']['localizations']['en']['stringUnit']['value'], 'Static wall')
    def test_focused_runtime_methods_are_authored_without_claiming_execution(self):
        tests = (ROOT / 'Tests/AppUnitTests/ObjectBadgeWallLayoutTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 8)
        for case in ['testAccountEpochSignOutAndConfigurationLoss', 'testReplacementReaderWithSameAccount',
                     'testOldRenderedControlCannotChangeCurrentOwnersChoice', 'testRetirementNeedsAnotherExplicitCurrentSelection',
                     'testBilingualLargeTextLabelsAndControlConstructInBothLayouts']:
            self.assertIn(case, tests)
        self.assertIn('.dynamicTypeSize(.accessibility5)', tests)
        self.assertIn('["en", "zh-Hans"]', tests)

if __name__ == '__main__': unittest.main(verbosity=2)
