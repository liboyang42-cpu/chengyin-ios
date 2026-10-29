# 账号、消息、社交、组队只读审查

审查基线：`liboyang42-cpu/chengyin-ios`，固定提交 `76ce1b313af2595f9b7d7ace49040866209c7974`。全部路径/行号均指此提交。通过 GitHub connector 读取源文件与测试；未执行 Swift/XCUITest、未访问真实后端、未登录账号、未写业务数据。该提交递归文件树未出现 AGENTS.md，根文件读取返回404。

## 最重要的事实

1. **正常 App 当前仍是未配置后端的组合。** `App/RegionalLaunchConfiguration.swift:7-10` 实际调用 `makeComposition(reviewed: nil, build: .current)`；45-46返回`.unconfigured`。`Config/Base.xcconfig:21`、`Config/China.xcconfig:6`的API地址为空。只向启动参数塞URL/token不能构成合法上线配置，也不得绕过现有scope和approval边界。
2. **消息发送/历史读取的适配器存在，但双端实时接收链路未实现于当前消息调用链。** `Core/MessagingService.swift:20-21`声明只提供两类读取，无socket/timer；`App/MessagingHistoryView.swift:109-110`仅在本机发送后reload，149-160为刷新按钮、refreshable和首次加载；未见接收方实时订阅/前台补偿接线。B保持聊天页且不刷新这一验收目前应标为BLOCKED_PRODUCT，而不是改测试自动刷新冒充通过。
3. **消息读取许可和发送许可分开。** `App/AppSession.swift:3034-3042`只有独立`.imSend`业务配置才给composer；3054-3071只有精确的`MessagingHistoryReadApproval`才返回可用reader。`App/AppCompositionRoot.swift:164`默认该批准为nil，202默认session dependencies为`.dormant`。
4. **已读接口不等于对端已读回执。** `Core/IMExpandedService.swift:25-26,41`有`api/im/read`及通用`.read`回执；`Core/MessagingContracts.swift:25-35`有会话未读计数。`MessagingMessage`75-114没有delivered/read/readAt字段，状态normal/recalled/blocked并非送达/已读状态。不能根据HTTP 200宣称对端已读。
5. **组队写适配器存在，但正常组合仍挂只读。** `App/AppSession.swift:2241-2243,2287-2320`构造`TeamReadOnlyService`；`TeamReadOnlyService.submit`（`Core/TeamService.swift:84`）恒返回`.notSent`。`Core/TeamHTTPService.swift`有create/join/quit/kick/disband/join-mode适配器，但不是正常工厂的写服务。附近队伍apply/withdraw/handle另有适配器，默认writeApproval和freshEvidence缺失，所以不启用。
6. **现有测试有相当多的边界保护，但多数是注入transport或synthetic UI。** 例如`Tests/AppUITests/IMExpandedUITests.swift:3-4`明确synthetic-only，`Tests/AppUITests/TeamFlowTests.swift:3`明确offline fixtures。本次仅核实源码存在，未将它们计作执行通过或真实E2E通过。

## 业务与覆盖台账

