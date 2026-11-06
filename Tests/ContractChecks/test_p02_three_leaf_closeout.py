"""P02 final three-leaf layout, localization and authority source checks only."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class P02ThreeLeafCloseoutTests(unittest.TestCase):
    def source(self, leaf): return (ROOT/'App'/(leaf+'.swift')).read_text()
    def contains(self, leaf, values):
        for value in values: self.assertIn(value, self.source(leaf))
    def testHoursPickerReflowsWithoutChangingRanges(self):
        self.contains('ProjectNodeBusinessHoursField', ['dynamicTypeSize.isAccessibilitySize', 'AnyLayout(VStackLayout(alignment: .leading, spacing: 12))', 'AnyLayout(HStackLayout())', 'ForEach(0...23, id: \\.self)', 'ForEach(0...59, id: \\.self)', 'component(original, start: start, hour: true)', 'component(original, start: start, hour: false)'])
    def testHoursKeepsOriginalClearReviewAndCapturedBinding(self):
        self.contains('ProjectNodeBusinessHoursField', ['controller.chooseClear(original)', 'controller.undoClear(original)', 'controller.beginReplacement(original)', 'controller.apply(original)', '.disabled(capture == nil || original != nil)', 'controller.binding(original)', '.onDisappear { controller.retire() }'])
    def testVariableRowsPreserveTokensLabelsAndSelectionMeaning(self):
        self.contains('ProjectStoryVariablePicker', ['Text(verbatim: variable.token)', 'Text(verbatim: variable.label)', 'dynamicTypeSize.isAccessibilitySize', '.accessibilityAddTraits(controller.selectedKey?.utf8.elementsEqual(variable.key.utf8) == true ? .isSelected : [])', '.disabled(!original.capture.snapshot.canAppend(variable.key))'])
    def testVariableAppendStillNeedsSameSessionLeaseAndExplicitButton(self):
        self.contains('ProjectStoryVariablePicker', ['model.isCurrentStarterLease(capture.lease)', 'model.coordinator.session == capture.session', 'model.coordinator.identity == capture.identity', 'model.draftMutationRevision == capture.revision', 'Button { controller.append(original) }', '.disabled(controller.selectedKey == nil || !controller.isCurrent(original))', '.disabled(capture == nil || snapshot.variables.isEmpty || original != nil)', '.onDisappear { controller.retire() }'])
    def testMeetingAddressAndAccessibilityRowsWrapFullValues(self):
        self.contains('ProjectTicketMeetingPointFields', ['summaryRow("projectTicketMeetingPoint.address", value: value.address, expanded: true)', 'if expanded || dynamicTypeSize.isAccessibilitySize', 'Text(verbatim: value).fixedSize(horizontal: false, vertical: true)', '.accessibilityElement(children: .combine)', 'LabeledContent(title, value: value)'])
    def testMeetingSummaryStillUsesSourceAwareProjectionAndWarnings(self):
        self.contains('ProjectTicketMeetingPointFields', ['let value = ProjectTicketMeetingPoint(ticket: ticket)', 'summaryRow("projectEdit.longitude", value: value.longitude)', 'summaryRow("projectEdit.latitude", value: value.latitude)', 'Text("projectTicketMeetingPoint.datum")', 'Text("projectTicketMeetingPoint.unsupported")', 'Text("projectTicketMeetingPoint.invalidCoordinates")', '.accessibilityIdentifier("projectTicketMeetingPoint.summary")'])
    def testOriginalDedicatedCatalogsRemainFullyBilingual(self):
        for table in ['ProjectNodeBusinessHours', 'ProjectStoryVariableInsertion']:
            strings=json.loads((ROOT/'Resources'/(table+'.xcstrings')).read_text())['strings']
            for key,entry in strings.items():
                for language in ['en','zh-Hans']:
                    unit=entry['localizations'][language]['stringUnit']
                    self.assertEqual(unit['state'],'translated',(key,language));self.assertTrue(unit['value'].strip(),(key,language))
    def testDynamicReasonKeysResolveInTheirOriginalCatalogs(self):
        for table,prefix,reasons in [('ProjectNodeBusinessHours','projectNodeHours.reason.', ['identity','unsupported']),('ProjectStoryVariableInsertion','projectStoryVariable.reason.',['identity','declarations','unsupported'])]:
            strings=json.loads((ROOT/'Resources'/(table+'.xcstrings')).read_text())['strings']
            for reason in reasons:self.assertIn(prefix+reason,strings)
    def testMeetingSummaryOriginalKeysRemainBilingual(self):
        strings=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['projectEdit.meetingPoint','projectTicketMeetingPoint.address','projectEdit.longitude','projectEdit.latitude','projectTicketMeetingPoint.datum','projectTicketMeetingPoint.unsupported','projectTicketMeetingPoint.invalidCoordinates']:
            for language in ['en','zh-Hans']:
                unit=strings[key]['localizations'][language]['stringUnit'];self.assertEqual(unit['state'],'translated');self.assertTrue(unit['value'].strip())
if __name__=='__main__':unittest.main()
