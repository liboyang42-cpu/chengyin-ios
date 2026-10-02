#!/usr/bin/env python3
"""Build this module's bilingual fragment; merge only during parent integration."""
import json,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
strings={}
def add(key,en,zh):
    strings['club.gov.'+key]={'extractionState':'manual','localizations':{lang:{'stringUnit':{'state':'translated','value':value}} for lang,value in [('en',en),('zh-Hans',zh)]}}
for row in '''workspace|Club workspace|俱乐部工作台
access|Club workspace|俱乐部工作台
hostStatus|Become a host|申请成为主理人
members|Member governance|成员治理
stats|Performance dashboard|数据看板
customerCount|Customer count|客户人数
customers|Customers|客户名单
customer|Customer detail|客户详情
checkin|Check-in record|核销记录
settlement|Settlement summary|分润汇总
eventTopics|Plan a series|创建系列场次
series|Event series|系列场次
seriesDetail|Series detail|系列详情
occurrences|Occurrences|场次清单
occurrenceStatus|Cancellation status|取消状态
roster|Attendance roster|考勤名册
bans|Governance records|治理记录
cases|My platform cases|我的平台工单
roles|Roles and permissions|角色与权限
audienceCounts|Member notifications|成员通知
notificationPreview|Audience preview|受众预览
notificationStatus|Delivery status|通知送达状态
topics|Club topics|俱乐部主题
topicOverview|Club topic workspace|俱乐部主题工作台
topicSettings|Topic settings|主题设置
topicCustomers|Topic customers|主题客户
topicStats|Topic operations metrics|主题运营数据
recruit|Recruitment overview|招商概览
nodeAnswer|Show protected answer|查看受保护答案
editions|Edition reports|期次自报
dissolutionBlockers|Dissolution blockers|解散阻塞事项
leaderboard|Contribution leaderboard|贡献排行
feed|Joined-club feed|已加入俱乐部动态
posts|Club posts|俱乐部动态
registrations|Registration records|报名名册
unavailable|This service has not been configured|此服务尚未配置
signedOut|Sign in to continue|请先登录
denied|Your current permissions do not allow this view|当前权限不允许访问此内容
malformed|The server response is incomplete. Refresh to check again|服务端回执不完整，请刷新重查
changed|The account or target changed. Review the latest information|账号或目标已变化，请重新查看最新信息
busy|An operation is in progress|正在处理操作
unknown|The result is unconfirmed. Do not submit again; check the original record|结果尚未确认，请勿重复提交，请核查原记录
conflict|The record changed elsewhere. Refresh and create a new review|记录已在其他地方变更，请刷新后重新审核
invalid|Check the required fields and selected target|请检查必填项与选定目标
rejected|The server rejected this request|服务端拒绝了此请求
close|Close|关闭
filter|Filter|筛选
keyword|Search customers|搜索客户
search|Search|搜索
sort|Sort by|排序
previous|Previous page|上一页
next|Next page|下一页
refresh|Refresh|刷新
delegatedEvents|Delegated event access|已委派场次
eventID %lld|Event #%lld|场次 #%lld
hostMerchantBlocked|Merchant accounts cannot apply as club hosts|商家账号不能申请成为俱乐部主理人
hostExisting|This account is already a club host|此账号已成为主理人
identityGate|Host submission requires an approved identity-registration flow. Identity documents are not collected here|主理人提交需要已批准的实名登记流程，此处不采集证件号码
financialGate|Financial actions require separate exact-action approval. These records do not prove funds have settled|资金操作需要单独的具体操作授权。这些记录不代表资金已结清
compensationGate|Reported hours and evidence require platform review. No confirmation or reconciliation endpoint is available in the source|自报工时与证据需要平台审核，源代码未提供确认或对账接口
providerGate|Live group-code issuance, refresh, redemption and saving require separate provider acceptance|真实团码签发、刷新、核销与保存需要单独完成服务验收
writeGate|Administrative changes require exact-action approval and current server permissions|管理操作需要具体操作授权及当前服务端权限
registered|Registered|已报名
waitlist|Waitlist|候补
arrived|Arrived|已到场
noShow|Not arrived|未到场
roleDefinitions|Available roles|可委派角色
assignments|Active assignments|生效委派
story|Story and gameplay|剧情与玩法
chapters|Chapters|章节
events|Event operations|场次运营
storyProjection|This is the public chapter and gameplay projection. Answers use a separate permission-checked request|此处展示公开章节与玩法，答案通过独立权限校验接口获取
deposits|Unresolved deposits|未结保证金
settlements|Unresolved settlements|未结结算
noJoinedClubs|Join a club to see its updates|加入俱乐部后可查看动态
empty|No records in this view|此视图暂无记录
deliveryPending|A campaign receipt does not mean every message was delivered|任务回执不代表每条通知均已送达
yes|Yes|是
no|No|否
unknownValue|Not provided or not visible|未提供或无查看权限
localDraft|Local draft and immutable review|本地草稿与固定审核内容
target|Target|操作目标
review|Review exact changes|审核具体修改
confirmOffline|Confirm synthetic operation|确认模拟操作
confirmProduction|Confirm action|确认操作
cancelReview|Return to editing|返回编辑
acknowledged|Request acknowledged|请求已受理
acknowledgedBody|The receipt below is the server acknowledgment. Delivery, refunds and settlement are separate results|以下是服务端受理回执，送达、退款及结算是独立结果
discardTitle|Close this draft?|关闭此草稿？
discard|Close draft|关闭草稿
keepEditing|Keep editing|继续编辑
discardBody|Unsaved local changes will be discarded|尚未保存的本地修改将被丢弃
synthetic|Synthetic fixtures only. No real club actions|仅模拟数据，不操作真实俱乐部
switchAccount|Switch synthetic account|切换模拟账号
simulateUnknown|Simulate an unconfirmed outcome|模拟结果未确认
expiredCode|This code has expired. Do not reuse it|此团码已过期，请勿复用
codeAvailable|Group code issued|团码已签发'''.splitlines():
    add(*row.split('|'))
