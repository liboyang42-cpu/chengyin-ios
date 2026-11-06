"""Source/catalog contracts only, not Swift compilation, rendering or VoiceOver execution."""
from pathlib import Path
import json,re,unittest
ROOT = Path(__file__).resolve().parents[2]
VIEWS = ['App/NativeChannelNotificationConversationView.swift','App/NativeChannelNotificationGlobalView.swift',
         'App/NativeNotificationPermissionNudgeView.swift','App/NativeChannelNotificationEntry.swift',
         'App/NativeChannelNotificationChannelContextEntry.swift']
PRESENTATION='Core/NativeChannelNotificationPresentation.swift'
class NativeChannelNotificationPresentationSourceContracts(unittest.TestCase):
    def read(self,path): return (ROOT/path).read_text()
    def catalog(self): return json.loads(self.read('Resources/NativeChannelNotification.xcstrings'))['strings']
    def test_all_owned_views_render_using_the_existing_selected_locale(self):
        for path in VIEWS:
            source=self.read(path)
            self.assertIn('@Environment(\\.locale) private var locale',source,path)
            self.assertIn('locale: locale',source,path)
            self.assertFalse(re.search(r'"[^"\n]*[\u4e00-\u9fff][^"\n]*"',source),path)
            self.assertNotIn('.authorization.label',source,path)
            self.assertNotRegex(source,r'\.id\([^)]*locale|\.task\(id:[^)]*locale')
        self.assertIn('.environment(\\.locale, RegionalLaunchConfiguration.language(storedLanguage).locale)',self.read('App/QuestifyApp.swift'))
    def test_existing_catalog_has_complete_bilingual_meanings_and_formats(self):
        rows=self.catalog()
        for key in ['state.outcomeUnknown','state.pending','state.applied','state.appliedRedacted','state.refreshFailed',
                    'state.persistenceFailed','state.accessClosed','error.versionConflict','error.read','empty',
                    'recovery.confirm','editor.invalid','permission.readFailed','permission.requestFailed','permission.settingsFailed']:
            self.assertIn('notification.'+key,rows)
        for key,row in rows.items():
            values=[row['localizations'][locale]['stringUnit'] for locale in ['en','zh-Hans']]
            self.assertTrue(all(v['state']=='translated' and v['value'] for v in values),key)
            self.assertEqual(values[0]['value'].count('%@'),values[1]['value'].count('%@'),key)
        self.assertEqual(rows['notification.global.title']['localizations']['en']['stringUnit']['value'],'Notifications')
    def test_every_literal_resource_reference_exists_in_the_same_table(self):
        keys=self.catalog().keys()
        for path in VIEWS+[PRESENTATION]:
            source=self.read(path)
            for key in re.findall(r'\bn\("([^"\n]+)"\)',source):self.assertIn('notification.'+key,keys,path)
            # Only lookup calls/return keys, never unrelated accessibility identifiers.
            for key in re.findall(r'(?:localized\(|return |format\()"(notification\.[A-Za-z0-9.]+)"',source):
                if not key.endswith('.'):self.assertIn(key,keys,path)
        for key in ['level.all','level.mentions','level.nothing','level.inherit','permission.notDetermined','permission.denied',
                    'permission.authorized','permission.provisional','permission.ephemeral','permission.unknown',
                    'permission.enabled','permission.disabled','permission.unsupported','permission.settingUnknown']:
            self.assertIn('notification.'+key,keys)
    def test_original_state_distinctions_and_error_privacy_are_preserved(self):
        source=self.read(PRESENTATION)
        for state in ['loading','saving','checkingReceipt','outcomeUnknown','pending','applied','appliedRedacted','refreshFailed','persistenceFailed','accessClosed']:
            self.assertIn(f'case .{state}: return "notification.state.{state}"',source)
        self.assertIn('case .idle, .ready: return nil',source)
        self.assertIn('guard state == .outcomeUnknown, let failure else { return nil }',source)
        self.assertIn('case "PREFERENCE_VERSION_CONFLICT": return "notification.error.versionConflict"',source)
        self.assertIn('default: return nil',source)
        self.assertNotIn('error.localizedDescription',source);self.assertNotIn('return failure.serverDetails',source)
    def test_recovery_controls_keep_same_original_request_operations(self):
        view=self.read(VIEWS[0])
        for token in ['if let key = model.pendingRequestID','value: key','await model.checkReceipt()',
                      'await model.retryOriginal()','.disabled(!model.canCheckReceipt)',
                      'let intent = draft; Task { await model.save(intent, expectedVersion: preference.version) }',
                      'Task { await model.mute(minutes: minutes) }']:
            self.assertIn(token,view)
        self.assertIn('NativeChannelNotificationPresentation.failureDetail(model.lastFailure, state: model.state, locale: locale)',view)
        self.assertIn('Text(n(localIssue))',view);self.assertIn('localIssue = "editor.invalid"',view)
    def test_permissions_remain_user_actions_and_unknown_is_not_authorized(self):
        view=self.read(VIEWS[2]);source=self.read(PRESENTATION)
        for token in ['if snapshot.authorization == .notDetermined','await model.requestFromUserAction()',
                      'await model.openSettingsFromUserAction()', '.disabled(model.busy)']:
            self.assertIn(token,view)
        for value in ['notDetermined','denied','authorized','provisional','ephemeral','unknown']:
            self.assertIn(f'case .{value}: key = "{value}"',source)
        for token in ['"readFailed"','"requestFailed"','"settingsFailed"','default: key = "actionUnknown"']:
            self.assertIn(token,source)
        self.assertIn('NativeChannelNotificationPresentation.permissionIssue(issue, locale: locale)',view)
    def test_exact_ids_and_time_values_are_not_rewritten_by_ui_language(self):
        source=self.read(PRESENTATION);view=self.read(VIEWS[1])
        self.assertIn('locale: locale, row.scope.value',view)
        self.assertIn('values.map { $0 as CVarArg }',source)
        self.assertIn('NativeChannelNotificationCommand.instant(until)',source)
        self.assertIn('Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)',source)
        for token in ['Double(','Int(','TimeZone(identifier: locale','MarketProfile','RegionalMarket']:self.assertNotIn(token,source)
    def test_presentation_neither_writes_nor_owns_request_or_permission_state(self):
        source=self.read(PRESENTATION)
        for token in ['URLSession','UserDefaults','journal.','requestID:','UUID()','await ','@Observable','@Published','setValue(']:self.assertNotIn(token,source)
        view=self.read(VIEWS[0]);self.assertIn('.id(row.version)',view)
        self.assertIn('_zone = State(initialValue: preference.quietHours?.timeZone ?? TimeZone.current.identifier)',view)
    def test_core_assertions_use_pure_keys_and_hosted_tests_keep_exact_copy(self):
        core=self.read('Tests/CoreTests/NativeChannelNotificationTests.swift');app=self.read('Tests/AppUnitTests/NativeChannelNotificationBindingTests.swift')
        for name in ['testPresentationNeverEchoesUnknownOrMalformedServerErrorCodes','testPresentationShowsKnownConflictOnceWithoutItsTechnicalCode',
                     'testPresentationDoesNotAttachStaleConflictToOtherOutcomes','testPresentationPreservesRecoverySuccessAndRedactionMeanings']:
            self.assertIn('func '+name,core)
        self.assertIn('NativeChannelNotificationPresentation.stateKey(',core)
        self.assertIn('testNotificationOriginalStateCopyRendersBothSelectedLocales',app)
        self.assertIn('结果待确认。保留了原请求，请先核对回执。',app)
        self.assertIn('private server detail',app);self.assertIn('9223372036854775807',app)
        pbx=self.read('Questify.xcodeproj/project.pbxproj')
        self.assertIn('Resources/NativeChannelNotification.xcstrings',pbx)
        self.assertIn('Tests/AppUnitTests/NativeChannelNotificationBindingTests.swift',pbx)
    def test_empty_loading_unverified_and_changed_access_do_not_claim_success(self):
        rows=self.catalog()
        def en(key):return rows['notification.'+key]['localizations']['en']['stringUnit']['value']
        self.assertIn('original request is retained',en('state.outcomeUnknown'))
        self.assertIn('current settings could not be loaded',en('state.refreshFailed'))
        self.assertIn('historical result is hidden',en('state.appliedRedacted'))
        self.assertIn('empty list does not mean all channels are enabled',en('global.overrideBoundary'))
        self.assertIn('permission is still valid',en('recovery.confirm'))
if __name__=='__main__':unittest.main()
