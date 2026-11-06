"""Presentation and authority source checks, not SwiftUI runtime verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class B03ReadOnlyUICloseoutTests(unittest.TestCase):
    def source(self, name): return (ROOT / name).read_text()
    def testSevenFactRowsUseVerticalFullWidthPresentationWithoutTruncatingValues(self):
        for name, count in [('WorkshopOwnedLibraryView.swift',1),('WorkshopOwnedPackageView.swift',3),('WorkshopPurchasedLibraryView.swift',3)]:
            source = self.source('App/' + name)
            self.assertEqual(source.count('VStack(alignment: .leading, spacing: RevolutContentStyle.spacing)'), count)
            self.assertEqual(source.count('.fixedSize(horizontal: false, vertical: true).textSelection(.enabled)'), count)
            self.assertEqual(source.count('.padding(.vertical, RevolutContentStyle.spacing)'), count)
            self.assertNotIn('RevolutInsetRow(', source)
            self.assertNotIn('.lineLimit(1)', source)
            self.assertNotIn('.truncationMode(', source)
            self.assertNotIn('.minimumScaleFactor(', source)
    def testOriginalMetadataRemainsVerbatimAndPoliciesKeepEnvironmentLocale(self):
        owned = self.source('App/WorkshopOwnedLibraryView.swift')
        package = self.source('App/WorkshopOwnedPackageView.swift')
        paid = self.source('App/WorkshopPurchasedLibraryView.swift')
        for source in [owned,package,paid]:
            self.assertIn('Text(verbatim: value)', source)
            self.assertIn('@Environment(\\.locale) private var locale', source)
            self.assertNotIn('Locale.current', source)
        for expression in ['packageLabel("policy." + value, locale: locale)', 'limit.unlimited ? packageLabel("unlimited", locale: locale) : String(limit.maximum)']:
            self.assertIn('Text(verbatim: ' + expression + ')', package)
        for expression in ['purchasedLabel("policy." + policy, locale: locale)', 'value.unlimited ? purchasedLabel("explicitUnlimited", locale: locale) : String(value.maximum)']:
            self.assertIn('Text(verbatim: ' + expression + ')', paid)
    def testOwnedDetailAndPackageKeepVisitFencesAndCapturedCallbacks(self):
        owned = self.source('App/WorkshopOwnedLibraryView.swift')
        package = self.source('App/WorkshopOwnedPackageView.swift')
        for text in ['navigation.isCurrentDetailVisit(routeID: routeID, visitID: visitID)', 'callbacks.appear(current: navigation.detailAppearance)', 'callbacks.disappear()', 'navigation.detailViewDisappeared(departing.appearance)', 'navigation.packageBinding(detailRouteID: routeID, visitID: visitID)']:
            self.assertIn(text, owned)
        for text in ['navigation.isCurrentPackageVisit(route)', 'callbacks.appear(current: navigation.packageAppearance)', 'callbacks.disappear()', 'navigation.packageViewDisappeared(departing.appearance)']:
            self.assertIn(text, package)
    def testPurchasedListKeepsPresentationAndIndependentInstallFactories(self):
        source = self.source('App/WorkshopPurchasedLibraryView.swift')
        for text in ['let rendered = displayed.permit', 'navigation.select(licenseId: item.id, presentation: rendered)', 'navigation.listViewDisappeared(displayed)', 'navigation.detailViewDisappeared(displayed)', 'WorkshopPaidInstallEntry(item: item, makeController: makeInstall, makeProfessional: makeProfessional, makeText: makeText)', 'if let handlers = makeUpgrade()']:
            self.assertIn(text, source)
        self.assertIn('makeUpgrade: @escaping WorkshopPurchasedUpgradeFactory = { nil }', source)
    def testNormalAccountStillUsesSeparatelyApprovedReadChains(self):
        account = self.source('App/AccountView.swift')
        self.assertIn('WorkshopOwnedAccountLink(browser: session.workshopOwnedBrowser)', account)
        self.assertIn('WorkshopPurchasedAccountLink(browser: session.workshopPurchasedBrowser', account)
        for name in ['WorkshopOwnedComposition.swift','WorkshopPurchasedComposition.swift']:
            source = self.source('App/' + name)
            self.assertIn('currentApproval()?.revision == approval.revision', source)
            self.assertIn('ContentDraftContextFence.matches(current(), context)', source)
        source = self.source('App/WorkshopOwnedComposition.swift')
        self.assertIn('packageApproval: WorkshopOwnedPackageReadApproval? = nil', source)
        self.assertIn('currentPackageApproval: @escaping () -> WorkshopOwnedPackageReadApproval? = { nil }', source)
    def testStoreKitPureDiagnosticRetainsOriginalSnapshotAndAccessibility(self):
        source = self.source('App/StoreKit2SubscriptionAndRefundSectionView.swift')
        view = source.split('public struct StoreKit2SubscriptionAndRefundSectionView: View {',1)[1]
        self.assertEqual(view.count('VStack(alignment: .leading, spacing: RevolutContentStyle.spacing)'),4)
        self.assertIn('Text(verbatim: snapshot.summaryText)',view)
        self.assertIn('Text(verbatim: row.badgeText)',view)
        self.assertIn('Text(verbatim: "规则：\\(row.enforcementRule)")',view)
        for identifier in ['storeKit2Lifecycle.overallBadge','storeKit2Lifecycle.summary','storeKit2Lifecycle.row.\\(row.id)']:
            self.assertIn('.accessibilityIdentifier("'+identifier+'")',view)
        self.assertNotIn('Spacer()',view)
        self.assertNotIn('.font(.caption2',view)
        for operation in ['.purchase(', 'AppStore.sync(', '.finish()', 'Task {', 'URLSession', 'Button(']:
            self.assertNotIn(operation,view)
    def testMetadataViewsDoNotGainPaymentOrMutationCalls(self):
        for name in ['WorkshopOwnedLibraryView.swift','WorkshopOwnedPackageView.swift','WorkshopPurchasedLibraryView.swift']:
            source = self.source('App/' + name)
            for operation in ['confirmPurchase(', 'AppStore.sync(', '.purchase(', 'URLSession', 'WorkshopCommerceApproval(']:
                self.assertNotIn(operation, source)
    def testNativeNarrowAccessibilityCasesAreAuthored(self):
        source=self.source('Tests/AppUnitTests/StoreKit2SubscriptionAndRefundSectionViewTests.swift')
        for text in ['testDefaultDiagnosticWrapsAtNarrowWidthWithAccessibilityText','testWarningDiagnosticWrapsLongOriginalRulesWithoutChangingSnapshot','.dynamicTypeSize(.accessibility5)','CGSize(width: 320, height: 20_000)']:
            self.assertIn(text,source)

if __name__ == '__main__': unittest.main()
