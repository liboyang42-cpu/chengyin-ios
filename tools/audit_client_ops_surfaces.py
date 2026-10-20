#!/usr/bin/env python3
"""Reform plan v9 W01.1 / W09.6 / W11 client audit hook (static, source-only).

Inventories, from App/ and Core/ Swift sources:
  * local persistent stores (Keychain services, UserDefaults/AppStorage, app files),
  * explicit request timeouts (`timeoutInterval = N`),
and checks that every production store file is listed in
docs/ops-safety/client-data-catalog.json. It proves only that a store exists in
source; it does not prove purpose, retention, deletion, deployment or acceptance.
Usage: audit_client_ops_surfaces.py [--report PATH] [--check]
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'docs/ops-safety/client-data-catalog.json'
PATTERNS = {
    'keychain': re.compile(r'kSecAttrService'),
    'userDefaults': re.compile(r'UserDefaults|@AppStorage\('),
    'file': re.compile(r'\.(applicationSupportDirectory|documentDirectory|cachesDirectory)\b'),
}
TIMEOUT = re.compile(r'timeoutInterval(?:ForRequest|ForResource)?\s*=\s*([0-9.]+)')
FIXTURE = re.compile(r'(Fixture|Synthetic)', re.I)

def swift_files():
    return sorted([*ROOT.glob('App/*.swift'), *ROOT.glob('Core/*.swift')])

def inventory():
    stores, timeouts = [], []
    for path in swift_files():
        text = path.read_text(encoding='utf-8')
        rel = str(path.relative_to(ROOT))
        kinds = sorted(k for k, p in PATTERNS.items() if p.search(text))
        if kinds:
            stores.append({'file': rel, 'kinds': kinds, 'fixtureOnly': bool(FIXTURE.search(path.stem))})
        for number, line in enumerate(text.splitlines(), 1):
            for match in TIMEOUT.finditer(line):
                timeouts.append({'file': rel, 'line': number, 'seconds': float(match.group(1))})
    return stores, timeouts

def check(stores):
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    listed = {entry['file']: entry for entry in catalog['entries']}
    errors = []
    for store in stores:
        if store['fixtureOnly']:
            continue
        entry = listed.get(store['file'])
        if entry is None:
            errors.append(f"uncatalogued local store: {store['file']} ({', '.join(store['kinds'])})")
        elif not set(store['kinds']) <= set(entry['kinds']):
            errors.append(f"catalog kinds incomplete for {store['file']}: {store['kinds']}")
    present = {s['file'] for s in stores}
    for name in listed:
        if name not in present:
            errors.append(f'catalog entry without a store in source: {name}')
    for entry in catalog['entries']:
        for field in ('purpose', 'retention', 'deletion'):
            if not entry.get(field):
                errors.append(f'{entry["file"]}: missing {field}')
    return errors

def main(argv):
    stores, timeouts = inventory()
    if '--report' in argv:
        out = pathlib.Path(argv[argv.index('--report') + 1])
        summary = {}
        for t in timeouts:
            summary[str(t['seconds'])] = summary.get(str(t['seconds']), 0) + 1
        out.write_text(json.dumps({'stores': stores, 'timeouts': timeouts, 'timeoutSummary': summary},
                                  ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if '--check' in argv:
        errors = check(stores)
        for error in errors:
            print('FAIL', error)
        if errors:
            return 1
        print(f'PASS {len(stores)} store files ({sum(not s["fixtureOnly"] for s in stores)} production) catalogued; '
              f'{len(timeouts)} explicit timeouts inventoried')
        print('SCOPE: static source scan only; purpose/retention/deletion entries marked pending are not decisions')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
