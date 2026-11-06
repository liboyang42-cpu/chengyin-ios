# H / I / J 只读审查交付
审查身份：liboyang42-cpu/chengyin-ios @ 76ce1b313af2595f9b7d7ace49040866209c7974（migration/native-ios）。
全树通过 GitHub git trees API 读取；该树无 AGENTS.md。以下所有代码/测试证据固定此 SHA。没有编译、运行 XCTest/UI、操作模拟器、调用后端、改源码或支付。源码阅读结论不等同业务验收。

## 关键事实
1. 普通 App 的真实后端装配仍默认关闭：App/RegionalLaunchConfiguration.swift:7–10 调用 makeComposition(reviewed:nil)，:67–70 approvedBaseURLs 为空；App/AppCompositionRoot.swift:147–195 default deployment=.unconfigured、业务读写 approvals 默认 nil。不能以改 URL、fixture 启动参数或一个总开关代替精确测试部署授权。
2. 正常路由已经存在：App/QuestifyApp.swift:223–245 的普通 SessionRootView 有 Club 标签和 Account；App/AccountView.swift:70–80 作者/编辑/模板/创作中心，:121–127 商家总览/项目/工作台；App/SessionPublishingModesView.swift:22–47 将简单发布、专业 ProjectEditView、结果详情串起来。但路由可达 ≠ 服务已装配 ≠ 后端部署已验收。
3. 商家、俱乐部、订单包含真正 HTTP factory，而非只有 mock。NativeRuntimeDependencies.swift:38–42 的 merchantBusinessApproval、clubGovernanceApproval、orderLifecycleConfiguration 等默认 nil。AppSession.swift:2604–2610、2721–2734、2355–2366 分别装配业务 factory/coordinator/durable journal。测试不能绕过这些门禁。
4. 普通简单发布服务目前仅可注入读取：AppSession.swift:1524–1540 的 makePublishingService 不提供写 approval/journal；Core/PublishModesService.swift:98–130 明确需要这两者且响应仅为 acknowledgment。专业主题另有 ProjectEditHTTPService + ApprovedTopicReleasePublicationClient，不能用专业链路已写来声称简单发布可用。
5. 商家售后意见不是退款执行。MerchantBusinessProduction.swift:6–19 action 有 aftercareAgree/Reject/Evidence，但无 refundExecution。MerchantBusinessProductionTests.swift:89 testProductionHTTPOpinionIsNotRefundExecution。订单支付 SDK 返回不是支付完成；OrderLifecycleProductionTests.swift:152 对应 testProviderReturnIsNotPaymentAndUsesServerReadback。
6. 未知写入恢复策略因协议而异，禁止统一“失败自动重试”：MerchantBusinessCoordinator.swift:22–45、124–170 保留精确 intent；ClubGovernanceCoordinator.swift:97–142 保留 durable target lock；OrderLifecycleProduction 保留订单锁；ApprovedTopicReleasePublicationClient.swift:140–145 则存在 status 和 retryExact，必须保留原 request/冻结快照，不能生成新 request 重做。
7. 文档不能直接作当前台账：docs/ios-current-status.md:3 的源码基线仍为 7c21af45（2026-10-15）；当前审查是 76ce1b31。docs/order-lifecycle-production/integration.md 写 22 个测试，当前文件实际 31 个 test 方法。全部计数仅“已编写”，本轮没有运行结果。

## 业务与覆盖台账
“已实现”只用于明确独立代码能力；整块业务通常部分实现。所有真实 E2E 执行状态均“无法核实 / 未运行”。

