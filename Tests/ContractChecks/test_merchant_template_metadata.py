"""Exact duration/players mapping and acknowledged readback source checks; no runtime proof."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateMetadataChecks(unittest.TestCase):
    def test_metadata_is_distinct_from_session_local_capacity(self):
        source = read('Core/MerchantOperationsContracts.swift')
        model = source.split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        self.assertIn('public var gameDurationMinutes = ""', model)
        self.assertIn('public var players = ""', model)
        self.assertIn('duration, players, imgUrl', model)
        self.assertNotIn('maximumParticipants', model.split('public var fields:')[1])
        self.assertNotIn('participationPlan?.durationMinutes', model)

    def test_duration_strict_decode_and_integer_wire_match_backend_dto_bound(self):
        model = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        for token in ['c.contains(.duration)', 'c.decode(Int.self, forKey: .duration)',
                      'guard Self.validDuration(gameDurationMinutes) != nil else { throw APIError.malformedResponse }',
                      'number >= 0, number <= Int(Int32.max)', 'fields["duration"] = duration', '"players": players']:
            self.assertIn(token, model)
        self.assertNotIn('Double(', model)

    def test_existing_protocol_carries_create_receipt_without_guessing_an_id(self):
        reader = read('Core/MerchantOperationsReading.swift')
        session = reader.split('public func saveTemplateReviewed(')[1].split('private func read<Value>')[0]
        self.assertIn('service.save(.template(draft)', session)
        for token in ['approval: approval', 'journal: journal', 'self.currentSession() == session', 'return acknowledgement.templateID']:
            self.assertIn(token, session)
        default = reader.split('public extension MerchantOperationsReading')[1]
        self.assertLess(default.index('guard let id = draft.id, id > 0'), default.index('try await saveReviewed(.template(draft)'))

    def test_confirmation_uses_frozen_baseline_then_exact_acknowledged_id(self):
        source = read('Core/MerchantOperationsReading.swift')
        confirm = source.split('public func confirm(')[1]
        self.assertIn('latest == .draft(value.baseline)', confirm)
        self.assertIn('reader.saveTemplateReviewed(template, baseline: baseline)', confirm)
        self.assertIn('submitted.id == nil || submitted.id == id', confirm)
        self.assertIn('destination = .template(id)', confirm)
        self.assertIn('returned.id == id', confirm)
        self.assertIn('baseline = .template(returned); draft = .template(returned)', confirm)
        self.assertIn('public private(set) var destination:', source)

    def test_readback_failure_cannot_reenter_write_catch_or_keep_submitted_baseline(self):
        source = read('Core/MerchantOperationsReading.swift')
        block = source.split('if case .template(let submitted) = value.draft')[1].split('else if destination == .character')[0]
        self.assertLess(block.index('document = nil; baseline = nil; draft = nil'), block.index('reader.document(destination)'))
        self.assertIn('merchant.templateMetadata.readbackFailed', block)
        self.assertIn('operation == generation, reader.scope == value.scope', block)
        self.assertNotIn('saveReviewed(', block); self.assertNotIn('saveTemplateReviewed(', block)
        self.assertNotIn('throw error', block)

    def test_new_identity_rebinds_existing_image_owner_after_confirmation(self):
        views = read('App/MerchantOperationsViews.swift')
        confirm = views.split('func confirm(_ value: MerchantOperationsConfirmation)')[1].split('func invalidate()')[0]
        self.assertIn('let previousDestination = coordinator.destination', confirm)
        self.assertIn('previousDestination != coordinator.destination', confirm)
        self.assertIn('imageOwner?.invalidate()', confirm)
        self.assertIn('imageHost?.document(reader: coordinator.reader, destination: coordinator.destination)', confirm)

    def test_server_metadata_editor_and_snapshot_are_localized_without_capacity_rename(self):
        app = read('App/MerchantOperationsEditor.swift')
        self.assertIn('templateField("merchant.templateMetadata.duration", \\.gameDurationMinutes', app)
        self.assertIn('templateField("merchant.templateMetadata.players", \\.players', app)
        self.assertIn('template.gameDurationMinutes.trimmingCharacters', app)
        fragment = json.loads(read('Resources/MerchantTemplateMetadataLocalizations.fragment.json'))
        keys = set()
        for path in ['Core/MerchantOperationsContracts.swift', 'Core/MerchantOperationsReading.swift', 'App/MerchantOperationsEditor.swift']:
            source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', read(path))
            keys.update(re.findall(r'"(merchant\.templateMetadata\.[A-Za-z]+)"', source))
        self.assertEqual(set(fragment), keys)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertIn('not a venue capacity limit', fragment['merchant.templateMetadata.scopeHint']['localizations']['en']['stringUnit']['value'])
        self.assertIn('does not clear', fragment['merchant.templateMetadata.omissionHint']['localizations']['en']['stringUnit']['value'])

    def test_default_off_and_local_only_guards_remain_before_transport(self):
        reader = read('Core/MerchantOperationsReading.swift')
        confirm = reader.split('public func confirm(')[1]
        self.assertLess(confirm.index('guard !value.draft.localOnlyReview'), confirm.index('reader.saveTemplateReviewed'))
        self.assertLess(confirm.index('guard reader.canSave'), confirm.index('reader.saveTemplateReviewed'))
        self.assertIn('guard !localOnlyReview else', read('Core/MerchantOperationsDraft.swift'))
        ai = read('Core/MerchantTemplateAssistContracts.swift')
        self.assertNotIn('case duration', ai); self.assertNotIn('case players', ai)
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift').split('public func saveTemplateReviewed')[1].split('public func replace')[0]
        self.assertLess(fixture.index('try MerchantOperationsDraft.template(draft).previews()'), fixture.index('try await saveExample'))

    def test_authored_runtime_tests_cover_exact_transport_and_failure_recovery(self):
        core = read('Tests/CoreTests/MerchantTemplateMetadataTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 13)
        for token in ['MetadataTransport: HTTPTransport', '"api/merchant/city-node/template/submit"',
                      '"/prod-api/api/template/myinfo"', 'XCTAssertEqual(saves.count, 1)',
                      'XCTAssertEqual(returned.gameDurationMinutes, "30")', 'reader.readFailure = nil; await coordinator.load()',
                      'reader.saveFailure = MerchantOperationsFailure.outcomeUnknown', 'reader.scope = UUID()']:
            self.assertIn(token, core)
        ui = read('Tests/AppUITests/MerchantTemplateMetadataFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 2)
        self.assertIn('XCTAssertEqual(field.value as? String, "25")', ui)
        self.assertIn('XCTAssertFalse(review.isEnabled)', ui)


if __name__ == '__main__': unittest.main()
