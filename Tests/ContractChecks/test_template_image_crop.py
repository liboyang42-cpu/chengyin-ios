"""Dormant component guardrails. These do not execute Swift, UIKit, or Xcode."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP_FILES = ["TemplateImageCropRenderer.swift", "TemplateImageCropSession.swift", "TemplateImageCropView.swift"]


class TemplateImageCropContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_source_aspect_geometry_is_not_merchant_or_independent_edge_editing(self):
        source = self.read("Core/TemplateImageCrop.swift")
        for text in ["width = Double(sourceWidth) / zoom", "height = Double(sourceHeight) / zoom",
                     "(Double(sourceWidth) - width) * horizontal", "(Double(sourceHeight) - height) * vertical",
                     "horizontal.isFinite", "vertical.isFinite", "zoom.isFinite", "(1...4).contains(zoom)",
                     "maximumOutputEdge = 1440", "max(1, Int((dimension * scale).rounded()))"]:
            self.assertIn(text, source)
        for text in ["aspect:", "setLeft", "setRight", "setTop", "setBottom", "widthUnits"]:
            self.assertNotIn(text, source)

    def test_identity_keeps_bytes_and_renderer_checks_exact_source(self):
        source = self.read("App/TemplateImageCropRenderer.swift")
        render = source.split("static func render", 1)[1]
        self.assertLess(render.index("if rect.isIdentity { return source }"), render.index("let output = draw"))
        for text in ["image.imageOrientation == .up", "pixels.width == source.width", "pixels.height == source.height",
                     "rect.sourceWidth == source.width", "rect.sourceHeight == source.height",
                     "format.scale = 1", "format.opaque = true", "UIColor.white.setFill()",
                     "bytes.count <= RetainedSelectedImage.maximumBytes", "CGFloat(rect.width)"]:
            self.assertIn(text, source)
        self.assertNotIn("pixels.cropping(", source)

    def test_cancel_keeps_prior_selection_and_old_callbacks_are_fenced(self):
        source = self.read("App/TemplateImageCropSession.swift")
        cancel = source.split("func cancel(id:", 1)[1].split("func invalidate()", 1)[0]
        self.assertIn("draft?.id == id", cancel)
        self.assertIn("draft = nil; failed = false", cancel)
        self.assertNotIn("selection =", cancel)
        for text in ["candidate.id == id", "guard checkCurrent()", "active = false", "selection = nil",
                     "guard active else { return false }", "guard isCurrent() else { invalidate(); return false }"]:
            self.assertIn(text, source)

    def test_bounded_local_host_has_no_upload_or_target_mutation(self):
        source = "\n".join(self.read("App/" + name) for name in APP_FILES)
        for text in ["URLSession", "HTTPTransport", "upload(", "uploads.", "PHPicker", "UserDefaults",
                     "TemplateAuthoringMedia", "RetainedImageScope", "requestAuthorization", "fileURL", "https://"]:
            self.assertNotIn(text, source)
        for path in (ROOT / "App").glob("*.swift"):
            if path.name not in APP_FILES + ["TemplateMediaReviewController.swift", "TemplateMediaReviewPanel.swift"]:
                self.assertNotIn("TemplateImageCrop", path.read_text(), str(path))
        host = self.read("App/TemplateMediaReviewController.swift")
        for forbidden in ["upload(", "TemplateAuthoringAdapter", "URLSession", "ImageUploadJournal", "RetainedUploadedImage"]:
            self.assertNotIn(forbidden, host)
        self.assertIn('imageSelectionApproved: @escaping () -> Bool = { false }', host)
        self.assertIn('TemplateImageCropSession(isCurrent:', host)
        project = self.read("Questify.xcodeproj/project.pbxproj")
        # Project registration permits compilation, not production mounting.
        for path in [*("App/" + name for name in APP_FILES), "Core/TemplateImageCrop.swift",
                     "Tests/AppUnitTests/TemplateImageCropAppTests.swift"]:
            self.assertEqual(project.count('"path" = "' + path + '";'), 1, path)

    def test_view_reset_dismissal_and_accessible_pan_zoom(self):
        source = self.read("App/TemplateImageCropView.swift")
        for text in [".id(draft.id)", ".onDisappear { cancel(draft.id) }", "confirm(draft.id, rect)",
                     ".aspectRatio(CGFloat(draft.source.width) / CGFloat(draft.source.height), contentMode: .fit)",
                     "horizontal = 0.5; vertical = 0.5; zoom = 1", ".disabled(zoom == 1)",
                     'accessibilityIdentifier("template.imageCrop.horizontal")',
                     'accessibilityIdentifier("template.imageCrop.vertical")',
                     'accessibilityIdentifier("template.imageCrop.zoom")']:
            self.assertIn(text, source)

    def test_dormant_bilingual_fragment_and_reused_labels(self):
        fragment = json.loads(self.read("Resources/TemplateImageCropLocalizations.fragment.json"))["strings"]
        self.assertEqual(set(fragment), {"template.imageCrop." + key for key in ["title", "localOnly", "reset", "confirm"]})
        for entry in fragment.values():
            for language in ["en", "zh-Hans"]:
                self.assertTrue(entry["localizations"][language]["stringUnit"]["value"])
        catalog = json.loads(self.read("Resources/Localizable.xcstrings"))["strings"]
        mounted = set(fragment).intersection(catalog)
        self.assertIn(mounted, [set(), set(fragment)], "Central integration must merge the complete reviewed fragment")
        for key in mounted: self.assertEqual(catalog[key], fragment[key])
        for key in ["image.crop.preview", "image.crop.horizontal", "image.crop.vertical", "image.crop.zoom",
                    "image.retained.failed", "image.retained.cancel"]:
            for language in ["en", "zh-Hans"]:
                self.assertTrue(catalog[key]["localizations"][language]["stringUnit"]["value"])

    def test_authored_tests_cover_geometry_rendering_and_interruption(self):
        core = self.read("Tests/CoreTests/TemplateImageCropTests.swift")
        app = self.read("Tests/AppUnitTests/TemplateImageCropAppTests.swift")
        self.assertEqual(core.count("func test"), 9)
        self.assertEqual(app.count("func test"), 10)
        for token in ["testIdentityReturnsSameIDAndExactSanitizedBytesForAllEXIFOrientations",
                      "testPanChoosesDifferentPixelsAndPreviewMatchesExportDimensions",
                      "testWrongSourceDimensionsMalformedBytesAndNonUprightInputFailClosed",
                      "testCancelPreservesPreviousSelectionAndDelayedConfirmationCannotReplaceIt",
                      "testReplacingCandidateRejectsOldConfirmAndOldDismissal",
                      "testScopeChangeAndExplicitInvalidationReleaseAllBytesAndStayTerminal"]:
            self.assertIn(token, app)



if __name__ == "__main__":
    unittest.main()