actions='''hostApply|Apply as host|申请成为主理人
saveCustomer|Edit tags and remark|编辑标签与备注
createSeries|Create event series|创建系列场次
updateSeries|Update future occurrences|修改未来场次
cancelOccurrence|Cancel this occurrence|取消本场
correctAttendance|Correct attendance|更正考勤
ban|Ban member|封禁成员
unban|Remove club ban|解除俱乐部封禁
transferOwner|Transfer ownership|移交主理人
report|Submit a platform report|提交平台举报
appeal|Appeal a platform case|提交封禁申诉
assignRole|Assign scoped role|委派范围角色
revokeRole|Revoke assignment|撤销委派
sendNotification|Compose member notification|编写成员通知
retryNotification|Retry failed recipients|重试失败收件人
saveTopicSettings|Edit topic settings|修改主题设置
endTopic|End topic and review refunds|结束主题并审核退款
chapterRecruit|Change chapter recruitment|修改章节招商
chapterFinish|Finish chapter|结束章节
reportHours|Report actual hours|自报实际工时
submitEvidence|Submit evidence hash|提交证据哈希
issueGroupCode|Issue group code|签发团核销码
dissolve|Review club dissolution|审核俱乐部解散'''
for row in actions.splitlines():
    key,en,zh=row.split('|');add('action.'+key,en,zh)
