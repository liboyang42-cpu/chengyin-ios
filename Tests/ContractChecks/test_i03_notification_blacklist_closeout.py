"""Source contracts for independent OS settings and original blacklist receipts."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
class I03NotificationBlacklistCloseoutTests(unittest.TestCase):
    def source(self,name):return (ROOT/'App'/(name+'.swift')).read_text()
    def contains(self,name,values):
        for value in values:self.assertIn(value,self.source(name))
    def testSettingsIncludesIndependentOSAndExistingServiceEntries(self):
        source=self.source('SettingsView')
        self.assertEqual(source.count('NativeNotificationPermissionEntry()'),1)
        self.assertIn('Section {\n                    NativeNotificationPermissionEntry()\n                    NativeChannelNotificationSettingsEntry(session: session)',source)
        self.assertIn('Text("notification.permission.delivery", tableName: "NativeChannelNotification")',source)
    def testEntryRequiresNoAccountOrServiceCoordinator(self):
        source=self.source('NativeNotificationPermissionEntry')
        self.assertIn('NavigationLink { NativeNotificationPermissionNudgeView(model: model) }',source)
        self.assertIn('NativeNotificationPermissionState(provider: NativeNotificationPermissionAdapter())',source)
        self.assertIn('.accessibilityIdentifier("notification.permission.entry")',source)
        for value in ['AppSession','makeFlow','coordinator','@EnvironmentObject','.task','onAppear','requestFromUserAction()','openSettingsFromUserAction()','refresh()']:self.assertNotIn(value,source)
    def testExistingUnavailableServiceDestinationCannotHideIndependentEntry(self):
        self.contains('NativeChannelNotificationEntry',['if let model { NativeChannelNotificationGlobalView(model: model','else if attempted { ContentUnavailableView(n("entry.unavailable")','model = makeFlow(nil)'])
        self.contains('SettingsView',['NativeNotificationPermissionEntry()'])
    def testNudgeReadOnlyAppearanceAndExplicitActionsRemainSeparate(self):
        self.contains('NativeNotificationPermissionNudgeView',['.task { await model.refresh() }','if phase == .active { Task { await model.refresh() } }','if snapshot.authorization == .notDetermined','Button(n("permission.request")) { Task { await model.requestFromUserAction() } }','Button(n("permission.settings")) { Task { await model.openSettingsFromUserAction() } }','.disabled(model.busy)'])
    def testAdapterRereadsCurrentOSStatusBeforePrompt(self):
        self.contains('NativeNotificationPermissionAdapter',['guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }','center.requestAuthorization(options: [.alert, .sound, .badge])','UIApplication.openNotificationSettingsURLString'])
        entry=self.source('NativeNotificationPermissionEntry');self.assertNotIn('registerForRemoteNotifications',entry);self.assertNotIn('setBadgeCount',entry)
    def testUnknownAndFailureNeverBecomeAuthorized(self):
        self.contains('NativeNotificationPermissionStatusPresentation',['if let authorization { return .known(authorization) }','if busy { return .loading }','if hasIssue { return .unavailable }','return .waiting'])
        core=(ROOT/'Core/NativeNotificationPermissionState.swift').read_text()
        for value in ['guard !busy, snapshot?.authorization == .notDetermined else { return }','guard !busy, let authorization = snapshot?.authorization, authorization != .notDetermined else { return }','guard ticket == generation, !Task.isCancelled else { return }']:self.assertIn(value,core)
    def testBlacklistOriginalIdentitiesRemainFullAndSelectable(self):
        source=self.source('NativeBlacklistView')
        self.assertEqual(source.count('.font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)'),3)
        for value in ['review.expectedBlockID','review.requestID.uuidString','original.peerID','original.expectedBlockID','original.requestID.uuidString','result.peerID','result.requestID','.accessibilityIdentifier("blacklist.original")','.accessibilityIdentifier("blacklist.resultIdentity")']:self.assertIn(value,source)
    def testBlacklistExplicitRecoveryAndHistoricalMeaningRemain(self):
        self.contains('NativeBlacklistView',['await flow.confirm(expected: review)','.disabled(!flow.canConfirm)','await flow.recover()','.disabled(!flow.canRecover)','text("blacklist.historical")','text("blacklist.unknown")','text("blacklist.confirmImpact")','await flow.settleOriginal(confirmed: original)'])
    def testBlacklistCurrentVisitAndForegroundFenceRemain(self):
        self.contains('NativeBlacklistView',['guard visible, scenePhase == .active, let capturedVisit = visit else { return }','guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }','.onDisappear { visible = false; close() }','.onChange(of: flow.isCurrent)','private func close() { visit = nil; settlement = nil; confirmingSettlement = false; flow.invalidate() }','.privacySensitive()'])
    def testBlacklistNormalFriendHomeRouteIsStillPresent(self):
        self.contains('NativeFriendSessionEntry',['blacklistFactory: { session.makeNativeBlacklistFlow() }'])
        self.contains('NativeFriendHomeView',['case .blacklist(let blacklist): NativeBlacklistView(flow: blacklist)'])
    def testEntryAndAllBlacklistLabelsKeepBilingualCatalogs(self):
        notification=json.loads((ROOT/'Resources/NativeChannelNotification.xcstrings').read_text())['strings']
        blacklist=json.loads((ROOT/'Resources/NativeBlacklist.xcstrings').read_text())['strings']
        entries=[notification[k] for k in ['notification.permission.title','notification.permission.delivery']]+list(blacklist.values())
        for entry in entries:
            for language in ['en','zh-Hans']:
                unit=entry['localizations'][language]['stringUnit'];self.assertEqual(unit['state'],'translated');self.assertTrue(unit['value'].strip())
    def testExistingSettingsOwnersAndLocaleLifecycleRemain(self):
        self.contains('SettingsView',['ProfileSettingsProfileEntry(session: session, owner: profileOwner)','ProfileSettingsFavoritesEntry(session: session, owner: favoritesOwner)','.onAppear { profileOwner.appear() }','.onDisappear { profileOwner.retire() }','.modifier(ProfileSettingsFavoritesLifecycle(session: session, owner: favoritesOwner))','.environment(\\.locale, RegionalLaunchConfiguration.language(storedLanguage).locale)'])
if __name__=='__main__':unittest.main()