| 子模块 | 代码状态 | 真实代码与调用证据 | 已有测试与可复用层 | 闭环限制 / 下一步 |
|---|---|---|---|---|
| H1 商家总览/权限/项目读取 | 部分实现 | MerchantService.swift:59–87 access/me/dashboard/todo-summary/events/orders/project/my；AppSession.swift:2441–2461 总览读批准，2556–2577 项目读批准；AccountView:121–127 | MerchantServiceTests、MerchantProjectBrowseCompositionTests、MerchantProjectWorkspaceScopeTests | 需要精确账户/部署读批准；对当前商家权限和分页真实数据做联合断言 |
| H2 店铺资料/装修/图库/营业时间/合作/城市据点 | 部分实现 | MerchantOperationsContracts.swift:32 destination 包含 profile/decor/gallery/story/cooperation/assets/cityNodes/templates；AppSession:2690–2713 reader/onboarding retained coordinator | MerchantOperationsTests、MerchantStoreFieldDraftTests、MerchantStoreHoursTests、MerchantOnboardingCoordinatorTests；对应 AppUnit | 不能把字段编辑器或 contract preview 当保存闭环；MerchantOperationsContracts:160 full payload 注释为无生产 send；需逐操作查当前 adapter/批准 |
| H3 商家 CRM/评价/售后/运营员工 | 部分实现 | MerchantBusinessQuery.swift:72–91 list/detail/aftercare/reviews/finance/operators；MerchantBusinessProduction.swift:6–19、45–61、116–136 精确 action/target/grant；AppSession:2604–2610 正常装配入口 | MerchantBusinessProductionTests 18 方法；AppUITests/MerchantBusinessFlowTests 10 方法 | 当前 UI 测试通过 --uitesting-merchant-business-fixture 启动；不证明真实 CRM 或售后；finance 可补证≠可同意退款 |
| H4 商家核销/账单/结算/收益 | 部分实现 | MerchantBusinessQuery:81–89 finance overview/redemptions/settlement entries/batches；AppSession:2630–2640 nativeVerificationFlow 需要独立 factory | MerchantRedemptionProgressTests、MerchantSettlementProgressTests、MerchantLedgerNetPresentationTests、NativeVerification tests | 模拟扫描分类≠真实核销；结算净额需保留负数/未知；财务测试必须沙箱 |
| H5 俱乐部浏览/成员/加入退出/管理 | 部分实现 | ClubService.swift:13–42 home/my/list/detail/members；ClubActionService:24 join/quit；ClubManagementService:20 join-requests、118 perform；QuestifyApp:239 正常入口 | ClubServiceTests、ClubActionCoordinator/SessionTests、ClubManagementTests；ClubActionFlowTests/ClubManagementFlowTests | 入会申请、批准、退出必须跨角色验证成员列表及权限回收；现有 fixture 不等于线上组员同步 |
| H6 俱乐部排期/名单/出勤/通知/治理/结算 | 部分实现 | ClubGovernanceContracts.swift:95–134 为 34 个读目录；ClubGovernanceProduction.swift:6–45 绑定 operation/scope/risk/target；AppSession:2721–2756 普通入口+durable stores | ClubGovernanceProductionTests 15；AppUITests/ClubGovernanceFlowTests 7；大量排期/出勤/名单 AppUnit | 写 factory 条件可用，部署仍未核实；事件范围不能被 club-wide 权限提升；通知需独立操作与 audience 批准 |
| I1 简单发布/活动发布/项目管理 | 部分实现 | SessionPublishingModesView:22–47；PublishModesContracts.swift:51–99 包含 publish/home、activity/publish、topic/create 以及项目删除/上下架；PublishModesService:98–130 | PublishingModesTests；AppUITests/PublishingModesFlowTests 4 | 普通 makePublishingService 只有 read grant，写未装配；简单草稿应转专业 seed，不能自行假设最终发布成功 |
| I2 专业主题/章节/节点/故事编辑与恢复 | 部分实现 | AppSession:1185–1200 ProjectEditCoordinator；ProjectEditHTTPService:33–44 edit-detail/publish-home，61–115 submit/ack；ProjectEditCoordinator:103–158 load/restore/saveLocal、254–379 confirm/continue/checkOutcome | ProjectEdit*、ProjectStory*、ProjectChapter* 等 Core/AppUnit/UI 套件 | 有账户隔离/本地恢复/未知锁；需真实保存后语义回读章节、节点和 ID 重映射；不等同发布/审核完成 |
| I3 审核/已批准版本发布 | 部分实现 | AppSession:1343–1375 只为 personal owner 装配 approved release；ApprovedTopicReleasePublicationClient:7–8 publish/status；ApprovedTopicReviewFlow:158–170 status/retryExact/observe | ApprovedTopicReleasePublicationFlowTests、JournalTests、ApprovedTopicReviewClient/Request/ObservationTests；多套 AppUITests | source approval/review receipt/current observation 是不同事实；后端已部署和管理员审核能力未核实 |
| I4 模板创作/草稿/上架 | 部分实现 | TemplateAuthoringCoordinator.swift:85–175 open/local checkpoint/confirm；:202–257 上下架 pending+readback；TemplateAuthoringHTTPTransport:4–18 无默认网络/token/approval | TemplateAuthoring*、TemplateAuthoringPublishReceiptTests、AppUnit TemplateAuthoringPublishResultTests、UI TemplateAuthoringFlowTests | 独立草稿保存算法已实现；真实模板写/审核/上架需要明确批准与服务端回读 |
| I5 工坊已购/已拥有/付费安装/作者声明与待办 | 部分实现 | AppSession.swift:465–745 会话绑定、分别读写批准；WorkshopPurchasedService:68–85 purchased/list/detail；WorkshopPaidInstall/Professional/CreatorConsent/Pending 系列 | WorkshopPurchased/Owned/PaidInstall/PaidProfessional/CreatorConsent/Pending Core与正常流程AppUnit/UI | 元数据可读≠购买已完成；FREE、PAID、安装正文、专业编辑、作者声明均独立grant；未查到已核验真实支付购买闭环 |
| I6 创作中心/合作/作者定价/取消/移交/毕业 | 部分实现 | CreatorContentService.swift:11–17 project/my、creator/center；PublisherLifecycleHTTP:68–121 pricing/cancel preview/budget/partner；PublisherLifecycleCoordinator:78–89 pricing/confirm、cancel、transfer-to-club、beta/graduate | CreatorContentTests、PublisherLifecycleTests、PublisherSourceAuthorityTests、PublisherLifecycleUITests | ownership、取消退款、pricing 授权独立；cooperation toId 是商家 owner member ID，不能替换为 merchant row ID |
| J1 报名/候补/订单状态 | 部分实现 | RegistrationProduction.swift:19–20 quote/create/info、consent及waitlist；:57–63 typed factory；OrderLifecycleService:16–24 registration/info/coupon/status | Registration*、RegistrationWaitlist*、OrderLifecycle*、OwnedOrderReadTests | 创建未知不能重复生成订单；免费报名可作为第一条跨角色闭环，真实支付不应挡住首阶段 |
| J2 支付/取消/退款/主办方取消 | 部分实现 | OrderLifecycleProduction.swift typed config; AppSession:2355–2366；ClubOwnerRefundApprovedAccess.swift:13 required paths cancel-by-owner/access/checkin | OrderLifecycleProductionTests 31 个 fake-HTTP 方法；OrderPaymentVerifierTests；ClubOwnerRefundTests | 模拟器无法证明真实微信 SDK；取消回执、registration status、payment status、现金/积分退款维度分别断言；真实资金禁用 |
| J3 非现金奖励列表/详情/上下文绑定 | 部分实现 | NonCashRewardService.swift:13–45 GET noncash list/detail，冻结 scope/terms、asOf、cursor校验；NonCashRewardReading.swift:62–109 账户与生命周期隔离 | NonCashRewardReader/Detail/Lifetime/Collection/Composition；UI NonCashRewardFlowTests | 客户端读取合同已实现；服务端发奖幂等、库存唯一领取、跨玩家竞争未验证，不能由奖励卡片推断 |
| J4 优惠券发行/停止/命令回执/二维码 | 部分实现 | CouponManagementRuntime.swift:33–53 publish/stop独立grant，:129 command-receipt，:138–180 confirmed dispatch/fresh permission | CouponManagement*、CouponCode*、CouponPublishedBatchCodeTests | 准确 requestId 的未知恢复应复用；不能扩大到不存在/未经审查的领取入口 |
| J5 钱包/资产/提现/商品与购物车 | 部分实现（补充模块） | WalletCommerceService.swift:17–84 points、balance/stages、ledger、product、cart、settlement preview、withdrawal list；AccountView:92 钱包入口 | WalletCommerce*、BankWithdrawal*、UI WalletCommerceFlowTests | 商品预览/结算预览≠购买，提现读面≠真实出款；应分别跟踪测试沙箱 provider 与合规同意 |

