"""Source contract for export hand-off. Does not execute Swift."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamExportDeliverySourceTests(unittest.TestCase):
    def setUp(self):
        self.lease = (ROOT / 'Core/RoamExportDeliveryLease.swift').read_text()
        self.view = (ROOT / 'App/RoamExplorationExportView.swift').read_text()
        self.tests = (ROOT / 'Tests/CoreTests/RoamExportDeliveryLeaseTests.swift').read_text()

    def test_write_does_not_wait_on_the_main_thread(self):
        self.assertNotIn('DispatchQueue.main.sync', self.lease)
        self.assertNotIn('MainActor.run', self.lease)
        self.assertIn('guard Thread.isMainThread else { return }', self.lease)
        self.assertIn('if Thread.isMainThread', self.lease)

    def test_clock_rollback_cannot_extend_the_file(self):
        self.assertIn('highWaterMs', self.lease)
        self.assertIn('if ms > highWaterMs { highWaterMs = ms }', self.lease)
        self.assertIn('A rolled-back clock does not extend the original lifetime', self.tests)

    def test_off_main_write_uses_facts_published_on_main(self):
        self.assertIn('publishedIdentity', self.lease)
        self.assertIn('publishedForeground', self.lease)
        self.assertIn('deliveryContext.publish()', self.view)
        self.assertIn('.onChange(of: tools.identity)', self.view)
        self.assertIn('.onChange(of: scenePhase)', self.view)
        self.assertIn('testOffMainWriteReadsPublishedFactsWithoutWaiting', self.tests)
        self.assertIn('model.revokeDelivery()', self.view)
