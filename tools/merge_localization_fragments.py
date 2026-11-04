#!/usr/bin/env python3
"""Key-wise union of bilingual fragment catalogs into Resources/Localizable.xcstrings.

Existing catalog entries are never overwritten; a fragment key whose value
differs from the catalog fails instead of silently replacing reviewed copy.
Duplicate JSON keys are rejected at every level, before any catalog write.
Usage: python3 -B tools/merge_localization_fragments.py Resources/X.fragment.json [...]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Resources/Localizable.xcstrings'


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key!r}')
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f'non-JSON numeric constant: {value}')


def read_catalog(path):
    path = Path(path)
    try:
        catalog = json.loads(path.read_text(encoding='utf-8'),
                             object_pairs_hook=unique_object, parse_constant=reject_constant)
    except (OSError, UnicodeError, ValueError) as error:
        raise SystemExit(f'{path}: invalid catalog: {error}') from error
    if not isinstance(catalog, dict) or not isinstance(catalog.get('strings'), dict):
        raise SystemExit(f'{path}: catalog must contain a strings object')
    if any(not isinstance(entry, dict) for entry in catalog['strings'].values()):
        raise SystemExit(f'{path}: every strings entry must be an object')
    return catalog


def merge(paths):
    catalog = read_catalog(CATALOG)
    strings = catalog['strings']
    added = 0
    for path in paths:
        fragment = read_catalog(path)['strings']
        for key, entry in fragment.items():
            localizations = entry.get('localizations')
            if not isinstance(localizations, dict) or set(localizations) != {'en', 'zh-Hans'}:
                raise SystemExit(f'{path}: {key} must have exactly en and zh-Hans')
            if any(not isinstance(value, dict) for value in localizations.values()):
                raise SystemExit(f'{path}: {key} localizations must be objects')
            if key in strings:
                if strings[key] != entry:
                    raise SystemExit(f'{path}: {key} differs from the existing catalog entry')
                continue
            strings[key] = entry
            added += 1
    # Validation of every input precedes the only write. Identical fragments
    # and empty additions do not reformat or touch reviewed catalog bytes.
    if added:
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'MERGED', 'added': added}))


if __name__ == '__main__':
    merge(sys.argv[1:])
