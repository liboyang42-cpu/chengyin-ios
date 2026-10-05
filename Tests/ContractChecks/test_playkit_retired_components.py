"""Retirement classification is distinct from implementation or visual acceptance."""
import json,os,pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayKitRetiredComponentChecks(unittest.TestCase):
    def test_retired_families_are_not_reported_as_migrated(self):
        record=json.loads((ROOT/'docs/playkit-retired-components.json').read_text())
        self.assertEqual(record['status'],'source_retirement_correction_not_implementation')
        self.assertEqual({x['name'] for x in record['components']},{'gameTimer','stickerBook'})
        self.assertTrue(all(x['classification']=='retired_source_stale_flutter_builder' for x in record['components']))
    def test_retired_families_have_no_native_screen_dispatch(self):
        native=(ROOT/'Core/PlayKitScreenContracts.swift').read_text()
        self.assertNotIn('case gameTimer',native);self.assertNotIn('case stickerBook',native)
        body=(ROOT/'App/PlayKitScreen.swift').read_text()
        self.assertNotIn('case .gameTimer',body);self.assertNotIn('case .stickerBook',body)
    def test_current_mini_dispatch_and_components_confirm_retirement(self):
        raw=os.environ.get('CHENGYIN_MINIPROGRAM_SOURCE_ROOT')
        if not raw:self.skipTest('External mini-program retirement comparison NOT_RUN: no configured source checkout')
        source=pathlib.Path(raw)
        self.assertTrue(source.is_dir(),'An explicitly configured source must exist')
        for path in ['pages/play/components/playkit/index.js','pages/play/components/playkit/index.json','pages/play/components/playkit/index.wxml']:
            text=(source/path).read_text()
            self.assertNotIn('gametimer',text);self.assertNotIn('stickerbook',text)
        self.assertFalse((source/'pages/play/components/game-timer').exists())
        self.assertFalse((source/'pages/play/components/playkit-stickerbook').exists())
        proof=(source/'tests/unit/playkit-view-contract.test.js').read_text()
        self.assertIn('2026-09-20',proof);self.assertIn('stickerbook / gametimer / woodfish',proof)
    def test_current_docs_do_not_retain_the_old_implementation_gap(self):
        for path in ['docs/playkit-native-screens.md','docs/playkit-authoring-legacy.md','docs/playkit-camera-presentation.md']:
            text=(ROOT/path).read_text()
            self.assertNotIn('gameTimer/stickerBook utilities still require implementation',text)
            self.assertNotIn('game-timer/sticker-book bodies remain implementation work',text)
            self.assertIn('retired' if 'retired' in text else 'deleted',text)
if __name__=='__main__':unittest.main()
