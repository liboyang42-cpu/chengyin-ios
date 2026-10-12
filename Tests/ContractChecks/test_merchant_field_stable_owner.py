import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class MerchantFieldStableOwnerContract(unittest.TestCase):
    def test_rows_only_borrow_owner(self):
        for kind in ['Store','NPC']:
            row=(ROOT/f'App/Merchant{kind}FieldEntry.swift').read_text().split('/// Owned by the stable editor')[0]
            for token in ['@StateObject','.sheet(','.onDisappear']:self.assertNotIn(token,row)
            self.assertIn(f'@ObservedObject var presentation: Merchant{kind}FieldPresentation',row)
    def test_editor_owns_and_injects(self):
        editor=(ROOT/'App/MerchantOperationsEditor.swift').read_text()
        for kind,key in [('Store','store'),('NPC','npc')]:
            self.assertIn(f'@StateObject private var {key}FieldPresentation = Merchant{kind}FieldPresentation()',editor)
            self.assertIn(f'.modifier(Merchant{kind}FieldStablePresentation(document: model, presentation: {key}FieldPresentation))',editor)
            for line in editor.splitlines():
                if f'Merchant{kind}FieldEntry(' in line:self.assertIn(f'presentation: {key}FieldPresentation',line)
    def test_fresh_sheet_identity_and_revocation(self):
        for kind in ['Store','NPC']:
            source=(ROOT/f'App/Merchant{kind}FieldEntry.swift').read_text()
            modifier=source.split('/// Owned by the stable editor')[1].split('@MainActor private struct')[0]
            for token in ['content.background','.sheet(item: presentation.presentationBinding())','.id(presentation.session?.id)', '.onChange(of: document.revision)','.onChange(of: document.coordinator.draftIdentity)','.onChange(of: document.coordinator.reader.scope)','.onChange(of: editable)','.onChange(of: scenePhase)','.onDisappear { presentation.deactivate() }']:self.assertIn(token,modifier)
    def test_original_confirmations_remain(self):
        for kind in ['Store','NPC']:
            source=(ROOT/f'App/Merchant{kind}FieldEntry.swift').read_text()
            for token in ['session.requestClose()', 'session.keepEditing()', 'session.discard()', 'session.apply()', '.interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)']:self.assertIn(token,source)
if __name__=='__main__':unittest.main()