## 本轮已读测试的证据级别
- MerchantBusinessProductionTests.swift：18 方法；ordinary fake HTTP factory 测试，含 default off、精确目标、finance不能决策、真实路径字节、撤权、取消屏障、未知恢复。
- ClubGovernanceProductionTests.swift：15 方法；fake HTTP，含 durable journal、risk/target/audience、两种multipart、导航间锁、同账户角色变更。
- OrderLifecycleProductionTests.swift：31 方法；fake HTTP，含独立取消/退款、变更快照、journal后退出、same-account relogin、provider return读回、跨realm隔离。
- AppUITests/MerchantBusinessFlowTests.swift：10；ClubGovernanceFlowTests.swift：7；PublishingModesFlowTests.swift：4。上述三套明确使用 fixture launchArguments。不得在真实 E2E 分子里计数。
- 其余测试名由固定树及调用链确认存在，未逐一展开全部测试体；报告不推导全模块的执行通过率。

## 建议优先场景（全部为待实现/待执行场景设计）
统一约定：Run ID=R，设备A/B/C为独占租赁的模拟器；测试账号只来自隔离环境；服务端断言优先用受授权观察 API/现有读合同，不读生产数据库。清理只限本 R 所有数据；UNKNOWN 写入先取证+读回，不能删客户端 journal 后重发。失败证据 E=case/run/build/commit/device/actor哈希、相关UI、请求ID/原始状态与时间线、日志/xcresult（脱敏）。

