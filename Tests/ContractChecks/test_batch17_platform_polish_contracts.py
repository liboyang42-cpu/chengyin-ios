"""Source guards for Batch 17 platform polish contracts and SwiftUI section views:
- App Clip & QR code handshake parity
- WebView & External Safari sandbox safety
- Localization plural & formatter consistency
- Device orientation & Split View adaptation
"""
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH17_CORE_TYPES = {
    "Core/AppClipAndQRCodeHandshakeParityAudit.swift": "AppClipAndQRCodeHandshakeParityAudit",
    "Core/WebViewAndExternalSafariSandboxAudit.swift": "WebViewAndExternalSafariSandboxAudit",
    "Core/LocalizationPluralAndFormatterConsistencyAudit.swift": "LocalizationPluralAndFormatterConsistencyAudit",
    "Core/DeviceOrientationAndSplitViewAdaptationAudit.swift": "DeviceOrientationAndSplitViewAdaptationAudit",
}

BATCH17_APP_VIEWS = {
    "App/AppClipAndQRCodeHandshakeSectionView.swift": "AppClipAndQRCodeHandshakeSectionView",
    "App/WebViewAndExternalSafariSandboxSectionView.swift": "WebViewAndExternalSafariSandboxSectionView",
    "App/LocalizationPluralAndFormatterConsistencySectionView.swift": "LocalizationPluralAndFormatterConsistencySectionView",
    "App/DeviceOrientationAndSplitViewAdaptationSectionView.swift": "DeviceOrientationAndSplitViewAdaptationSectionView",
}

BATCH17_CORE_TESTS = {
    "Tests/CoreTests/AppClipAndQRCodeHandshakeParityAuditTests.swift": "AppClipAndQRCodeHandshakeParityAuditTests",
    "Tests/CoreTests/WebViewAndExternalSafariSandboxAuditTests.swift": "WebViewAndExternalSafariSandboxAuditTests",
    "Tests/CoreTests/LocalizationPluralAndFormatterConsistencyAuditTests.swift": "LocalizationPluralAndFormatterConsistencyAuditTests",
    "Tests/CoreTests/DeviceOrientationAndSplitViewAdaptationAuditTests.swift": "DeviceOrientationAndSplitViewAdaptationAuditTests",
}

BATCH17_APP_UNIT_TESTS = {
    "Tests/AppUnitTests/AppClipAndQRCodeHandshakeSectionViewTests.swift": "AppClipAndQRCodeHandshakeSectionViewTests",
    "Tests/AppUnitTests/WebViewAndExternalSafariSandboxSectionViewTests.swift": "WebViewAndExternalSafariSandboxSectionViewTests",
    "Tests/AppUnitTests/LocalizationPluralAndFormatterConsistencySectionViewTests.swift": "LocalizationPluralAndFormatterConsistencySectionViewTests",
    "Tests/AppUnitTests/DeviceOrientationAndSplitViewAdaptationSectionViewTests.swift": "DeviceOrientationAndSplitViewAdaptationSectionViewTests",
}


class Batch17PlatformPolishContractTests(unittest.TestCase):
    def test_batch17_core_audits_exist_and_expose_public_types(self):
        for rel_path, symbol in BATCH17_CORE_TYPES.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing Core file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import Foundation", content, rel_path)
            self.assertIn(symbol, content, rel_path)
            self.assertIn("Sendable", content, rel_path)
            self.assertIn("Equatable", content, rel_path)

    def test_batch17_app_section_views_exist_and_use_text_verbatim_discipline(self):
        for rel_path, view_symbol in BATCH17_APP_VIEWS.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing App view file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, rel_path)
            self.assertIn(f"public struct {view_symbol}: View", content, rel_path)
            self.assertIn("Text(verbatim:", content, rel_path)
            self.assertIn(".accessibilityIdentifier(", content, rel_path)

    def test_batch17_core_tests_and_app_unit_tests_exist(self):
        for rel_path, test_class in {**BATCH17_CORE_TESTS, **BATCH17_APP_UNIT_TESTS}.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing test file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import XCTest", content, rel_path)
            self.assertIn(f"final class {test_class}: XCTestCase", content, rel_path)
            self.assertIn("func test", content, rel_path)


if __name__ == "__main__":
    unittest.main()
