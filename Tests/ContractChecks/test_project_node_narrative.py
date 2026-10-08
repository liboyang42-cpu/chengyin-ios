"""Executable source contracts only. Model XCTest and Apple UI execution are separate."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProjectNodeNarrativeContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_real_node_host_and_explicit_local_commit(self):
        forms = self.read('App/ProjectEditDetailForms.swift')
        host = self.read('App/ProjectNodeNarrativeFields.swift')
        self.assertIn('ProjectNodeNarrativeEntry(model: model, chapterID: chapterID, nodeID: nodeID)', forms)
        self.assertIn('model.persistLocalChange(next, lease: value.lease)', host)
        self.assertIn('ProjectNodeNarrative.applying(text, to:', host)
        self.assertIn('guard self.isCurrent(value) else { return }', host)
        for forbidden in ['URLSession', 'transport.send', 'coordinator.confirm(', 'OperationEndpointApproval', 'prefix(2000)', 'Locale(identifier:']:
            self.assertNotIn(forbidden, host)

    def test_source_field_set_exact_bytes_and_loss_prevention(self):
        core = self.read('Core/ProjectNodeNarrative.swift')
        for field in ['hookText', 'cardHookLong', 'fragmentText']:
            self.assertIn(field, core)
            self.assertIn(field, self.read('Core/ProjectEditStoryContract.swift'))
        for token in ['Set<[UInt8]>()', 'Array($0.utf8)', 'joined(separator: "\\n")', 'default: throw ProjectEditError.invalidDraft', 'maximumLength = 2000', 'description.utf16.count <= maximumLength']:
            self.assertIn(token, core)
        before_apply = core.split('public static func applying')[0]
        self.assertNotIn('localMetadata[field.rawValue] =', before_apply)

    def test_identity_and_aba_fences_precede_any_write(self):
        host = self.read('App/ProjectNodeNarrativeFields.swift')
        for token in ['model.isCurrentStarterLease(value.lease)', 'model.draftMutationRevision == value.revision',
                      'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                      'firstIndex(where: { $0.id == value.chapterID })', 'firstIndex(where: { $0.id == value.nodeID })',
                      'destination?.id == value.id']:
            self.assertIn(token, host)
        self.assertNotIn('nodes[0]', host)

    def test_state_object_is_keyed_by_model_reference_and_exact_route(self):
        host = self.read('App/ProjectNodeNarrativeFields.swift')
        outer = host.split('struct ProjectNodeNarrativeEntry: View')[1].split('private struct ProjectNodeNarrativeHost: View')[0]
        self.assertNotIn('@StateObject', outer)
        self.assertIn('.id(ProjectNodeNarrativeHostIdentity(model: ObjectIdentifier(model), chapterID: chapterID, nodeID: nodeID))', outer)
        self.assertIn('self.model === model', host)
        self.assertIn('value.hostGeneration == hostGeneration', host)
        self.assertIn('func retire() { hostGeneration += 1;', host)
        self.assertIn('.onDisappear { controller.retire() }', host)

    def test_review_uses_captured_payload_only(self):
        review = self.read('App/ProjectEditPreparedReview.swift')
        self.assertIn('ProjectEditPreparedValue(value: .init(node.raw.object?[field.rawValue]))', review)
        prepared = review.split('struct ProjectEditPreparedNodesView: View')[1].split('private struct ProjectEditPreparedValue')[0]
        self.assertNotIn('model.draft', prepared)
        self.assertNotIn('mergedDescription', prepared)

    def test_bilingual_fragment_covers_all_labels(self):
        fragment = json.loads(self.read('Resources/ProjectNodeNarrativeLocalizations.fragment.json'))
        self.assertEqual(fragment['sourceLanguage'], 'en')
        strings = fragment['strings']
        ui = self.read('App/ProjectNodeNarrativeFields.swift')
        ui = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', ui)
        keys = set(re.findall(r'"(projectNodeNarrative\.[A-Za-z.]+)"', ui))
        keys.update('projectNodeNarrative.field.' + field for field in ['hookText', 'cardHookLong', 'fragmentText'])
        self.assertEqual(keys, set(strings))
        for entry in strings.values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

    def test_authored_real_model_regressions_are_present_without_claiming_execution(self):
        core = self.read('Tests/CoreTests/ProjectNodeNarrativeTests.swift')
        model = self.read('Tests/AppUnitTests/ProjectNodeNarrativeTests.swift')
        self.assertEqual(core.count('func test'), 5)
        self.assertEqual(model.count('func test'), 9)
        for token in ['"deleteABA"', '"textABA"', '"chapterABA"', '"reorder"', 'fresh.restore()', 'service.submissions.isEmpty', 'storage.failAt = storage.writes + offset', 'scope: .whitelist']:
            self.assertIn(token, model)


if __name__ == '__main__':
    unittest.main()
