"""Source guards for the reform plan v9 world/market/game-state client contracts (agent H).

These contracts are client-side proposals awaiting reviewed server APIs. The guards
keep them offline (no transport, no endpoint strings), default-disabled, and free of
invented business values. They do not compile Swift or run XCTest.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = {
    "ReformWorldCapabilities": "CapabilitiesAreAllDisabledByDefault",
    "ThemeSeasonRelease": "RunStaysPinnedWhenNewReleasePublishes",
    "PublishMediaChain": "VideoWalksEveryStageInOrderWithMatchingReadbacks",
    "RunAuthorityContract": "UnknownResultKeepsPendingAndSameRequestRetries",
    "QmodManifestContract": "H5StaysDesignOnlyAndAuthorityFieldsAreRejected",
    "WorkshopModUpgradeChoice": "UpgradeDraftNeedsExplicitConfirmationAndKnownCoverage",
    "RevokeWinsLedger": "RevokeBeatsLateAcceptAndRestoredCache",
    "BeijingDeadlineDisplay": "HintUsesServerOffsetNotDeviceClock",
    "FriendMultiInvite": "PartialFailureRetriesOnlyFailedWithStableRequestIds",
    "TeamFirstMeeting": "MeetingRequiresServerConfirmedTeamAndRealNameOnlyHere",
    "HomeReturnRestore": "RestoreReceiptNeverExceedsServerMaximum",
    "CityActionContract": "PaidActionNeedsExplicitConsentFromThePayerThemself",
    "CityDeltaStream": "DeltaStreamDedupesReordersAndRefetchesOnGap",
}


def source(name):
    return (ROOT / "Core" / f"{name}.swift").read_text(encoding="utf-8")


class ReformWorldContractGuards(unittest.TestCase):
    def test_files_are_in_project_and_have_core_tests(self):
        project = (ROOT / "Questify.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        tests = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "Tests/CoreTests").glob("*.swift"))
        for name, test in CORE.items():
            self.assertIn(f'"Core/{name}.swift"', project, name)
            self.assertIn(f"func test{test}()", tests, name)

    def test_contracts_perform_no_io_and_name_no_endpoint(self):
        for name in CORE:
            # Doc comments may cite existing mini-program/read routes; code lines may not.
            text = "\n".join(line for line in source(name).splitlines() if not line.lstrip().startswith("//"))
            for forbidden in ("URLRequest", "URLSession", "HTTPTransport", "transport.send", "api/", "http://", "https://"):
                self.assertNotIn(forbidden, text, f"{name}: {forbidden}")

    def test_capabilities_start_disabled_and_nfc_cannot_be_enabled(self):
        text = source("ReformWorldCapabilities")
        self.assertIn("public static let disabled = ReformWorldCapabilities(enabled: [])", text)
        self.assertIn("private init(enabled:", text)
        self.assertRegex(text, r"#if DEBUG\s+/// Offline fixtures and Core tests only\.")
        self.assertIn("features.subtracting([.meetingNFC])", text)

    def test_h5_is_design_only_and_limits_are_labelled_proposals(self):
        text = source("QmodManifestContract")
        self.assertIn('if kind == "questify.h5" { throw QmodManifestIssue.h5DesignOnly }', text)
        self.assertIn('kind == "questify.mod"', text)
        self.assertIn("isProposal: true", text)
        for field in ("reviewed", "approved", "ownerRole", "rewardBudget"):
            self.assertIn(f'"{field}"', text)

    def test_city_actions_use_existing_points_and_explicit_payer(self):
        text = source("CityActionContract")
        self.assertIn("memberPointsCost", text)
        self.assertNotRegex(text, r"(?i)city\s*coin|cityCurrency|teamWallet|城市币")
        self.assertIn("guard quote.payerMemberId == confirmingMemberId else { throw CityActionIssue.payerMismatch }", text)
        body = re.search(r"public func body\(\) throws -> Data \{(.*?)\n    \}", text, re.S).group(1)
        for value in ("memberPointsCost", "actionCost", "dice", "reward"):
            self.assertNotIn(value, body)

    def test_no_invented_business_defaults(self):
        media = source("PublishMediaChain")
        self.assertNotRegex(media, r"static let \w+ = PublishMediaProfile")
        home = source("HomeReturnRestore")
        self.assertNotRegex(home, r"maxAccuracyMeters:\s*[0-9]")
        invite = source("FriendMultiInvite")
        self.assertNotRegex(invite, r"maximum: Int = [0-9]")

    def test_private_home_values_stay_redacted(self):
        text = source("HomeReturnRestore")
        self.assertIn('"HomeReturnCheck[redacted]"', text)
        self.assertNotIn("latitude", text)
        self.assertNotIn("longitude", text)

    def test_meeting_never_carries_coordinates_and_real_name_is_scoped(self):
        text = source("TeamFirstMeeting")
        self.assertNotRegex(text, r"(?i)latitude|longitude|coordinate:")
        self.assertIn("public static func requiresRealName(_ flow: Flow) -> Bool { flow == .strangerTeamMeeting }", text)
        self.assertIn('formation == "CONFIRMED"', text)


if __name__ == "__main__":
    unittest.main()
