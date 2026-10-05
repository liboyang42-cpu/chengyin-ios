"""Structural guardrails only; Swift/UIKit behavior requires Apple execution."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantImageCropContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_source_backed_ratio_and_no_other_field_grant(self):
        source = self.read('Core/MerchantImageCrop.swift')
        for value in ['case .merchant(_, .logo): return .logo', 'case .merchant(_, .coverImage): return .cover',
                      'case .merchant(_, .gallery): return .gallery', 'default: return nil',
                      'case .logo: return 1; case .cover: return 5; case .gallery: return 16',
                      'case .logo: return 1; case .cover: return 3; case .gallery: return 9']:
            self.assertIn(value, source)
    def test_gallery_uses_existing_entry_and_preserves_consumer_boundaries(self):
        editor = self.read('App/MerchantOperationsEditor.swift')
        for value in ['imageControls(.gallery)', 'value.gallery.remove(at: index)', 'value.gallery.count < 9']:
            self.assertIn(value, editor)
        bridge = self.read('Core/RetainedImageConsumerBridges.swift')
        for value in ['scope == expectedScope', 'd.gallery.count < 9', '!d.gallery.contains(value)', 'd.gallery.append(value)']:
            self.assertIn(value, bridge)
        self.assertIn('case .profile, .decor, .gallery, .story: return profileWrite', self.read('Core/MerchantOperationsContracts.swift'))
    def test_gallery_title_and_authored_lifecycle_coverage(self):
        self.assertIn('case .gallery: return "image.crop.gallery"', self.read('App/MerchantImageCropView.swift'))
        app = self.read('Tests/AppUnitTests/MerchantImageCropAppTests.swift')
        for value in ['testGalleryCropReviewReplacementCancelAndLeave',
                      'testGalleryScopeChangeRejectsReviewAndUnknownLocksReplacement',
                      'testGalleryPickerCancellationDropsReplacementWithoutUpload']:
            self.assertIn(value, app)
        entry = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']['image.crop.gallery']
        for language in ['en', 'zh-Hans']:
            self.assertIn('16:9', entry['localizations'][language]['stringUnit']['value'])
    def test_geometry_rejects_nonfinite_and_keeps_bounds(self):
        source = self.read('Core/MerchantImageCrop.swift')
        for value in ['horizontal.isFinite', 'vertical.isFinite', 'zoom.isFinite', '(1...4).contains(zoom)',
                      'RetainedSelectedImage.maximumDimension', 'sourceWidth / aspect.widthUnits',
                      'sourceHeight / aspect.heightUnits', 'sourceWidth - width', 'sourceHeight - height']:
            self.assertIn(value, source)
    def test_confirm_crop_only_prepares_existing_upload_review(self):
        source = self.read('App/RetainedImageSelectionView.swift')
        for value in ['let draft = cropDraft, draft.id == id', 'guard current, !context.uploads.locked',
                      'MerchantImageCropAspect.forDestination(context.scope.destination)',
                      'cropDraft = nil; context.uploads.prepare(cropped, scope: context.scope)',
                      'context.uploads.clear(); cropDraft = nil', '.id(draft.id)',
                      'if phase != .active { model.leave() }', 'if !current { model.leave() }']:
            self.assertIn(value, source)
        crop = source.split('func confirmCrop', 1)[1].split('func cancelCrop', 1)[0]
        self.assertNotIn('uploads.confirm(', crop)
        self.assertNotIn('URLSession', self.read('App/MerchantImageCropView.swift'))
    def test_orientation_and_metadata_boundary_is_preserved(self):
        source = self.read('App/RetainedNativeImagePicker.swift')
        self.assertIn('kCGImageSourceCreateThumbnailWithTransform: true', source)
        crop = self.read('App/MerchantImageCropView.swift')
        for value in ['image.imageOrientation == .up', 'pixels.width == source.width',
                      'pixels.height == source.height', 'UIGraphicsImageRenderer', 'format.scale = 1',
                      'RetainedSelectedImage.maximumBytes', 'UIImage(cgImage: cropped)']:
            self.assertIn(value, crop)
    def test_production_gates_remain_off(self):
        self.assertIn('var nativeSelectionEnabled = false', self.read('App/RetainedImagePresenterHost.swift'))
        self.assertIn('enabled: false, approvedOrigins: []', self.read('App/RetainedImageContextCache.swift'))
        self.assertIn('enabled: Bool = false', self.read('App/RetainedNativeImagePicker.swift'))
    def test_bilingual_controls_and_project_wiring(self):
        fragment = json.loads(self.read('Resources/MerchantImageCropLocalizations.fragment.json'))['strings']
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, entry in fragment.items():
            self.assertEqual(entry, catalog[key])
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        project = self.read('Questify.xcodeproj/project.pbxproj')
        for source in ['App/MerchantImageCropView.swift', 'Core/MerchantImageCrop.swift', 'Tests/AppUnitTests/MerchantImageCropAppTests.swift']:
            self.assertIn(source, project)

if __name__ == '__main__': unittest.main()
