#!/usr/bin/env python3
"""Write the separate MerchantCoopCenter bilingual table (source pages/merchant/coop-center)."""
import json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
P = 'merchantCoopCenter.'
ROWS = {
 'title': ('Cooperation center', '合作中心'),
 'customerEntry': ('Go to the cooperation center', '去合作中心'),
 'tab.official': ('Official events', '官方活动'),
 'tab.plaza': ('Plaza', '广场'),
 'inbox': ('Cooperation invitations: received and sent', '协作邀请：收到的与我发出的'),
 'loading': ('Loading', '正在加载'),
 'mode.city': ('City orienteering', '城市定向'),
 'mode.free': ('Free exploration', '自由探索'),
 'seat.full': ('Full', '已满'),
 'seat.remaining': ('Seats left: %@', '余 %@ 席'),
 'date.monthDay': ('%1$lld/%2$lld', '%1$lld月%2$lld日'),
 'date.range': ('%1$@ – %2$@', '%1$@ – %2$@'),
 'meta.stations': ('%@ stops', '%@ 站'),
 'terms.perk': ('Perk redemption', '权益核销'),
 'terms.perkAmount': ('Perk redemption · perks worth at least ¥%@', '权益核销 · 权益不低于 ¥%@'),
 'terms.revshare': ('Revenue share', '分润计酬'),
 'terms.revshareAmount': ('Revenue share · per-head fee up to ¥%@ per visit', '分润计酬 · 人头费上限 ¥%@/人次'),
 'terms.traffic': ('Traffic partnership · no settlement', '引流合作 · 无结算'),
 'terms.trafficShort': ('Traffic partnership', '引流合作'),
 'deadline.open': ('Recruiting until %@', '招商截止 %@'),
 'deadline.closed': ('Closed', '已截止'),
 'detail': ('View details', '看详情'),
 'detail.label': ('View details: %@', '看详情：%@'),
 'plaza.scope': ('%1$lld open opportunities · showing the first %2$lld', '共 %1$lld 个开放商机 · 当前列出前 %2$lld 个'),
 'plaza.refreshing': ('Refreshing open routes…', '正在刷新开放承接路线…'),
 'plaza.empty': ('No open routes yet', '还没有开放的路线'),
 'plaza.error.title': ('Routes did not load', '路线没有加载出来'),
 'plaza.error.fallback': ('Could not load routes', '路线加载失败'),
 'official.refreshing': ('Refreshing official events…', '正在刷新官方活动…'),
 'official.empty': ('No official events yet', '还没有官方活动'),
 'official.error.title': ('Official events did not load', '官方活动没有加载出来'),
 'official.error.fallback': ('Could not load official events', '官方活动加载失败'),
 'official.cityAll': ('Citywide', '全城'),
 'official.gap': ('Information incomplete', '信息不全'),
 'official.gapFallback': ('A key partner is missing and a replacement is pending', '关键承接方缺失，待补位'),
 'official.open': ('View event', '查看活动'),
 'official.openLabel': ('View official event: %@', '查看官方活动：%@'),
 'refresh': ('Refresh opportunities', '刷新合作机会'),
 'retry': ('Reload', '重新加载'),
 'signIn.title': ('Sign in to view', '登录后查看'),
 'signIn.reason': ('Sign in to view business information', '请登录后查看经营信息'),
 'denied.title': ('Not available right now', '暂时不能查看'),
 'denied.reason': ('This account does not have permission to view this', '当前账号没有查看权限'),
 'fixture.banner': ('Offline synthetic example. Nothing is sent or saved.', '离线示例数据，不会发送或保存任何内容。'),
}
strings = {P + k: {'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': en}}, 'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}} for k, (en, zh) in sorted(ROWS.items())}
out = ROOT / 'Resources/MerchantCoopCenter.xcstrings'
out.write_text(json.dumps({'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
SOURCES = ['App/MerchantCoopCenterView.swift', 'App/MerchantCoopCenterFixtureHost.swift', 'App/MerchantCoopCenterSessionBinding.swift', 'App/MerchantHomeView.swift', 'App/MerchantBusinessViews.swift']
used = set()
for source in SOURCES:
    used |= set(re.findall(r'mcc\("(merchantCoopCenter\.[A-Za-z0-9.]+)"', (ROOT / source).read_text()))
assert used == set(strings), (used ^ set(strings))
print(len(strings), 'keys')