|模块|代码状态|可定位实现|现有测试与缺口|
|---|---|---|---|
|CN手机号登录/短信|部分实现|`Core/AuthChannelService.swift:70-74`；`Core/AuthChannelCoordinator.swift:132,153,198-214`，登录后userInfo同账号核实才提交token|`AuthChannelCoordinatorTests.testPhoneReadbackAndAtomicHostCommit`等；真实短信provider/deployment与账号池未验证|
|密码/US Apple/Email/Google登录|未形成正常可用登录|`Core/RegionalConfiguration.swift:87-98`只将CN国内手机号列为implementedCapabilities；US集合为空；`App/AppSession.swift:1052-1056`WeChat配置nil且gate默认关闭|可保留禁用/错误分支测试；不能拿保留AuthService.login方法当作密码登录已可用|
|Token保存、冷启动恢复、退出|已实现客户端规则，后端闭环部分|`App/KeychainTokenStore.swift:10-15,29-38`按deployment scope且ThisDeviceOnly；`App/AppSession.swift:3389-3422`恢复userInfo，401清除、网络失败保留；3462-3480先写退出tombstone再清token|`CNAccountSessionServiceTests`/`AuthChannelCoordinatorTests`；没有真实过期、撤销、双端登录策略证据；不虚构客户端refresh-token接口|
|身份隔离、迟到响应、角色切换|已实现多处保护|`AppSession`gate/epoch、compositionViewerRevision、读取lease；`MessageSessionWriter.send`71-83核实snapshot与senderID|`MessagingSessionTests`、`MessagingHistoryCompositionTests`、`TeamReadCompositionTests`；运行结果本次未验证|
|资料、公开用户、关注/取消关注|部分实现|`Core/SocialAccountService.swift:11`；`Core/SocialActionContracts.swift:140-148`显式follow=0/1与start chat；`SocialMemberActionFactory.swift:185-188`要求回执和fresh public-info一致|`SocialMemberActionFactoryTests`和App tests；默认approval空，真实写未核实；未找到独立“好友双向申请/接受”合同，不将follow视为好友|
|消息会话、历史、分页|部分实现|`MessagingService`conversations/messages；`MessagingHistory`按服务端顺序、opaque cursor、message ID去重|`MessagingHistoryTests`7类、`MessagingServiceTests`形状/鉴权/closed验证；默认reader关闭|
|文本发送/未知结果|部分实现|`MessageActionService:23-39` POST `api/im/send`，client_message_id保持不变；`MessageActionCoordinator:29-59`单次dispatch、unknown阻挡新意图、显式retry复用ID|`MessageActionTests.testDuplicateTapWhileSuspendedSendsOnce`、`testUnknownOutcomeBlocksReplacementAndExplicitRetryKeepsIntent`；9-10明确无持久化保证，进程杀死后的未知发送恢复未闭环|
|实时消息、断线补偿、远端已读|未实现于被审查消息链路 / 服务端能力无法核实|历史View无接收订阅；模型没有对端已读字段；未找到当前消息入口的socket/reconnect接线|阶段2硬阻断；要求真实服务端transport合同和消息游标/补偿语义后实施，不能让test runner定时刷新替代App能力|
|私聊、商家会话、群聊|部分实现|`MessagingConversationKind`direct/system/merchant/group；IM start、clubChat、poll接口存在|不是“群管理/群实时同步完整”；需各会话类型真实成员scope与闭群验证|
|标记已读、静音、全部已读|部分实现|`IMExpandedService` read/mute；`IMConversationReadAll`串行逐会话记ack/unknown/rejected|`IMConversationReadAllTests`、`IMConversationRowActionsTests`；应核实服务器unread回读，不能只看本地count变零|
|组队列表/详情/邀请链接/状态|部分实现|`Core/TeamContracts.swift:36-42,56-88`；`TeamReadOnlyService`my/info；`SessionTeamViews.swift`真实导航|`TeamReadCompositionTests`/`TeamFlowTests`；仅用户所属队伍和有权限邀请上下文，不能把nearby行解成owned团队|
|创建/加入/退出/踢人/解散|部分实现（normal写未挂载）|`TeamWriteContract:148-162`具体接口，`TeamHTTPService:36-66`持久journal后dispatch与fresh preflight；`receipt`直接nil|`TeamCoordinatorTests`广泛状态保护；真实写、operation receipt和同步未闭环|
|附近队伍申请/撤回/审批|部分实现（默认禁用）|`NearbyTeamContracts.swift:120-146`；`NearbyTeamHTTPWriteAdapter.swift:103-150`；`AppSession:2264-2284`默认不提供writeApproval/evidence|`NearbyTeamHTTPWriteTests`、`NearbyTeamWithdrawalRaceTests`；应测试申请撤回与队长处理竞争|
|多人任务与队伍实时状态|无法核实为完整闭环|已有team/readback/game状态相关模块，但上述入队写和实时订阅未就绪|与玩法域联合验收，不能由存在TeamView判通过|

## 已有可复用测试的准确入口

