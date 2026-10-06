"""Source-only locator/lifecycle assertions; not Apple UI execution."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CouponNoticeSurfaceChecks(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_each_mounted_notice_has_an_explicit_distinct_surface(self):
        s=self.read('App/CouponManagementView.swift')
        for surface in ['list','detail','editor']:
            self.assertEqual(s.count('CouponManagementNotice(model: model, surface: .'+surface+')'),1)
        self.assertIn('case list, detail, editor',s)
        for kind in ['issue','readback','serverMessage']:
            self.assertIn('couponManagement.notice.\\(surface.rawValue).'+kind,s)
            self.assertNotIn('.accessibilityIdentifier("couponManagement.'+kind+'")',s)
    def test_assertions_target_editor_then_owned_detail_without_first_match(self):
        runtime=(self.read('Tests/AppUITests/CouponRuntimeFlowTests.swift') + '\n' +
                 self.read('Tests/AppUITests/CouponRuntimeChineseFlowTests.swift'))
        recovery=self.read('Tests/AppUITests/CouponCommandRecoveryFlowTests.swift')
        self.assertIn('couponManagement.notice.editor.readback',runtime)
        self.assertIn('couponManagement.notice.detail.readback',runtime)
        self.assertIn('couponManagement.notice.editor.issue',recovery)
        self.assertNotIn('.firstMatch',runtime+recovery)
        for required in ['record["writes"] as? Int, 2','record["writes"] as? Int, 1','record["writes"] as? Int, 0',
                         'record["pending"] as? Bool, true','record["couponAccessReads"] as? Int, 2',
                         'record["pendingBeforeWrites"] as? [Bool], [true, true]']:
            self.assertIn(required,runtime)
        for required in ['api/coupon/command-receipt','record["writes"] as? Int, 0','record["violations"] as? [String], []']:
            self.assertIn(required,recovery)
    def test_login_is_a_single_validated_native_tap_with_same_arrival_assertion(self):
        s=self.read('Tests/AppUITests/CouponRuntimeJourney.swift')
        branch=s.split('if id == "auth.channels.phoneSignIn" {',1)[1].split('        if element.exists',1)[0]
        self.assertIn('element.isEnabled && element.isHittable',branch)
        self.assertEqual(branch.count('.tap()'),1)
        self.assertNotIn('while ',branch)
        self.assertIn('XCTAssertEqual(code.value as? String, "123456")',s)
        self.assertIn('waitForExistence(timeout: 8), app.debugDescription',s)
    def test_runtime_journeys_and_recovery_method_are_preserved(self):
        runtime=(self.read('Tests/AppUITests/CouponRuntimeFlowTests.swift') + '\n' +
                 self.read('Tests/AppUITests/CouponRuntimeChineseFlowTests.swift'))
        recovery=self.read('Tests/AppUITests/CouponCommandRecoveryFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+',runtime)),6)
        self.assertEqual(len(re.findall(r'func test\w+',recovery)),1)
        self.assertIn('testNormalRootDiskRestartDoesNotRedispatchUnknownCreation',runtime)
        self.assertIn('testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal',recovery)
