"""Source-structure assertions only; Swift runtime tests are separate."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CouponValidityParityTests(unittest.TestCase):
 def test_wire_matches_dto_and_no_new_routes(self):
  s=(ROOT/'Core/CouponManagementContract.swift').read_text()
  self.assertIn('CouponValidityTime.wire(start)',s)
  self.assertIn('CouponValidityTime.wire(end)',s)
  self.assertNotIn('ISO8601DateFormatter',s)
  self.assertNotIn('/api/coupon/update',s)
  self.assertIn('dormantWritesEnabled: Bool = false',s)
 def test_picker_review_and_readback_keep_time(self):
  s=(ROOT/'App/CouponManagementView.swift').read_text()
  self.assertEqual(s.count('displayedComponents: [.date, .hourAndMinute]'),2)
  self.assertIn('.environment(\\.timeZone, CouponValidityTime.timeZone)',s)
  self.assertIn('.environment(\\.calendar, CouponValidityTime.calendar)',s)
  self.assertNotIn('startOfDay',s)
  self.assertIn('CouponValidityTime.display(start)',s)
  self.assertIn('CouponValidityTime.display(end)',s)
  self.assertEqual(s.count('CouponValidityTime.display(row.startTime)'),2)
  self.assertEqual(s.count('CouponValidityTime.display(row.endTime)'),2)
 def test_strict_parser_and_wire_order(self):
  s=(ROOT/'Core/CouponManagementDomain.swift').read_text()
  self.assertIn('TimeZone(secondsFromGMT: 8 * 3600)',s)
  self.assertIn('value.string(from: date) == raw',s)
  self.assertIn('value.isLenient = false',s)
  self.assertIn('wireEnd > wireStart',s)
  self.assertIn('start.timeIntervalSince1970.isFinite',s)
 def test_localization_generator_matches_catalog(self):
  f=json.loads((ROOT/'Resources/CouponManagementLocalizations.fragment.json').read_text())
  c=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
  self.assertEqual(c['couponManagement.chinaTime'],f['couponManagement.chinaTime'])
  self.assertIn("'chinaTime':",(ROOT/'tools/build_coupon_management_localizations.py').read_text())
if __name__ == '__main__': unittest.main()
