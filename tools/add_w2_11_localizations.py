#!/usr/bin/env python3
"""Merge docs/w2-11-localizations.json (key -> [en, zh-Hans]) into the string catalog."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    pairs = json.loads((ROOT / 'docs/w2-11-localizations.json').read_text(encoding='utf-8'))
    path = ROOT / 'Resources/Localizable.xcstrings'
    catalog = json.loads(path.read_text(encoding='utf-8'))
    for key, (en, zh) in pairs.items():
        catalog['strings'][key] = {'extractionState': 'manual', 'localizations': {lang: {'stringUnit': {'state': 'translated', 'value': text}} for lang, text in [('en', en), ('zh-Hans', zh)]}}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Merged {len(pairs)} w2-11 strings')
