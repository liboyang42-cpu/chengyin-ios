#!/usr/bin/env python3
"""Additive merge; conflicts fail instead of replacing unrelated translations."""
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[1]
target = pathlib.Path(sys.argv[1])
base = json.loads(target.read_text())
new = json.loads((root / 'docs/square-workspace-localizations.json').read_text())
for key, value in new['strings'].items():
    if key in base['strings'] and base['strings'][key] != value:
        raise SystemExit('Conflicting localization: ' + key)
    base['strings'][key] = value
target.write_text(json.dumps(base, ensure_ascii=False, indent=2) + '\n')
