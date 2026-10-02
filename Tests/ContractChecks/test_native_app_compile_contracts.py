"""Source regressions for compiler-diagnosed adapter and localization boundaries."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeAppCompileContracts(unittest.TestCase):
    def test_audio_completion_is_consumed_before_optional_invocation(self):
        source = (ROOT / 'App/NativePlatformAdapters.swift').read_text()
        body = source.split('didCompleteWithError error: Error?) {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('let callback = completion; completion = nil', body)
        self.assertIn('callback?(error == nil && !bytes.isEmpty ? bytes : nil)', body)
        self.assertLess(body.index('completion = nil'), body.index('callback?('))
        self.assertIn('session.finishTasksAndInvalidate()', body)
        self.assertNotIn('callback!', body)

    def test_integer_badge_axes_are_converted_to_localization_suffixes(self):
        source = (ROOT / 'App/ObjectBadgeViews.swift').read_text()
        self.assertIn('"objects.track." + String(track)', source)
        self.assertIn('"objects.rarity." + String(parameters.rarity)', source)
        self.assertNotIn('"objects.track." + (track)', source)
        self.assertNotIn('"objects.rarity." + (parameters.rarity)', source)


if __name__ == '__main__':
    unittest.main()
