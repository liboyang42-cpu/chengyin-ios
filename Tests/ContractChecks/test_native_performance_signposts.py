"""I10 source contracts and synthetic parser checks; not device measurement evidence."""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('signpost_measure', ROOT / 'tools/signpost_measure.py')
measure = importlib.util.module_from_spec(spec); spec.loader.exec_module(measure)

# Shape of an xctrace export: first values carry id=, repeats use ref=. Synthetic only.
SYNTHETIC_EXPORT = '''<?xml version="1.0"?>
<trace-query-result><node><schema name="os-signpost-interval"/>
<row><start-time id="1">10</start-time><duration id="2">4000000</duration>
<subsystem id="3" fmt="Questify.Performance">Questify.Performance</subsystem>
<category id="4" fmt="PointsOfInterest">PointsOfInterest</category><string id="5" fmt="walking.refreshTick">walking.refreshTick</string></row>
<row><start-time id="6">20</start-time><duration id="7">2000000</duration><subsystem ref="3"/><category ref="4"/><string ref="5"/></row>
<row><start-time id="8">30</start-time><duration id="9">9000000</duration><subsystem ref="3"/><category ref="4"/>
<string id="10" fmt="audio.startToPlaying">audio.startToPlaying</string></row>
<row><start-time id="11">40</start-time><duration id="12">1000000</duration>
<subsystem id="13" fmt="com.apple.other">com.apple.other</subsystem><category ref="4"/><string ref="5"/></row>
<row><start-time id="14">50</start-time><duration id="15">1000000</duration><subsystem ref="3"/><category ref="4"/>
<string id="16" fmt="unlisted.name">unlisted.name</string></row>
</node></trace-query-result>'''


class NativePerformanceSignpostContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_script_catalog_matches_core_enum_and_core_test(self):
        names = measure.catalog()
        self.assertEqual(names, ['walking.refreshTick', 'walking.cameraFit', 'playRoute.mapProjection',
                                 'playRoute.cameraFocus', 'image.artworkLoad', 'audio.startToPlaying'])
        core_test = self.read('Tests/CoreTests/NativePerformanceSignpostsTests.swift')
        for name in names:
            self.assertIn(f'"{name}"', core_test)
            self.assertEqual(self.read('Core/NativePerformanceSignposts.swift').count(f'"{name}"'), 2)

    def test_points_of_interest_carry_static_names_only(self):
        core = self.read('Core/NativePerformanceSignposts.swift')
        self.assertIn('category: .pointsOfInterest', core)
        self.assertIn('var signpostName: StaticString', core)
        for forbidden in ['OSSignposter.Message', '"\\(', 'emitEvent(', 'URL', 'token', 'accountID', 'latitude']:
            self.assertNotIn(forbidden, core.split('public enum NativePerformancePoint', 1)[1])

    def test_hot_paths_are_instrumented_and_close_on_every_exit(self):
        hooks = {
            'App/WalkingNavigationView.swift': ['.begin(.walkingRefreshTick)', 'tick.end()', '.begin(.walkingCameraFit)'],
            'App/PlayRouteMapView.swift': ['.measure(.playRouteMapProjection)', '.begin(.playRouteCameraFocus)'],
            'App/QuestifyProgressiveBlurArtwork.swift': ['.begin(.artworkLoad)'],
            'App/NativePlatformAdapters.swift': ['.begin(.audioStartToPlaying)'],
        }
        for path, tokens in hooks.items():
            source = self.read(path)
            for token in tokens:
                self.assertIn(token, source, path)
            for begin in re.findall(r'let (\w+) = NativePerformanceSignposts\.shared\.begin', source):
                self.assertTrue(f'defer {{ {begin}.end() }}' in source or f'{begin}.end()' in source, path)
        audio = self.read('App/NativePlatformAdapters.swift')
        stop = audio.split('    func stop() {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('startInterval?.end(); startInterval = nil', stop)

    def test_map_projection_is_built_once_per_render(self):
        source = self.read('App/PlayRouteMapView.swift')
        body = source.split('private func map(', 1)[1].split('private func coordinate(', 1)[0]
        annotation = body.split('Annotation("", coordinate:', 1)[1]
        self.assertNotIn('.init(snapshot: snapshot, context: context)', annotation)
        self.assertNotIn('cameraRead', annotation)
        self.assertIn('let inspecting = inspectingID == stop.id', annotation)
        walking = self.read('App/WalkingNavigationView.swift')
        self.assertEqual(walking.count('route.coordinates.map'), 1)

    def test_accessibility_and_reduce_motion_additions(self):
        walking = self.read('App/WalkingNavigationView.swift')
        self.assertIn('@QuestifyReduceMotion private var reduceMotion', walking)
        self.assertIn('if power.isLowPowerMode || reduceMotion { $0.animation = nil }', walking)
        self.assertIn('.accessibilityAddTraits(model.progress?.stepIndex == index ? .isSelected : [])', walking)
        route = self.read('App/PlayRouteMapView.swift')
        self.assertIn('Text("playRouteCamera.notice")', route)
        self.assertIn('.accessibilityAddTraits(.isHeader)', route)

    def test_parser_resolves_refs_filters_subsystem_and_unknown_names(self):
        summary = measure.summarize_text([SYNTHETIC_EXPORT], 'synthetic')
        self.assertEqual(summary['points']['walking.refreshTick'], {'count': 2, 'median_ms': 3.0, 'p95_ms': 4.0, 'max_ms': 4.0})
        self.assertEqual(summary['points']['audio.startToPlaying']['count'], 1)
        self.assertEqual(summary['points']['image.artworkLoad'], {'count': 0})
        self.assertNotIn('unlisted.name', summary['points'])
        rows = measure.compare_summaries(summary, summary)
        self.assertIn(('walking.refreshTick', 2, 2, 3.0, 3.0), rows)
        self.assertIn(('image.artworkLoad', 0, 0, None, None), rows)

    def test_recording_refuses_to_pretend_outside_macos(self):
        if measure.platform.system() == 'Darwin':
            self.skipTest('Recording requires a connected device; not exercised here.')
        with self.assertRaises(SystemExit):
            measure.main(['record', '--device', 'synthetic', '--output', '/nonexistent/x.trace'])


if __name__ == '__main__':
    unittest.main()
