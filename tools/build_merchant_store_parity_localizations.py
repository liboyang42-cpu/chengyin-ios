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
# pages/merchant/reviews summary (index.wxml:31-77)
'merchant.reviewSummary.title': ('Reviews', '口碑'),
'merchant.reviewSummary.stars %lld': ('%lld of 5 stars', '%lld 星（满分 5 星）'),
'merchant.reviewSummary.total %lld': ('%lld verified-redemption reviews · merchants cannot edit original reviews', '%lld 条已核销评价 · 商家不能改用户原评'),
'merchant.reviewSummary.pending': ('Awaiting reply', '待回复'),
'merchant.reviewSummary.pendingHint': ('Replies can be edited later', '回复后可修改'),
'merchant.reviewSummary.month': ('New this month', '本月新增'),
'merchant.reviewSummary.monthHint': ('From this month’s redemption reviews', '来自本月核销评价'),
'merchant.reviewSummary.rate': ('Reply rate', '已回复率'),
'merchant.reviewSummary.rateHint': ('Across all public reviews', '按全量公开评价计算'),
'merchant.reviewSummary.average30': ('30-day average', '近 30 天均分'),
'merchant.reviewSummary.average30Hint': ('Average of public reviews', '公开评价平均分'),
# pages/merchant/team non-admin card (index.wxml:109-114)
'merchant.operatorSelf.title': ('Your role permissions', '你的岗位权限'),
'merchant.operatorSelf.copy': ('The workbench only shows the business entries available to your current role. The owner changes roles or ends access, and it takes effect on the next request.', '工作台只显示当前岗位可用的经营入口。岗位调整或离职由店主操作，并在下一次请求时立即生效。'),
'merchant.operatorSelf.openWorkbench': ('Go to workbench', '进入工作台'),
# pages/merchant/decor entry subtitles (index.wxml:69-119)
'merchant.operationsHint.profile': ('Name · address · hours', '名称 · 地址 · 营业时间'),
'merchant.operationsHint.businessStatus': ('Open or closed', '营业中 / 已打烊'),
'merchant.operationsHint.decor': ('Cover · tagline · feature tags · featured', '封面 · 一句话介绍 · 特色标签 · 主推'),
'merchant.operationsHint.gallery': ('Up to 9 store photos', '最多 9 张门店照片'),
'merchant.operationsHint.story': ('Story · highlights · tagline', '故事 · 特色 · 一句话介绍'),
'merchant.operationsHint.cooperation': ('Capacity · hours · fees · cooperation needs', '承接 · 时段 · 收费 · 合作诉求'),
'merchant.operationsHint.character': ('Look · voice', '形象 · 语音'),
'merchant.operationsHint.assets': ('Voice · 3D assets', '声音 · 3D 资源'),
'merchant.operationsHint.cityNodes': ('Host interactive play', '挂互动玩法'),
# pages/merchant/decor/coop-setting labels (index.wxml:73,80); key owned here, value realigned
'merchant.operations.demand': ('Cooperation needs', '合作诉求'),
'merchant.operations.chargeType': ('Fee type', '收费方式'),
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
