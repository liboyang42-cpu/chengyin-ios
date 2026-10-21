#!/usr/bin/env python3
"""Key-wise union of bilingual fragment catalogs into Resources/Localizable.xcstrings.

Existing catalog entries are never overwritten; a fragment key whose value
differs from the catalog fails instead of silently replacing reviewed copy.
Usage: python3 -B tools/merge_localization_fragments.py Resources/X.fragment.json [...]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Resources/Localizable.xcstrings'


def merge(paths):
    catalog = json.loads(CATALOG.read_text())
    strings = catalog['strings']
    added = 0
    for path in paths:
        fragment = json.loads(Path(path).read_text())['strings']
        for key, entry in fragment.items():
            if set(entry.get('localizations', {})) != {'en', 'zh-Hans'}:
                raise SystemExit(f'{path}: {key} must have exactly en and zh-Hans')
            if key in strings:
                if strings[key] != entry:
                    raise SystemExit(f'{path}: {key} differs from the existing catalog entry')
                continue
            strings[key] = entry
            added += 1
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': 'MERGED', 'added': added}))


if __name__ == '__main__':
    merge(sys.argv[1:])
