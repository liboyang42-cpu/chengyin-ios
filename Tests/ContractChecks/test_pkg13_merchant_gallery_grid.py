from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Pkg13MerchantGalleryGridContracts(unittest.TestCase):
    def read(self, rel: str) -> str:
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_three_by_three_slot_layout_and_can_remove_guard(self):
        grid = self.read("App/MerchantGalleryGrid.swift")
        self.assertIn("struct MerchantGalleryGridLayout: Equatable", grid)
        self.assertIn("static let columns = 3", grid)
        self.assertIn("static let capacity = 9", grid)
        self.assertIn("static func canRemove(index: Int, in gallery: [String]) -> Bool", grid)
        self.assertIn('.accessibilityIdentifier("merchant.operations.gallery.grid")', grid)
        self.assertIn('.accessibilityIdentifier("merchant.operations.gallery.slot." + String(index))', grid)
        self.assertIn('.accessibilityIdentifier("merchant.operations.gallery.empty." + String(index))', grid)
        self.assertIn('.accessibilityIdentifier("merchant.operations.gallery.remove." + String(index))', grid)
        for forbidden in ["URLSession", "https://", "http://", "api/merchant/"]:
            self.assertNotIn(forbidden, grid)

    def test_editor_wires_merchant_gallery_grid_and_removal_guard(self):
        editor = self.read("App/MerchantOperationsEditor.swift")
        self.assertIn("MerchantGalleryGrid(gallery: value.gallery, isExample: isExample)", editor)
        self.assertIn("MerchantGalleryGridLayout.canRemove(index: index, in: value.gallery)", editor)
        self.assertIn('value.gallery.remove(at: index); model.edit(.gallery(value))', editor)


if __name__ == "__main__":
    unittest.main()
