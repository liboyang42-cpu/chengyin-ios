"""Supplemental source checks only: not Swift compilation, XCTest or device proof."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class PlayLocationFidelitySourceChecks(unittest.TestCase):
    def test_measurements_forward_through_every_production_hop(self):
        for path in ['App/PlayNativeDeviceProvider.swift', 'App/RuntimePlayDeviceProvider.swift',
                     'App/PlayDeviceTaskViews.swift', 'Core/PlayPrefabRuntime.swift']:
            text = read(path)
            forwards = re.findall(r'\.location\([^\n]+', text)
            self.assertTrue(forwards, path)
            for call in forwards:
                if 'let ' not in call:
                    self.assertIn('accuracyMeters:', call, (path, call))
                    self.assertIn('measuredAt:', call, (path, call))
        codec = read('Core/PlayRecoveryStorage.swift')
        for assignment in ['self = .location', 'stored = .location']:
            line = next(line for line in codec.splitlines() if assignment in line)
            self.assertIn('accuracyMeters: accuracy, measuredAt: time', line)

    def test_wire_encoding_preserves_accuracy_without_a_quality_filter(self):
        service = read('Core/PlayExperienceService.swift')
        location = block(service, 'case .location(let longitude', 'case .photo(let url)')
        self.assertIn('coordinateSystem == "GCJ02"', location)
        self.assertIn('PlayLocationMeasurement.validate(', location)
        self.assertIn('now: nil', location)
        self.assertIn('if let accuracyMeters { fields["accuracy"] = String(accuracyMeters) }', location)
        self.assertNotRegex(location, r'accuracyMeters\s*[<>]')
        self.assertNotRegex(location, r'fields\["(?:measuredAt|timestamp)"\]')

    def test_new_submit_checks_freshness_before_dispatch_and_replay_does_not(self):
        text = read('Core/PlayExperienceCoordinator.swift')
        submit = block(text, 'public func submit(_ review:', 'private func dispatch(')
        self.assertLess(submit.index('validateNewLocationMeasurement()'), submit.index('await dispatch(review)'))
        retry = block(text, 'public func retryExactBranchAfterReadback()', 'public func requestHint')
        self.assertIn('await dispatch(review, recovering: pending)', retry)
        self.assertNotIn('validateNewLocationMeasurement', retry)
        service = read('Core/PlayExperienceService.swift')
        direct = block(service, 'public func complete(', 'func completionRequest(')
        self.assertLess(direct.index('validateNewLocationMeasurement()'), direct.index('completionRequest('))

    def test_integrity_and_freshness_are_explicit(self):
        helper = read('Core/PlayDeviceTasks.swift').split('public enum PlayLocationMeasurement', 1)[1]
        for guard in ['accuracyMeters == nil && measuredAt == nil', 'let accuracyMeters, let measuredAt',
                      'accuracyMeters.isFinite, accuracyMeters >= 0',
                      'measuredAt.timeIntervalSinceReferenceDate.isFinite',
                      'now.timeIntervalSinceReferenceDate.isFinite, age >= 0, age <= 30']:
            self.assertIn(guard, helper)
        self.assertNotIn('accuracyMeters <= 80', helper)

    def test_manager_identity_precedes_continuation_clear(self):
        text = read('App/PlayNativeDeviceProvider.swift')
        take = block(text, 'private func takeLocationReply(', 'func locationManager(_ manager: CLLocationManager, didUpdateLocations')
        self.assertLess(take.index('guard manager === locationManager'), take.index('locationReply = nil'))
        self.assertIn('manager.delegate = nil; manager.stopUpdatingLocation()', take)
        update = block(text, 'func locationManager(_ manager: CLLocationManager, didUpdateLocations', 'func locationManager(_ manager: CLLocationManager, didFailWithError')
        self.assertIn('guard let reply = takeLocationReply(manager) else { return }', update)
        self.assertIn('coordinateSystem: "WGS84"', update)
        failure = block(text, 'func locationManager(_ manager: CLLocationManager, didFailWithError', 'func cancel()')
        self.assertIn('takeLocationReply(manager)?.resume(throwing: error)', failure)
        authorization = block(text, 'private func requestLocationIfAuthorized(', '/// Take only')
        self.assertIn('guard manager === locationManager, locationReply != nil else { return }', authorization)

    def test_cancel_is_scoped_and_default_grants_stay_empty(self):
        text = read('App/PlayNativeDeviceProvider.swift')
        self.assertIn('init(grants: Set<PlayDeviceKind> = []', text)
        location = block(text, 'case .location:', 'case .motion:')
        self.assertIn('try Task.checkCancellation()', location)
        self.assertIn('self.locationGeneration == generation', location)
        cancel = block(text, 'func cancel()', '@MainActor struct PlayNativeCameraSheet')
        self.assertIn('takeLocationReply(manager)?.resume(throwing: CancellationError())', cancel)
        self.assertIn('enabled: Set<PlayExperienceCapability> = []', read('Core/PlayExperienceService.swift'))

    def test_real_xctest_coverage_is_authored_not_claimed_run(self):
        core = read('Tests/CoreTests/PlayExperienceTests.swift')
        app = read('Tests/AppUnitTests/RuntimeDependencyAppTests.swift')
        for test in ['testUnknownJournalRoundTripKeepsMeasurementIdentityAndRequestBytes',
                     'testLegacyStoredEvidenceDecodesWithoutInventingAccuracyAndKeepsBody',
                     'testNewMeasurementFreshnessBoundaries',
                     'testLegacyUnknownJournalKeepsItsIDAndAbsentMeasurementAfterRestart',
                     'testStaleNewSubmitDoesNotCreatePendingOrDispatch',
                     'testProposedServerBoundaryPreservesBoth80And81RatherThanDroppingPoorAccuracy']:
            self.assertIn('func ' + test, core)
        for test in ['testCancelledManagerCallbacksCannotConsumeSuccessorOrRequestAuthorization',
                     'testTaskCancellationDetachesItsManagerAndDoesNotCancelSuccessor',
                     'testNativeRejectsInvalidAccuracyStaleAndFutureSamples']:
            self.assertIn('func ' + test, app)
        self.assertIn('XCTAssertEqual(first, replay)', core)
        self.assertIn('XCTAssertNil(next.delegate)', app)


    def test_arrival_accuracy_label_is_advisory_and_never_gates_or_drops(self):
        helper = block(read('Core/PlayDeviceTasks.swift'), 'public enum PlayArrivalAccuracy', '\n}\n')
        self.assertIn('advisoryLimitMeters = 80.0', helper)
        self.assertIn('accuracyMeters.isFinite, accuracyMeters >= 0 else { return false }', helper)
        for path in ['Core/PlayExperienceService.swift', 'Core/PlayExperienceCoordinator.swift',
                     'Core/PlayPrefabRuntime.swift', 'App/RuntimePlayDeviceProvider.swift',
                     'App/PlayNativeDeviceProvider.swift']:
            self.assertNotIn('PlayArrivalAccuracy', read(path), path)
        view = read('App/PlayDeviceTaskViews.swift')
        review = block(view, 'Text("playx.device.locationCaptured")', 'case .photo(')
        self.assertIn('PlayArrivalAccuracy.isLow(accuracyMeters)', review)
        self.assertIn(".disabled(!model.canReviewOutput || coordinateSystem != \"GCJ02\")", review)
        self.assertNotIn('isLow(accuracyMeters)) ||', review)

    def test_unprojectable_runtime_sample_is_invalid_not_unknown(self):
        wrapper = block(read('App/RuntimePlayDeviceProvider.swift'), 'if kind == .location {', '} else { result')
        self.assertIn('RuntimeLocationProjection.gcj02(raw)', wrapper)
        self.assertIn('catch { throw PlayExperienceError.invalidAction }', wrapper)
        self.assertLess(wrapper.index('location.currentFix()'), wrapper.index('do {'))
        self.assertIn('coordinateSystem: "GCJ02", accuracyMeters: fix.accuracyMeters, measuredAt: fix.measuredAt', wrapper)

    def test_i01_wave3_localizations_and_tests_are_present(self):
        import json
        strings = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key in ['playx.device.accuracy', 'playx.device.lowAccuracy']:
            self.assertEqual(set(strings[key]['localizations']), {'en', 'zh-Hans'}, key)
        self.assertEqual(strings['playx.device.lowAccuracy']['localizations']['zh-Hans']['stringUnit']['value'], '定位精度不足 · 可扫码完成')
        core = read('Tests/CoreTests/PlayExperienceTests.swift')
        for test in ['testMissingAccuracyStaysLegacyAndInsideThresholdIsSentExactly',
                     'testOutsideThresholdIsStillSentAndServerVerdictIsARejectionNotUnknown',
                     'testInvalidIncompleteStaleAndWGS84EvidenceNeverReachesTransport',
                     'testScanCompletionCarriesNoLocationMetadata',
                     'testProjectionBoundaryKeepsMeasurementOrStaysUnavailable',
                     'testAdvisoryLabelNeverTreatsMissingOrInvalidAsLow']:
            self.assertIn('func ' + test, core)
        self.assertIn('func testAccuracyBoundaryKeepsMeasuredMetadataThroughProjection', read('Tests/CoreTests/RoamLiveSessionTests.swift'))
        self.assertIn('func testScopedLocationWrapperCarriesPoorAccuracyAndRefusesUnprojectableSamples', read('Tests/AppUnitTests/RuntimeDependencyAppTests.swift'))


if __name__ == '__main__':
    unittest.main()
