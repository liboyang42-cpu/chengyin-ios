"""Hosted scene/fixture contract only. Does not execute UIKit or establish a CI pass."""
from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
COOP = ROOT / "Tests/AppUnitTests/CoopRelationPresentationOwnerTests.swift"
PAID = ROOT / "Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift"
OWNED = ROOT / "Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift"


def original_owned_scene_source(source, helper_source=None):
    """Reverse only the approved fixture-host delta for the immutable run129 guard."""
    digest = lambda value: hashlib.sha256(value.encode()).hexdigest()
    assert digest(source) == "7be3ed17a629baba13dbe47300b2d4dca13d31117ee18d2588a520e591c2b361", "Owned postimage changed"
    if helper_source is None:
        helper_source = PAID.read_text().split("@MainActor enum WorkshopPurchasedAppFixture")[0]
    assert digest(helper_source) == "ef17e7ca3b0d8253677ef5374d21f2aee56c0eb0619eff9b5db219e229581934", "Scene helper changed"
    replacements = [
        (
            "        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window\n"
            "        window.rootViewController = host; window.makeKeyAndVisible()\n"
            "        defer { sceneWindow.retire() }\n",
            "        let window = UIWindow(frame:UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()\n"
            "        defer { window.isHidden = true; window.rootViewController = nil }\n",
        ),
        (
            "        XCTAssertTrue(host.view.window === window)\n"
            "        XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)\n",
            "",
        ),
    ]
    for after, before in replacements:
        assert source.count(after) == 1, "The exact scene-only fixture hunk must occur once"
        source = source.replace(after, before, 1)
    assert digest(source) == "36d9d15040ca678a5220cd0a399323c478f37f752a73a10e14f20745a6187bec", "Owned preimage changed"
    historical = re.sub(r"(?ms)^#if DEBUG\n.*?^#endif\n", "", source)
    assert digest(historical) == "fa5f26ef28dba62ec36c8f78b45fd9fee5f946277c8eb5a1dab11cf93b3d499e", "Historical assertions/actions changed"
    return source