fields='''channel|Delivery channel|发送渠道
id|Record ID|记录编号
clubId|Club ID|俱乐部编号
topicId|Topic ID|主题编号
activityId|Event ID|场次编号
seriesId|Series ID|系列编号
memberId|Member ID|成员编号
registrationId|Registration ID|报名编号
campaignId|Campaign ID|通知任务编号
chapterId|Chapter ID|章节编号
nodeId|Station ID|站点编号
name|Name|名称
title|Title|标题
topicName|Topic|主题
displayName|Customer|客户
nickname|Member|成员
memberName|Member|成员
content|Content|内容
remark|Remark|备注
tags|Tags, separated by commas|标签，以逗号分隔
status|Status|状态
statusCode|Status code|状态代码
statusText|Status|状态
state|State|状态
occurrenceAt|Occurrence time|场次时间
startDate|Start date, YYYY-MM-DD|开始日期，YYYY-MM-DD
endDate|End date|结束日期
startTime|Meeting time, HH:mm|集合时间，HH:mm
signupCount|Registrations|报名人数
refundedCount|Refunded records|已退款记录
lockReason|Lock reason|锁定原因
recurrenceType|Recurrence|重复规则
defaultLeadMemberId|Lead member ID|默认领队成员编号
defaultCapacity|Capacity|人数上限
capacity|Capacity, blank if unlimited|人数上限，不限可留空
offerMinutes|Waitlist offer minutes|候补名额有效分钟
waitlistEnabled|Waitlist enabled|开启候补
occurrenceCount|Number of occurrences|场次数量
customDates|Custom dates, comma separated|自定义日期，以逗号分隔
version|Current version|当前版本
expectedVersion|Reviewed version|审核版本
banReason|Ban reason|封禁理由
sourceType|Governance source|治理来源
expiresAt|Expiration supplied to server|提交给服务端的到期时间
reason|Reason|理由
decisionReason|Platform decision reason|平台处理说明
roleCode|Role code|角色代码
roleName|Role|角色
scopeType|Scope type|范围类型
scopeId|Scope ID|范围编号
total|Total|总数
monthNew|New this month|本月新增
verifiedCount|Verified records|已核销记录
pendingCount|Pending records|待处理记录
arrivedCount|Arrivals|到场次数
paidAmount|Amount as supplied by server|服务端提供的金额
score|Source-computed score|服务端综合分
clearCount|Completions|通关次数
mileage|Distance (km)|里程（公里）
durationMin|Duration (minutes)|用时（分钟）
hostedCount|Hosted events|带队次数
pace|Pace (minutes/km)|配速（分钟/公里）
completionDuration|Completion time (minutes)|完成用时（分钟）
settledAmountText|Settled amount|已入账金额
settledAmountStatus|Amount verification|金额核验状态
unverifiedSettledCount|Unverified settled records|待核验已结算笔数
amountText|Amount|金额
amountStatus|Amount verification|金额核验状态
originalAmountText|Original amount|原始应结金额
executedAdjustmentText|Executed adjustment|已执行调整
netAmountText|Net amount|核算净额
arrivedText|Arrivals|到场情况
paidText|Payments|支付情况
depositStatus|Deposit status|保证金状态
amount|Source amount; currency not supplied|源金额，未提供币种
direction|Direction|收付方向
retryable|Server permits retry|服务端允许重试
orderNo|Order number|订单号
ticketText|Ticket|票种
orderTimeText|Order time|下单时间
paidAmountText|Paid amount|支付金额
verifyTimeText|Verification time|核销时间
storeName|Store|门店
operatorName|Operator|操作员
railStep|Progress step|进度步骤
phoneText|Server-visible contact|服务端允许显示的联系方式
coopOpen|Merchant cooperation open|开放商家合作
pinned|Pinned|置顶
memberOnly|Members only|仅成员
canManage|May manage|可管理
nodeCount|Stations|站点数
sessionHeadcount|Event headcount|本场人数
pendingVerifyCount|Pending check-in|待核销
verifiedByMeCount|Checked in by me|我已核销
totalCount|Recipients|收件人数
successCount|Succeeded|成功数
failedCount|Failed|失败数
recipientCount|Preview recipients|预览受众人数
inApp|In-app channel|站内渠道
wechatSubscription|WeChat subscription channel|微信订阅渠道
question|Question|题目
answerReveal|Protected answer|受保护答案
feedbackText|Feedback|反馈
leaderName|Host name|主理人姓名
phone|Contact phone|联系电话
identity|Occupation or identity|职业或身份
coFounders|Co-founders|共同发起人
experience|Organizing experience|组织经验
hasExperience|Has experience|已有经验
maxEventSize|Largest event size|最大活动人数
avgEventSize|Average event size|平均活动人数
certImages|Existing certificate image references|已有资质图片引用
canDesignRoute|Can design routes|可设计路线
canDesignTask|Can design tasks|可设计任务
canNpc|Can perform as NPC|可扮演NPC
canMerchantCoop|Can coordinate merchants|可对接商家
hasGuideCert|Has guide qualification|有导游资质
registered|Identity registered|已登记实名
accountRole|Account role|账号身份
targetMemberId|Target member ID|目标成员编号
banId|Ban record ID|封禁记录编号
assignmentId|Assignment ID|委派编号
targetType|Report target type|举报目标类型
targetId|Report target ID|举报目标编号
requestId|Stable request reference|固定请求标识
audienceType|Audience|通知受众
arrived|Arrived|已到场
enabled|Enabled|开启
hourKind|Hours category|工时类别
actualHours|Actual hours|实际工时
dimension|Quality dimension|质量维度
evidenceHash|64-character SHA-256 evidence hash|64位SHA-256证据哈希
dissolveConfirmed|I reviewed dissolution|我已审核解散操作
memberConsequencesConfirmed|I reviewed member consequences|我已审核成员影响
auditStatus|Review status|审核状态
rejectReason|Rejection reason|未通过原因
playModeText|Gameplay mode|玩法模式
storyReady|Story ready|剧情已写
gameConfiguredCount|Configured games|已配置玩法数
category|Category|类别
recruiting|Recruiting|正在招商
merchantCount|Merchants|商家数
finishTime|Finished at|结束时间
timeText|Session time|场次时间
mode|Mode|模式
totalInventory|Inventory|库存
signupDeadline|Registration deadline|报名截止
teamStatus|Group status|成团状态
description|Description|说明
totalTime|Estimated minutes|预计分钟数
validationMethodStr|Validation method|验证方式
players|Players|玩家数
duration|Duration|时长
difficulty|Difficulty|难度
refundStatus|Refund progress|退款进度
refundedOrders|Refunded orders|已退款订单
manualOrders|Orders needing manual handling|需人工处理订单
merchantName|Merchant|商家
soldCount|Sold tickets|已售票数'''
for row in fields.splitlines():
    key,en,zh=row.split('|');add('field.'+key,en,zh)
