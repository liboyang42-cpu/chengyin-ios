"""Preference/summary source checks; no Swift execution or backend acceptance."""
import pathlib
import unittest
from flutter_source import read_flutter_source
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayPreferenceSourceChecks(unittest.TestCase):
    def read(self,name):return (ROOT/name).read_text()
    def test_exact_preference_and_tag_paths(self):
        target=self.read('Core/PlayPreferenceRuntime.swift')
        for suffix in ['preference','submit','confirm','correct']:
            self.assertIn(suffix,target)
        for key in ['"choices"','"reuseTagCode"','"routeActionId"','"expectedRouteVersion"','"tagValue"']:self.assertIn(key,target)
        self.assertIn('postWithoutBody: true',target)
    def test_preference_paths_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/play_api.dart')
        for suffix in ['preference','submit','confirm','correct']:
            self.assertIn(suffix,source)
    def test_no_client_preference_outcome_or_destination(self):
        target=self.read('Core/PlayPreferenceRuntime.swift')
        self.assertNotIn('"outcomeCode":',target);self.assertNotIn('"targetNodeId":',target)
        self.assertIn('progress["nodeId"].tolerantInteger == nodeID',target)
    def test_tiebreak_retains_route_identity_and_requires_server_step(self):
        text=self.read('Core/PlayPreferenceRuntime.swift')
        self.assertIn('routeAdvance == nil',text);self.assertIn('tiebreakStep = step',text)
        self.assertIn('existing != step',text);self.assertIn('result.needsTiebreak',text)
    def test_tag_recipient_purpose_and_values_gate(self):
        text=self.read('Core/PlayPreferenceRuntime.swift')
        self.assertIn('result.canDiscloseTag',text);self.assertIn('result.availableTagValues.contains(correctedValue)',text)
        self.assertIn('disclosure["purpose"]',text);self.assertIn('disclosure["recipientLabel"]',text)
    def test_revoke_requires_authoritative_readback(self):
        text=self.read('Core/PlayOperatingSummary.swift')
        self.assertIn('unresolvedTagIDs = unresolvedTagIDs.filter',text)
        self.assertIn('value.tags.contains { $0.id == id && !$0.revoked }',text)
        self.assertIn('unresolvedTagIDs.isEmpty',text)
    def test_session_wrapper_observes_epoch_replacement(self):
        text=self.read('App/SessionPlayRuntimeView.swift')
        self.assertIn('@ObservedObject var session: AppSession',text)
        self.assertIn('.id(session.sessionRevision)',text)
        snippet=self.read('docs/app-session-play-extension.snippet.swift.txt')
        self.assertNotIn('enabled:',snippet)
        self.assertIn('PlayDormantDeviceProvider()',snippet);self.assertIn('PlayDormantMotionProvider()',snippet)
if __name__=='__main__':unittest.main()
