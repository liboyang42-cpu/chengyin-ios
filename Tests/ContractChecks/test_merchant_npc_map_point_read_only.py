"""Read-only map-point source checks. These do not compile Swift or execute XCTest."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
CORE = read('Core/MerchantNPCMapPoint.swift')
APP = read('App/MerchantNPCMapPointView.swift')
SERVICE = read('Core/MerchantOperationsService.swift')
READONLY = CORE.split('public final class MerchantNPCMapPointReadOnlyCoordinator')[1]

class MerchantNPCMapPointReadOnlyContracts(unittest.TestCase):
    def test_read_relaxation_is_only_the_map_destination(self):
        guard = SERVICE.split('public func document(')[1].split('switch destination')[0]
        self.assertIn('destination == .npcMapPoint ? access.cooperationManage : access.allows(destination)', guard)
        self.assertIn('guard canRead else', guard)
        branch = SERVICE.split('case .npcMapPoint:')[1].split('case .businessStatus:')[0]
        self.assertIn('value.merchantID == access.identity.merchantID', branch)
        self.assertIn('"api/merchant/coop-profile", body: .json', branch)
    def test_write_policy_and_preflight_still_require_both_permissions(self):
        self.assertIn('case .npcMapPoint: return profileWrite && cooperationManage', read('Core/MerchantOperationsContracts.swift'))
        save = SERVICE.split('public func save(')[1]
        for text in ['guard access.allows(draft.destination)', 'fresh == .draft(baseline)', 'proposed.merchantID == original.merchantID', 'try journal.write(record)', 'try checkSession()']:
            self.assertIn(text, save)
        self.assertNotIn('canRead', save)
    def test_read_only_projection_has_no_edit_confirmation_or_write_path(self):
        for forbidden in ['func edit', 'func prepare', 'func confirm', 'saveReviewed(', 'saveExample(', 'journal.write', 'journal.clear', 'MerchantOperationsCoordinator(']:
            self.assertNotIn(forbidden, READONLY)
        self.assertIn('reader.document(.npcMapPoint)', READONLY)
        self.assertEqual(READONLY.count('try await reader.access()'), 2)
    def test_initial_and_latest_permission_owner_and_session_fences(self):
        for text in ['guard initial.cooperationManage', 'guard latest.cooperationManage', 'value.merchantID == initial.identity.merchantID', 'value.merchantID == latest.identity.merchantID', 'operation == generation', 'scope == reader.scope', 'reader.isAuthenticated', '!Task.isCancelled']:
            self.assertIn(text, READONLY)
        self.assertEqual(READONLY.count('guard accepts(operation, scope) else'), 3)
        self.assertIn('public var point: MerchantNPCMapPoint? { isCurrent ? savedPoint : nil }', READONLY)
    def test_unknown_write_is_observed_without_unlocking(self):
        self.assertIn('reader.hasPending(.npcMapPoint)', READONLY)
        self.assertIn('access?.allows(.npcMapPoint) == true && !hasPendingWrite', READONLY)
        self.assertNotIn('isLocked = false', READONLY)
        detail = APP.split('struct MerchantNPCMapPointReadOnlyView')[1].split('/// Edits stay in this sheet')[0]
        self.assertIn('if coordinator.hasPendingWrite', detail)
        self.assertIn('merchant.operations.unknownOutcome', detail)
    def test_entry_routes_to_details_before_exposing_editing(self):
        entry = APP.split('struct MerchantNPCMapPointEntry')[1].split('struct MerchantNPCMapPointReadOnlyView')[0]
        self.assertIn('MerchantNPCMapPointReadOnlyView(reader:', entry)
        self.assertNotIn('MerchantOperationsDocumentView', entry)
        self.assertNotIn('document.coordinator.isLocked', entry)
        detail = APP.split('struct MerchantNPCMapPointReadOnlyView')[1].split('/// Edits stay in this sheet')[0]
        self.assertIn('else if coordinator.canOpenEditor', detail)
        self.assertIn('MerchantOperationsDocumentView(reader: reader, destination: .npcMapPoint)', detail)
        self.assertIn('merchantMapPoint.readOnly', detail)
        self.assertNotIn('MerchantNPCMapPointFields', detail)
        self.assertIn('.navigationDestination(isPresented: $showEditor)', detail)
        self.assertIn('guard coordinator.canOpenEditor else', detail)
        self.assertNotIn('NavigationLink {', detail)
    def test_read_only_lifetime_discards_stale_points(self):
        detail = APP.split('struct MerchantNPCMapPointReadOnlyView')[1].split('/// Edits stay in this sheet')[0]
        for text in ['.task(id: model.refreshIntent)', '.onChange(of: reader.scope)', 'phase != .active', '.onDisappear { model.disappear() }']:
            self.assertIn(text, detail)
        self.assertIn('generation += 1; savedPoint = nil; access = nil', READONLY)
    def test_read_only_user_copy_is_bilingual(self):
        strings = json.loads(read('Resources/MerchantNPCMapPointLocalizations.fragment.json'))['strings']
        for key in ['merchantMapPoint.readOnly', 'merchantMapPoint.edit']:
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][lang]['stringUnit']['value'])
    def test_active_fixtures_supply_a_real_recognized_role_and_merchant(self):
        core = read('Tests/CoreTests/MerchantNPCMapPointReadOnlyTests.swift')
        app = read('Tests/AppUnitTests/MerchantNPCMapPointReadOnlyTests.swift')
        roles = set(re.findall(r'= "(MERCHANT_[A-Z]+)"', read('Core/MerchantAccess.swift')))
        for text, pattern in [(core, r'role: String = "(MERCHANT_[A-Z]+)"'), (app, r'roleCode = "(MERCHANT_[A-Z]+)"')]:
            values = re.findall(pattern, text)
            self.assertTrue(values); self.assertTrue(set(values).issubset(roles))
            self.assertIn('"roleCode":', text); self.assertIn('"merchant": ["id":', text)
            self.assertIn('JSONDecoder().decode(MerchantOperationsAccess.self', text)
        self.assertIn('testRecognizedRoleFixturesDecodeWithoutGrantingRoleDerivedPermissions', core)
        self.assertIn('testMalformedRoleFixtureFailsClosedWithoutDocumentOrSave', app)
    def test_runtime_zero_write_and_race_cases_are_authored_not_claimed_executed(self):
        core = read('Tests/CoreTests/MerchantNPCMapPointReadOnlyTests.swift')
        app = read('Tests/AppUnitTests/MerchantNPCMapPointReadOnlyTests.swift')
        for name in ['testCoopOnlyReadsExactOwnerScopedPointWithoutAWrite', 'testCoopOnlyCannotUseAnApprovedWriterOrMutateItsJournal', 'testSessionReaderReadOnlyFlowNeverSendsSaveOrMutatesJournal', 'testProfileRevocationDuringReadKeepsReadOnlyVisibilityWithoutEditor', 'testUnknownWriteCanBeReadButNeverClearedOrReopenedForEdit', 'testInvalidationDuringReadDiscardsLateResponse']:
            self.assertIn('func ' + name, core)
        self.assertIn('XCTAssertEqual(journal.writeCount, 0)', core)
        self.assertIn('XCTAssertEqual(reader.saveCount, 0)', core)
        self.assertIn('XCTAssertEqual(reader.saveCount, 0)', app)

    def test_shipping_model_rejects_stale_and_cancelled_intents_before_dispatch(self):
        model = APP.split('final class MerchantNPCMapPointReadOnlyModel')[1].split('/// Source-like row')[0]
        load = model.split('func load(_ intent: RefreshIntent?) async')[1]
        guard = 'guard !Task.isCancelled, let intent, intent == refreshIntent else { return }'
        self.assertIn(guard, load)
        self.assertLess(load.index(guard), load.index('await coordinator.load()'))
        self.assertNotIn('appear(', load)
        self.assertNotIn('resume(', load)
        self.assertNotIn('activeIntent =', load)
    def test_same_scope_reopen_gets_new_intent_and_closed_resume_cannot_activate(self):
        model = APP.split('final class MerchantNPCMapPointReadOnlyModel')[1].split('/// Source-like row')[0]
        for text in ['appearanceID: UUID', 'activeIntent.scope == coordinator.reader.scope', 'func disappear() { isVisible = false; suspend() }', 'activeIntent = nil; coordinator.invalidate()', 'guard isVisible else { return nil }']:
            self.assertIn(text, model)
        self.assertEqual(model.count('.init(appearanceID: UUID(), scope: coordinator.reader.scope)'), 2)
    def test_views_capture_exact_intent_and_never_activate_from_async_task(self):
        views = APP.split('struct MerchantNPCMapPointEntry')[1].split('/// Edits stay in this sheet')[0]
        for owner in ['point', 'model']:
            self.assertIn('.task(id: ' + owner + '.refreshIntent) { [intent = ' + owner + '.refreshIntent] in await ' + owner + '.load(intent) }', views)
            self.assertIn('.onAppear { ' + owner + '.appear(isActive: scenePhase == .active) }', views)
            self.assertIn('.onDisappear { ' + owner + '.disappear() }', views)
        self.assertIn('let intent = model.refreshIntent\n                    Task { await model.load(intent) }', views)
        self.assertNotIn('Task { await model.load()', views)
        self.assertNotIn('Task { model.appear', views)
        self.assertNotIn('Task { model.resume', views)
        self.assertNotIn('await model.load(model.refreshIntent)', views)
    def test_actual_shipping_model_has_queued_close_reopen_cancel_regressions(self):
        tests = read('Tests/AppUnitTests/MerchantNPCMapPointReadOnlyTests.swift')
        for name in ['testQueuedRefreshAfterCloseDoesNotDispatchEvenAccessRead', 'testSameScopeReopenRejectsOldQueuedIntentButCurrentRefreshWorks', 'testCancelledTaskCannotDispatchOrActivateAnAppearance', 'testCancelledOldTaskCannotAdoptReopenedAppearance', 'testScopeChangeBeforeDispatchRejectsOldIntentWithoutAnyRead', 'testQueuedResumeAfterDisappearCannotReopenTheModel', 'testBackgroundInvalidatesQueuedIntentAndForegroundGetsFreshIntent', 'testInactiveAppearanceAndUndisplayedResumeCannotStartARead']:
            self.assertIn('func ' + name, tests)
        for text in ['MerchantNPCMapPointReadOnlyModel(reader: reader)', 'XCTAssertEqual(reader.accessCount, 0)', 'XCTAssertEqual(reader.readCount, 0)', 'XCTAssertEqual(reader.saveCount, 0)', 'queued.cancel(); await queued.value']:
            self.assertIn(text, tests)

    def test_swiftui_task_identifier_is_equatable_with_synthesized_uuid_fields(self):
        model = APP.split('final class MerchantNPCMapPointReadOnlyModel')[1].split('/// Source-like row')[0]
        intent = model.split('struct RefreshIntent:')[1].split('    let coordinator:')[0]
        self.assertTrue(intent.startswith(' Equatable {'))
        self.assertIn('let appearanceID: UUID', intent)
        self.assertIn('let scope: UUID', intent)
        self.assertNotIn('static func ==', intent)
        self.assertNotIn('func hash(', intent)
        self.assertIn('.task(id: point.refreshIntent)', APP)
        self.assertIn('.task(id: model.refreshIntent)', APP)

if __name__ == '__main__': unittest.main()
