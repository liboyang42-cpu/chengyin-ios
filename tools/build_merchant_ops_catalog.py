#!/usr/bin/env python3
"""Write the separate MerchantOps bilingual table for the w2-18 merchant-ops parity surfaces.

Chinese copy follows the mini-program pages named next to each group; English is a plain translation.
The script fails when App sources use a key that is not defined here, or a defined key is unused.
"""
import json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
ROWS = {
 # pages/merchant/marketing/index.{js,wxml}
 'merchantOps.marketing.hero.label %lld': ('Sign-ups in the last %lld days', '近 %lld 天报名'),
 'merchantOps.marketing.hero.noSignup': ('No sign-ups yet · publish content to start', '还没有人报名 · 发布内容后开始积累'),
 'merchantOps.marketing.hero.noVerification': ('No redemptions yet', '还没有核销记录'),
 'merchantOps.marketing.hero.verified %@': ('Redeemed %@', '核销 %@'),
 'merchantOps.marketing.analytics.unavailable': ('Marketing data has not loaded', '营销数据暂未加载'),
 'merchantOps.marketing.analytics.retry': ('Tap to retry', '点击重试'),
 'merchantOps.marketing.tool.insight': ('Store advisor', '店铺参谋'),
 'merchantOps.marketing.tool.decor': ('Store decoration', '店铺装修'),
 'merchantOps.marketing.tool.topic': ('Post a topic', '发主题'),
 'merchantOps.marketing.tool.activity': ('Take on activities', '接活动'),
 'merchantOps.marketing.myContent': ('My content', '我的内容'),
 'merchantOps.marketing.coupon.live %lld': ('%lld live', '%lld 张在投放'),
 'merchantOps.marketing.coupon.counts %lld %lld': ('Claimed %lld · Redeemed %lld', '领取 %lld · 核销 %lld'),
 'merchantOps.marketing.coupon.rate %lld': ('Redeemed after claiming %lld%%', '领取后核销 %lld%%'),
 'merchantOps.marketing.coupon.empty.title': ('No coupons yet', '还没有优惠券'),
 'merchantOps.marketing.coupon.empty.body': ('Issue an in-store coupon to bring viewers through the door', '发一张到店券，把看过的人带进门'),
 'merchantOps.marketing.coop.title': ('Cooperation opportunities', '合作机会'),
 'merchantOps.marketing.coop.count %lld': ('%lld open opportunities', '%lld 个开放商机'),
 'merchantOps.marketing.coop.body': ('See open opportunities and invitations sent to me', '查看开放商机与发给我的邀约'),
 'merchantOps.marketing.empty.title': ('No marketing data yet', '还没有营销数据'),
 'merchantOps.marketing.empty.body': ('Marketing data appears here after views, sign-ups, payments, redemptions or refund requests', '有浏览、报名、支付、核销或退款申请后，这里会显示营销数据'),
 'merchantOps.marketing.empty.cta': ('Publish your first topic', '发布第一个主题'),
 'merchantOps.marketing.denied.title': ('Your role does not have marketing data access yet', '你的岗位还没有营销数据权限'),
 'merchantOps.marketing.denied.body': ('Ask the store owner to enable it', '请联系店主开通'),
 'merchantOps.marketing.denied.retry': ('Check again', '重新确认'),
}

def main():
    strings = {k: {'extractionState': 'manual', 'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': en}},
               'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}} for k, (en, zh) in sorted(ROWS.items())}
    for key, (en, zh) in ROWS.items():
        specs = re.findall(r'%(?:lld|@)', key)
        assert re.findall(r'%(?:lld|@)', en) == specs == re.findall(r'%(?:lld|@)', zh), key
    out = ROOT / 'Resources/MerchantOps.xcstrings'
    out.write_text(json.dumps({'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    used = set()
    for path in sorted((ROOT / 'App').glob('*.swift')):
        used |= set(re.findall(r'MerchantOpsCopy\.text\("(merchantOps\.[^"]+)"', path.read_text()))
    assert used == set(strings), sorted(used ^ set(strings))
    print(len(strings), 'keys')

if __name__ == '__main__':
    main()
