"""Source/catalog checks only. XCTest, Foundation, and SwiftUI are not executed."""
from pathlib import Path
import json,re,unittest
R=Path(__file__).resolve().parents[2]
class WalletIncomeAnalysisClosureContracts(unittest.TestCase):
 def src(self,path):return (R/path).read_text()
 def testNormalEntryUsesExistingIncomeGateAndSameReader(self):
  s=self.src('App/WalletCommerceViews.swift')
  expected='''if visibility.income {
                NavigationLink { WalletIncomeAnalysisView(reader: reader) } label: {'''
  self.assertIn(expected,s);self.assertIn('.accessibilityIdentifier("wallet.analysis.open")',s)
  self.assertIn('WalletCommerceHomeView(reader: session.walletHistoryReader',self.src('App/SessionWalletCommerceView.swift'))
 def testAnalysisNeverCreatesReaderGrantOrMutation(self):
  s=self.src('App/WalletIncomeAnalysisReader.swift')+self.src('App/WalletIncomeAnalysisView.swift')
  for text in ['WalletCommerceReader(', 'WalletHistoryReadApproval(', 'URLSession', '.checkout(', '.perform(', '.recover(', '.purchase(', 'AppStore.sync', 'UserDefaults']:
   self.assertNotIn(text,s)
  self.assertIn('try await reader.read {',s);self.assertIn('$0.ledger(.income(.all), page: pageNumber',s)
 def testBudgetExactPagingValidationAndUnknownTotalFailClosed(self):
  s=self.src('App/WalletIncomeAnalysisReader.swift')
  for text in ['static let pageSize = 20','static let pageBudget = 10','requestedPage == pagesRead + 1','page.page == requestedPage','page.pageSize == Self.pageSize','Set(page.rows.map(\\.id)).count == page.rows.count','observedTotal.map({ $0 == total }) ?? true','page.rows.count == min(Self.pageSize, total - offset)','return .unverified']:
   self.assertIn(text,s)
 def testPermissionDenialCannotRetainPartialMoney(self):
  s=self.src('App/WalletIncomeAnalysisReader.swift')
  expected='''} else if WalletReadFailurePresentation.isUnavailable(error) || WalletReadFailurePresentation.isForbidden(error) {
                result = nil; receivedCount = 0; pagesRead = 0; unavailable = true'''
  self.assertIn(expected,s)
  self.assertLess(s.index('WalletReadFailurePresentation.isForbidden(error)'),s.index('} else if !accumulator.rows.isEmpty'))
 def testReaderIdentityAndCancellationFencePublication(self):
  s=self.src('App/WalletIncomeAnalysisReader.swift')
  for text in ['ObjectIdentifier(value)','identity == WalletIncomeAnalysisReadIdentity(reader)','generation = UUID(); task?.cancel()','await withTaskCancellationHandler','onCancel: { work.cancel() }','try Task.checkCancellation()','error as? WalletCommerceSafetyError != .staleSession']:
   self.assertIn(text,s)
  v=self.src('App/WalletIncomeAnalysisView.swift')
  for text in ['.task(id: WalletIncomeAnalysisReadIdentity(reader))','.onDisappear { visible = false; model.cancel() }','if value != .active { model.cancel() }','guard visible, phase == .active, !Task.isCancelled']:
   self.assertIn(text,v)
 def testFormattingReusesRoundtripSafeWalletPolicyWithoutCurrencyInference(self):
  s=self.src('App/WalletIncomeAnalysisPresentation.swift')
  self.assertIn('WalletFormatting(locale: locale).amount(WalletAmount(amount), currency: currency)',s)
  self.assertNotIn('formatter.numberStyle = .currency',s)
  for text in ['unit == currency','NSDecimalAdd','row.changeType','direction == 2 && row.eventType == 3','unknown += 1','BeijingServerTime(raw)']:
   self.assertIn(text,s)
 def testBothFeatureTablesCoverEveryStaticAndDynamicKey(self):
  s=self.src('App/WalletIncomeAnalysisView.swift')
  keys=set(re.findall(r'(?<!\w)text\("([^"]+)"',s))-{'source.'}
  keys|={'slice','more','source.topic','source.activity','source.returned','source.invitation','source.other'}
  reads=set(re.findall(r'readText\("([^"]+)"',s))|{'interrupted','changed','unverified'}
  for table,prefix,names in [('WalletIncomeAnalysis','wallet.analysis.',keys),('WalletIncomeAnalysisRead','wallet.analysis.read.',reads)]:
   catalog=json.loads(self.src('Resources/'+table+'.xcstrings'))['strings']
   self.assertEqual(set(catalog),{prefix+k for k in names})
   for name in names:
    for language in ['en','zh-Hans']:
     unit=catalog[prefix+name]['localizations'][language]['stringUnit'];self.assertEqual(unit['state'],'translated');self.assertTrue(unit['value'])
 def testReadScopeAndWithdrawalLabelsDoNotPromiseCompletenessOrPayout(self):
  catalog=json.loads(self.src('Resources/WalletIncomeAnalysis.xcstrings'))['strings']
  en=lambda k:catalog['wallet.analysis.'+k]['localizations']['en']['stringUnit']['value']
  self.assertEqual(en('withdrawal'),'Withdrawal request debits')
  self.assertEqual(en('source.invitation'),'Merchant referral')
  self.assertIn('not complete account income',en('noPayout'))
  self.assertIn('not an atomic snapshot',en('slice'))
 def testLocalLayoutReplacesMissingHistoricalHelpers(self):
  s=self.src('App/WalletIncomeAnalysisView.swift')
  self.assertNotIn('.walletContentList()',s);self.assertNotIn('WalletReadOnlyDetailStyle()',s)
  self.assertIn('private struct WalletIncomeAnalysisDetailStyle: LabeledContentStyle',s)
  self.assertIn('if !dynamicTypeSize.isAccessibilitySize',s)
  self.assertIn('else { monthRows(summary, currency: currency) }',s)
 def testNativeRegressionScenariosAreAuthored(self):
  s=self.src('Tests/AppUnitTests/WalletIncomeAnalysisClosureTests.swift')
  self.assertEqual(len(re.findall(r'func test',s)),12)
  for text in ['WalletCommerceService(configuration:','WalletHistoryReadRoute(request:','suspendSecond','secondStatus = business ? 200 : 403','testSameOwnerReplacementReader','1234.5678','testTenPageBudget','testAccountChange']:
   self.assertIn(text,s)
if __name__=='__main__':unittest.main()
