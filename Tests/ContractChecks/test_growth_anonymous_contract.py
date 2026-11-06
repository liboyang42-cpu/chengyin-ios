"""Narrow Swift source contracts; not execution of the Swift decoder or service."""
from pathlib import Path
import unittest,re
R=Path(__file__).resolve().parents[2]
class AnonymousContractChecks(unittest.TestCase):
 def setUp(self):
  self.dto=(R/'Core/GrowthAnonymousLeaderboardContract.swift').read_text()
  self.service=(R/'Core/GrowthCenterService.swift').read_text()
 def test_whitelist_rejects_unknown_and_legacy_identifier_keys(self):
  self.assertIn('Set(c.allKeys.map(\\.stringValue)).isSubset(of: allowed)',self.dto)
  self.assertIn('allowed: ["metric", "period", "list", "me"]',self.dto)
  self.assertIn('allowed: ["rank", "score", "nickname", "avatar", "rankPercentage", "self"]',self.dto)
 def test_typed_boolean_and_int64_not_legacy_coercion(self):
  for text in ['decode(Bool.self','decodeIfPresent(Int64.self','decodeIfPresent(Int32.self','Int(exactly: score)']:self.assertIn(text,self.dto)
  for text in ['growthInteger','Double.self','decodeIfPresent(Bool.self']:self.assertNotIn(text,self.dto)
 def test_current_self_and_anonymous_other_contract(self):
  for text in ['guard me.isSelf','selfRows.count <= 1','row.rank == me.rank, row.score == me.score','nickname == "匿名玩家" && avatar == nil']:self.assertIn(text,self.dto)
 def test_projection_contains_no_identity(self):
  self.assertIn('memberID: nil, nickname: nil, avatar: nil',self.dto)
  self.assertIn('.withoutUnrankedPlaceholders()',self.dto)
 def test_query_order_limit_are_checked(self):
  for text in ['metric == query.metric, period == query.period, list.count <= limit','row.rank == index + 1','list.count <= 100']:self.assertIn(text,self.dto)
 def test_default_contract_preserves_existing_callers(self):
  self.assertIn('leaderboardContract: GrowthLeaderboardReadContract = .legacy',self.service)
  self.assertIn('if case .anonymous = leaderboardContract',self.service)
  self.assertIn('let snapshot: GrowthAnonymousLeaderboardSnapshot = try await read("api/growth/leaderboard/anonymous"',self.service)
  self.assertIn('return try snapshot.projection(query: query, limit: limit)',self.service)
 def test_original_auth_error_and_cancel_pipeline_used(self):
  self.assertIn('if status == 401 || envelope?.code == 401 { throw APIError.unauthorized }',self.service)
  self.assertIn('try Task.checkCancellation()',self.service)
  self.assertNotIn('try?',self.service.split('if case .anonymous = leaderboardContract')[1].split('// The source binds')[0])
 def test_normal_transport_admission_is_still_three_original_reads(self):
  source=(R/'Core/GrowthNormalReadTransport.swift').read_text()
  self.assertEqual(re.findall(r'case \w+ = "(api/[^"\s]+)"',source),['api/growth/center','api/play/growth','api/play/my-completed'])
 def test_regressions_cover_positive_negative_and_errors(self):
  tests=(R/'Tests/CoreTests/GrowthAnonymousLeaderboardContractTests.swift').read_text()
  self.assertEqual(tests.count('func test'),13)
  for name in ['testLegacyMemberIdentifierEvenNullIsRejected','testInt64ScoreDoesNotRoundThroughDouble','testAnonymousErrorsNeverBecomeEmptySuccessOrLegacyRetry','testEmptyUnrankedIsSuccessButPlaceholderValuesDisappear']:self.assertIn(name,tests)
if __name__=='__main__':unittest.main()
