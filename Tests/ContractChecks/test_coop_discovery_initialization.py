"""Source contracts for actor-safe view initialization; not Apple compile/runtime proof."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CoopDiscoveryInitializationChecks(unittest.TestCase):
    def test_main_actor_model_is_created_inside_the_isolated_view_initializer(self):
        source = (ROOT / 'App/CoopRelationDiscoveryView.swift').read_text()
        self.assertIn('@MainActor struct CoopRelationDiscoveryView: View', source)
        self.assertIn('@State private var model: CoopRelationDiscoveryModel', source)
        header, body = source.split('    init(reader:', 1)[1].split('        self.reader =', 1)
        self.assertIn('model: CoopRelationDiscoveryModel? = nil', header)
        self.assertNotIn('model: CoopRelationDiscoveryModel = .init()', header)
        self.assertIn('_model = State(initialValue: model ?? .init())', body.split('    var body:', 1)[0])
        self.assertNotIn('@State private var model = CoopRelationDiscoveryModel()', source)
        self.assertNotIn('nonisolated', source)
        self.assertNotIn('MainActor.assumeIsolated', source)

    def test_presentation_owner_and_existing_lifecycle_fences_are_unchanged(self):
        source = (ROOT / 'App/CoopRelationDiscoveryView.swift').read_text()
        for required in ['@StateObject private var presentation: CoopRelationPresentationOwner',
                         'presentation: CoopRelationPresentationOwner? = nil',
                         '_presentation = StateObject(wrappedValue: presentation ?? .init(identityChanges: profiles?.identityChanges))',
                         'presentation.reconcileIdentity()', 'model.leaveScreen()',
                         'acceptedModel.isCurrent(choice, reader: acceptedReader, scope: profiles.scope, context: context)']:
            self.assertIn(required, source)
        owner = (ROOT / 'App/CoopRelationPresentationOwner.swift').read_text()
        self.assertIn('@MainActor final class CoopRelationPresentationOwner', owner)
        self.assertIn('selection?.id == choice.id && selectionIsCurrent?() == true', owner)

    def test_default_and_exact_injected_models_have_bounded_hosting_regressions(self):
        source = (ROOT / 'Tests/AppUnitTests/CoopRelationDiscoveryInitializationTests.swift').read_text()
        self.assertIn('#if DEBUG', source)
        self.assertIn('@MainActor final class CoopRelationDiscoveryInitializationTests', source)
        for required in ['testDefaultModelInitializationHostsDiscoveryWithoutAnInjectedModel',
                         'testInjectedModelInitializationLoadsTheExactSuppliedInstance',
                         'CoopRelationDiscoveryView(reader: reader)',
                         'CoopRelationDiscoveryView(reader: reader, model: model, presentation: owner)',
                         'model.isCurrent(reader: reader)', 'UIHostingController',
                         'for _ in 0..<250', 'Task.sleep(nanoseconds: 20_000_000)',
                         'window.isHidden = true; window.rootViewController = nil']:
            self.assertIn(required, source)
        self.assertEqual(source.count('    func test'), 2)


if __name__ == '__main__':
    unittest.main()
