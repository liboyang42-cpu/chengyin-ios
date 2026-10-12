import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class InvitationDirectionContract(unittest.TestCase):
    def test_explicit_source_boxes(self):
        s=(ROOT/'App/CooperationFlowWorkbench.swift').read_text()
        self.assertIn('section: "cooperation.received", direction: .received',s)
        self.assertIn('section: "cooperation.sent", direction: .sent',s)
        self.assertIn('sourceActions(row, direction: direction)',s)
    def test_no_principal_inference(self):
        s=(ROOT/'App/CooperationFlowWorkbench.swift').read_text()
        self.assertNotIn('let isFrom = row["fromId"].integer == reader.session?.accountID',s)
        self.assertIn('if let direction, let id = row["id"].integer',s)
        self.assertIn('let isFrom = direction == .sent',s)
        self.assertIn('.actions(direction: direction)',s)
    def test_existing_matrix_and_unknown_direction(self):
        s=(ROOT/'Core/CooperationFlowContracts.swift').read_text()
        self.assertIn('guard let direction else { return [] }',s)
        self.assertIn('return actions(isFrom: direction == .sent, isTo: direction == .received)',s)
        self.assertIn('case .pending: return (isTo ? [.accept, .reject] : []) + (isFrom ? [.cancel] : [])',s)
        self.assertIn('case .accepted: return isFrom ? [.cancel] : []',s)
    def test_fresh_evidence_direction_and_coordinator(self):
        e=(ROOT/'Core/CooperationFlowEvidenceReader.swift').read_text()
        c=(ROOT/'Core/CooperationFlowCoordinator.swift').read_text()
        self.assertIn('unique(sent + received, key: "id", id: id)',e)
        self.assertIn('guard from != to else',e)
        self.assertIn('"invitationDirection": .string(direction.rawValue)',e)
        self.assertIn('fresh.baseline["invitationDirection"].text',c)
        self.assertNotIn('let isFrom = row["fromId"].integer == session.accountID',c)
        self.assertIn('guard fresh.baseline == accepted.baseline',c)
        self.assertIn('freshEvidence(for: accepted.operation, session: session)',c)
if __name__=='__main__': unittest.main()