choices='''ALL_MEMBERS|All members|全部成员
ADMINS|Administrators|管理员
REGISTERED|Registered attendees|本场已报名
WAITLIST|Waitlist|候补成员
NO_SHOW|Not arrived|未到场
INACTIVE|Inactive members|不活跃成员
CLUB_OWNER|Club owner|主理人
CLUB_CO_OWNER|Co-owner|联席主理人
CLUB_OPERATOR|Club operator|俱乐部运营员
EVENT_LEAD|Event lead|场次领队
EVENT_CHECKIN|Event check-in staff|场次核销员
CLUB_MEMBER|Club member|俱乐部成员
ONCE|Once|单次
WEEKLY|Weekly|每周
CUSTOM_DATES|Custom dates|自定义日期
CLUB|Club|俱乐部
ACTIVITY|Event|场次
MEMBER|Member|成员
PREP|Preparation|准备
CONTENT|Content|内容
ONSITE|On-site|现场
REVIEW|Review|复盘
DELIVERY_SAFETY|Delivery and safety|交付与安全
PLAYER_EXPERIENCE|Player experience|玩家体验
CONTENT_REPORT|Content and report|内容与回顾报告
没有经验|No experience|没有经验
1-5场|1–5 events|1-5场
5-20场|5–20 events|5-20场
20场以上|More than 20 events|20场以上'''
for row in choices.splitlines():
    key,en,zh=row.split('|');add('choice.'+key,en,zh)
    if key in ['ALL_MEMBERS','ADMINS','REGISTERED','WAITLIST','NO_SHOW','INACTIVE']:add('field.'+key,en,zh)
    if key.startswith('CLUB_') or key.startswith('EVENT_'):add('role.'+key,en,zh)
for key,en,zh in [('all','All','全部'),('repeat','Repeat customers','回头客'),('new','New customers','新客户'),('remark','With remarks','有备注')]:add('filter.'+key,en,zh)
for key,en,zh in [('composite','Composite','综合'),('mileage','Distance','里程'),('pace','Pace','配速'),('duration','Duration','用时')]:add('sort.'+key,en,zh)
path=ROOT/'Resources/ClubGovernanceLocalizations.fragment.json';path.write_text(json.dumps({'sourceLanguage':'en','strings':strings,'version':'1.0'},ensure_ascii=False,indent=2)+'\n')
print(len(strings),'bilingual keys')
