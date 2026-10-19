#!/usr/bin/env python3
"""Upsert the w2-07 (topic / square / guide) bilingual strings from their reviewed JSON source.

Only listed keys are written; unrelated catalog entries are left untouched, so a
key-wise JSON union with concurrent branches stays mechanical.
"""
import json, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/parity/w2-07-localizations.json'
CATALOGS = {'Localizable': ROOT / 'Resources/Localizable.xcstrings'}
# Square UI literals are also registered in the Square key list checked by test_square_structure.
SQUARE_REGISTRY = ROOT / 'docs/square-localizations.json'


def entry(row, existing=None):
    value = dict(existing or {})  # keep sibling metadata such as extractionState
    value['localizations'] = {lang: {'stringUnit': {'state': 'translated', 'value': row[lang]}} for lang in ('en', 'zh-Hans')}
    return value


def main(check=False):
    rows = json.loads(SOURCE.read_text())
    keys = [row['key'] for row in rows]
    assert len(keys) == len(set(keys)), 'duplicate w2-07 key'
    stale = []
    for name, path in CATALOGS.items():
        data = json.loads(path.read_text())
        table = data['strings'] if name == 'Localizable' else data
        for row in rows:
            assert row['en'].strip() and row['zh-Hans'].strip(), row['key']
            if row.get('table', 'Localizable') != name: continue
            wanted = entry(row, table.get(row['key']))
            if table.get(row['key']) != wanted: stale.append(row['key']); table[row['key']] = wanted
        if not check:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    registry = json.loads(SQUARE_REGISTRY.read_text())
    index = {row['key']: i for i, row in enumerate(registry)}
    for row in rows:
        if not row['key'].startswith('square.') or row['key'] == 'square.title': continue
        wanted = {'key': row['key'], 'en': row['en'], 'zh-Hans': row['zh-Hans']}
        if row['key'] in index:
            if registry[index[row['key']]] != wanted: stale.append(row['key']); registry[index[row['key']]] = wanted
        else: stale.append(row['key']); registry.append(wanted)
    if not check:
        SQUARE_REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + '\n')
    if check and stale: sys.exit('stale w2-07 strings: ' + ', '.join(stale))
    print(f'w2-07 strings: {len(rows)} rows, {len(stale)} updated' + (' (check only)' if check else ''))


if __name__ == '__main__':
    main(check='--check' in sys.argv)
