"""Source guards only; not substitutes for Swift/device verification."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class PlayObjectCardReceiptContract(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_one_shot_wire_is_decoded_but_not_synthesized(self):
        runtime = self.text('Core/PlayAdvancedRuntime.swift')
        self.assertIn('PlayObjectCardReceiptDecoder.decode(raw["objectCard"])', runtime)
        cache = self.text('Core/PlayObjectCardReceipt.swift')
        for boundary in ['pending.action == "SUBMIT_PHOTO_CHECK"', 'state.version > pending.version', 'prior.owner == owner', 'prior.nodeID == state.nodeID', 'guard receipt == nil else', 'let card = state.objectCard']:
            self.assertIn(boundary, cache)
    def test_late_delivery_and_exit_are_fenced(self):
        runtime = self.text('Core/PlayAdvancedRuntime.swift')
        self.assertIn('self.cardLifetime == cardLifetime', runtime)
        self.assertIn('cardReceipts.reconcile(result, owner: session)', runtime)
        self.assertIn('if case PlayExperienceError.rejected = error { pending = nil; clearObjectCardReceipt(); phase = "rejected" }', runtime)
        self.assertIn('if kind == .photoCheck { model.clearObjectCardReceipt() }', self.text('App/PlayKitScreen.swift'))
    def test_ordinary_mode_and_existing_media_boundary_remain(self):
        form = self.text('App/PlayKitPersonalForms.swift')
        self.assertIn('if raw["mode"].text == "CARD" { objectCardForm }', form)
        self.assertIn('else { ordinaryPhotoCheckForm }', form)
        view = self.text('App/PlayObjectCardRevealView.swift')
        self.assertIn('ObjectCardBoundedImageLoader', view)
        self.assertNotIn('AsyncImage', view)
        self.assertNotIn('URLSession', view)
    def test_no_production_grants_or_new_routes(self):
        session = self.text('App/AppSession.swift')
        self.assertIn('enabled: factory.accepted?.play.intersection([.reads]) ?? []', session)
        view = self.text('App/PlayObjectCardRevealView.swift')
        self.assertNotIn('api/', view)
