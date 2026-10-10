"""P045 source/structure checks. These do not compile Swift or exercise the iOS UI."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLOB = '4a6545ae95e98d4a51ed1c3893bce08510d3d73b'


class ClubMerchantDiscoveryContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_detail_mounts_existing_reader_without_changing_session_composition(self):
        source = self.read('App/ClubDetailView.swift')
        self.assertIn('ClubMerchantDiscoveryView(club: club, clubReader: reader, reader: session.cooperationFlowReader)', source)
        core = self.read('Core/ClubMerchantDiscovery.swift')
        self.assertIn('isOwner && clubID > 0 && configured && identity.isSignedIn', core)
        self.assertIn('identity.accountID == session?.accountID && identity.epoch == session?.epoch', core)

    def test_search_is_local_exact_text_and_order_preserving(self):
        core = self.read('Core/ClubMerchantDiscovery.swift')
        self.assertIn('["name", "merchantName", "suitActivityTypes", "address", "city"]', core)
        self.assertIn('trimmingCharacters(in: Self.whitespace).lowercased()', core)
        self.assertIn('row.fields.joined(separator: " ").lowercased().utf16', core)
        self.assertIn('.elementsEqual(needle)', core)
        self.assertIn('keywordRevision &+= 1', core)
        self.assertIn('let phase = storedPhase', core)
        for prohibited in ['localizedCaseInsensitiveContains', '.folding(', '.sorted(', '.sort(', 'Set(rows', '.merchants(name: value)']:
            self.assertNotIn(prohibited, core)
        setter = core.split('public func setKeyword(', 1)[1].split('public func leave(', 1)[0]
        self.assertNotIn('read(', setter)

    def test_each_async_stage_uses_existing_readers_current_gate(self):
        core = self.read('Core/ClubMerchantDiscovery.swift')
        for token in [
            'clubReaderID == ObjectIdentifier(clubReader)', 'directoryReaderID == ObjectIdentifier(reader)',
            'session == reader.session', 'boundContext == permit.context', 'visibility == permit.visibility',
            'generation == request', 'clubReader.clubDetail(id: permit.context.clubID, isCurrent: current)',
            'club.id == permit.context.clubID, club.isOwner', 'reader.read(.merchants(name: nil), isCurrent: current)',
            'guard !Task.isCancelled, current() else { return }',
        ]:
            self.assertIn(token, core)
        self.assertLess(core.index('clubReader.clubDetail('), core.index('reader.read(.merchants'))
        for prohibited in ['CoopFlowMutation', 'dormantWritesEnabled', 'perform(', 'URLSession', 'httpBody', 'token:']:
            self.assertNotIn(prohibited, core)

    def test_view_rebinds_before_task_and_captures_visible_period_permits(self):
        ui = self.read('App/ClubMerchantDiscoveryView.swift')
        self.assertIn('let _ = model.bind(scope)', ui)
        self.assertIn('let permit = model.permit(in: scope)', ui)
        self.assertIn('if scope.canRead', ui)
        self.assertIn('.task(id: scope)', ui)
        self.assertIn('.onDisappear { model.leave(scope) }', ui)
        self.assertIn('set: { model.setKeyword($0, permit: permit) }', ui)
        self.assertIn('Task { await model.load(clubReader: clubReader, reader: reader, permit: permit) }', ui)
        self.assertNotIn('NavigationLink', ui)
        self.assertNotIn('.onChange(of: model.keyword', ui)

    def test_failed_and_empty_have_separate_paths_and_bad_types_fail_closed(self):
        core = self.read('Core/ClubMerchantDiscovery.swift')
        ui = self.read('App/ClubMerchantDiscoveryView.swift')
        self.assertIn('default: throw CoopFlowFailure.malformed', core)
        self.assertIn('guard let raw = value.rows else { throw CoopFlowFailure.malformed }', core)
        self.assertIn('case .failed:', ui)
        self.assertIn('case .ready:', ui)
        self.assertIn('model.hasLoadedRows(in: scope)', ui)
        self.assertIn('ClubMerchantDiscoveryRow(value: $0.element, index: $0.offset)', core)

    def test_localization_fragment_is_complete_and_nonconflicting(self):
        fragment = json.loads(self.read('Resources/ClubMerchantDiscoveryLocalizations.fragment.json'))['strings']
        keys = set(re.findall(r'"(club\.merchantDiscovery\.[A-Za-z]+)"', self.read('App/ClubMerchantDiscoveryView.swift')))
        keys -= {'club.merchantDiscovery.' + key for key in ['loading', 'denied', 'reload']}
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, entry in fragment.items():
            self.assertTrue(key.startswith('club.merchantDiscovery.'))
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][lang]['stringUnit']['value'].strip())
            if key in catalog:
                self.assertEqual(catalog[key], entry)
        self.assertEqual(len(fragment), 9)
        self.assertLessEqual(keys, set(fragment))
        self.assertTrue({'club.merchantDiscovery.title', 'club.merchantDiscovery.search', 'club.merchantDiscovery.noMatches'} <= set(fragment))

    def test_pinned_mini_filter_oracle_when_explicit_source_is_available(self):
        source_path = os.environ.get('CHENGYIN_CLUB_DETAIL_SOURCE')
        if source_path is None:
            self.skipTest('NOT_RUN: set CHENGYIN_CLUB_DETAIL_SOURCE to the pinned private Mini file')
        path = Path(source_path)
        data = path.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        self.assertEqual(actual, SOURCE_BLOB, 'Source must be the exact fixed Mini blob')
        source = data.decode()
        body = source.split('  filterMerchants() {\n', 1)[1].split('\n  },', 1)[0]
        self.assertIn('[m.name, m.merchantName, m.suitActivityTypes, m.address, m.city]', body)
        samples = [
            ({'name': 'Alpha'}, ' alpha ', True),
            ({'merchantName': 'Alpha'}, 'ALPHA', True),
            ({'suitActivityTypes': 'Walk;Workshop'}, 'workshop', True),
            ({'address': '中山路'}, '中山', True),
            ({'city': '上海'}, '上海', True),
            ({'name': 'First', 'merchantName': 'Second'}, 'first second', True),
            ({'name': 'Cafe'}, '\ufeff\u3000CAFE\u2029', True),
            ({'name': 'Cafe'}, '\u0085Cafe', False),
            ({'name': 'Cafe'}, '\u200bCafe', False),
            ({'name': 'Cafe\u0301'}, 'Café', False),
            ({'name': 'Cafe\u0301'}, '\u0301', True),
            ({'name': '👩‍🚀'}, '🚀', True),
            ({'name': '👩‍🚀'}, '👩', True),
            ({'name': 'Straße'}, 'STRASSE', False),
            ({'name': 'İSTANBUL'}, 'i\u0307stanbul', True),
            ({'name': 'İSTANBUL'}, 'istanbul', False),
            ({'description': 'hidden'}, 'hidden', False),
            ({'name': None}, '\ufeff', True),
            ({'name': 'Two  Spaces'}, 'two spaces', False),
        ]
        script = r"""
const fs = require('fs'), vm = require('vm');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const fn = vm.runInNewContext('(function () {' + input.body + '\n})');
for (const [row, keyword, hit] of input.samples) {
  const rows = [{...row, marker: 2}, {...row, marker: 1}];
  const page = {data: {merchantKeyword: keyword, rawMerchants: rows}, setData(v) {Object.assign(this.data, v)}};
  fn.call(page);
  const expected = hit ? [2, 1] : [];
  if (JSON.stringify(page.data.merchants.map(x => x.marker)) !== JSON.stringify(expected)) throw Error('oracle mismatch');
}
process.stdout.write('PASS ' + input.samples.length + ' pinned Mini filter vectors; order and duplicates preserved\n');
"""
        result = subprocess.run(['node', '-e', script], input=json.dumps({'body': body, 'samples': samples}), text=True, capture_output=True, check=True)
        self.assertIn('PASS 19 pinned Mini filter vectors', result.stdout)
        print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
