#!/usr/bin/env python3
"""Write the separate MerchantOps bilingual table for the w2-18 merchant-ops parity surfaces.

Chinese copy follows the mini-program pages named next to each group; English is a plain translation.
The script fails when App sources use a key that is not defined here, or a defined key is unused.
"""
import json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
DYNAMIC_PREFIXES = ['merchantOps.customer.tier.', 'merchantOps.aftercare.processing.', 'merchantOps.aftercare.processingHint.', 'merchantOps.aftercare.stepState.']
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
 # pages/merchant/predict/index.{js,wxml}
 'merchantOps.predict.denied.title': ('Your role cannot settle predictions', '当前岗位不能结算竞猜'),
 'merchantOps.predict.denied.body': ('Settling issues coupons by your rules and needs project management access. Ask the store owner to adjust team permissions.', '结算会按规则发券，需要项目管理权限。请联系店主调整经营团队权限'),
 'merchantOps.predict.error': ('Pending predictions failed to load', '待答列表加载失败'),
 'merchantOps.predict.retry': ('Reload', '重新加载'),
 'merchantOps.predict.empty.title': ('No predictions waiting for your answer', '没有等你给答案的竞猜'),
 'merchantOps.predict.empty.body': ('After players place their picks, the round appears here for you to publish the answer', '玩家押完之后，那一轮会出现在这里等你公布答案'),
 'merchantOps.predict.summary %lld': ('%lld rounds waiting for your answer', '共 %lld 轮等你给答案'),
 'merchantOps.predict.round %@': ('Round of %@', '%@ 那一轮'),
 'merchantOps.predict.daysLeft %lld': ('%lld days left', '还剩 %lld 天'),
 'merchantOps.predict.lastDay': ('Void unless answered today', '今天不给就作废'),
 'merchantOps.predict.bets %lld': ('%lld people picked this round', '%lld 个人押了这一轮'),
 'merchantOps.predict.noBets': ('Nobody has picked this round yet', '这一轮还没有人押'),
 'merchantOps.predict.options %lld': ('%lld options', '%lld 个选项'),
 'merchantOps.predict.workbenchAlert %lld': ('%lld prediction rounds are waiting for your answer', '有 %lld 轮竞猜待给答案'),
 # pages/merchant/aftercare/index.* and aftercare/detail/view-model.js
 'merchantOps.aftercare.status.awaitingResponse': ('Awaiting response', '待回应'),
 'merchantOps.aftercare.status.returned': ('Returned', '已退回'),
 'merchantOps.aftercare.takenOver': ('Sent to platform support', '已转平台客服'),
 'merchantOps.aftercare.amountPending': ('Amount to be confirmed', '金额待确认'),
 'merchantOps.aftercare.day.today': ('Today', '今天'),
 'merchantOps.aftercare.day.yesterday': ('Yesterday', '昨天'),
 'merchantOps.aftercare.day.monthDay %lld %lld': ('%1$lld/%2$lld', '%1$lld月%2$lld日'),
 'merchantOps.aftercare.day.yearMonthDay %lld %lld %lld': ('%1$lld/%2$lld/%3$lld', '%1$lld年%2$lld月%3$lld日'),
 'merchantOps.aftercare.day.unknown': ('Time to be confirmed', '时间待确认'),
 'merchantOps.aftercare.empty.PENDING': ('No requests awaiting your response', '没有待回应售后'),
 'merchantOps.aftercare.empty.PROCESSING': ('No requests in progress', '没有处理中的售后'),
 'merchantOps.aftercare.empty.COMPLETED': ('No completed requests yet', '还没有已完成售后'),
 'merchantOps.aftercare.source.registration': ('Registration refund', '报名退款'),
 'merchantOps.aftercare.source.other': ('Refund request', '退款申请'),
 'merchantOps.aftercare.policy.exploreEnd': ('Full refund can be requested before redemption and the deadline', '截止前未核销可全额申请'),
 'merchantOps.aftercare.policy.snapshot': ('Refund rules follow the order snapshot', '退款规则以订单快照为准'),
 'merchantOps.aftercare.policy.unknown': ('Refund policy to be confirmed', '退款政策待确认'),
 'merchantOps.aftercare.policyVersion %lld': ('Policy version %lld', '政策版本 %lld'),
 'merchantOps.aftercare.platformSteps': ('Platform progress', '平台处理进度'),
 'merchantOps.aftercare.step.funds': ('Funds result', '款项结果'),
 'merchantOps.aftercare.step.approved': ('Platform approved the refund', '平台已批准退款'),
 'merchantOps.aftercare.funds.unconfirmed': ('Return not confirmed yet', '尚未确认退回'),
 'merchantOps.aftercare.stepState.done': ('Done', '已完成'),
 'merchantOps.aftercare.stepState.doing': ('In progress', '进行中'),
 'merchantOps.aftercare.stepState.todo': ('Not yet', '未开始'),
 'merchantOps.aftercare.stepState.rejected': ('Ended', '已结束'),
 'merchantOps.aftercare.processing.WAITING_PLATFORM_REVIEW': ('Platform reviewing', '平台审核中'),
 'merchantOps.aftercare.processing.PLATFORM_REJECTED': ('Platform did not approve the refund', '平台未通过退款'),
 'merchantOps.aftercare.processing.REFUND_PROCESSING': ('Refund processing', '退款处理中'),
 'merchantOps.aftercare.processing.MANUAL_REFUND_PENDING': ('Waiting for manual refund', '等待人工退款'),
 'merchantOps.aftercare.processing.MANUAL_REFUND_REVIEW': ('Manual refund awaiting review', '人工退款待复核'),
 'merchantOps.aftercare.processing.REFUNDED': ('Platform confirmed the refund', '平台确认已退款'),
 'merchantOps.aftercare.processing.UNKNOWN': ('Platform status to be confirmed', '平台状态待确认'),
 'merchantOps.aftercare.processingHint.WAITING_PLATFORM_REVIEW': ('The platform has not finished reviewing the refund', '平台尚未完成退款审核'),
 'merchantOps.aftercare.processingHint.PLATFORM_REJECTED': ('Review has ended; the money will not be returned because of it', '平台审核已结束，款项不会因此退回'),
 'merchantOps.aftercare.processingHint.REFUND_PROCESSING': ('Approved by the platform; the money is still being processed', '平台已批准，款项仍在处理'),
 'merchantOps.aftercare.processingHint.MANUAL_REFUND_PENDING': ('The original-route refund failed; the platform is handling it manually', '原路退款异常，平台正在人工处理'),
 'merchantOps.aftercare.processingHint.MANUAL_REFUND_REVIEW': ('Manual handling is recorded and still awaits platform review', '人工处理已登记，仍待平台复核'),
 'merchantOps.aftercare.processingHint.REFUNDED': ('The platform confirmed the money was returned', '平台已确认款项退回'),
 'merchantOps.aftercare.processingHint.UNKNOWN': ('The current status cannot be judged safely; refresh later', '当前状态无法安全判断，请稍后刷新'),
 'merchantOps.aftercare.readOnly.role': ('Your role can only view this. Ask the store owner to adjust permissions.', '当前岗位只有查看权限，请联系店主调整权限。'),
 # pages/merchant/ledger/index.{js,wxml}
 'merchantOps.ledger.state.noCash': ('No cash settlement this time', '本次不产生现金结算'),
 'merchantOps.ledger.state.pendingTheme': ('Pending theme settlement', '待主题结算'),
 'merchantOps.ledger.state.pending': ('Pending settlement', '待结算'),
 'merchantOps.ledger.state.settledPersonal': ('In personal account', '已入个人账户'),
 'merchantOps.ledger.state.settledPaid': ('Paid by platform', '平台已打款'),
 'merchantOps.ledger.state.adjusting': ('Adjusting', '调整中'),
 'merchantOps.ledger.state.adjusted': ('Adjusted', '已调整'),
 'merchantOps.ledger.state.reversed': ('Redemption reversed', '核销已撤销'),
 'merchantOps.ledger.state.ledgerError': ('Settlement data does not match; contact support', '结算数据对不上，请联系客服'),
 'merchantOps.ledger.state.unknown': ('Status to be confirmed', '状态待确认'),
 'merchantOps.ledger.fulfilment.active': ('Redemption valid', '核销有效'),
 'merchantOps.ledger.fulfilment.reversed': ('Redemption reversed', '核销已撤销'),
 'merchantOps.ledger.fulfilment.unknown': ('Redemption status to be confirmed', '核销状态待确认'),
 'merchantOps.ledger.redemptionTitle': ('Redemption record', '核销记录'),
 'merchantOps.ledger.customerProtected': ('Customer details protected', '顾客信息受保护'),
 'merchantOps.ledger.amount.none': ('—', '—'),
 'merchantOps.ledger.amount.pending': ('To be determined', '待定'),
 'merchantOps.ledger.source.redemptionFee': ('Redemption fee', '核销计酬'),
 'merchantOps.ledger.source.coopShare': ('Cooperation share', '合作分润'),
 'merchantOps.ledger.source.activityShare': ('Activity share', '活动分润'),
 'merchantOps.ledger.source.clawback': ('Deduction executed', '已执行扣划'),
 'merchantOps.ledger.source.adjustment': ('Adjustment', '调整'),
 'merchantOps.ledger.batch.zero': ('No payment needed this period', '本期无需打款'),
 'merchantOps.ledger.batch.owes': ('Adjustment pending', '调整待处理'),
 'merchantOps.ledger.batch.frozen': ('Settlement in progress', '结算处理中'),
 'merchantOps.ledger.batch.paidInvoiced': ('Paid by platform · invoiced', '平台已打款 · 已开票'),
 'merchantOps.ledger.batch.paidNotInvoiced': ('Paid by platform · not invoiced', '平台已打款 · 未开票'),
 'merchantOps.ledger.batch.confirmed': ('Confirmed', '已确认'),
 'merchantOps.ledger.batch.reconciling': ('Awaiting reconciliation', '待对账'),
 'merchantOps.ledger.batch.publicTransfer': ('Corporate settlement', '对公结算'),
 'merchantOps.ledger.invoice.none': ('Not invoiced', '未开票'),
 'merchantOps.ledger.invoice.issued': ('Invoiced', '已开票'),
 'merchantOps.ledger.invoice.red': ('Invoice reversed', '已红冲'),
 'merchantOps.ledger.summary.count': ('Redeemed this month', '本月核销'),
 'merchantOps.ledger.summary.countValue %lld': ('%lld', '%lld 笔'),
 'merchantOps.ledger.summary.pending': ('Pending settlement', '待结算'),
 'merchantOps.ledger.summary.arrived': ('Credited', '已入账'),
 # pages/merchant/customer/index.{js,wxml}
 'merchantOps.customer.unnamed': ('No name left', '未留姓名'),
 'merchantOps.customer.tier.pending': ('To redeem', '待核销'),
 'merchantOps.customer.tier.abnormal': ('Exception', '异常'),
 'merchantOps.customer.tier.dormant': ('Dormant', '沉睡'),
 'merchantOps.customer.tier.repeat': ('Repeat', '复购'),
 'merchantOps.customer.tier.new': ('New', '新客'),
 'merchantOps.customer.noteBadge': ('Note', '备注'),
 'merchantOps.customer.relative.today': ('Today', '今天'),
 'merchantOps.customer.relative.yesterday': ('Yesterday', '昨天'),
 'merchantOps.customer.relative.days %lld': ('%lld days ago', '%lld 天前'),
 'merchantOps.customer.relative.months %lld': ('%lld months ago', '%lld 个月前'),
 'merchantOps.customer.relative.years %lld': ('%lld years ago', '%lld 年前'),
 'merchantOps.customer.summary.monthly %lld %lld': ('%1$lld · %2$lld new this month', '%1$lld 位 · 本月新增 %2$lld'),
 'merchantOps.customer.summary.total %lld': ('%lld customers', '%lld 位'),
 'merchantOps.customer.summary.unavailable': ('Customer count unavailable', '客户数量暂不可用'),
 'merchantOps.customer.footer %lld': ('%lld customers · all shown', '共 %lld 位客户 · 已全部显示'),
 'merchantOps.aftercare.readOnly.closed': ('Platform review has ended; no further merchant opinion can be added.', '平台审核已结束，不能再追加商家意见。'),
}

def main():
    strings = {k: {'extractionState': 'manual', 'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': en}},
               'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}} for k, (en, zh) in sorted(ROWS.items())}
    for key, (en, zh) in ROWS.items():
        count = lambda text: len(re.findall(r'%(?:\d\$)?(?:lld|@)', text))
        assert count(en) == count(key) == count(zh), key
    out = ROOT / 'Resources/MerchantOps.xcstrings'
    out.write_text(json.dumps({'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    used, sources = set(), ''
    for path in sorted((ROOT / 'App').glob('*.swift')) + sorted((ROOT / 'Core').glob('*.swift')):
        text = path.read_text(); sources += text
        used |= set(re.findall(r'MerchantOpsCopy\.text\("(merchantOps\.[^"]+)"', text))
    # Keys chosen at runtime (row status, platform steps) must be spelled out in Core or reached by a listed prefix.
    for key in strings:
        if '"' + key + '"' in sources or any(key.startswith(prefix) and '"' + prefix + '"' in sources for prefix in DYNAMIC_PREFIXES):
            used.add(key)
    used = {key for key in used if not key.endswith('.')}
    assert used == set(strings), sorted(used ^ set(strings))
    print(len(strings), 'keys')

if __name__ == '__main__':
    main()
