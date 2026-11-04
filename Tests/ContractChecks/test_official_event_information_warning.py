"""Native source contracts only; not Swift compilation, UI, or live-service evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class OfficialEventInformationWarningChecks(unittest.TestCase):
    def test_decoding_uses_only_strict_optional_source_fields(self):
        model = read("Core/OfficialEventContracts.swift")
        self.assertIn("public let recruitmentBlocked: Bool?", model)
        self.assertIn("public let recruitmentBlockedReason: String?", model)
        self.assertIn('recruitmentBlocked = c.flag("recruitmentBlocked")', model)
        self.assertIn('recruitmentBlockedReason = c.text("recruitmentBlockedReason")', model)
        self.assertIn('func flag(_ key: String) -> Bool? { try? decode(Bool.self', model)
        self.assertIn('func text(_ key: String) -> String? { try? decode(String.self', model)
        reason = model.split("public var recruitmentWarningReason: String? {", 1)[1].split("public init(from decoder:", 1)[0]
        self.assertIn("guard recruitmentBlocked == true", reason)
        self.assertIn("trimmingCharacters(in: .whitespacesAndNewlines)", reason)
        self.assertIn("!reason.isEmpty else { return nil }", reason)

    def test_card_has_explicit_true_gate_verbatim_reason_and_unknown_fallback(self):
        card = read("App/OfficialEventComponents.swift").split("struct OfficialEventCard: View", 1)[1].split("struct OfficialEventTimeValue", 1)[0]
        self.assertIn("if event.recruitmentBlocked == true {", card)
        self.assertIn('Label("official.informationIncomplete", systemImage: "exclamationmark.triangle")', card)
        self.assertIn("if let reason = event.recruitmentWarningReason { Text(verbatim: reason) }", card)
        self.assertIn('else { Text("official.informationReasonUnknown") }', card)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", card)
        self.assertIn(".accessibilityElement(children: .combine)", card)
        for forbidden in ["Button(", "Link(", ".task", ".onChange", "lineLimit(1)", "LocalizedStringKey(reason)"]:
            self.assertNotIn(forbidden, card)

    def test_warning_is_not_an_availability_or_action_input(self):
        model = read("Core/OfficialEventContracts.swift")
        for section in [model.split("public var statusKey:", 1)[1],
                        read("Core/OfficialEventService.swift"), read("Core/OfficialEventReading.swift"),
                        read("App/OfficialEventsBrowserView.swift"), read("App/OfficialEventDetailView.swift")]:
            self.assertNotIn("recruitmentBlocked", section)
            self.assertNotIn("recruitmentWarningReason", section)
        for path in (ROOT / "Core").glob("Official*Action*.swift"):
            self.assertNotIn("recruitmentBlocked", path.read_text())

    def test_original_bilingual_copy_makes_no_unsupplied_reason_claim(self):
        strings = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        expected = {
            "official.informationIncomplete": ("Information incomplete", "信息不全"),
            "official.informationReasonUnknown": ("Reason not provided by the source", "来源未提供原因"),
        }
        for key, values in expected.items():
            for language, value in zip(["en", "zh-Hans"], values):
                self.assertEqual(strings[key]["localizations"][language]["stringUnit"]["value"], value)
        # The old module snapshot remains an exact contract for all historic copy.
        historical = json.loads(read("docs/official-event-localizations.json"))["strings"]
        for key, value in historical.items():
            self.assertEqual(strings[key], value)

    def test_warning_fixtures_are_synthetic_and_have_strict_marker_variants(self):
        source = read("App/OfficialEventFixtureSupport.swift")
        matches = re.findall(r'case \.(warning\w+): warningFields = #"(.*?)"#', source)
        self.assertEqual(len(matches), 5)
        records = {name: json.loads('{"id":71,"title":"Synthetic event information","status":3' + fields + '}')
                   for name, fields in matches}
        self.assertIs(records["warningKnown"]["recruitmentBlocked"], True)
        self.assertIs(records["warningUnknown"]["recruitmentBlocked"], True)
        self.assertFalse(records["warningUnknown"]["recruitmentBlockedReason"].strip())
        self.assertNotIn("recruitmentBlocked", records["warningAbsent"])
        self.assertIs(records["warningFalse"]["recruitmentBlocked"], False)
        self.assertEqual(records["warningMalformed"]["recruitmentBlocked"], "true")
        for record in records.values():
            self.assertEqual(record["id"], 71)
            self.assertNotIn("https://", json.dumps(record))

    def test_authored_domain_and_ui_coverage_is_present_but_not_execution(self):
        core = read("Tests/CoreTests/OfficialEventTests.swift")
        for name in ["testInformationWarningFieldsAreStrictOptionalServerFacts",
                     "testExplicitInformationWarningTrimsOnlyOuterReasonWhitespace",
                     "testMissingBlankOrMalformedWarningReasonNeverInventsExplanation",
                     "testReasonAloneAndUnrelatedFlagsCannotCreateInformationWarning",
                     "testInformationWarningCannotChangeEventIdentityStatusOrParticipation",
                     "testPublicReadKeepsMarkedRowsAndExistingDuplicateIdentityRules"]:
            self.assertIn("func " + name + "(", core)
        ui = read("Tests/AppUITests/OfficialEventFlowTests.swift")
        for name in ["testExplicitInformationWarningKeepsEventOpenableAfterBackAndScopeChange",
                     "testBlankWarningReasonUsesHonestChineseFallbackAtLargeText",
                     "testAbsentFalseAndMalformedMarkersNeverShowWarningFromReasonAlone"]:
            self.assertIn("func " + name + "(", ui)


if __name__ == "__main__":
    unittest.main(verbosity=2)
