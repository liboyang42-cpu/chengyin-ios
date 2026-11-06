import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ParticipantListDirectActionsContract(unittest.TestCase):
    def setUp(self):
        self.list = (ROOT / 'App/ProfileParticipantsView.swift').read_text()
        self.form = (ROOT / 'App/ParticipantFormView.swift').read_text()

    def test_swipe_actions_open_existing_flows_only(self):
        self.assertIn('.swipeActions', self.list)
        self.assertIn('ParticipantFormView(id: target.id', self.list)
        self.assertIn('ParticipantListDeleteView(id: target.id', self.list)
        self.assertIn('coordinator.isConfigured, reader.identity != nil', self.list)

    def test_delete_requires_review_and_confirmation_and_cancel_is_local(self):
        self.assertIn('model.prepareDelete()', self.list)
        self.assertIn('model.confirmMutation()', self.list)
        self.assertIn('model.cancelConfirmation()', self.list)
        self.assertNotIn('coordinator.confirm(', self.list)

    def test_unknown_outcome_only_reads_back_and_pii_cleared(self):
        self.assertIn('model.readBack()', self.list)
        self.assertIn('model.disappear()', self.list)
        self.assertNotIn('retry', self.list.lower().split('struct participantlistdeleteview')[1])

    def test_no_new_endpoint_or_gate(self):
        for text in (self.list, self.form):
            self.assertIsNone(re.search(r'"/?user/address|https?://', text))
        self.assertIn('coordinator: ParticipantMutationCoordinator? = nil', self.list)


if __name__ == '__main__':
    unittest.main()