| ID / 优先级 | 前置条件 / 角色 / 设备 | 动作 | 可观察预期结果 | 清理 | 证据 / 自动化 |
|---|---|---|---|---|---|
| H-MER-01 P0 | 仅A商家M1有workspace批准，B商家M2/玩家无权限 | A读取本店项目/参与者；B尝试相同资源 | A UI/API ID集合一致；B 403/不可访问且无M1数据缓存；角色切换后A旧响应不落屏 | 只读，无删除 | E+access快照，Core+API+双UI |
| H-MER-02 P0 | M1 owner与finance员工，测试售后单，A/B | owner AGREE；finance尝试AGREE和EVIDENCE | server allowedDecisions+权限决定结果；仅意见增加；支付/退款状态不被客户端推导为成功 | R售后单隔离保留/沙箱归档 | E+意见ID+退款独立快照，API并发+UI |
| H-MER-03 P0 | M1 CRM target已批准；可注入超时点 | A加备注请求发送后丢响应，杀App重启，重开表单 | 一次写调用/同requestId；显示UNKNOWN；原target锁保持；其他独立target可操作 | 确认原请求持久化后按精确ID清理；锁仅依协议处置 | E+journal脱敏快照，Core+单UI+API |
| H-MER-04 P1 | owner A，operator B；role version可变 | A打开角色修改确认；B权限在server撤回；A确认 | 重新读取assignable role/version，零越权写；B接入权限改变 | 恢复R测试角色，不影响其他运行 | E+版本/写计数，API+双UI |
| H-CLUB-01 P0 | A俱乐部主理人，B新成员，C无关成员；独占测试club | B申请→A批准→B查看名单→B退出 | request/member ID一致；B已成员状态在双方回读；退出后B私有读取与旧回调不可用 | B退出、清R申请 | E+成员/申请观察，Core+API+双UI |
| H-CLUB-02 P1 | A/B为同club不同activity授权负责人，version=v | 同时更新同一未来场次，barrier后提交 | 仅合法version操作成功；另一明确冲突；两端最终同server状态；其他活动权限不能扩展 | R场次归档 | E+CAS冲突与状态，API并发+UI |
| H-CLUB-03 P1 | club已批准通知audience，测试notification sink | A预览人数→成员变化→确认；同时退出页面 | 预览与最终audience合同一致，unknown不是0；离开后的未发动作不发；已发未知不重复 | 清sink与R通知记录，保留审计 | E+audience IDs/count+command ID，Core+API |
| H-CLUB-04 P1 | 测试报名和出勤，A有目标activity纠正权限 | A纠正出勤，B查看自身记录；C跨scope尝试 | 准确报名/出勤version回读；C不变更；统计与单项状态一致 | 按R纠正/归档，保留审计链 | E+目标/统计，API+双UI |
| I-PUB-01 P0 | A作者，B第二账号；无write grant也跑负例 | A编辑故事/章节/节点保存本地→终止→重开；切B | A数据和章节关联恢复；B不得读A草稿；没有批准时网络写0 | 清专属草稿namespace；未知记录保留 | E+draft hash+request count，Core+AppUnit+UI |
| I-PUB-02 P1 | 专业保存/prepare批准+真实测试backend | 保存含票价、协作者、章节与节点，服务端合法ID重映射后回读 | 意图字段语义一致；node.chapterId属于回读章节；回读缺字段不得显示完整成功/清恢复稿 | 精确topicID清理，不批量删草稿 | E+脱敏意图/响应/语义diff，API+UI |
| I-PUB-03 P1 | personal topic有冻结审核快照/独立publish+status grant | A提交approved release后丢响应→重启→查status→原请求精确重试 | request ID、head revision、frozen cover不变；最多一个release；状态查询不是新发布；拒绝错误source | R主题/审核记录沙箱归档 | E+release/version/request IDs，Core+API+UI |
| I-PUB-04 P1 | A俱乐部活动发布写路径被明确装配；B玩家 | A发布免费活动→独立回读可见→B报名→A看报名 | code200只记ack；详情/列表状态与ID一致；报名落到该活动且owner scope正确 | R报名取消，活动精确归档 | E+活动+报名ID，跨角色UI+API |
| I-WORK-01 P1 | A拥有paid license、B无license，独立各grant | A读购入元数据/安装/正文；B用相同ID；A声明作者请求超时恢复 | free授权不解锁paid；B无正文；声明/安装不重复生成；原pending保存 | R许可/目标数据归档；禁止真实购买 | E+grant/revision/license hash，Core+API+UI |
| J-REG-01 P0 | 免费R活动余量1；玩家A/B，barrier | 两方同时quote/create，成功者重启查订单 | 不能超额；服务端允许的一次成功/候补/冲突；UI不虚构报名成功；未知不重新create | 仅R报名按合同取消 | E+quote/registration IDs+名额回读，双UI+API |
| J-ORD-01 P0 | 隔离订单、sandbox provider或确定性adapter，A | pay返回success/cancel/timeout分别注入，后台/重登后回读 | SDK结果不能变paid；只有server paymentStatus=2且registrationStatus=2才确认；原锁不因重登消失 | 沙箱订单归档，禁止资金动作 | E+provider与server双时间线，Core+API；真SDK真机单独验收 |
| J-ORD-02 P0 | A本人订单，B他人；独立cancel/refund grants | A取消/退款重复点击和网络超时；B尝试订单ID | B零越权；cancel grant不允许refund；现金/积分/registration维度分别一致；unknown无自动重发 | 测试provider按协议reset；保留账务审计 | E+原请求+订单三维快照，Core+API+双UI |
| J-REW-01 P1 | A/B竞争唯一非现金奖励；后端发奖规则已明确 | 同步完成资源动作→两个客户端读奖励→重启分页 | 全局唯一award/库存一次消费；context/release/instance/rulesVersion冻结；列表和详情一致无重复cursor | 重置R资源与奖励由隔离seed/cleanup服务执行 | E+server唯一性观察+award ID，API并发+双UI |
| J-COUP-01 P1 | 商家A与玩家B，受控券批次/receipt合同 | A发行后丢响应→command-receipt恢复→停止发行→B查看受影响券 | 精确request恢复不重复批次；发行与停止权限独立；既有券状态依合同而非前端猜测 | 精确R批次停发/归档 | E+command receipt/batch ID，Core+API+双UI |
| J-WALLET-01 P1 | R钱包账目含负调整与不同asset kinds，无真实钱 | 分页/筛选/读失败/重登/不同角色查看 | 总额、分项、币种/积分单位独立；未知金额不是0；分页失败不跳页；不得由列表快照发起资金动作 | 只读；R账本归档 | E+账目ID/净额算式，Core+API+UI |

