"""Source/data contracts only. Does not compile Swift or run iOS UI/HTTP writes."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = (ROOT / 'Core/MerchantNPCPresetAvatar.swift').read_text()
APP = (ROOT / 'App/MerchantNPCPresetPicker.swift').read_text()
CONTRACT = (ROOT / 'Core/MerchantOperationsContracts.swift').read_text().split('public struct MerchantStoreCharacter:')[1].split('public enum MerchantOperationsReview')[0]
EDITOR = (ROOT / 'App/MerchantOperationsEditor.swift').read_text().split('case .character(let value):')[1].split('case .template(let value):')[0]
CATALOG = json.loads((ROOT / 'Resources/MerchantNPCPresetLocalizations.fragment.json').read_text())['strings']
EXPECTED_IDS = ['p01','p04','p07','p10','p13','p17','p18','p23','p25','p27','p31','p36']
# Canonical source data extracted from Git blob 87ee78031820e4e370635e004fc10501a4e7c9a8.
EXPECTED_DATA_SHA256 = '0f121d1296400c18b6f73c2a3a470182b589e64b53ee6b1376f9f2d8c49215d2'

def artwork():
    pattern = r'\.init\(id: "(p\d+)", gridSize: (\d+), backgroundRGB: (0x[0-9A-Fa-f]+), paletteRGB: \[([^]]+)\], encodedRuns: "([A-Za-z0-9]+)"\)'
    return [dict(id=i, gridSize=int(n), backgroundRGB=int(bg,16), paletteRGB=[int(c.strip(),16) for c in pal.split(',')], encodedRuns=d)
            for i,n,bg,pal,d in re.findall(pattern,CORE)]

class MerchantNPCPresetContracts(unittest.TestCase):
    def test_upstream_artwork_bytes_are_exact(self):
        values=artwork()
        self.assertEqual([v['id'] for v in values], EXPECTED_IDS)
        digest=hashlib.sha256(json.dumps(values,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        self.assertEqual(digest,EXPECTED_DATA_SHA256)
    def test_all_runs_decode_inside_original_grid(self):
        alphabet='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
        for a in artwork():
            self.assertIn(a['gridSize'], [32,48]);self.assertGreater(len(a['encodedRuns']),0)
            self.assertEqual(len(a['encodedRuns'])%4,0)
            for i in range(0,len(a['encodedRuns']),4):
                x,y,w,c=[alphabet.index(ch) for ch in a['encodedRuns'][i:i+4]]
                self.assertLessEqual(x+w,a['gridSize']);self.assertLess(y,a['gridSize'])
                self.assertGreater(w,0);self.assertLess(c,len(a['paletteRGB']))
    def test_unknown_codes_never_fall_back_to_first_preset(self):
        self.assertIn('all.first { $0.code == code }',CORE)
        self.assertNotIn('FALLBACK',CORE)
        self.assertIn('matching(code: value.avatar)?.id',APP)
        self.assertNotIn('all.first!',APP)
    def test_only_explicit_apply_changes_avatar(self):
        apply=APP.split('@discardableResult func apply() -> Bool')[1].split('func cancel()')[0]
        self.assertIn('guard canApply',apply)
        self.assertIn('var edited = original; edited.avatar = avatar.code',apply)
        self.assertIn('document.edit(.character(edited))',apply)
        self.assertEqual(APP.count('document.edit('),1)
        select=APP.split('func select(_ id: String)')[1].split('@discardableResult')[0]
        self.assertNotIn('document.edit',select)
    def test_current_scope_draft_and_write_fences(self):
        for fence in ['!consumed','owner.isCurrent','!owner.isBusy','!owner.isLocked','owner.confirmation == nil','owner.reader.scope == scope','owner.draftIdentity == draftIdentity','owner.draft == .character(original)']:
            self.assertIn(fence,APP)
    def test_background_reload_and_dismiss_cancel(self):
        for value in ['phase != .active','cancelPicker()','document.coordinator.draftIdentity','document.coordinator.reader.scope','.onDisappear { model.cancel() }','func cancel() { consumed = true; selectedID = nil }']:
            self.assertIn(value,APP)
    def test_no_new_transport_authority_upload_or_provider(self):
        for token in ['URLSession','HTTPTransport','OperationEndpointApproval','PhotosPicker','AVAudioRecorder','MerchantNPCGrants','saveReviewed(','Task {','api/','UserDefaults']:
            self.assertNotIn(token,APP+CORE)
    def test_character_is_only_host_branch(self):
        self.assertIn('MerchantNPCPresetSection(document: model)',EDITOR)
        self.assertIn('if !value.avatar.hasPrefix("px1:")',EDITOR)
        self.assertIn('mediaSection("merchant.operations.avatar", field: .avatar)',EDITOR)
    def test_character_bounds_and_explicit_empty_wire_values(self):
        self.assertIn('utf16.count > 32',CONTRACT)
        self.assertIn('utf16.count > 500',CONTRACT)
        self.assertIn('utf16.count > 2000',CONTRACT)
        self.assertIn('utf16.count > 60',CONTRACT)
        self.assertNotIn('personaRequired',CONTRACT)
        fields=CONTRACT.split('public var fields:')[1].split('public var rejectionReason')[0]
        self.assertEqual(set(re.findall(r'"(\w+)":',fields)),{'name','avatar','greeting','persona','knowledge'})
        self.assertIn('trimmingCharacters',fields)
        self.assertNotIn('NSNull',fields)
    def test_audit_is_read_only_and_labeled_as_last_loaded(self):
        self.assertIn('decodeIfPresent(String.self, forKey: .auditReason)',CONTRACT)
        self.assertIn('guard auditStatus == 2',CONTRACT)
        self.assertIn('merchantPreset.lastReview',EDITOR)
        self.assertIn('Text(verbatim: reason)',EDITOR)
        self.assertIn('merchantPreset.emptyPersona',EDITOR)
    def test_all_visible_keys_and_preset_names_are_bilingual(self):
        text=re.sub(r'\.accessibilityIdentifier\([^\n]*\)', '', APP+EDITOR+CONTRACT)
        keys={k for k in re.findall(r'"(merchantPreset\.[A-Za-z0-9.]+)"',text) if not k.endswith('.')}
        keys.update('merchantPreset.name.'+i for i in EXPECTED_IDS)
        self.assertFalse(keys-set(CATALOG),keys-set(CATALOG))
        for key in keys:
            for language in ['en','zh-Hans']:
                self.assertTrue(CATALOG[key]['localizations'][language]['stringUnit']['value'].strip())
    def test_confirmation_artwork_only_uses_frozen_snapshot(self):
        confirmation=(ROOT/'App/MerchantOperationsEditor.swift').read_text().split('struct MerchantOperationsConfirmationView:')[1]
        self.assertIn('MerchantNPCCharacterAvatarSnapshot(draft: confirmation.draft)',confirmation)
        self.assertNotIn('model.coordinator.draft',confirmation)
        self.assertIn('source: avatar.rawValue',confirmation)
        self.assertIn('Text(verbatim: avatar.rawValue)',confirmation)
        self.assertIn('ForEach(confirmation.draft.reviewLines)',confirmation)
    def test_native_rendering_has_integer_scale_accessible_selection(self):
        for token in ['Canvas {','floor(min(size.width, size.height)','paletteRGB[run.paletteIndex]','LazyVGrid','minHeight: 44','.isSelected','accessibilityLabel','privacySensitive()']:
            self.assertIn(token,APP)
    def test_focused_runtime_tests_are_present_without_claiming_run(self):
        core=(ROOT/'Tests/CoreTests/MerchantNPCPresetAvatarTests.swift').read_text()
        app=(ROOT/'Tests/AppUnitTests/MerchantNPCPresetPickerTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(',core)),11)
        self.assertEqual(len(re.findall(r'func test\w+\(',app)),15)
        for token in ['testUnknownWriteLock','testAccountSwitch','testConcurrentFieldEdit','testNullProfile','testOpenAndCancel']:
            self.assertIn(token,app)

if __name__ == '__main__': unittest.main()
