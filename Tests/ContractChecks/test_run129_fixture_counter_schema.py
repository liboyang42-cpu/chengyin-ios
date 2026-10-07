"""Source controls complement the authored real synthetic-client AppUnit checks."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def verify(source):
    assert source.startswith('#if DEBUG\n') and source.rstrip().endswith('#endif')
    assert '"storyImageUploadCount": image?.uploadCount ?? 0' in source
    assert '"storyAudioUploadCount": audio?.uploadCount ?? 0' in source
    assert 'snapshot(image: storyImageSource, audio: storyAudioSource)' in source
    assert 'for (key, count) in ProjectStoryMediaFixtureCounters.snapshot' in source
    assert '{ payload[key] = count }' in source
    assert 'if let source = storyAudioSource { payload["storyAudioReference"] = source.reference }' in source
    assert 'if let source = storyImageSource { payload["storyImageReference"] = source.reference }' in source


class Run129FixtureCounterSchema(unittest.TestCase):
    def source(self): return (ROOT / 'App/ProjectEditFixtureSupport.swift').read_text()

    def test_closed_debug_snapshot_reads_actual_optional_sources(self):
        verify(self.source())

    def test_constant_zero_or_swapped_or_missing_source_is_rejected(self):
        source = self.source()
        for before, after in [('image?.uploadCount ?? 0', '0'),
                              ('audio?.uploadCount ?? 0', '0'),
                              ('image: storyImageSource', 'image: nil'),
                              ('audio: storyAudioSource', 'audio: nil'),
                              ('payload[key] = count', 'payload[key] = 0')]:
            with self.subTest(before=before):
                with self.assertRaises(AssertionError): verify(source.replace(before, after, 1))

    def test_both_nil_directions_and_nonzero_actual_uploads_are_authored(self):
        tests = (ROOT / 'Tests/AppUnitTests/ProjectStoryFixtureCounterTests.swift').read_text()
        self.assertEqual(tests.count('func test'), 3)
        for token in ['decoded(image: nil, audio: nil)', 'decoded(image: source, audio: nil)',
                      'decoded(image: nil, audio: source)', 'source.upload(source.picked, attemptID: UUID(), session: session)',
                      'counts.storyImageUploadCount, 1', 'counts.storyAudioUploadCount, expected',
                      'source.wire.requests.count, expected']:
            self.assertIn(token, tests)
        self.assertNotIn('URLSession', tests)

    def test_existing_ui_decode_and_cross_media_zero_assertions_stay_strict(self):
        ui = (ROOT / 'Tests/AppUITests/ProjectStoryMediaGapFlowSupport.swift').read_text()
        self.assertIn('storyImageUploadCount: Int, storyAudioUploadCount: Int', ui)
        self.assertNotIn('storyImageUploadCount: Int?', ui)
        self.assertNotIn('storyAudioUploadCount: Int?', ui)
        self.assertIn('XCTAssertEqual(saved.storyImageUploadCount, 0)', ui)
        self.assertIn('XCTAssertEqual(saved.storyAudioUploadCount, number + 1)', ui)


if __name__ == '__main__': unittest.main()
