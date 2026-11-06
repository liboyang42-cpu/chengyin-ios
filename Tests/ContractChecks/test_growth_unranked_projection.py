"""Focused source/contract checks. These do not execute Swift or an Apple UI."""
import copy
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class GrowthUnrankedProjectionChecks(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'Core/GrowthLeaderboardStanding.swift').read_text()
        self.body = self.source.split('func withoutUnrankedPlaceholders() -> GrowthLeaderboard {', 1)[1].split('\n    }', 1)[0]

    def projected(self, board):
        """Evaluate only this exact source guard and returned-rank expression."""
        self.assertIn('guard me.rank.map({ $0 <= 0 }) ?? true else { return self }', self.body)
        expression = re.search(r'GrowthLeaderboardEntry\(rank: (nil|me\.rank),', self.body)
        self.assertIsNotNone(expression)
        if board['me'].get('rank') is not None and board['me']['rank'] > 0:
            return copy.deepcopy(board)
        result = copy.deepcopy(board)
        result['me']['rank'] = None if expression.group(1) == 'nil' else board['me'].get('rank')
        result['me']['score'] = None
        result['me']['rankPercentage'] = None
        return result

    def board(self, rank):
        return {'metric': 'point', 'period': 'week',
                'list': [{'rank': 2, 'memberId': 22}, {'rank': 1, 'memberId': 11}],
                'me': {'rank': rank, 'memberId': 41, 'nickname': 'Synthetic viewer',
                       'avatar': 'opaque-avatar', 'score': 0, 'rankPercentage': 'TOP100%'}}

    def test_nonpositive_rank_expression_is_nil_for_optional_only_consumers(self):
        self.assertIn('GrowthLeaderboardEntry(rank: nil,', self.body)
        self.assertNotIn('GrowthLeaderboardEntry(rank: me.rank,', self.body)

    def test_zero_negative_and_nil_omit_personal_rank(self):
        for rank in [None, 0, -1, -(2 ** 63)]:
            with self.subTest(rank=rank):
                self.assertIsNone(self.projected(self.board(rank))['me']['rank'])

    def test_ranked_values_and_real_zero_score_are_not_rewritten(self):
        for rank in [1, 3, 50, 87, 2 ** 63 - 1]:
            original = self.board(rank)
            self.assertEqual(self.projected(original), original)

    def test_existing_unknown_score_and_percentage_remain_unknown(self):
        for rank in [None, 0, -1]:
            projected = self.projected(self.board(rank))
            self.assertIsNone(projected['me']['score'])
            self.assertIsNone(projected['me']['rankPercentage'])
        self.assertIn('score: nil, rankPercentage: nil', self.body)

    def test_all_other_viewer_fields_and_server_list_order_are_preserved(self):
        self.assertIn('metric: metric, period: period, list: list', self.body)
        self.assertIn('memberID: me.memberID, nickname: me.nickname, avatar: me.avatar', self.body)
        original = self.board(0)
        projected = self.projected(original)
        for key in ['metric', 'period', 'list']:
            self.assertEqual(projected[key], original[key])
        for key in ['memberId', 'nickname', 'avatar']:
            self.assertEqual(projected['me'][key], original['me'][key])

    def test_idempotent_without_synthetic_rank_or_score(self):
        for rank in [None, 0, -1, 1, 87]:
            once = self.projected(self.board(rank))
            self.assertEqual(self.projected(once), once)

    def test_positive_boundary_matches_existing_standing_contract(self):
        self.assertIn('guard let rank = board.me.rank, rank > 0 else { self = .unknown; return }', self.source)
        for rank in [None, 0, -1]:
            # The two actual views only show personal rows for a non-nil rank.
            projected = self.projected(self.board(rank))
            self.assertFalse(projected['me']['rank'] is not None)

if __name__ == '__main__':
    unittest.main()
