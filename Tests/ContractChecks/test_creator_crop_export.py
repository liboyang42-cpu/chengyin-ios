"""C4 creator crop: MiniCrop reaches the formal template media host locally."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT / p).read_text()

class CreatorCropExportContracts(unittest.TestCase):
    def test_export_preserves_original_and_validates_pixels(self):
        s = read('App/CreatorCropExport.swift')
        for t in ['case .original:', 'return source // Exact retained bytes',
                  'image.imageOrientation == .up', 'pixels.width == source.width',
                  'rect.x + rect.width <= Double(source.width)', 'format.scale = 1',
                  'bytes.count <= RetainedSelectedImage.maximumBytes']:
            self.assertIn(t, s)
        for t in ['URLSession', 'upload(', 'requestAuthorization', 'PHPicker', 'UserDefaults']:
            self.assertNotIn(t, s)

    def test_session_fences_old_draft_and_cancel_keeps_selection(self):
        s = read('App/CreatorCropExportSession.swift')
        for t in ['candidate.id == id', 'results.count == candidate.sources.count',
                  'func cancel(id: UUID)', 'guard active else { return false }',
                  'guard isCurrent() else { invalidate(); return false }']:
            self.assertIn(t, s)
        cancel = s.split('func cancel(id:', 1)[1].split('func invalidate()', 1)[0]
        self.assertNotIn('selections =', cancel)

    def test_formal_host_chain_picker_to_preview(self):
        panel = read('App/TemplateMediaReviewPanel.swift')
        for t in ['CreatorCropExportView(draft: draft', 'controller.confirmCreatorCrop(value.review, id: id, results: results)',
                  'controller.cancelCreatorCrop(value.review, id: id)', 'templateMedia.image']:
            self.assertIn(t, panel)
        c = read('App/TemplateMediaReviewController.swift')
        for t in ['creator.stage([image])', 'imageSelectionApproved()', 'creatorCrop?.selection ?? crop?.selection',
                  'func confirmCreatorCrop', 'func cancelCreatorCrop']:
            self.assertIn(t, c)
        self.assertIn('imageSelectionApproved: @escaping () -> Bool = { false }', c)

    def test_view_binds_draft_and_geometry_contract_unchanged(self):
        v = read('App/CreatorCropExportView.swift')
        for t in ['MiniCropGeometry.presets', 'MiniCropView(images: draft.images', '.id(draft.id)', '.onDisappear { cancel(draft.id) }']:
            self.assertIn(t, v)
        g = read('Tests/CoreTests/MiniCropGeometryTests.swift')
        self.assertEqual(g.count('func test'), 5)
        merchant = read('App/MerchantImageCropView.swift')
        self.assertNotIn('MiniCrop', merchant)
        self.assertNotIn('CreatorCrop', merchant)

    def test_story_host_reuses_export_without_new_picker_or_upload_contract(self):
        s = read('App/ProjectStoryImageAuthorView.swift')
        for t in ['let crop: CreatorCropExportSession', 'self.crop.stage([image])',
                  'CreatorCropExportView(draft: draft', 'model.confirmCrop($0, $1)',
                  'flow.finishPicking(image, original: pickerID)',
                  'self.flow.isCurrent && self.flow.matchesCapturedDraft && self.original.opening.source.permitsPicker(session: self.original.opening.lease.session)',
                  'flow.claimUpload(review)', 'projectStoryImage.localPreview']:
            self.assertIn(t, s)
        for t in ['requestAuthorization', 'PHPhotoLibrary', 'URLSession', 'TemplateImageCropView']:
            self.assertNotIn(t, s)

if __name__ == '__main__': unittest.main()
