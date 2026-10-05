"""Source-only camera boundaries, not Swift execution or MapKit visual acceptance."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalkingCameraControlsTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/WalkingNavigationView.swift').read_text()
        self.gate = (ROOT / 'Core/WalkingMapCamera.swift').read_text()
        self.coordinator = (ROOT / 'Core/WalkingNavigationCoordinator.swift').read_text()

    def test_bound_camera_compass_and_existing_safe_area_are_present(self):
        for value in ['Map(position: $cameraPosition)', 'MapCompass().mapControlVisibility(.visible)',
                      'MapScaleView()', '.safeAreaInset(edge: .bottom, spacing: 0)',
                      'typeSize.isAccessibilitySize ? 0.72 : 0.54', 'routeCasing', 'Marker(target.title']:
            self.assertIn(value, self.view)
        map_body = self.view.split('@ViewBuilder private var mapContent:', 1)[1].split('private func cameraControl', 1)[0]
        self.assertLess(map_body.index('Map(position:'), map_body.index('if let snapshot = model.cameraSnapshot'))
        self.assertIn('} else if let model, isCameraScopeCurrent(model) {', map_body)
        self.assertIn('.id(retainedCameraScope?.id)', map_body)
        self.assertNotIn('.overlay(', map_body)

    def test_only_explicit_buttons_change_position_without_automatic_follow(self):
        self.assertEqual(self.view.count('cameraPosition = .region'), 1)
        control = self.view.split('private func cameraControl', 1)[1].split('@ViewBuilder private func actions', 1)[0]
        self.assertIn('Button {', control)
        self.assertIn('cameraGate.consume(request, current: model.cameraSnapshot)', control)
        self.assertIn('cameraPosition = .region', control)
        self.assertNotIn('.automatic', self.view)
        self.assertNotIn('withAnimation', control)
        for value in ['.onChange(of: model?.cameraSnapshot) { _, _ in cameraGate.invalidate() }',
                      '.onChange(of: model?.cameraScope) { _, _ in synchronizeCamera() }',
                      '.onDisappear { cameraGate.invalidate();']:
            self.assertIn(value, self.view)
        self.assertNotIn('cameraPosition', self.view.split('.task {', 1)[1].split('@ViewBuilder private var mapContent', 1)[0])

    def test_camera_has_no_location_network_authorization_or_navigation_actions(self):
        control = self.view.split('private func cameraControl', 1)[1].split('@ViewBuilder private func actions', 1)[0]
        for value in ['MapUserLocationButton', 'UserAnnotation', 'CLLocationManager', 'MKDirections',
                      'currentFix(', '.start()', '.update()', 'authorize(', 'URLSession', 'Task {',
                      'UserDefaults', 'checkpoint', 'RuntimeLocationProjection']:
            self.assertNotIn(value, control + self.gate)
        self.assertIn('MapMarkerDensity.fit(points.map', self.gate)
        self.assertIn('snapshot.route.coordinates + [snapshot.target.coordinate.point]', self.gate)

    def test_live_snapshot_checks_context_permission_expiry_and_exact_route(self):
        snapshot = self.coordinator.split('public var cameraSnapshot:', 1)[1].split('public func start()', 1)[0]
        for value in ['cameraScope != nil', 'target.reference == reference', 'target.expiresAt > now()',
                      'target.coordinate.datum == .wgs84', 'route.datum == .wgs84', '!route.isStraightLine',
                      'revision: cameraRevision', 'ownerNamespace: ownerNamespace', 'target: target, route: route']:
            self.assertIn(value, snapshot)
        scope = self.coordinator.split('public var cameraScope:', 1)[1].split('public func start()', 1)[0]
        for value in ['current()', 'foreground', 'location.authorization == .authorized', 'scope.expiresAt > now()',
                      'currentScope.identity == scope.identity']:
            self.assertIn(value, scope)
        for value in ['currentFix(', 'preview(', 'authorize(', 'synchronize(', 'stopWork(']:
            self.assertNotIn(value, snapshot)
        start = self.coordinator.split('public func start()', 1)[1].split('public func update()', 1)[0]
        self.assertIn('cameraRevision = UUID()', start)
        self.assertIn('generation = UUID(); cameraRevision = UUID()', self.coordinator)

    def test_gate_is_ephemeral_one_shot_and_exact_snapshot_fenced(self):
        for value in ['let revision: UUID', 'let ownerNamespace: String',
                      'public let target: AuthorizedWalkingTarget', 'public let route: SearchRoutePreview',
                      'guard request.revision == revision', 'invalidate()\n            guard request.snapshot == current']:
            self.assertIn(value, self.gate)
        self.assertNotIn('Codable', self.gate)

    def test_summary_controls_are_accessible_bilingual_and_explain_unavailable_fit(self):
        for value in ['.frame(minHeight: 44)', '.fixedSize(horizontal: false, vertical: true)',
                      '.disabled(request == nil)', 'Text("walkingCamera.unavailable")',
                      'cameraControl(model, action: .route)', 'cameraControl(model, action: .target)']:
            self.assertIn(value, self.view)
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['walkingCamera.showRoute', 'walkingCamera.showTarget', 'walkingCamera.focusHint', 'walkingCamera.unavailable']:
            for language in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][language]['stringUnit']['value'])
        self.assertEqual(strings['walkingCamera.showTarget']['localizations']['en']['stringUnit']['value'], 'Show destination')

    def test_lost_scope_unmounts_and_erases_camera_without_reviving_prior_geometry(self):
        current = self.view.split('private func isCameraScopeCurrent', 1)[1].split('private func synchronizeCamera', 1)[0]
        self.assertIn('guard let current = model.cameraScope else { return false }', current)
        self.assertIn('current.id == retainedCameraScope?.id', current)
        reset = self.view.split('private func synchronizeCamera', 1)[1].split('private func cameraControl', 1)[0]
        for value in ['model?.synchronizeCameraScope()', 'current?.id != retainedCameraScope?.id',
                      'cameraPosition = Self.neutralCamera', 'cameraGate.invalidate()', 'cameraAction = "none"',
                      'retainedCameraScope = current']:
            self.assertIn(value, reset)
        self.assertEqual(self.view.count('cameraPosition = Self.neutralCamera'), 1)
        self.assertIn('cameraScopeValue != nil && cameraScope == nil { cameraScopeValue = nil }', self.coordinator)
        self.assertIn('phase != .cancelled, phase != .paused', self.coordinator)
        self.assertIn('cameraScopeValue = nil; busy = false', self.coordinator)

    def test_camera_privacy_reset_does_not_invoke_domain_synchronization_or_provider_stop(self):
        reset = self.view.split('private func synchronizeCamera', 1)[1].split('private func cameraControl', 1)[0]
        self.assertNotIn('model?.synchronize()', reset)
        cleanup = self.coordinator.split('public func synchronizeCameraScope()', 1)[1].split('private func invalidate()', 1)[0]
        for forbidden in ['stopWork(', 'invalidate()', 'phase =', 'route =', 'location.', 'planner.', '.cancel(', '.stop(']:
            self.assertNotIn(forbidden, cleanup)
        self.assertIn('cameraScopeValue = nil', cleanup)
        task = self.view.split('.task {', 1)[1].split('.onChange(of:', 1)[0]
        self.assertIn('model?.synchronize()', task)
        self.assertIn('testCameraRetentionCleanupNeverCancelsOrMutatesNavigation',
                      (ROOT / 'Tests/CoreTests/WalkingMapCameraTests.swift').read_text())

    def test_same_scope_renewal_keeps_identity_only_before_previous_expiry(self):
        for value in ['previous.identity == identity', 'previous.expiresAt > now', 'id = previous.id', 'else { id = UUID() }']:
            self.assertIn(value, self.gate)
        self.assertIn('retaining: cameraScopeValue, now: now()', self.coordinator)
        tests = (ROOT / 'Tests/CoreTests/WalkingMapCameraTests.swift').read_text()
        for value in ['testSuspendedSameScopeRefreshKeepsRetentionWhileRouteAndTargetAreCleared',
                      'testExpiredScopeDuringSuspendedRefreshCannotReuseCameraIdentityAfterRenewal',
                      'testExpiredScopeIsNotRevivedByClockOrPermissionRestorationAfterSynchronization',
                      'testPauseBackgroundAndCancelReopeningStartWithDifferentRetentionIdentity']:
            self.assertIn(value, tests)

    def test_authored_test_seams_use_shipping_coordinator_and_offline_camera_state(self):
        core = (ROOT / 'Tests/CoreTests/WalkingMapCameraTests.swift').read_text()
        self.assertIn('WalkingNavigationCoordinator(', core)
        self.assertIn('testLiveAccountRevocationRejectsTapBeforeSynchronize', core)
        self.assertIn('testCancelResumeCannotReviveOldActionWithIdenticalTargetAndRoute', core)
        self.assertIn('testSameRouteRefreshDoesNotReplaceSnapshotOrFetchRouteAgain', core)
        ui = (ROOT / 'Tests/AppUITests/WalkingNavigationFlowTests.swift').read_text()
        self.assertIn('testBilingualMaximumCameraActionsAreExplicitAndClearWithRoute', ui)
        self.assertIn('cameraAction=none', ui)
        self.assertIn('launch("longText", chinese: chinese, maximumType: true)', ui)
        app = (ROOT / 'Tests/AppUnitTests/WalkingNavigationAppTests.swift').read_text()
        self.assertIn('testCameraRejectsChangedFactoryIdentityBeforePollingClearsRoute', app)

if __name__ == '__main__':
    unittest.main()
