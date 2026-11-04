#!/usr/bin/env python3
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PAIRS={
 'title':('Publishing','发布'), 'offlineNotice':('You can fill in and review your content. Publishing isn\'t available right now.','可先填写和检查内容；发布暂不可用。'),
 'quick':('Quick route setup','快速配置'), 'activity':('Publish an activity','发布活动'), 'projects':('My projects','我的项目'), 'identity':('Publisher registration','发布人登记'),
 'aiNotice':('AI only assists with drafts. Confirm every place before opening the professional editor.','AI 只协助起草；进入专业编辑器前须逐个确认地点。'),
 'aiDisabled':('AI generation is not connected. You can create nodes manually.','AI 生成尚未接入，可以手动添加点位。'),
 'details':('Details','基本信息'), 'name':('Name','名称'), 'description':('Description','说明'), 'product':('Route type','路线类型'),
 'choosePlace':('Choose a place','选择地点'), 'remove':('Delete','删除'), 'addNode':('Add a stop','添加点位'),
 'confirmEveryPlace':('Add a title and at least one named stop, then confirm every location.','填写标题和至少一个有名称的点位，并逐个确认地点。'),
 'continueEditor':('Continue in professional editor','进入专业编辑器'), 'clubOnly':('Only club hosts can publish activities. Publishing is subject to quota and content review.','仅俱乐部主理人可发布活动，发布需符合配额与内容安全审核。'),
 'cover':('Existing cover URL','已有封面地址'), 'uploadDisabled':('Media upload isn\'t available right now.','媒体上传暂不可用。'), 'addressName':('Venue name','活动地点'),
 'start':('Start time','开始时间'), 'end':('End time','结束时间'), 'dateFormat':('Use yyyy-MM-dd HH:mm:ss in the event’s local time.','请使用活动当地时间，格式 yyyy-MM-dd HH:mm:ss。'),
 'categories':('Choose categories','选择分类'), 'template':('Choose play template','选择玩法模板'), 'collaborators':('Choose collaborators','选择合作者'),
 'ticket':('Ticket','票种'), 'price':('Price (enter 0 for free)','价格（免费填 0）'), 'stock':('Total stock','总库存'), 'addTicket':('Add a ticket','添加票种'),
 'review':('Review','审核内容'), 'reviewNotice':('Check your request before sending. Receiving it doesn\'t mean your content has passed review or is live.','发送前请核对内容。已收到请求不代表内容已通过审核或已上架。'),
 'confirm':('Confirm request','确认请求'), 'cancel':('Cancel','取消'), 'invalid':('Check the required fields, event times and ticket windows. Publishing also requires a current club-leader role.','请检查必填项、活动时间和票种履约窗口；发布还需要当前主理人身份。'),
 'acknowledged':('Request received. Refresh to see the latest status.','请求已收到，请刷新查看最新状态。'),
 'unknown':('The outcome is uncertain. This operation is locked across restarts to prevent duplicates. Do not resubmit; contact support to establish the result.','结果尚不确定。为防止重复提交，本次操作已跨重启锁定。请勿重发，请联系客服核实结果。'),
 'notSent':('Nothing was sent. Access, configuration or the reviewed data changed.','未发送请求；权限、配置或审核内容发生变化。'), 'rejected':('This request couldn\'t be completed.','请求未能完成。'),
 'readFailed':('Could not load this list. Check your connection and sign-in, then retry.','列表加载失败，请检查网络和登录状态后重试。'), 'retry':('Retry','重试'), 'empty':('No results','暂无结果'),
 'selected':('Selected','已选择'), 'notSelected':('Not selected','未选择'), 'choose':('Choose','选择'), 'done':('Done','完成'),
 'mapUnavailable':('Place search isn\'t available right now. Confirm a place to continue quick setup.','地点搜索暂不可用；需确认地点后才能继续快速配置。'),
 'searchPlace':('Search for a place and select a result.','搜索地点并选择结果。'), 'confirmPlace':('Confirm this place','确认此地点'),
 'type':('Content type','内容类型'), 'state':('Status','状态'), 'owner':('Publisher','发布主体'),
 'truncated':('Only the first page is shown. Narrow the filters to find other projects.','仅显示第一页，请缩小筛选范围以查找其他项目。'),
 'unknownTypes':('Some items aren\'t supported yet, so no actions are available for them.','部分记录的类型暂不支持，无法操作。'),
 'signups':('sign-ups','人报名'), 'takeOffline':('Take offline','下架'), 'putOnline':('Put online','上架'),
 'refundHandoff':('Cancellation with refunds needs the separate financial workflow.','取消并退款需要进入单独的金融操作流程。'),
 'deleteReview':('Delete this project? This action requires the current state and no sign-ups.','是否删除此项目？需符合当前状态且无人报名。'),
 'statusReview':('Change this project’s listing status?','是否更改此项目的上架状态？'), 'conflict':('The project changed or access is unavailable. Refresh before reviewing again.','项目已变化或暂时无权访问，请刷新后重新审核。'),
 'identityUSUnsupported':('Publisher registration isn\'t available in the US right now.','暂不支持美国发布者登记。'),
 'registered':('Registered','已登记'), 'notRegistered':('Not registered or status unavailable','未登记或暂时无法查询状态'),
 'identityChange':('To change registered identity information, contact platform support.','如需变更实名信息，请联系平台客服。'),
 'identityHandoff':('Identity verification isn\'t available on this screen. We never ask for your ID number here.','此页面暂不支持实名认证，不会在此收集身份证号。'),
 'identityPrivacy':('Only registration status is returned. Names and ID numbers are never fetched or stored here.','仅查询登记状态，不读取或保存姓名和身份证号。'),
 'rewards':('Topic rewards and self-play','主题奖励与自玩票'), 'selfPlay':('Offer self-play tickets','开放自玩票'), 'quota':('Self-play quantity (empty means unlimited)','自玩票数量（留空不限）'),
 'medalName':('Completion medal name','完成奖章名称'), 'medalImage':('Existing medal image URL','已有奖章图片地址'), 'coupon':('Reward coupon ID (0 for none)','奖励券 ID（0 表示无）'),
 'couponNotice':('Only select an existing authorized coupon. This form does not publish, claim or redeem coupons.','仅选择已有且有权使用的优惠券；此表单不会发布、领取或核销优惠券。'),
}
for key,en,zh in [('all','All','全部'),('topic','Topics','主题'),('activity','Activities','活动'),('template','Templates','模板'),('draft','Draft','草稿'),('pending','Pending','待审核'),('rejected','Rejected','未通过'),('running','Running','进行中'),('notStarted','Not started','未开始'),('offline','Offline','已下架'),('completed','Completed','已结束'),('member','Personal','个人'),('club','Club','俱乐部'),('merchant','Merchant','商家')]: PAIRS['filter.'+key]=(en,zh)
PAIRS.update({
 'seedPending': ('A quick-route draft is ready. Resolve any saved draft before replacing the current editor contents.', '快速路线草稿已准备好。请先处理已保存草稿，再替换当前编辑内容。'),
 'applySeed': ('Use quick-route draft', '使用快速路线草稿'),
 'saveLocal': ('Save on this device', '保存到本机'),
 'restoreLocal': ('Restore saved draft', '恢复已保存草稿'),
 'savedLocal': ('Saved securely on this device for this account.', '已为当前账号安全保存到本机。'),
 'restoredLocal': ('Saved draft restored. Review it before continuing.', '已恢复草稿，请检查后继续。'),
 'noSavedLocal': ('No saved draft for this account and mode.', '此账号和模式暂无已保存草稿。'),
 'storageFailed': ('Secure storage is unavailable. Your current draft remains on this screen.', '安全存储暂不可用，当前草稿仍保留在此页面。'),
})
strings={'publishModes.'+key:{'localizations':{'en':{'stringUnit':{'state':'translated','value':en}},'zh-Hans':{'stringUnit':{'state':'translated','value':zh}}}} for key,(en,zh) in PAIRS.items()}
target=ROOT/'Resources'/'Localizable.xcstrings'
catalog=json.loads(target.read_text())
catalog['strings'].update(strings)
target.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
print(f'Generated {len(strings)} bilingual keys')
