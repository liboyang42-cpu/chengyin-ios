"""Read-only source contracts for the three owner-reviewed UI hunks; no Swift execution."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[2]

class X01ExistingEntryUICloseoutTests(unittest.TestCase):
    def source(self,path): return (R/path).read_text()
    def testPoolTitleInstructionsAndValidationCanWrap(self):
        s=self.source('App/CoopPoolApplicationEditor.swift')
        for text in ['Text(verbatim: name).font(.headline).fixedSize(horizontal: false, vertical: true)',
                     'Text("coopflow.poolMessage.intent").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)',
                     'Text("coopflow.poolMessage.tooLong").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)']:
            self.assertIn(text,s)
        self.assertNotIn('.lineLimit(1)',s)
        self.assertNotIn('.minimumScaleFactor(',s)
    def testPoolKeepsUnicodeScalarBoundaryAndFrozenReview(self):
        s=self.source('App/CoopPoolApplicationEditor.swift')
        self.assertIn('message.unicodeScalars.count <= CoopPoolApplicationDraft.maximumMessageScalars',s)
        self.assertIn('Text("coopflow.poolMessage.length \\(message.unicodeScalars.count)").font(.caption).foregroundStyle(.secondary)',s)
        for text in ['review.messageBytes == Data(message.utf8)', 'context.readerID == ObjectIdentifier(reader)',
                     'model.invalidateReview(sessionID: session.id); review = nil; message = value',
                     'CoopFlowRequestPreview(operation: review.operation)', '.disabled(!valid)']:
            self.assertIn(text,s)
    def testTopicMenuKeepsLoadedOnlyAndRetainsOutOfPageSelection(self):
        s=self.source('App/CooperationBrowserView.swift')
        self.assertIn('}.pickerStyle(.menu).accessibilityIdentifier("cooperation.topicFilter.choose")',s)
        self.assertIn('Text("cooperation.topicFilter.loadedOnly").font(.footnote).foregroundStyle(.secondary)\n                    .fixedSize(horizontal: false, vertical: true)',s)
        self.assertIn('if let selected, !options.contains(where: { $0.id == selected })',s)
        self.assertIn('Text(verbatim: "#" + String(selected)).tag(selected)',s)
    def testTopicSelectionDoesNotAcquireAuthorityOrPerformNetworkIO(self):
        s=self.source('App/CooperationBrowserView.swift')
        part=s.split('private func topicFilterSection',1)[1].split('private func invitationSection',1)[0]
        self.assertIn('guard reader.isConfigured, reader.isAuthenticated,',part)
        self.assertIn('ObjectIdentifier(reader) == owner, reader.scope == scope',part)
        for forbidden in ['Task {','.inbox(','.detail(','.execute(','URLSession','permitsDispatch']:
            self.assertNotIn(forbidden,part)
        self.assertIn('CooperationProjectNavigationHost(scope: reader.scope, authenticated: reader.isAuthenticated, reader: ObjectIdentifier(reader))',s)
    def testCalendarDisplaysOriginalValueAndKeepsSourceTimeZone(self):
        s=self.source('App/MerchantPerkValidityCalendar.swift')
        self.assertIn('Text(verbatim: session.draft.original).fixedSize(horizontal: false, vertical: true)',s)
        self.assertIn('.navigationTitle("merchant.perkCalendar.title")\n            .navigationBarTitleDisplayMode(.inline)',s)
        self.assertIn('.environment(\\.timeZone, MerchantPerkValidityDraft.timeZone)',s)
        self.assertIn('.environment(\\.calendar, MerchantPerkValidityDraft.calendar)',s)
    def testCalendarApplyRemainsLocalAndRetiresStaleCallbacks(self):
        s=self.source('App/MerchantPerkValidityCalendar.swift')
        for text in ['guard session?.id == shown.id', 'guard session?.id == shownID',
                     'let value = try draft.value(now: now); cancel(); return value',
                     'value = next; appliedValue = next; appliedContext = context()',
                     '.disabled(!session.isCurrent || session.asksDiscard)',
                     'phase != .active { session?.cancel(); session = nil }']:
            self.assertIn(text,s)
        for forbidden in ['URLSession','permitsDispatch','CoopFlowService(','sendRequest']:
            self.assertNotIn(forbidden,s)
    def testRealExistingHostsRemainWired(self):
        self.assertIn('CooperationBrowserView(reader:session.cooperationReader',self.source('App/AccountView.swift'))
        self.assertIn('CoopPoolApplicationEntry(reader: reader, topicID: id',self.source('App/CooperationFlowWorkbench.swift'))
        self.assertIn('MerchantPerkValidityEntry(value: $validEnd',self.source('App/CooperationFlowEditors.swift'))
    def testCalendarDoesNotEnableDormantTemplateSubmission(self):
        self.assertIn('Button("coopflow.submit") {}.disabled(true)',self.source('App/CooperationFlowEditors.swift'))
        self.assertIn('dormantWritesEnabled: Bool = false',self.source('Core/CooperationFlowService.swift'))
        coordinator=self.source('Core/CooperationFlowCoordinator.swift')
        self.assertIn('enabled: @escaping () -> Bool = { false }',coordinator)
        self.assertIn('guard enabled(), executor.permitsDispatch(accepted.operation)',coordinator)

if __name__=='__main__':unittest.main()
