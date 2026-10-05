#!/usr/bin/env python3
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
values={
'dashboard':('Marketing','营销概览'),'insight':('Shop insights','店铺参谋'),'subscriptions':('Entitlements','付费权益'),'predictions':('Prediction inbox','竞猜待答'),
'unavailable':('This feature is not configured','此功能尚未配置'),'signIn':('Sign in to continue','请登录后继续'),'stale':('The account, permission or round changed. Review again.','账号、权限或轮次已变化，请重新确认'),
'denied':('Your current merchant role does not grant this permission','当前商家岗位没有此权限'),'malformed':('The server data could not be confirmed','无法确认服务端数据'),'invalid':('Review the selected answer and acknowledge its effects','请核对答案并确认操作后果'),
'locked':('This round has a submission record. Further settlement is blocked.','此轮已有提交记录，已禁止再次结算'),
'unknown':('The outcome is unconfirmed. Resubmission is locked; do not settle this round again.','结果尚未确认，已锁定重复提交，请勿再次结算此轮'),
'storage':('The safety record could not be saved. Nothing was submitted.','无法保存安全记录，尚未提交'),'serverError':('The server returned a message','服务端返回了提示'),
'dormant':('Live service access, AI processing and prediction settlement require separate activation.','真实服务、AI 分析和竞猜结算需分别开通'),
'section':('Section','栏目'),'loading':('Loading','加载中'),'refresh':('Refresh','刷新'),'acknowledged':('Server acknowledgement','服务端确认'),'winners':('Winning participants','猜中人数'),
'coupons':('Coupons','优惠券'),'active':('Active coupons','有效优惠券'),'claimed':('Claimed','已领取'),'redeemed':('Redeemed','已核销'),'redemptionRate':('Redemption rate','核销率'),
'content':('Content','内容'),'topics':('Topics','主题'),'exploration':('Free exploration','自由探索'),'activities':('Activities','活动'),'funnel':('Conversion funnel','转化漏斗'),
'hour':('Hour','时段'),'maleRate':('Male share','男性占比'),'femaleRate':('Female share','女性占比'),'interest':('Reported interest','兴趣偏好'),
'facts':('Measured business facts','经营数据事实'),'window':('Reporting window','统计范围'),'sample':('Sample members','样本人数'),'lowSample':('Small sample: interpret these results cautiously','样本较少，请谨慎解读'),
'checkins':('Check-ins','到店次数'),'repeatRate':('Repeat visit rate','复访率'),'wait':('Average wait (minutes)','平均等待（分钟）'),'members':('Members','用户数'),'offers':('Active offers','生效供给'),'quotaRate':('Quota usage','额度使用率'),
'suggestions':('AI suggestions','AI 建议'),'suggestionNotice':('Suggestions are generated advice, separate from measured facts.','建议为 AI 生成内容，与经营数据事实分开呈现'),
'aiUnavailable':('Suggestions are unavailable; measured facts remain available','暂时无法生成建议，经营事实仍可查看'),'generatedAt':('Generated at','生成时间'),'openSuggestion':('Open related section','前往相关页面'),
'recommendedTopics':('Server-recommended topics','服务端推荐主题'),'recommendedPartners':('Server-recommended partners','服务端推荐商家'),
'activeEntitlements':('Active entitlements','生效权益'),'noEntitlements':('No active entitlements','暂无生效权益'),'permanent':('Permanent','永久'),'usage':('Used / maximum','已使用 / 上限'),
'capabilities':('Capabilities and quotas','能力与额度'),'iOSCheckoutUnavailable':('Digital-entitlement checkout is unavailable on iOS. No Apple purchase integration has been supplied.','iOS 暂不支持数字权益自助购买，尚未提供 Apple 内购接口'),
'premium':('Premium templates','高级模板权益'),'cityNode':('City nodes','城市点位'),'promotion':('Promotion slots','推广位权益'),'brand':('Brand homepage','品牌主页权益'),'customEvent':('Custom events','活动定制权益'),
'used':('Used','已用'),'limit':('Limit','上限'),'remaining':('Remaining','剩余'),
'couponWarning':('Settlement is one-time and cannot be undone. The server may issue coupons to winners according to the merchant rules.','结算只能进行一次且不可撤销，服务端可能按商家规则向猜中者发券'),
'deadlinePolicy':('The source allows 48 hours to answer. The platform voids overdue rounds; no one receives a reward. Follow the server deadline.','源规则要求 48 小时内给出答案，超时由平台作废且无人获奖，请以服务端期限为准'),
'emptyPredictions':('No predictions awaiting settlement','暂无待结算竞猜'),'unnamed':('Unnamed location','未命名点位'),'today':('Answer today or the round is void','今天不给答案就作废'),'daysLeft':('Days remaining','剩余天数'),'bets':('Participants in this round','本轮参与人数'),'noBets':('No one has entered this round yet','这一轮还没有人押'),
'reviewHint':('Review this answer before one-time settlement','先确认答案再进行一次性结算'),'review':('Review settlement','确认结算'),'answer':('Selected answer','所选答案'),
'acknowledgeEffects':('I understand this is final and may issue coupons','我理解此操作不可撤销且可能发券'),'confirmSettlement':('Confirm settlement','确认结算'),'cancel':('Cancel','取消'),
'synthetic':('Synthetic test data only','仅为合成测试数据'),'fixtureSignOut':('Sign out of example','退出示例账号')
}
fragment={'merchantMarketing.'+key:{'extractionState':'manual','localizations':{lang:{'stringUnit':{'state':'translated','value':text}} for lang,text in zip(('en','zh-Hans'),pair)}} for key,pair in values.items()}
(root/'Resources/MerchantMarketingLocalizations.fragment.json').write_text(json.dumps(fragment,ensure_ascii=False,indent=2)+'\n')
print(len(fragment),'bilingual keys')