- `Tests/CoreTests/AuthChannelCoordinatorTests.swift`: `testPhoneReadbackAndAtomicHostCommit`(64)、`testDuplicateLoginAndSMSDuringLoginAreIgnored`(78)、`testCancellationThenReentryRejectsOldResponse`(91)、`testMismatchedCurrentAccountCannotCommit`(122)、`testStorageAndCommitRejectionDoNotReportSignedIn`(142)、`testSMSUncertainResponseDoesNotAutoRetryOrClaimSent`(177)。
- `Tests/CoreTests/CNAccountSessionServiceTests.swift`: `testPhoneOnlyConfigurationRestoresWithoutPasswordCapabilityOrLoginRequest`(49)、`testUSCannotUseLegacyCNRestorationEvenWithEveryVerificationFlag`(99)、`testDifferentEndpointOrMarketCannotReuseVaultScope`(109)、`testUnauthorizedIsDistinctFromOfflineAndServerFailure`(143)、`testMissingOrUnknownRoleCannotRestoreFromLegacyCachedProjection`(227)。
- `Tests/CoreTests/MessagingServiceTests.swift`: `testHistoryUsesExactMultipartFieldNamesAndNeverMarksRead`(27)、`testHistoryRejectsWrongConversationAndMissingPagingContract`(74)、`testClosedUsesExactErrorCodeNotMessageTextOrHTTPAlone`(81)。
- `Tests/CoreTests/MessagingHistoryTests.swift`: `testPagesKeepSourceOrderAndOpaqueCursorInsteadOfSortingOrGuessing`(11)、`testDuplicateIDsAreUniqueAndIncomingCopyWinsOnOverlap`(23)、`testWrongConversationPageCannotOverwriteExistingHistory`(32)、`testCursorCycleRejectsWithoutLosingValidIntermediatePage`(53)。
- `Tests/CoreTests/MessageActionTests.swift`: exact wire/no implicit read receipt(34)、timeout no retry(47)、duplicate tap(90)、unknown intent reuse(99)、account change hides pending(116)。
- `Tests/AppUnitTests/MessagingHistoryCompositionTests.swift`: `testNormalFactoryHistoryKeepsSenderPrivacyAndBlockedHistoryWithoutWrites`(25)、`testCachedLegacySenderIsWithheldWhenIndependentCapabilityIsRemoved`(39)、`testLoadedReaderInvalidatesOnRevocationExpiryRoleABAAndReissue`(64)、`testCurrent401ExpiresButMembership403AndClosedHistoryDoNotExpireAccount`(109)。
- `Tests/CoreTests/TeamCoordinatorTests.swift`: duplicate confirm(251)、role during preflight(266)、journal failure prevents submission(290)、unknown survives reauth(300)、account/region scoped unknown(307)、wrong receipt cannot unlock(327)、departure late detail cannot resurrect membership(501)。
- `Tests/AppUnitTests/TeamReadCompositionTests.swift`: `testNormalSessionFactoryReadsFreshMemberAndInvitationWithoutWriter`(20)、`testExactShapesClonesCrossScopeAndAllAdjacentMutations`(77)、`testReadRefreshAndLogoutPreserveUnknownJournalInIsolatedStore`(117)。
- `Tests/AppUITests/TeamFlowTests.swift`: invitation join review/simulation(95)、unknown cannot replay after same-account reauth(119)、Chinese accessibility/dark mode(200)。这些是fixture，须独立标记。

## 建议首批场景（全部为计划，未运行）

公共规则：E2E只用已核准staging、租借账号、run-scoped数据；设备D1/D2/D3为独立Simulator UDID。清理C1=服务端按runID删除/过期已登记测试实体并释放账号；若无合法清理能力则隔离并隔离标记账号，不直接删库。C2=仅清任务拥有的App sandbox/Keychain namespace，归还设备前验证guest。失败证据E=脱敏UI tree/截图、请求ID、状态断言、日志、build SHA、设备UDID、服务端只读结果；每条都保留E，不记录token/SMS。

