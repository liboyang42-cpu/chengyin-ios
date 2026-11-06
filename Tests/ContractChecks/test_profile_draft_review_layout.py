"""Source contracts only. Native SwiftUI/XCTest execution remains a separate gate."""
from pathlib import Path
import re,unittest
ROOT=Path(__file__).resolve().parents[2]
class ProfileDraftReviewLayoutContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def testBeforeAndAfterAreSeparateUnboundedVerticalRows(self):
  source=self.read('App/ProfileDraftReviewSection.swift')
  for role in ['before','after']:
   self.assertIn('Text("profile.reviewRestore.'+role+'").font(.caption).foregroundStyle(.secondary)',source)
   self.assertIn('value(change.'+role+').lineLimit(nil).fixedSize(horizontal: false, vertical: true)',source)
  self.assertEqual(source.count('.frame(maxWidth: .infinity, alignment: .leading)'),2)
 def testAccessibilityContainsButDoesNotMergeExistingChildLabels(self):
  source=self.read('App/ProfileDraftReviewSection.swift')
  self.assertEqual(source.count('.accessibilityElement(children: .contain)'),2)
  self.assertNotIn('.accessibilityElement(children: .combine)',source)
  old=self.read('Tests/AppUITests/ProfileDraftReviewRestoreFlowTests.swift')
  for label in ['Before','After saving','Trail Friend','Trail Friend Local']:
   self.assertIn('app.staticTexts["'+label+'"].exists',old)
 def testLocalRestoreAndConfirmationContractStillBelongToExactReview(self):
  host=self.read('App/ProfileEditView.swift');source=self.read('App/ProfileDraftReviewSection.swift')
  self.assertIn('restore: { _ = model.restoreReviewedDraft(value) })\n                        .id(value.id)',host)
  for token in ['.disabled(!canRestore)','role: .destructive, action: restore','Button("action.cancel", role: .cancel)', 'ForEach(summary.changes)']:
   self.assertIn(token,source)
  for token in ['.save(','.load(','.recover(','.grant(', 'URLSession', 'AppSession']:
   self.assertNotIn(token,source)
 def testExactTextAndUnknownImagePresentationRemain(self):
  source=self.read('App/ProfileDraftReviewSection.swift')
  for token in ['Text(verbatim: text).textSelection(.enabled)','Text(verbatim: raw).textSelection(.enabled)','case .newAvatar:', 'profile.reviewRestore.whitespace', 'case .imageCount(let count)']:
   self.assertIn(token,source)
 def testNewNativeCasesUseRealFixtureAndRetain140UnitLimit(self):
  source=self.read('Tests/AppUITests/ProfileDraftReviewLayoutFlowTests.swift')
  self.assertEqual(len(re.findall(r'func test',source)),2)
  for token in ['--uitesting-profile-edit-fixture', 'caseRemoval', 'UICTContentSizeCategoryAccessibilityXXXL', 'XCTAssertLessThanOrEqual(after.utf16.count, 140)', 'XCTAssertEqual(value.label, after)', 'profile.reviewRestore.cancel', 'XCTAssertTrue(entry.label.contains(suffix))']:
   self.assertIn(token,source)
if __name__=='__main__':unittest.main()
