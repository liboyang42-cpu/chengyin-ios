#!/usr/bin/env python3
"""w2-05 coupons/withdrawal parity copy. Writes the fragment and merges it key-wise into
Localizable.xcstrings (idempotent; rerun after resolving catalog conflicts)."""
from pathlib import Path
import json
root = Path(__file__).resolve().parents[1]
values = {
    # subpackageMember/tixianjilu + scene-member-withdraw-history
    'withdrawal.history.status.processing': ('Withdrawal in progress', '提现中'),
    'withdrawal.history.status.succeeded': ('Withdrawal succeeded', '提现成功'),
    'withdrawal.history.status.failed': ('Withdrawal failed; the full amount was returned', '提现失败，提现金额已全部退回'),
    'withdrawal.history.status.unknown': ('Status unconfirmed', '状态待确认'),
    'withdrawal.history.login.title': ('Sign in to view withdrawal history', '登录后查看提现记录'),
    'withdrawal.history.login.detail': ('After signing in you can view your actual withdrawal records.', '登录后可查看你的真实提现记录'),
    'withdrawal.history.denied.title': ("This account can't view withdrawal history", '当前账号无法查看提现记录'),
    'withdrawal.history.denied.detail': ("Check this account's viewing permission.", '请确认当前账号的查看权限'),
    'withdrawal.history.failed.title': ("Withdrawal history didn't load", '提现记录没加载出来'),
    'withdrawal.history.failed.detail': ('Reading is temporarily unavailable.', '读取暂不可用'),
    'withdrawal.history.unavailable.detail': ('Withdrawal history is not available in this build.', '此版本暂未开放提现记录读取'),
    # subpackageMember/tixian
    'withdrawal.apply.title': ('Withdrawal application', '提现申请'),
    'withdrawal.apply.method': ('Withdrawal method', '提现方式'),
    'withdrawal.apply.method.value': ('Contact platform support; support handles it offline', '联系平台客服，由客服协助线下处理'),
    'withdrawal.apply.note.title': ('Withdrawal notes', '提现说明'),
    'withdrawal.apply.note.detail': ('Withdrawals are now handled offline by support. Add the platform support WeChat to verify.', '提现已改为客服协助线下处理，请添加平台客服微信核对。'),
    'withdrawal.apply.contact': ('Contact support to withdraw', '联系客服提现'),
    # subpackageMember/coupon-qr
    'couponCode.missing': ('Coupon details missing', '缺少券信息'),
    'couponCode.missing.detail': ('Go back to your coupon wallet and open it again.', '请返回票夹重新进入'),
    'couponCode.presentToMerchant': ('Show this to the merchant to scan and redeem', '出示给商家扫码核销'),
    'couponCode.refresh': ('Refresh QR code', '刷新二维码'),
    'couponCode.fetchAgain': ('Fetch again', '重新获取'),
    'couponCode.serviceDisabled': ('Coupon codes are unavailable', '优惠券出示码暂不可用'),
    'couponCode.serviceDisabled.detail': ('Coupon code display is currently unavailable. Contact the administrator.', '优惠券出示码暂不可用，请联系管理员'),
}
# Existing keys whose copy is aligned to the source (scene-game-coupon-wallet). English
# titles pinned by UI tests are kept; only the Chinese title and the hints change.
overrides = {
    'accountCollection.coupons.empty': (None, '这里还没有优惠券'),
    'accountCollection.coupons.emptyHint': ('Coupons from exploration or activity tasks will appear here.', '完成探索或活动任务后，领取的券会出现在这里。'),
    'accountCollection.coupons.filteredEmpty': (None, '当前筛选暂无优惠券'),
    'accountCollection.coupons.filteredEmptyHint': ('Switch to another status to view coupons.', '切换其他状态查看优惠券。'),
}
def entry(pair):
    return {'extractionState': 'manual', 'localizations': {lang: {'stringUnit': {'state': 'translated', 'value': text}} for lang, text in zip(('en', 'zh-Hans'), pair)}}
fragment = {key: entry(pair) for key, pair in values.items()}
(root/'Resources/W205CouponsWithdrawalLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2)+'\n')
path = root/'Resources/Localizable.xcstrings'
catalog = json.loads(path.read_text())
strings = catalog['strings']
for key, item in fragment.items():
    strings[key] = item
for key, (en, zh) in overrides.items():
    localizations = strings[key]['localizations']
    for lang, text in (('en', en), ('zh-Hans', zh)):
        if text is not None:
            localizations[lang] = {'stringUnit': {'state': 'translated', 'value': text}}
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
print(f'{len(fragment)} bilingual keys, {len(overrides)} aligned keys')
