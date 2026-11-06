"""New source contract; preserves the legacy four-route check verbatim beside it."""
from pathlib import Path
import re
import unittest
R=Path(__file__).resolve().parents[2]
class GrowthRouteModes(unittest.TestCase):
 def test_complete_route_set_is_exact_not_an_unbounded_superset(self):
  s=(R/'Core/GrowthCenterService.swift').read_text()
  paths=set(re.findall(r'"(api/[^"\s]+)"',s))
  self.assertEqual(paths,{'api/growth/center','api/growth/leaderboard','api/growth/leaderboard/anonymous','api/play/growth','api/play/my-completed'})
 def test_legacy_four_routes_and_default_are_unchanged(self):
  s=(R/'Core/GrowthCenterService.swift').read_text()
  self.assertIn('leaderboardContract: GrowthLeaderboardReadContract = .legacy',s)
  prefix,tail=s.split('        if case .anonymous = leaderboardContract {',1)
  anonymous,suffix=tail.split('        // The source binds',1)
  paths=set(re.findall(r'"(api/[^"\s]+)"',prefix+suffix))
  self.assertEqual(paths,{'api/growth/center','api/growth/leaderboard','api/play/growth','api/play/my-completed'})
  self.assertEqual(re.findall(r'"(api/[^"\s]+)"',anonymous),['api/growth/leaderboard/anonymous'])
  self.assertIn('let snapshot: GrowthAnonymousLeaderboardSnapshot',anonymous)
  self.assertIn('return try snapshot.projection(query: query, limit: limit)',anonymous)
  self.assertNotIn('catch',anonymous);self.assertNotIn('try?',anonymous)
 def test_normal_transport_does_not_gain_the_fifth_route(self):
  s=(R/'Core/GrowthNormalReadTransport.swift').read_text()
  self.assertEqual(re.findall(r'case \w+ = "(api/[^"\s]+)"',s),['api/growth/center','api/play/growth','api/play/my-completed'])
 def test_audit_defaults_have_no_external_avatar(self):
  s=(R/'App/GrowthAndLeaderboardParitySectionView.swift').read_text()
  self.assertNotRegex(s,r'https?://')
  defaults=s.split('rows: [GrowthLeaderboardAuditRow] = [',1)[1].split('    ) {',1)[0]
  self.assertEqual(re.findall(r'avatarURL: ([^,]+),',defaults),['nil','nil'])
 def test_explicit_avatar_url_is_parsed_and_anonymous_still_rejected(self):
  s=(R/'App/GrowthAndLeaderboardParitySectionView.swift').read_text().split('public var usesRemoteAvatar: Bool {',1)[1].split('    public init(',1)[0]
  for v in ['guard !isAnonymous','URLComponents(string: trimmedAvatar)','url.scheme?.lowercased() == "https"','let host = url.host, !host.isEmpty','url.user == nil, url.password == nil']:self.assertIn(v,s)
if __name__=='__main__':unittest.main()
