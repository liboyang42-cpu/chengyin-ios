import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class CoopStableOwnerContract(unittest.TestCase):
    def test_lazy_row_only_borrows_route(self):
        text=(ROOT/'App/MerchantCoopFieldEntry.swift').read_text().split('/// Stable editor presentation boundary')[0]
        self.assertIn('@Binding var route:',text)
        for token in ['@State','.sheet(','.onDisappear','retire()']:self.assertNotIn(token,text)
    def test_stable_editor_owns_and_presents(self):
        text=(ROOT/'App/MerchantOperationsEditor.swift').read_text()
        for token in ['@State private var coopFieldRoute: MerchantCoopFieldSession?', '.modifier(MerchantCoopFieldStablePresentation(document: model, route: $coopFieldRoute))','MerchantCoopFieldEntry(document: model, route: $coopFieldRoute, fieldID: id)']:self.assertIn(token,text)
    def test_same_dismissal_and_context_guards(self):
        text=(ROOT/'App/MerchantCoopFieldEntry.swift').read_text().split('/// Stable editor presentation boundary')[1].split('@MainActor private struct')[0]
        for token in ['content.background','.id(route?.id)','if value == nil, let shownID { close(shownID) }','guard route?.id == id else { return }','.onChange(of: document.revision)','.onChange(of: document.coordinator.draftIdentity)','.onChange(of: document.coordinator.reader.scope)','.onChange(of: scenePhase)','.onDisappear { retire() }']:self.assertIn(token,text)
if __name__=='__main__':unittest.main()
