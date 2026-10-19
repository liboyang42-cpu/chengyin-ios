#!/usr/bin/env python3
"""Write the coop parity (w2-14) English/Chinese strings and merge them key-wise into Localizable.

Chinese copy follows the mini-program source pages under pages/coop and
components/cy/scene-merchant-profit; English is a faithful translation.
Re-running is idempotent; existing keys owned by other catalogs are left untouched
unless they are listed here.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
FRAGMENT = ROOT / 'Resources/CoopParityLocalizations.fragment.json'
CATALOG = ROOT / 'Resources/Localizable.xcstrings'

STRINGS = {
    # pages/coop/finance + scene-merchant-profit
    'cooperation.finance.title': ('Profit share details', '分润明细'),
    'cooperation.finance.stat.income': ('Credited profit share', '已入账分润'),
    'cooperation.finance.stat.adjustPending': ('Adjustments pending', '调整待处理'),
    'cooperation.finance.stat.adjustExecuted': ('Adjustments applied', '已执行调整'),
    'cooperation.finance.withdraw': ('Contact platform support to withdraw', '联系平台客服提现'),
    'cooperation.finance.withdraw.unknown': ('Credited amount awaiting confirmation', '已入账金额待确认'),
    'cooperation.finance.withdraw.zero': ('No credited profit share yet', '还没有已入账分润'),
    'cooperation.finance.withdraw.a11y.unknown': ('Contact platform support to withdraw; credited amount awaiting confirmation', '联系平台客服提现，已入账金额待确认'),
    'cooperation.finance.withdraw.a11y.zero': ('Contact platform support to withdraw; no credited profit share yet', '联系平台客服提现，还没有已入账分润'),
    'cooperation.finance.topics': ('Settlement by topic', '各主题结算'),
    'cooperation.finance.explainer': ('Settled is not the same as credited: settled means the amount has been calculated; credited means the money has reached your personal account.', '已结算不等于已入账：已结算表示金额完成核算，已入账表示款项已进入个人账户。'),
    'cooperation.finance.empty': ('No cooperation settlements yet', '还没有合作结算'),
    'cooperation.finance.settled': ('Settled', '已结算'),
    'cooperation.finance.topicFallback %lld': ('Topic #%lld', '主题 #%lld'),
    'cooperation.finance.status.settlementUnknown': ('Settlement status awaiting confirmation', '结算状态待确认'),
    'cooperation.finance.status.unsettled': ('Pending settlement', '待结算'),
    'cooperation.finance.status.amountUnknown': ('Amount awaiting confirmation', '金额待确认'),
    'cooperation.finance.status.noIncomeDue': ('Nothing to credit', '无需入账'),
    'cooperation.finance.status.arrivalUnknown': ('Arrival status awaiting confirmation', '到账状态待确认'),
    'cooperation.finance.status.credited': ('Credited', '已入账'),
    'cooperation.finance.status.awaitingCredit': ('Awaiting credit', '待入账'),
    'cooperation.finance.merchant.amountUnknown': ('Amount awaiting confirmation', '金额待确认'),
    'cooperation.finance.merchant.noMerchantShare': ('No merchant share', '无商家分润'),
    'cooperation.finance.merchant.payoutUnknown': ('Payout status awaiting confirmation', '打款状态待确认'),
    'cooperation.finance.merchant.paid': ('Paid', '已打款'),
    'cooperation.finance.merchant.partiallyPaid': ('Partially paid', '部分打款'),
    'cooperation.finance.merchant.unpaid': ('Awaiting payout', '待打款'),
    'cooperation.finance.issue.auth.title': ('Sign in to view organizer profit share', '登录后查看主办分润'),
    'cooperation.finance.issue.auth.detail': ('After signing in you can see your actual organizer profit share', '登录后可查看你的真实主办分润'),
    'cooperation.finance.issue.denied.title': ('This account cannot view profit share', '当前账号无法查看分润'),
    'cooperation.finance.issue.denied.detail': ('Check this account’s viewing permission', '请确认当前账号的查看权限'),
    'cooperation.finance.issue.failed.title': ('Profit share data did not load', '分润数据没加载出来'),
    'cooperation.finance.issue.failed.detail': ('Reload the profit share data', '请重新加载分润数据'),
    'cooperation.finance.stages.pending': ('Pending settlement (activity not ended)', '待结算（活动未结束）'),
    'cooperation.finance.stages.disputed': ('Complaint in progress', '客诉处理中'),
    'cooperation.finance.stages.unknown': ('Some unreceived amounts cannot be calculated yet; the settled credit is authoritative', '部分未到账金额暂时算不出，以结算到账为准'),
    'cooperation.finance.stages.failed': ('Unreceived amounts are temporarily unavailable', '未到账金额暂时取不到'),
    # pages/coop/withdraw and pages/coop/withdraw/records
    'cooperation.withdraw.entry': ('Withdraw', '提现'),
    'cooperation.withdraw.title': ('Withdrawal method changed', '提现方式已调整'),
    'cooperation.withdraw.subtitle': ('Now handled offline by platform support', '改为联系平台客服线下处理'),
    'cooperation.withdraw.detail': ('Add the support WeChat account; the amount is checked and handled offline.', '添加客服微信，核对金额后线下处理。'),
    'cooperation.withdrawRecords.title': ('Withdrawal records', '提现记录'),
    'cooperation.withdrawRecords.subtitle': ('Bank-card withdrawals and arrival progress', '银行卡提现与到账进度'),
    'cooperation.withdrawRecords.failed.title': ('Page failed to open', '页面打开失败'),
    'cooperation.withdrawRecords.failed.detail': ('Withdrawal records failed to open. Try again.', '提现记录页面打开失败，请重试'),
    # pages/coop/settlement-detail + components/settlement-detail/view-model.js
    'cooperation.settlement.title': ('Settlement details', '结算详情'),
    'cooperation.settlement.refreshing': ('Updating settlement details', '正在更新结算详情'),
    'cooperation.settlement.refreshing.detail': ('The current details remain viewable', '现有详情仍可查看'),
    'cooperation.settlement.staleError': ('Settlement details were not updated', '结算详情没有更新'),
    'cooperation.settlement.missingParam': ('Settlement record identifier missing', '缺少结算记录标识'),
    'cooperation.settlement.missingParam.detail': ('Go back to the settlement list and open it again', '请返回结算列表重新进入'),
    'cooperation.settlement.back': ('Go back', '返回上一页'),
    'cooperation.settlement.missingRecord': ('Settlement record not visible', '结算记录不可见'),
    'cooperation.settlement.missingRecord.detail': ('This record may have been withdrawn or may not belong to the current account', '这条记录可能已撤回或不属于当前账号'),
    'cooperation.settlement.backToList': ('Back to settlement list', '返回结算列表'),
    'cooperation.settlement.failed': ('Settlement details did not load', '结算详情没加载出来'),
    'cooperation.settlement.failed.detail': ('Service temporarily unavailable. Try again later.', '服务暂时不可用，请稍后重试'),
    'cooperation.settlement.reload': ('Settlement details need to be reloaded', '结算详情需要重新加载'),
    'cooperation.settlement.breakdown': ('Amount breakdown', '金额分解'),
    'cooperation.settlement.progress': ('Settlement progress', '结算进度'),
    'cooperation.settlement.perspective.host': ('Organizer profit share', '主办分润'),
    'cooperation.settlement.perspective.merchant': ('Host-side profit share', '承接分润'),
    'cooperation.settlement.status.awaitingCredit': ('Awaiting credit', '待入账'),
    'cooperation.settlement.status.creditedBalance': ('Added to balance', '已入余额'),
    'cooperation.settlement.status.void': ('Voided', '已作废'),
    'cooperation.settlement.status.unknown': ('Status awaiting confirmation', '状态待确认'),
    'cooperation.settlement.status.unsettled': ('Pending settlement', '待结算'),
    'cooperation.settlement.status.amountUnknown': ('Amount awaiting confirmation', '金额待确认'),
    'cooperation.settlement.status.noIncomeDue': ('Nothing to credit', '无需入账'),
    'cooperation.settlement.status.credited': ('Credited', '已入账'),
    'cooperation.settlement.line.payee': ('Payee', '收款方'),
    'cooperation.settlement.line.verifiedSales': ('Redeemed sales', '核销销售额'),
    'cooperation.settlement.line.verifiedHeads': ('Redeemed participants', '核销人数'),
    'cooperation.settlement.line.shareRule': ('Profit share method', '分润方式'),
    'cooperation.settlement.line.income': ('My profit share', '我的分润'),
    'cooperation.settlement.line.totalSales': ('Total sales', '总销售额'),
    'cooperation.settlement.line.platform': ('Platform service fee', '平台服务费'),
    'cooperation.settlement.line.merchant': ('Merchant receivable', '商家应收'),
    'cooperation.settlement.step.created': ('Settlement record created', '结算记录已创建'),
    'cooperation.settlement.step.settled': ('Cooperation settled', '合作已结算'),
    'cooperation.settlement.step.payable': ('Expected credit', '预计入账'),
    'cooperation.settlement.step.payableWaiting': ('Awaiting credit', '等待入账'),
    'cooperation.settlement.step.paid': ('Added to balance', '已入余额'),
    'cooperation.settlement.step.void': ('Settlement voided', '结算已作废'),
    'cooperation.settlement.step.unknown': ('Settlement status awaiting confirmation', '结算状态待确认'),
    'cooperation.settlement.step.hostSettlementUnknown': ('Settlement status awaiting confirmation', '结算状态待确认'),
    'cooperation.settlement.step.hostSettled': ('Topic settled', '主题已结算'),
    'cooperation.settlement.step.hostUnsettled': ('Topic awaiting settlement', '主题待结算'),
    'cooperation.settlement.step.hostCredited': ('My profit share credited', '我的分润已入账'),
    'cooperation.settlement.step.hostAwaiting': ('My profit share awaiting credit', '我的分润待入账'),
    'cooperation.settlement.step.hostNoIncome': ('Nothing to credit this period', '本期无需入账'),
    'cooperation.settlement.step.merchantPayable': ('Merchant receivable creditable', '商家应收可入账'),
    'cooperation.settlement.step.merchantPaid': ('Merchant receivable paid', '商家应收已打款'),
    'cooperation.settlement.value.payee.club': ('Club profit share', '俱乐部分润'),
    'cooperation.settlement.value.payee.merchant': ('Merchant profit share', '商家分润'),
    'cooperation.settlement.value.share.traffic': ('Traffic', '引流'),
    'cooperation.settlement.value.share.rate': ('Revenue share', '分成'),
    'cooperation.settlement.value.share.fixed': ('Fixed', '固定'),
    'cooperation.settlement.value.shareRate %@': ('Revenue share · %@%%', '分成 · %@%%'),
    'cooperation.settlement.value.fixedFee %@': ('Fixed · ¥%@/person', '固定 · ¥%@/人'),
    'cooperation.settlement.value.heads %lld': ('%lld people', '%lld 人'),
    'cooperation.settlement.value.timeUnknown': ('Time awaiting confirmation', '时间待确认'),
    'cooperation.settlement.value.arrivalUnknown': ('Arrival time awaiting confirmation', '到账时间待确认'),
    'cooperation.settlement.value.refreshLater': ('Refresh later', '请稍后刷新'),
    'cooperation.settlement.value.currentState': ('Current status', '当前状态'),
    'cooperation.settlement.value.arrived': ('Arrived', '已到账'),
    'cooperation.settlement.value.awaitingArrival': ('Awaiting arrival', '等待到账'),
    'cooperation.settlement.value.zeroShare': ('Profit share is 0', '分润为 0'),
}


def entry(en, zh):
    return {'localizations': {
        'en': {'stringUnit': {'state': 'translated', 'value': en}},
        'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}},
    }}


def main():
    strings = {key: entry(*value) for key, value in STRINGS.items()}
    FRAGMENT.write_text(json.dumps({'sourceLanguage': 'en', 'version': '1.0', 'strings': strings}, ensure_ascii=False, indent=2) + '\n')
    catalog = json.loads(CATALOG.read_text())
    catalog['strings'].update(strings)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    print(f'Merged {len(strings)} coop parity strings')


if __name__ == '__main__':
    main()
