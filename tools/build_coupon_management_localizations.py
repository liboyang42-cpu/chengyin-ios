#!/usr/bin/env python3
from pathlib import Path
import json
root = Path(__file__).resolve().parents[1]
values = {
'unavailable': ('Coupon management is not configured', '优惠券管理尚未配置'),
'invalid': ('Check the coupon details', '请检查优惠券信息'),
'malformed': ('Coupon data could not be confirmed', '无法确认优惠券数据'),
'signIn': ('Sign in to manage your coupons', '请登录后管理优惠券'),
'changed': ('The account, permission, or coupon changed. Review it again.', '账号、权限或优惠券已变化，请重新确认'),
'forbidden': ('This action is not available for the current account or coupon', '当前账号或优惠券不支持此操作'),
'storage': ('The safety record could not be saved. Nothing was submitted.', '无法保存安全记录，尚未提交'),
'unknownOutcome': ('The result is unknown. Resubmission is locked until the original outcome can be verified.', '结果尚未确认。确认原操作结果前不能重复提交'),
'serverError': ('The server returned a message', '服务端返回了提示'),
'scheduled': ('Not started', '未开始'), 'active': ('Active', '进行中'), 'ended': ('Ended', '已结束'),
'invalidated': ('Invalidated', '已失效'), 'stopped': ('Distribution stopped', '已停发'), 'unknownStatus': ('Status unconfirmed', '状态待确认'),
'nameRequired': ('Enter a coupon name', '请输入优惠券名称'), 'datesRequired': ('Select coupon dates', '请选择优惠券日期'),
'typeRequired': ('Select a coupon type', '请选择优惠券类型'), 'quantityRequired': ('Enter a quantity greater than zero', '请输入大于0的投放数量'),
'dateOrder': ('End time must be later than start time', '结束时间要晚于开始时间'),
'gift': ('Gift coupon', '礼品券'), 'tenPercent': ('10% off coupon', '9折券'), 'twentyPercent': ('20% off coupon', '8折券'), 'experience': ('Experience pass', '体验卡'), 'coupon': ('Coupon', '优惠券'),
'loading': ('Loading coupons', '正在加载优惠券'), 'empty': ('No published coupons', '暂无已发布优惠券'),
'create': ('Create coupon', '创建优惠券'), 'title': ('Published coupons', '我发布的券'),
'dormant': ('Live publication and stopping distribution are disabled in this build.', '此版本未开放真实发布和停发'),
'synthetic': ('Synthetic test data only', '仅为合成测试数据'), 'simulated': ('Simulation finished. No real coupon changed.', '模拟已完成，未更改真实优惠券'),
'noDescription': ('No description provided', '未填写说明'), 'status': ('Status', '状态'), 'type': ('Coupon type', '券类型'),
'start': ('Valid from', '开始时间'), 'end': ('Valid until', '结束时间'), 'dateNotice': ('Dates are display information. The server confirms eligibility and status.', '日期仅供展示，资格和状态由服务端确认'),
'counts': ('Distribution details', '发放信息'), 'published': ('Published', '投放数量'), 'received': ('Claimed', '已领取'), 'used': ('Redeemed', '已核销'), 'remaining': ('Remaining', '库存'),
'perLimit': ('Claim limit, if provided', '领取限制（如有）'), 'amount': ('Amount, if provided', '金额（如有）'), 'currency': ('Currency, if provided', '币种（如有）'),
'stopPolicy': ('Stopping distribution cannot be undone. New claims and issuance stop; already claimed coupons remain usable and redeemable.', '停发不可撤销。停发后不能再被领取、发放；已领到的券照常可用、可核销'),
'reviewStop': ('Review stopping distribution', '确认停发'),
'claimUnavailable': ('Claiming is unavailable: the source contract does not define a claim operation. Claimed coupons remain in your coupon wallet.', '暂不支持领取：源接口尚未定义领取操作。已领券仍可在券包中查看'),
'detail': ('Coupon details', '优惠券详情'), 'refresh': ('Refresh', '刷新'), 'details': ('Coupon information', '优惠券信息'), 'name': ('Coupon name', '优惠券名称'), 'description': ('Description', '说明'),
'chooseType': ('Select a type', '请选择'), 'quantity': ('Quantity', '投放数量'), 'dates': ('Validity dates', '有效期'), 'setStart': ('Set start date', '设置开始日期'), 'setEnd': ('Set end date', '设置结束日期'),
'reviewPublish': ('Review publication', '确认发布'), 'cancel': ('Cancel', '取消'), 'discardTitle': ('Discard this draft?', '放弃编辑？'), 'discard': ('Discard', '放弃'), 'keepEditing': ('Keep editing', '继续编辑'),
'review': ('Review', '确认信息'), 'reviewNotice': ('Review these exact details. Changes require a new review.', '请核对上述信息，修改后需重新确认'), 'simulate': ('Confirm simulation', '确认模拟'),
'acknowledged': ('The server acknowledged the action. Check the refreshed list.', '服务端已确认操作，请检查刷新后的列表'),
'chinaTime': ('Validity times are shown in China Standard Time (UTC+8).', '有效期均为北京时间（UTC+8）。'),
'readbackPending': ('Server acknowledged. Current record is not yet verified; do not submit again.', '服务器已确认，当前记录尚未核验，请勿重复提交。'),
'readbackVerified': ('Server acknowledged; current coupon record verified.', '服务器已确认，并已核验当前优惠券记录。'),
'confirmSubmission': ('Confirm submission', '确认提交'),
'fixtureReopen': ('Reopen example', '重新打开示例'), 'fixtureSignOut': ('Sign out of example', '退出示例账号')
}
fragment = { 'couponManagement.'+key: {'extractionState': 'manual', 'localizations': {lang:{'stringUnit': {'state':'translated','value':text}} for lang,text in zip(('en','zh-Hans'), pair)}} for key,pair in values.items()}
(root/'Resources/CouponManagementLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2)+'\n')
print(f'{len(fragment)} bilingual keys')
