#!/usr/bin/env python3
"""Source parity for pages/activity/official-detail; local source assertions, not Swift compilation."""
import json
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
# Pending catalog fragment for this page, merged into Resources/Localizable.xcstrings by the integrator.
FRAGMENT = os.environ.get("OFFICIAL_DETAIL_KEYS_JSON",
                          "")

def read(path):
    return (ROOT / path).read_text()

def known_keys():
    keys = set(json.loads(read("Resources/Localizable.xcstrings"))["strings"])
    fragment = pathlib.Path(FRAGMENT)
    if fragment.is_file():
        keys |= set(json.loads(fragment.read_text()))
    return keys

class OfficialDetailParityChecks(unittest.TestCase):
    def test_view_uses_core_presentation_in_source_order(self):
        view = read("App/OfficialEventDetailView.swift")
        self.assertIn("let presentation = OfficialEventDetailPresentation(event: event, now: Date())", view)
        order = ["OfficialEventCard(event: event)", "OfficialDetailID.organizer", 'Section("official.facts")',
                 "OfficialDetailID.overview", "presentation.storyDetail", "presentation.cards",
                 '"official.detailParity.tasks.heading"', '"official.detailParity.rewards.heading"',
                 '"official.collective"', "OfficialDetailID.rewardFootnote", "presentation.cta.key"]
        positions = [view.index(marker) for marker in order]
        self.assertEqual(positions, sorted(positions))
        model = read("Core/OfficialEventDetailPresentation.swift")
        for marker in ['"city_light"', '"merchant_hunt"', '"ROAM_POI_ARRIVAL"', '"EVENT_POINT_ARRIVAL"',
                       '"THEME_VERIFIED_FINISH"', '"ROAM_SESSION_AREA"', '"Asia/Shanghai"', "if let status, status >= 5 { return .ended }"]:
            self.assertIn(marker, model)
        for forbidden in ["URLSession", "httpMethod", "NavigationLink", "openURL"]:
            self.assertNotIn(forbidden, model)

    def test_locked_identifiers_price_row_and_actions_survive(self):
        view = read("App/OfficialEventDetailView.swift")
        for required in ['.accessibilityLabel(Text("official.price"))', '.accessibilityValue(Text("official.priceNotProvided"))',
                         '.accessibilityIdentifier("official.price")', '.accessibilityIdentifier("official.detail.content")',
                         '.accessibilityIdentifier("official.participationState")', '"official.mission.\\(mission.index)"',
                         "OfficialParticipationActions(coordinator: actions, event: event, onReturn: {",
                         "lease.permits(eventID: id, scope: reader.scope, visit: visit,", "readback = UUID()",
                         "reader.isAuthenticated ? event.participationKey : event.statusKey"]:
            self.assertIn(required, view)
        self.assertNotIn("recruitmentBlocked", view)

    def test_new_identifiers_use_detail_prefix(self):
        view = read("App/OfficialEventDetailView.swift")
        self.assertIn('private static func leaf(_ name: String) -> String { "official.detail" + "." + name }', view)
        for leaf in ["organizer", "facts", "overview", "story", "cards", "tasks", "rewards", "collective",
                     "rewardFootnote", "cta", "unavailable", "backToList", "network"]:
            self.assertIn(f'leaf("{leaf}")', view)
        for use in ["OfficialDetailID.facts", "OfficialDetailID.cta", "identifier: OfficialDetailID.unavailable",
                    "backIdentifier: OfficialDetailID.backToList"]:
            self.assertIn(use, view)

    def test_unavailable_exits_while_other_failures_keep_retry(self):
        view = read("App/OfficialEventDetailView.swift")
        self.assertIn("@Environment(\\.dismiss) private var dismiss", view)
        self.assertIn("issueCopy: OfficialEventDetailView.issueCopy, onBack: { dismiss() },", view)
        self.assertIn("switch OfficialDetailLoadFailure(error) {", view)
        screen = read("App/OfficialEventComponents.swift")
        self.assertIn("var issueCopy: ((Error) -> OfficialIssueCopy?)? = nil", screen)
        self.assertIn("var onBack: (() -> Void)? = nil", screen)
        self.assertIn("copy = issueCopy?(error)", screen)
        self.assertIn('} else if case .failed = issue, let retry {', screen)
        self.assertIn("} else if case .unavailable = issue, let onBack, let copy, let backTitle = copy.backTitle {", screen)
        service = read("Core/OfficialEventService.swift")
        self.assertIn("if missingEvent && (status == 404 || status == 410) { throw OfficialReadFailure.unavailable }", service)
        self.assertIn("if missingEvent && (code == 404 || code == 410", service)
        self.assertIn('== "活动不存在") { throw OfficialReadFailure.unavailable }', service)

    def test_cta_is_a_label_not_navigation(self):
        view = read("App/OfficialEventDetailView.swift")
        cta = view[view.index("Text(LocalizedStringKey(presentation.cta.key))") - 400:view.index("OfficialDetailID.cta)")]
        for forbidden in ["Button(", "NavigationLink", "onTapGesture", "openURL"]:
            self.assertNotIn(forbidden, cta)

    def test_every_detail_parity_key_is_catalogued_with_two_languages(self):
        known = known_keys()
        used = set()
        for path in list((ROOT / "App").glob("Official*.swift")) + list((ROOT / "Core").glob("Official*.swift")):
            for literal in re.findall(r'"(official\.detailParity\.[^"\n]*)"', path.read_text()):
                key = re.sub(r"\\\((count|number|index)\)", "%lld", literal)
                used.add(re.sub(r"\\\([A-Za-z.]+\)", "%@", key))
        self.assertGreater(len(used), 60)
        self.assertFalse(used - known, sorted(used - known))
        fragment = pathlib.Path(FRAGMENT)
        if fragment.is_file():
            for key, value in json.loads(fragment.read_text()).items():
                self.assertTrue(key.isascii(), key)
                self.assertTrue(value["en"] and value["zh-Hans"], key)

if __name__ == "__main__":
    unittest.main(verbosity=2)