class HostedNavigationSceneChecks(unittest.TestCase):
    def test_owned_fixture_normalization_accepts_only_exact_scene_hunks(self):
        source = OWNED.read_text()
        restored = original_owned_scene_source(source)
        self.assertNotIn("HostedNavigationSceneWindow", restored)
        hunks = [
            "        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window\n"
            "        window.rootViewController = host; window.makeKeyAndVisible()\n"
            "        defer { sceneWindow.retire() }\n",
            "        XCTAssertTrue(host.view.window === window)\n"
            "        XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)\n",
        ]
        for hunk in hunks:
            for kind, changed in [
                ("missing", source.replace(hunk, "", 1)),
                ("duplicate", source.replace(hunk, hunk + hunk, 1)),
                ("modified", source.replace(hunk, hunk.replace("window", "otherWindow", 1), 1)),
                ("relocated", source.replace(hunk, "", 1) + hunk),
            ]:
                with self.subTest(kind=kind, hunk=hunk), self.assertRaises(AssertionError):
                    original_owned_scene_source(changed)
        assertion = "XCTAssertFalse(f.navigation.listPermit === listPermit)"
        changed = source.replace(assertion, "XCTAssertTrue(true)", 1)
        with self.assertRaises(AssertionError):
            original_owned_scene_source(changed)
        helper = PAID.read_text().split("@MainActor enum WorkshopPurchasedAppFixture")[0]
        with self.assertRaises(AssertionError):
            original_owned_scene_source(source, helper.replace("window.isHidden = true", "window.isHidden = false", 1))
        historical = ROOT / "tools/tests/fixtures/run129_published_sources/WorkshopOwnedNavigationPresentationTests.swift.txt"
        self.assertEqual(hashlib.sha256(historical.read_bytes()).hexdigest(),
                         "fa5f26ef28dba62ec36c8f78b45fd9fee5f946277c8eb5a1dab11cf93b3d499e")

    def test_scene_owner_requires_the_real_foreground_scene_and_restores_its_key_window(self):
        source = PAID.read_text().split("@MainActor final class HostedNavigationSceneWindow {")[1]
        helper = source.split("@MainActor enum WorkshopPurchasedAppFixture")[0]
        for required in ["UIApplication.shared.connectedScenes", ".foregroundActive",
                         "activeScenes.count == 1", "UIWindow(windowScene: selected)",
                         "selected.coordinateSpace.bounds", "window.windowScene = nil",
                         "previousKeyWindow.windowScene === scene", "!previousKeyWindow.isHidden",
                         "previousKeyWindow.windowLevel == .normal",
                         "previousKeyWindow.rootViewController != nil",
                         "scene.windows.contains(where: { $0 === previousKeyWindow })",
                         "previousKeyWindow.makeKey()"]:
            self.assertIn(required, helper)
        for forbidden in ["UIScreen.main", "beginAppearanceTransition", "endAppearanceTransition",
                          "setAnimationsEnabled", "disablesAnimations", "sleep(", "Task {"]:
            self.assertNotIn(forbidden, helper)
        self.assertNotIn("#if DEBUG", PAID.read_text().split("@MainActor enum WorkshopPurchasedAppFixture")[0])

    def test_existing_hosted_cases_use_scene_ownership_and_real_navigation(self):
        cases = [
            (COOP.read_text(), "testHostedCoveredListPopsVisibleProfileAfterAccountReplacement"),
            (PAID.read_text(), "testNormalHostedPurchasedEntryPreservesCanonicalContextForMerchantAndClubAndBackReopen"),
            (OWNED.read_text(), "testHostedListDetailPackageBackAndReopenIssueFreshPermits"),
        ]
        for source, name in cases:
            with self.subTest(case=name):
                case = source.split("func " + name)[1].split("\n    func ")[0]
                for required in ["UIHostingController(rootView:", "NavigationStack",
                                 "try HostedNavigationSceneWindow()", "sceneWindow.retire()",
                                 "host.view.window === window",
                                 "XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)"]:
                    self.assertIn(required, case)
                self.assertNotIn("UIWindow(frame:", case)
                self.assertNotIn("XCTSkip", case)

    def test_original_two_second_bounds_and_authority_assertions_remain(self):
        coop, paid = COOP.read_text(), PAID.read_text()
        for source in (coop, paid, OWNED.read_text()):
            self.assertIn("for _ in 0..<100", source)
            self.assertIn("20_000_000", source)
        for original in [
            "owner.selection == nil && !probe.childVisible && !probe.parentCovered && model.isCurrent(reader: reader)",
            "XCTAssertFalse(owner.isCurrent(old)", "XCTAssertEqual(reader.ownerReads, reads)",
            "XCTAssertTrue(owner.isCurrent(fresh)); XCTAssertFalse(owner.isCurrent(old))",
            "owner.selection == nil && !probe.childVisible", "throw error",
        ]:
            self.assertIn(original, coop)
        for original in [
            "browser.phase == .ready && navigation.listPermit != nil",
            "browser.detail != nil && navigation.detailPermit != nil",
            "navigation.listPermit != nil && browser.phase == .ready",
            'XCTAssertEqual(context,h.strictExpectedContext);XCTAssertEqual(context.session.role,"player")',
            'XCTAssertNil(h.session.workshopOwnedBrowser,"Paid approval cannot enable FREE library")',
            "XCTAssertNil(browser.detail);XCTAssertTrue(browser === h.session.workshopPurchasedBrowser)",
            "throw WorkshopPurchasedIssue.unavailable",
        ]:
            self.assertIn(original, paid)
        owned = OWNED.read_text()
        for original in [
            "f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil",
            "f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil",
            "XCTAssertFalse(f.navigation.detailPermit === detailPermit)",
            "XCTAssertFalse(f.navigation.listPermit === listPermit)",
            "XCTAssertEqual(f.state.unauthorized,0)",
            "guard stageCount < 12",
        ]:
            self.assertIn(original, owned)
        self.assertNotIn("executionTimeAllowance", owned)

    def test_each_purchased_stage_is_identified_without_logging_credentials_or_content(self):
        paid = PAID.read_text()
        for stage in ["initial purchased list ready", "purchased detail ready", "Back restores purchased list"]:
            self.assertIn(stage, paid)
        diagnostic = paid.split("let diagnostic = {")[1].split("\n")[0]
        for forbidden in [".token", "accountID", "licenseId", ".httpBody", ".url"]:
            self.assertNotIn(forbidden, diagnostic)
        self.assertIn("file: file, line: line", paid)


if __name__ == "__main__":
    unittest.main()