## 实施分工建议（本lane）
1. 先交付“受影响测试索引”而非全新框架：上述Core/AppUnit/UI现有文件按 feature/path 关联case；fixture和real分标签，禁止复制现有测试另起框架。
2. H/I/J共享AppSession.swift、AppCompositionRoot.swift、NativeRuntimeDependencies.swift、QuestifyApp.swift。三Agent只各自写Core/测试/fixture（后续授权阶段），这些共享文件只归一个Integration Owner。候选分支基于固定SHA，合并后统一重建一次。
3. 第一条跨角色链选免费活动/报名；现金支付、退款、出款不成为双设备消息里程碑前置。
4. H/I/J真实写入批准须由后端/部署所有者提供可验证合同与隔离账号/对象；本轮只提出要求，不能改生产权限或根据登录role自造grant。
5. 原子测试数据租赁键为环境+R+actor+业务对象，客户端journal的产品realm不可被测试Run ID替换到绕过未知写保护；跨run重用账号前核实未决动作，未知则隔离账号而非删除锁。
6. 本lane不推荐直接DB查询。若现有读API不足，可提最小测试环境观察API：精确R+resourceID，返回状态/版本/持久化事件ID/收件回执等非敏感字段；只读、短期凭据、部署白名单、无任意SQL和生产路由。

## 未核实
补充候选备注：主控确认 open PR #122（head 82da635f）与 #123（head 0c2789d8）尚未合入固定基线。已读取两 PR 的 files/patch：#122 在 MerchantOperationsEditor/Views、MerchantNPCDraftApprovalGate/KnowledgeAuthorFlow/KnowledgeReviewWriter 增加原知识审核请求一次 GET 回读；#123 将 accepted reentry 保留在 author flow 并在编辑器 state 为空时恢复。它们不是 76ce1b31 的已合入能力；没有 AppSession/PBX 修改，不能推断普通入口完成接线或真实 HTTP/Swift 通过。后续场景需独立加入“关闭编辑器后恢复同一审核 requestID、不同 member 不接受、不重复 POST、不自动发布”的候选验收；禁止整包拷贝覆盖。
没有真实后端部署/账号/provider/双端状态的运行证据；没有完整逐测试体审查；本lane不报告“所有模块完成”或百分比。列出的是现有业务切片与可执行验收要求，后续必须以固定build的实际跑数更新。

