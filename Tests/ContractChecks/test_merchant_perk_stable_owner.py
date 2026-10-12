import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PerkStableOwnerContract(unittest.TestCase):
    def test_row_only_borrows(self):
        source=(ROOT/'App/MerchantPerkValidityCalendar.swift').read_text();row=source.split('@MainActor struct MerchantPerkValidityEntry')[1].split('@MainActor struct MerchantPerkValidityStablePresentation')[0]
        for token in ['@State','.sheet(','.onDisappear']:self.assertNotIn(token,row)
        for token in ['@Binding var session:','@Binding var appliedValue:','@Binding var appliedContext:']:self.assertIn(token,row)
    def test_editor_owns_state_and_presentation(self):
        source=(ROOT/'App/CooperationFlowEditors.swift').read_text()
        for token in ['@State private var calendarSession:','@State private var calendarAppliedValue:','@State private var calendarAppliedContext:','.modifier(MerchantPerkValidityStablePresentation','_ = try operation.body()']:self.assertIn(token,source)
    def test_stable_lifecycle_and_guards(self):
        source=(ROOT/'App/MerchantPerkValidityCalendar.swift').read_text().split('@MainActor struct MerchantPerkValidityStablePresentation')[1].split('@MainActor private struct')[0]
        for token in ['content.background','.id(session?.id)','guard session?.id == shownID else { return }','guard session?.id == shown.id, let next = shown.apply()','.onChange(of: context())','.onChange(of: scenePhase)','.onDisappear { session?.cancel(); session = nil; appliedValue = nil; appliedContext = nil }']:self.assertIn(token,source)
if __name__=='__main__':unittest.main()
