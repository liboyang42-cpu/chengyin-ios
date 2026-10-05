"""Source wiring checks only; Swift/SwiftUI behavior needs Apple execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ActivityPeopleNavigationChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_allowed_detail_mounts_people_and_existing_profile_reader(self):
        view = self.read('App/ActivityDetailView.swift')
        gate = view.split('case .clubRequired', 1)[1].split('case .allowed', 1)[0]
        self.assertNotIn('ActivityPeopleSection', gate)
        for token in ['ActivityPeopleSection(people: detail.people',
                      'reader: session.socialAccountReader, squareReader: session.squareReader',
                      'SocialPublicProfileView(memberID: selection.memberID',
                      '.id(session.contentDetailRevision)',
                      'loadedProfileIdentity == peopleProfile.reader.identity',
                      'selection.matches(activityID: id, people: detail.people',
                      'snapshotID: loadedPeopleSnapshotID',
                      'profileSelection=nil;loadedPeopleSnapshotID=nil',
                      '.onChange(of: peopleProfile?.reader.identity)',
                      'profileSelection = nil; loadedProfileIdentity = nil']:
            self.assertIn(token, view)
        self.assertIn('people=try ActivityPeople(from:decoder)', self.read('Core/ActivityDetail.swift'))

    def test_display_projection_never_uses_record_or_owner_id(self):
        model = self.read('Core/ActivityPeople.swift')
        self.assertIn('host = hosts.first?.person', model)
        self.assertIn('case memberId, memberRealName, nickname', model)
        self.assertIn('1...9_007_199_254_740_991', model)
        self.assertIn('guard preview.count <= 5 else', model)
        self.assertIn('self.snapshotID == snapshotID', model)
        self.assertNotIn('case id', model)
        self.assertNotIn('hostMemberID', model)
        self.assertNotIn('registrationCount = participants.count', model)
        for prohibited in ['phone', 'address', 'token', 'URLSession', '/api/']:
            self.assertNotIn(prohibited, model)

    def test_missing_member_id_is_read_only_and_all_labels_are_bilingual(self):
        view = self.read('App/ActivityPeopleSection.swift')
        self.assertIn('if let memberID = person.memberID, let onOpenProfile', view)
        self.assertIn('identifier + ".readOnly"', view)
        self.assertIn('.frame(minHeight: 44)', view)
        self.assertIn('ForEach(Array(people.participants.enumerated()), id: \\.offset)', view)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in ['host', 'participants', 'total', 'countUnknown', 'unnamed']:
            self.assertEqual(set(catalog['activity.people.' + key]['localizations']), {'en', 'zh-Hans'})

    def test_authored_behavior_and_fixture_scenarios_exist(self):
        tests = self.read('Tests/CoreTests/ActivityPeopleTests.swift')
        for name in ['testReadsDesignatedHostAndPartialPublicRosterWithoutInferringTotal',
                     'testOnlyPositiveSafeMemberIdentifiersBecomeDestinations',
                     'testMalformedPublicListsDoNotBecomeEmptySuccess',
                     'testPublicParticipantPreviewRejectsMoreThanFiveRows',
                     'testClubGateNeverDecodesHiddenPeople',
                     'testProfileSelectionIsBoundToExactActivityPeopleAndViewer']:
            self.assertIn(name, tests)
        ui = self.read('Tests/AppUITests/ActivityFlowTests.swift')
        self.assertIn('testPeopleOpenExactProfilesAndPreserveReadOnlyRowsAfterBack', ui)
        self.assertIn('activity.people.switchAccount', ui)
        self.assertIn('Fixture host profile', ui)
        self.assertIn('Fixture participant profile', ui)
        fixture = self.read('App/ActivityFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('case people', fixture)
        self.assertNotIn('https://', fixture)
