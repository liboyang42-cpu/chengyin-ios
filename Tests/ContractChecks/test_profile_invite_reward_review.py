"""Source-only seams. Does not compile or execute Swift."""
import json,re,unittest
from pathlib import Path
W=Path(__file__).resolve().parents[2]
C=(W/'Core/ProfileInviteRewardReview.swift').read_text();A=(W/'App/ProfileInviteRewardReviewSection.swift').read_text();V=(W/'App/SocialInviteHistoryView.swift').read_text()
class ProfileInviteRewardReviewSourceTests(unittest.TestCase):
 def test_01_exact_complete(self):self.assertIn('if scan.total == scan.fetchedCount',C)
 def test_02_contradictory_total(self):self.assertIn('total < scan.fetchedCount',C);self.assertIn('ledgerState = .invalid; cumulativePoints = nil',C)
 def test_03_missing_scan(self):self.assertIn('ledgerState = .unavailable; cumulativePoints = nil; rewards = [:]',C)
 def test_04_partial_total_hidden(self):self.assertIn('ledgerState = .partial; cumulativePoints = nil',C)
 def test_05_global_not_loaded_member_sum(self):self.assertIn('scan.rewards.keys.sorted().compactMap { scan.rewards[$0]?.points }',C)
 def test_06_zero_preserved(self):self.assertIn('ledgerState = .complete; cumulativePoints = sum',C)
 def test_07_distinct_loaded_people(self):self.assertIn('seen.insert($0.id).inserted',C)
 def test_08_exact_member_mapping(self):self.assertIn('distinct.compactMap { rewards[String($0.id)]?.points }',C)
 def test_09_invalid_month_unknown(self):self.assertIn('ledgerState == .invalid || ledgerState == .unavailable ? nil',C)
 def test_10_partial_month(self):self.assertIn('isPartial: ledgerState != .complete',C);self.assertIn('month.isPartial ? "profile.inviteRewards.partialPoints"',A)
 def test_11_positive_subtotal_else_people(self):self.assertIn('earnedPoints.map { $0 > 0 } ?? false',C);self.assertIn('String(month.loadedMemberCount)',A)
 def test_12_exact_decimal(self):self.assertIn('NSDecimalAdd(&next, &total, &amount, .plain) == .noError',C)
 def test_13_invalid_decimal(self):self.assertIn('guard !value.isNaN, value >= 0',C)
 def test_14_no_double_conversion(self):self.assertNotIn('Double',C+A);self.assertNotIn('Float(',C+A)
 def test_15_unknown_copy(self):self.assertIn('profile.inviteRewards.pending',A);self.assertIn('review.ledgerState != .complete',A)
 def test_16_current_permit_retry(self):self.assertIn('model.start(reader, permit: permit, reset: true)',V)
 def test_17_duplicate_retry_disabled(self):self.assertIn('action: reload).disabled(isLoading)',A)
 def test_18_view_under_matching_reader(self):self.assertLess(V.index('else if !model.matches(reader)'),V.index('ProfileInviteRewardReviewSection'))
 def test_19_existing_model_guard(self):self.assertIn('self.permit(reader) == permit, !loading || reset',V);self.assertIn('presentation = nil; requestID = nil',V)
 def test_20_loaded_month_scope(self):self.assertIn('.month(members: group.1)',V);self.assertIn('profile.inviteRewards.monthScope',A)
 def test_21_existing_navigation(self):self.assertIn('SocialPublicProfileView(memberID: member.id',V);self.assertIn('.refreshable { await model.refresh(reader, permit: permit) }',V)
 def test_22_privacy(self):self.assertIn('.privacySensitive()',V);self.assertIn('if reader.identity.accountID == nil',V)
 def test_23_no_new_io(self):
  for s in ['URLSession','http://','https://','UserDefaults','token:','HTTPTransport','WalletCommerceReading']:self.assertNotIn(s,C+A)
 def test_24_ordinary_host(self):
  self.assertIn('SocialInviteHistoryView(reader: session.profileInviteHistoryReader',(W/'App/AccountView.swift').read_text())
  self.assertIn('ProfileInviteHistoryReader(base: socialAccountReader',(W/'App/AppSession.swift').read_text())
 def test_25_bilingual(self):
  f=json.loads((W/'Resources/ProfileInviteRewardReviewLocalizations.fragment.json').read_text())['strings'];self.assertEqual(len(f),7)
  for v in f.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
 def test_26_native_inventory(self):
  for path,count in [('CoreTests/ProfileInviteRewardReviewTests.swift',16),('AppUnitTests/ProfileInviteRewardReviewAppTests.swift',7),('AppUITests/ProfileInviteRewardReviewFlowTests.swift',6)]:self.assertEqual(len(re.findall(r'func test\w+\(', (W/'Tests'/path).read_text())),count)
if __name__=='__main__':unittest.main()
