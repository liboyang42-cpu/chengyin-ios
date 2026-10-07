"""Protect unchanged admin guards and diagnose presentation, not a permission repair."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
EXPECTED='''    func testAdminProfileHasNoOwnerSettingsOrRoleActions() {
        launch("admin"); tap("club.ops.openManage")
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.setting.publicVisible").exists); XCTAssertFalse(element("club.ops.member.704").exists)
        XCTAssertTrue(reveal("club.ops.reviewProfile").exists)
        for id in ["club.ops.prioritySignup", "club.ops.field.quota", "club.ops.joinPolicy"] {
            XCTAssertFalse(element(id).exists, app.debugDescription)
        }
    }
'''
ADDED=',\n            "CLUB_OPS_SYNTHETIC_PRESENTATION " + String(describing: element("club.ops.fixtureNotice").value ?? "unavailable")'
def preserved_method(source):
    method='    func testAdminProfileHasNoOwnerSettingsOrRoleActions()'+source.split('    func testAdminProfileHasNoOwnerSettingsOrRoleActions()',1)[1].split('    func testOrdinaryViewerIsDeniedAndCreateRoleGated()',1)[0]
    return method.replace(ADDED,'') == EXPECTED
class ClubAdminSheetDiagnosticContracts(unittest.TestCase):
    def test_original_case_is_identical_after_removing_failure_message_only(self):
        self.assertTrue(preserved_method((ROOT/'Tests/AppUITests/ClubOperationsFlowTests.swift').read_text()))
    def test_negative_controls_reject_weakened_owner_guards_extra_tap_and_wait(self):
        original=(ROOT/'Tests/AppUITests/ClubOperationsFlowTests.swift').read_text()
        for altered in [original.replace('"club.ops.field.quota", ','',1),
                        original.replace('XCTAssertFalse(element("club.ops.setting.publicVisible").exists)','XCTAssertTrue(element("club.ops.setting.publicVisible").exists)',1),
                        original.replace('launch("admin"); tap("club.ops.openManage")','launch("admin"); tap("club.ops.openManage"); tap("club.ops.openManage")',1),
                        original.replace('XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5),','XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 10),',1)]:
            self.assertFalse(preserved_method(altered))
    def test_diagnostics_are_debug_synthetic_counts_without_new_routes_or_identity_data(self):
        source=(ROOT/'App/ClubOperationsFixtureSupport.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('manageTapCount += 1; destination = .init(target: .club(81))',source)
        self.assertIn('.sheet(item: $destination)',source)
        self.assertIn('.onAppear { sheetAppearCount += 1; sheetVisible = true }',source)
        self.assertIn('.onDisappear { sheetDisappearCount += 1; sheetVisible = false }',source)
        diagnostic=source.split('private var presentationDiagnostic: String {',1)[1].split('\n    }',1)[0]
        for key in ['manageTaps=','destinationSet=','sheetVisible=','appeared=','disappeared=','reads=','writes=']:
            self.assertIn(key,diagnostic)
        for forbidden in ['accountID','token','URL','session','epoch','club.name','snapshot(']:
            self.assertNotIn(forbidden,diagnostic)
if __name__=='__main__':unittest.main()
