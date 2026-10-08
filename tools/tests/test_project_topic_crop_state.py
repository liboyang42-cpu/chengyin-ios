"""Source-only CI137 regression; does not compile Swift or execute the crop UI."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEFAULTS = {'horizontal': '0.5', 'vertical': '0.5', 'zoom': '1.0'}


def independent_crop_state(source):
    # Each complete declaration must carry its own property wrapper. Matching
    # the whole line deliberately rejects comma-separated additional bindings.
    return all(re.search(r'(?m)^[ \t]*@State[ \t]+private[ \t]+var[ \t]+'
                         + name + r'[ \t]*=[ \t]*' + re.escape(value)
                         + r'[ \t]*$', source)
               for name, value in DEFAULTS.items())


class ProjectTopicCropStateTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / 'App/ProjectTopicMediaHost.swift').read_text()
        self.crop = source.split('private struct ProjectTopicImageCropControls: View {', 1)[1]
        self.crop = self.crop.split('/// Exact topic-specific multipart route.', 1)[0]

    def test_crop_parameters_have_independent_wrappers_and_original_defaults(self):
        self.assertTrue(independent_crop_state(self.crop))
        self.assertEqual(len(re.findall(r'@State\b', self.crop)), 3)

    def test_original_multi_binding_regression_is_rejected(self):
        mutant = self.crop
        for name, value in DEFAULTS.items():
            mutant = mutant.replace(f'@State private var {name} = {value}', '')
        mutant = '@State private var horizontal = 0.5, vertical = 0.5, zoom = 1.0\n' + mutant
        self.assertFalse(independent_crop_state(mutant))

    def test_sliders_and_crop_rect_still_use_the_same_independent_state(self):
        for name, limits in [('horizontal', '0...1'), ('vertical', '0...1'), ('zoom', '1...4')]:
            self.assertIn(f'Slider(value: ${name}, in: {limits})', self.crop)
            self.assertIn(f'{name}: {name}', self.crop)


if __name__ == '__main__':
    unittest.main()
