#!/usr/bin/env python3
"""w2-17 merchant store parity strings (mini-program pages/merchant/{index,apply,profile,team,
reviews,relation,decor/*}). Writes the slice fragment and merges it into the app catalog
key by key; unrelated catalog entries and their order are preserved. Re-running is idempotent."""
import json, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
FRAGMENT = ROOT / 'Resources/MerchantStoreParityLocalizations.fragment.json'
CATALOG = ROOT / 'Resources/Localizable.xcstrings'
PAIRS = {
# pages/merchant/index reminders (index.wxml:113-132)
'merchant.workbench.aftercareReminder %lld': ('%lld after-sales requests await your response', '有 %lld 笔售后待回应'),
'merchant.workbench.predictReminder %lld': ('%lld prediction rounds await your answer', '有 %lld 轮竞猜待给答案'),
'merchant.workbench.reminderUnavailable': ('Open this from the business workspace.', '请从经营工作区进入处理。'),
}


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def entries():
    return {key: {'localizations': {'en': unit(en), 'zh-Hans': unit(zh)}} for key, (en, zh) in PAIRS.items()}


def main():
    check = '--check' in sys.argv
    fragment = {'sourceLanguage': 'en', 'version': '1.0', 'strings': entries()}
    fragment_text = json.dumps(fragment, ensure_ascii=False, indent=2) + '\n'
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    strings = catalog['strings']
    changed = [key for key, value in fragment['strings'].items() if strings.get(key) != value]
    if check:
        stale = not FRAGMENT.exists() or FRAGMENT.read_text(encoding='utf-8') != fragment_text
        if changed or stale:
            print('STALE merchant store parity localizations:', changed or [FRAGMENT.name]); return 1
        print('PASS merchant store parity localizations:', len(PAIRS)); return 0
    for key in changed:
        strings[key] = fragment['strings'][key]
    FRAGMENT.write_text(fragment_text, encoding='utf-8')
    raw = CATALOG.read_text(encoding='utf-8')
    separators = (',', ' : ') if '" : ' in raw else (',', ': ')
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=separators) + '\n', encoding='utf-8')
    print('merged', len(changed), 'of', len(PAIRS), 'merchant store parity keys')
    return 0


if __name__ == '__main__':
    sys.exit(main())