|测试ID|模块/优先级|前置/角色/设备|动作|预期与可观察断言|清理|证据/自动化|
|---|---|---|---|---|---|---|
|AUTH-001|登录 P0|核准CN测试身份渠道；玩家A；D1|获取测试登录挑战并通过正常登录页提交；userInfo回读；重启|token不出日志；UI账号ID=userInfo ID；冷启动不重新登录且同scope；账号不匹配不得保存|C2、释放挑战|E；XCUITest+API只读oracle|
|AUTH-002|退出/恢复 P0|A已登录；D1|退出时令Keychain clear失败（本地组件层）；杀进程重启|tombstone阻止恢复；真实UI退出重启是guest；旧logout响应不影响后续B登录|C2|E；AppUnit+单机UI|
|AUTH-003|跨账号隔离 P0|A/B；D1|挂起A历史读取，退出并登录B，释放A成功/401|B无A正文、未读、头像、队伍；旧401不注销B；请求归属与UI一致|C1+C2|E；组件transport故障+stagingUI|
|AUTH-004|角色/区域隔离 P0|玩家/商家与CN/US配置；D1|角色A→B→A、撤销lease、切realm后尝试旧回调/令牌|旧revision不可采用；未授权区域零请求；无角色提升|C2|E；Core+AppUnit，服务端RBAC另验|
|IM-001|双端文本 P0|真实A/B、正常读写批准、App实时接收能力；D1/D2|双方身份屏障，A唯一文本，后端回读，B不刷新收到，B回复|server message ID、sender、conversation、正文相等；两端各一次；顺序以服务端合同；每一步有期限|C1+C2|E；确定性orchestrator+UI/API；当前BLOCKED_PRODUCT|
|IM-002|未读/已读 P0|A/B会话基线n、B不在会话；D1/D2|A发送k条；读B会话；B显式标read；再次回读|未读按合同n+k→0；mark-read不可误说remote-read；需新合同才能断言A看到已读|C1+C2|E；UI+API oracle；远端回执BLOCKED_CONTRACT|
|IM-003|断网补偿 P0|实时能力与B独立网络故障控制；D1/D2|B网络隔离；A发N条；恢复B，不人工刷新|全部合法message IDs出现且唯一、服务端顺序一致、超时为失败，不用截图猜|C1+C2、撤销故障规则|E+网络故障时间线；当前BLOCKED_PRODUCT|
|IM-004|发送超时幂等 P0|A/B；D1/D2；可丢失发送响应但服务器提交|A发同一client_message_id；丢回执；重试原意图|服务器仅1行且同ID；UI unknown禁止新意图冒充；手动retry不换clientID|C1+C2|E+oracle计数；Core测试先跑，真实server幂等待验证|
|IM-005|进程退出历史 P0|IM-001已有持久化消息；D1/D2|B终止App重启重新进会话|重新从服务端可见同message IDs；不得以本地fixture缓存替代|C1+C2|E；UI+API|
|IM-006|历史分页/撤回隐私 P0|>50条含重叠页、撤回/blocked；D1|加载多页，失败重试，收到跨会话/循环cursor|不串会话不丢旧页；ID唯一；撤回内容不在UI、AX树和搜索；opaque cursor不自算|C1+C2|E；Core+UI；服务端fixture需合法初始化|
|SOC-001|关注闭环 P1|A/B未关注；D1/D2|A关注、取消；读双方profile相关事实|follow显式值对应服务端；未知结果不自动翻转重放；不宣称双向好友|C1恢复原关系+C2|E；UI/API+现有factory单测|
|TEAM-001|邀请加入/退出 P1|可创建批准且真实报名已支付测试资格；A队长B成员；D1/D2|A建队，B读邀请并加入，双方回读，B退出|同teamID、人数集合一致、只有合法状态允许操作；退出后私有名单清除|C1+C2|E；双端UI/API；normal writer当前BLOCKED_PRODUCT|
|TEAM-002|申请/拒绝/接受 P1|公开队伍A、B/C；D1/D2/D3或分两轮|B/C申请，A分别拒绝/接受|申请状态、成员列表、票资格回读匹配；拒绝者不成为成员；过期请求不能接受|C1+C2|E；三角色；需要写许可和fresh evidence|
|TEAM-003|名额竞争 P1|剩余1席，B/C均有票；D2/D3同步屏障|同时加入/审批，收集双方结果|只1个新增成员且不超max；失败者UI与服务器一致；不得根据响应先后自定赢家|C1+C2|E+服务端提交事实；并发API+UI|
|TEAM-004|队长/非成员权限 P0|A队长、B普通、C外部；D1/D2/D3|B/C直接调用kick/disband/改模式，A合法执行|B/C拒绝且队伍无变化；A结果回读后才展示完成；UI禁用不是权限证明|C1+C2|E；API negative+UI|
|TEAM-005|unknown与解散恢复 P0|A/B在队；D1/D2|解散后丢响应、重启、读名单；重放旧review|未知锁保留，不再重复写；匹配回执/权威事实恢复；晚到详情不能恢复旧名单|C1+C2|E；组件+双端UI；服务端operation receipt目前缺合同|

## 双端阶段的最小产品接线任务边界

- AUTH-GATE：先在独立测试build中落实合法`ReviewedAppDeployment`和精确读写grant、登录渠道和测试身份租约；绝不可删guard或把测试token写入源代码。正常构造应继续走现有`AppCompositionRoot`，不是另做假的测试App。
- IM-TRANSPORT：先取得真实后端事件协议（WS/SSE/轮询是否存在、认证、游标、重连），再为消息入口实现唯一接收路径。若产品决定轮询，这必须是App本身经过批准的能力，测试报告如实称“自动同步”，不能宣称WebSocket实时。
- IM-RECOVERY：在界面订阅/恢复与服务器history之间做确定性去重；保留message ID、server order与opaque cursor合同；传输ack、持久化、对端可见、对端已读四类事实分开。
- IM-ORACLE：最小测试侧只读oracle返回run/account/conversation绑定的message IDs与unread；不能直接开放生产DB，也不需要把所有业务内部状态暴露给AI。
- TEAM-WRITE：阶段2消息闭环后，才审查正常factory写服务挂载和create资格源；现有TeamHTTPService无远端operation receipt，超时不得自动解锁。队伍实时同步应复用已选事件通道，不能每个业务新建一个框架。

## 文档/产品叙述与实现差异

- 用户起点中的“双端实时消息、远端已读、完整多人邀请与即时成员变化”是目标，当前源代码不是已经具备的闭环。计划必须把产品接线缺口列为前置工作。
- “好友”目前已证实的是follow和startChat；不把关注关系擅自改名为双向好友。
- 账号与消息/组队测试丰富，但均不能提供真实环境验收证据；已有fixture需要保留用于快速回归，同时新建明确命名的live E2E层。
- 全部结论基于固定提交代码，未宣称未读取的后端部署不存在这些能力。
