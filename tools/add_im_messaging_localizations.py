#!/usr/bin/env python3
"""Merge docs/im-messaging-localizations.json into Resources/Localizable.xcstrings.

Idempotent and key-wise: only the listed keys are added or updated, other keys and
their order are untouched. Re-run after resolving a catalog merge conflict.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/im-messaging-localizations.json'
CATALOG = ROOT / 'Resources/Localizable.xcstrings'


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def main():
    rows = json.loads(SOURCE.read_text())
    keys = [row['key'] for row in rows]
    assert len(keys) == len(set(keys)), 'duplicate key in source'
    catalog = json.loads(CATALOG.read_text())
    strings = catalog['strings']
    for row in rows:
        assert row['en'].strip() and row['zh-Hans'].strip(), row['key']
        entry = strings.setdefault(row['key'], {})
        entry['localizations'] = {'en': unit(row['en']), 'zh-Hans': unit(row['zh-Hans'])}
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(',', ': ')) + '\n')
    print(f'merged {len(rows)} IM messaging keys')


if __name__ == '__main__':
    main()
