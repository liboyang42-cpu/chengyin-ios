"""Source contracts for the read-only Club itinerary display; not Swift execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


def projection_contract(source):
    assert 'for (nodeIndex, node) in nodesByChapter[index].enumerated()' in source
    assert 'estimatedWalkingMinutes: nodeIndex > 0' in source
    assert 'Self.walkingMinutes(from: nodesByChapter[index][nodeIndex - 1], to: node) : nil' in source
    assert 'latitude != 0, longitude != 0 else { return nil }' in source
    assert 'return RoamCoordinate(latitude: latitude, longitude: longitude)' in source
    assert 'guard let origin = coordinate(previous), let destination = coordinate(current) else { return nil }' in source
    assert 'RoamExperienceMath.distanceMeters(origin, destination)' in source
    assert 'guard meters.isFinite, meters > 0 else { return nil }' in source
    assert 'return max(1, Int((meters / 80).rounded()))' in source


class ClubStoryWalkEstimateContracts(unittest.TestCase):
    def core(self):
        return (ROOT / 'Core/ClubStoryPresentation.swift').read_text()

    def app(self):
        return (ROOT / 'App/ClubStoryViews.swift').read_text()

    def test_each_chapter_pairs_only_original_adjacent_rows(self):
        projection_contract(self.core())
        self.assertIn('public let estimatedWalkingMinutes: Int?', self.core())
        self.assertNotIn('compactMap', self.core().split('var sequence = 0', 1)[1].split('private static func rows', 1)[0])

    def test_coordinate_parsing_uses_existing_finite_bounded_value_type(self):
        source = self.core()
        self.assertIn('Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))', source)
        self.assertIn('return value.number', source)
        domain = (ROOT / 'Core/RoamContracts.swift').read_text()
        self.assertIn('latitude.isFinite, longitude.isFinite', domain)
        self.assertIn('(-90...90).contains(latitude), (-180...180).contains(longitude)', domain)
        value = (ROOT / 'Core/ClubGovernanceContracts.swift').read_text()
        number = value.split('public var number: Double?', 1)[1].split('public var text:', 1)[0]
        self.assertNotIn('.bool', number)

    def test_estimate_display_is_in_real_stop_card_with_bilingual_caveat(self):
        card = self.app().split('@MainActor struct ClubStoryStopCard: View', 1)[1].split('@MainActor struct ClubStoryGameplayCard', 1)[0]
        self.assertIn('if let minutes = stop.estimatedWalkingMinutes', card)
        self.assertIn('LabeledContent("topic.itinerary.estimatedWalkMinutes") { Text(minutes, format: .number) }', card)
        self.assertIn('Text("topic.itinerary.estimateNotice")', card)
        self.assertIn('accessibilityIdentifier("club.story.walk.\\(stop.id)")', card)
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['topic.itinerary.estimatedWalkMinutes', 'topic.itinerary.estimateNotice']:
            for language in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][language]['stringUnit']['value'])
        notice = strings['topic.itinerary.estimateNotice']['localizations']['en']['stringUnit']['value']
        self.assertIn('straight-line', notice)
        self.assertIn('80 m/min', notice)

    def test_normal_host_keeps_existing_current_snapshot_and_permission_gates(self):
        host = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('club.gov.openStory', host)
        self.assertIn('ClubStoryStopCard(stop: stop, imageReader: templates.imageReader)', host)
        self.assertIn('ClubStoryPresentation(snapshot: snapshot)', host)
        source = self.core()
        self.assertIn('snapshot.permissions?.allows(ClubGovernanceRead.topicOverview.permission, scope: snapshot.scope) == true', source)
        self.assertIn('ClubGovernanceValidation.validate(snapshot.value, operation: .topicOverview, scope: snapshot.scope)', source)
        self.assertIn('Self.fingerprint(snapshot.value) == fingerprint', source)

    def test_no_location_collection_planning_or_write_is_added(self):
        helper = self.core().split('private static func coordinate', 1)[1].split('private static func rows', 1)[0]
        for token in ['Task {', '.send(', '.read(', 'URLSession', 'CLLocationManager', '.preview(', '.save(', '.confirm(']:
            self.assertNotIn(token, helper)
        self.assertNotIn('totalTime', helper)
        self.assertNotIn('businessTime', helper)
        for token in ['["routeGeometry"]', '["blocks"]', '["blocksJson"]']:
            self.assertNotIn(token, self.core())

    def test_core_regressions_cover_unknown_edges_reload_and_scope(self):
        source = (ROOT / 'Tests/CoreTests/ClubStoryPresentationTests.swift').read_text()
        for name in [
            'testWalkingEstimateRestartsAtEveryChapterBoundary',
            'testWalkingEstimateDoesNotBridgeAnUnknownIntermediateStop',
            'testWalkingEstimateRejectsUnknownMalformedAndZeroCoordinatesOnEitherEnd',
            'testWalkingEstimateRejectsOutOfRangeCoordinates',
            'testWalkingEstimateReloadUsesNewCoordinatesAndDoesNotRetainAnOldEstimate',
            'testWalkingEstimateCannotBypassExistingProjectionPermission',
            'testWalkingCoordinateChangeExpiresTheOriginalTemplateAndAnswerRoutes',
            'testWalkingEmptyVisibleNodeProjectionDoesNotUseOpaqueGeometry',
            'testWalkingSingleVisibleNodeCannotEstimateTowardAnOmittedNode',
            'testWalkingOnlyUsesReturnedChaptersWithoutReconstructingLockedContent',
        ]:
            self.assertIn('func ' + name, source)

    def test_contract_rejects_cross_chapter_unknown_zero_and_fake_route_mutations(self):
        original = self.core()
        for before, after in [
            ('nodeIndex > 0', 'nodeIndex >= 0'),
            ('[nodeIndex - 1]', '[0]'),
            ('latitude != 0, longitude != 0', 'latitude == latitude, longitude == longitude'),
            ('meters.isFinite, meters > 0', 'meters.isFinite, meters >= 0'),
            ('meters / 80', 'meters / 100'),
            ('max(1, Int(', 'max(0, Int('),
            ('coordinate(previous)', 'coordinate(current)'),
        ]:
            self.assertIn(before, original)
            with self.assertRaises(AssertionError, msg=before):
                projection_contract(original.replace(before, after, 1))


if __name__ == '__main__':
    unittest.main()
