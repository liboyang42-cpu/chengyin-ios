#!/usr/bin/env python3
"""Write the separate MerchantAICommerce bilingual table used only by its offline fixture."""
import json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
P = 'merchantAICommerce.'
ROWS = {
 'title': ('AI & commerce readiness', 'AI 与商户交易准备'),
 'section.gates': ('Capability switches', '能力开关'),
 'section.authoring': ('AI draft publish check', 'AI 草稿发布检查'),
 'section.branch': ('Time, weather and place branch', '时间、天气与地点分支'),
 'section.order': ('Order by line', '按订单行查看'),
 'section.reward': ('Merchant-sponsored reward', '商户赞助奖励'),
 'gate.sceneAI': ('Scene AI and NPC generation', '分场景 AI 与 NPC 生成'),
 'gate.authoring': ('Publish approved AI drafts', '发布已审核 AI 草稿'),
 'gate.orders': ('Order line readback', '订单行回读'),
 'gate.staff': ('Store staff scope readback', '门店员工权限回读'),
 'gate.ledger': ('Reward ledger readback', '奖励账本回读'),
 'gate.rewards': ('Non-cash sponsored rewards', '非现金赞助奖励'),
 'gate.payment': ('Payment, cash and payouts', '支付、现金与付款'),
 'state.on': ('On', '已开启'),
 'state.off': ('Off', '未开启'),
 'blocker.notApproved': ('This revision has not been approved.', '该版本尚未审核通过。'),
 'blocker.missingMerchantFacts': ('The store owner has not confirmed the store facts.', '门店负责人尚未确认本店信息。'),
 'blocker.missingThemeApproval': ('The theme owner has not approved the story, characters or rewards.', '主题负责人尚未批准剧情、角色或奖励。'),
 'blocker.wrongAuthority': ('An approval came from a role that cannot approve this part.', '有审核来自无权批准该部分的角色。'),
 'blocker.selfApproval': ('The author cannot approve their own draft.', '作者不能审核自己的草稿。'),
 'blocker.editedAfterReview': ('The draft changed after review. Submit it for review again.', '草稿在审核后有改动，请重新提交审核。'),
 'blocker.capabilityDisabled': ('Publishing AI drafts is not enabled. Nothing will be published.', '尚未启用 AI 草稿发布，不会发布任何内容。'),
 'branch.selected': ('An approved branch matches current conditions.', '已选中符合当前条件的已审核分支。'),
 'branch.fallback': ('Conditions are unknown or unmet, so the reviewed fallback branch is used.', '条件未知或不满足，改用已审核的固定替代分支。'),
 'branch.paused': ('Paused for safety. You can leave safely; no new challenge is created.', '因安全原因暂停，可安全退出，不会临时生成新挑战。'),
 'branch.none': ('No approved branch is available right now.', '当前没有可用的已审核分支。'),
 'order.awaiting': ('Paid on the server; waiting for store fulfilment.', '服务端已确认支付，等待门店履约。'),
 'order.partial': ('Part of this order has been fulfilled.', '订单已部分履约。'),
 'order.fulfilled': ('Every line has been fulfilled.', '所有订单行均已履约。'),
 'order.refund': ('A refund is being processed. Check the latest result before acting.', '退款处理中，请先查看最新结果再操作。'),
 'order.checkServer': ('Check the latest order status from the server.', '请以服务端最新订单状态为准。'),
 'order.entitlementSeparate': ('Theme access from this purchase is shown separately and does not mean pickup or arrival.', '购买附带的主题权益单独显示，不代表已取货或已到店。'),
 'reward.limited': ('Limited quantity, while supplies last.', '限量，领完为止。'),
 'reward.guaranteed': ('A reward is reserved for this qualification.', '已为该资格预留奖励。'),
 'reward.notEnabled': ('Sponsored rewards are not enabled. Nothing can be claimed here.', '尚未启用赞助奖励，此处不能领取。'),
 'notice.offline': ('Offline synthetic example. Nothing is sent, saved, paid or published.', '离线示例数据。不会发送、保存、支付或发布任何内容。'),
}
strings = {P + k: {'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': en}}, 'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}} for k, (en, zh) in sorted(ROWS.items())}
out = ROOT / 'Resources/MerchantAICommerce.xcstrings'
out.write_text(json.dumps({'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
used = set(re.findall(r'Text\("(merchantAICommerce\.[A-Za-z0-9.]+)", tableName: "MerchantAICommerce"\)', (ROOT / 'App/MerchantAICommerceFixtureHost.swift').read_text()))
assert used == set(strings), (used ^ set(strings))
print(len(strings), 'keys')
