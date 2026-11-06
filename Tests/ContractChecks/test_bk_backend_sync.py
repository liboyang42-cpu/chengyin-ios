"""BK backend-sync card: source-structure checks only. No Swift compiler, simulator or live service is run."""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
DOC = 'docs/handoff/ios-BK-20261019.md'
ITEMS = ['E06-17', 'E01-19', 'E02-23', 'E02-12', 'E02-24', 'E02-25', 'E04-07', 'E01-13']
class BackendSyncSourceTests(unittest.TestCase):
 def swift(self):
  return {p: p.read_text() for d in ('Core', 'App') for p in (ROOT/d).rglob('*.swift')}
 def test_endpoints_recorded_without_ios_consumer_stay_unused(self):
  # E06-17 share snapshot: a future consumer must adopt the handoff first.
  for p, value in self.swift().items():
   if p.name == 'RoamSubpagePresentation.swift':
    self.assertIn('guard (200..<300).contains(status) else { return .error }', value)
    continue
   self.assertNotIn('roam/share/snapshot', value, p)
 def test_topic_like_write_is_only_the_explicit_type0_unlike(self):
  # E01-19 consumers: explicit type only; the legacy blank-type toggle keeps failing on DELETE0.
  users = sorted(str(p.relative_to(ROOT)) for p, v in self.swift().items() if re.search(r'"api/topic/like"', v))
  self.assertEqual(users, ['Core/TopicLikeDirection.swift', 'Core/TopicUnlike.swift'])
  value = (ROOT/'Core/TopicUnlike.swift').read_text()
  self.assertIn('fields: ["id": String(topicID), "type": "0"]', value)
  self.assertIn('if envelope.code == 200 {\n            unresolved.remove(topicID); phase = .removed(topicID: topicID)', value)
  direction = (ROOT/'Core/TopicLikeDirection.swift').read_text()
  self.assertIn('fields: ["id": String(topicID), "type": direction.typeField]', direction)
  self.assertIn("return envelope.code == 200 ? .acknowledged : .rejected(envelope.msg)", direction)
 def test_topic_like_direction_factory_stays_unwired(self):
  # BK-LIKE/I05 factory is audited request construction only: no transport or approval in App/Core.
  for p, value in self.swift().items():
   if p.name == 'TopicLikeDirection.swift': continue
   self.assertNotIn('TopicLikeOperationFactory', value, p)
 def test_legacy_square_bookmark_never_routes_through_community_id(self):
  contracts = (ROOT/'Core/SocialActionContracts.swift').read_text()
  self.assertIn('case .communityComment, .communityCommentLike, .postAction: return .communityV1', contracts)
  self.assertIn('guard snapshot.post?.generation == requiredGeneration', contracts)
  detail = (ROOT/'App/SquareDetailView.swift').read_text()
  self.assertRegex(detail, r'social\.editor\.bookmark"\) \{[^\n]*\}\n\s*\.disabled\(post\.generation != \.communityV1\)')
 def test_legacy_unbookmark_keeps_readback_only_resolution(self):
  value = (ROOT/'Core/ProfileFavoriteRemoval.swift').read_text()
  self.assertIn('"bookmark": "0"', value); self.assertNotIn('"bookmark": "1"', value)
  self.assertIn('phase = dispatched ? .unknown : .failed', value)
  self.assertIn('A pending write can be observed, never automatically submitted a second time.', value)
 def test_handoff_table_lists_every_item(self):
  doc = (ROOT/DOC).read_text()
  for item in ITEMS: self.assertRegex(doc, r'\n\| ' + re.escape(item) + r' \|', item)
  self.assertIn('TEST_DEPLOYED=NO', doc)
  self.assertTrue((ROOT/'Tests/CoreTests/BackendSyncContractTests.swift').exists())
if __name__ == '__main__': unittest.main()
