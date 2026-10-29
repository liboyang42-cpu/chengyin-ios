# D/E/F/G/K 玩法域只读审查

固定来源：liboyang42-cpu/chengyin-ios @ 76ce1b313af2595f9b7d7ace49040866209c7974。未修改源码、未安装、未运行Swift/UI/真实API测试。仓库递归tree未包含AGENTS.md。全部路径证据可用 https://github.com/liboyang42-cpu/chengyin-ios/blob/76ce1b313af2595f9b7d7ace49040866209c7974/ + 路径定位。

## 核心结论

已有相当多领域模型、请求合同、状态机和synthetic回归；真实多账号链路主要受批准部署/账号/能力、设备/传感器和后端观测证据阻断。不得为了跑测试将所有grants统一打开。App/AppCompositionRoot.swift:147默认unconfigured，:159/202缺省sessionDependencies返回dormant，:179 city读取批准默认nil。Core/RuntimeDependencyConfiguration.swift:26–32默认空play/devices/sensors及false journey/NPC，:99–109按批准能力生成服务。App/NativeRoamLiveDependencies.swift:3–17默认dormant。App/AppSession.swift:348普通Play reader answersEnabled=false；:363以后独立组合高级运行时，不能据普通读页假设可写。

## 模块台账

|范围|已核实实现与入口|状态|真实闭环缺口/误判风险|
|---|---|---|---|
|活动与主题浏览|Core/TopicService.swift:35–53 list/info-to-user；Core/TopicContracts.swift:245–341有章节、storyLocked、total/unlockedChapterCount；App/TopicDetailView.swift存在|部分实现|目标部署、可见性/授权需真账号核实，公开营销详情不是运行期隐藏剧情|
|经典任务|Core/PlayService.swift:26–57 nodes/route-state/answer，回执nodeID核对；Core/PlayExperienceService.swift:59–107 answer/checkin/arrive/photo/sensor-result|部分实现|受classicCompletion及持久化/设备批准约束；提交成功不等于完成，必须回读nodes|
|玩法分型|Core/PlayGameplayMode.swift:5–7明确cityOrientation=1/freeExploration=2|已实现（本地分型切片）|不是完整自由探索/城市定向业务验收；两种模式需分别测UI和证据规则|
|章节剧情|Core/ChapterStoryContracts.swift:57–135遇未完成/unknown/跨章节点停止后文；JourneyNarrativeContracts.swift:20–35 casebook/backpack/stage-end/ending/encounter|部分实现|需验证实际发布内容与服务端解锁。未解锁文字不能出现在UI树或缓存读回中|
|任务持久化|PlayExperienceService.swift:150–168 run-session/list/save/clear；PlayDurableRecovery、PlayRecoveryStorage与PlayPrefabRuntime|部分实现|不同协议具有不同恢复能力，不能全称幂等；ordinary photo upload未知结果不能直接重发|
|漫游实时会话|App/RoamLiveSessionView + Core/RoamLiveSessionController + RoamLiveService.swift:20–63 reveal/session/pois/map-nearby/discover/shopVisit/presence/finish|部分实现|出厂dormant；坐标GCJ02、accuracy<=80、时间-2...30秒验证见:63–64；真机定位/权限待验|
|漫游隐私/恢复|写前journal、stable clientSessionKey、来源域映射、暂停恢复/结算读回已有实现与88个同文件测试方法|部分实现|真实后端持久化与奖励唯一性未验；模拟位置不能证明物理位置作弊防护有效|
|高级小游戏|TemplateAdvancedDraft.swift:3–10已有12种coin/dice/react/shake/quiet/countdown/stopwatch/sort/match/classify/compass/shout；PlayAdvancedRuntime.swift:77–98实际advanced/start/state/action/leaderboard|部分实现|作者rehearsal是本地演练，不能当live结果；骰子/金币不得客户端自造随机结果，见PlayAdvancedRuntime:55|
|多人高级玩法|PlayAdvancedRuntime角色分配/completeUnit/version/retry；PlayGameSessionRuntime:110–119 PLAYER view/command/receipt；PlayDirectorRuntime:111–118 CLUB同源协议|部分实现|服务器竞争规则、同局跨账号可见性与持久化需真实E2E；UI同时点击不是写入线性化证据|
|城市棋盘/大富翁相关|Core/CityPlayerReading.swift:9–16 board含gameId/boardId/regionId/seasonId/rulesReleaseId/rulesHash/revision；:69–106只GET current/participation/points；App/CityPlayerView:84 readOnly|部分实现（只读棋盘）|当前审查链未实现占领/过路费/掷骰/竞争写闭环，不能据city-game命名宣布大富翁完成|
|城市赛季快照|CityPlayerReading.swift:170–207遇409最多重读一次完整快照；禁止旧成员/新点位混用|已实现（本地一致性逻辑）|实际赛季切换API/部署和多设备一致性未验|
|末日寒冬|检索tree、已审查玩法入口/配置/Prefab运行时，未核实该主题专属规则/内容包/运行路径|无法核实|PrefabPreviewEngine/PlayPrefabRuntime是预制人生，不是寒冬证据。需要实际版本hash、7幕内容及资源/体温规则合同；不能据产品规划计已实现|
|模组包/qmod/H5|WorkshopOwnedPackage.swift:71–80仅metadataOnly，contentUseStatus=UNAVAILABLE、manifestStatus=NOT_AVAILABLE；InstalledDraftReceipts.swift:63–65强制executionAllowed等false|部分实现（元数据/历史凭据）；执行器无法核实|未在当前审查入口发现qmod/H5 SDK运行闭环，不能把packageInfo和历史installationId当可执行包；后续付费安装切片需创作者审查组另核|
|玩家NPC|ShopNPCHTTP.swift:31–45 /api/ai/npc/shop-chat和voice-chat；ShopNPCContracts:76–106检查requestId/outcome/retryable/safety；AppSession:282挂节点host|部分实现|默认grants均false；文字成功与任务推进是不同事实；音频播放契约明确unavailableInSource|
|NPC异常恢复|ShopNPCCoordinator保留原review/requestId与等待/终态/重试冷却；ShopNPCInterruptionTests 21方法覆盖后台/迟到/跨账号/撤权|已实现（进程内机制）|messages/pending是内存状态，此协调器未提供跨进程持久化；不能把suspend/resume测试说成杀进程恢复。商家history是另一条链|
|World/Season/Quest完整体系|能确认City season字段以及Topic/Chapter/PlaySessionScope(activity/topic)切片|无法核实完整体系|未核实独立World→Season→Quest模型/API/生命周期关系；不能以主题章节结构代称完整体系|

## 已读测试证据（仅已写，NOT_RUN）

|文件|方法数|代表断言|
|---|---:|---|
|Tests/CoreTests/PlayGameSessionRecoveryTests.swift|13|testAppliedProjectionFailureRetriesOnlyReadbackWithoutAnotherPost；testUnmatchedTerminalReceiptsCannotClearOriginalAttempt；testLateRecoveryCannotPublishIntoAnotherAccountRealmOrEpoch|
|Tests/CoreTests/RoamLiveSessionTests.swift|88|testRevealUnknownSurvivesRelaunchAndCannotBlindStartAgain；testFinishUnknownAndWrongOwnerReadbackNeverAwardOrRetry；testUnknownPendingCannotBeLaunderedThroughFinishAndAnotherRecovery|
|Tests/CoreTests/ShopNPCInterruptionTests.swift|21|testBackgroundInFlightKeepsUnknownIDAndDiscardsLateResponse；testAccountRoleNodeRunAndRevisionChangesPermanentlyInvalidate；testProductionGateOffCannotRestoreOrDispatch|
|Tests/CoreTests/CityPlayerReadRecoveryTests.swift|10|testSnapshotChangeRestartsCurrentAndNeverMixesMembershipOrSeason；testSecondSnapshotConflictStopsWithoutLoopOrPartialProjection|
|Tests/CoreTests/ChapterStoryTests.swift|8|testUnknownLockedAndCrossChapterNodeStopWithoutSpoilers；testCompletedNodeAddsEarnedNotesAndKnownThoughtsOnly|
|Tests/CoreTests/PlayAdvancedTeamTests.swift|17|testDuplicateClickWaitsForServerAndUsesFrozenRequest；testUnknownTeamWriteRecoversThenRetriesExactBytes；testNonleaderAndExpiredRequestsNeverDispatch|
|Tests/AppUITests/PlayExperienceFlowTests.swift|9|launchArguments使用--uitesting-module/playExperience synthetic场景；testBranchDoesNotRevealHiddenTask、testDormantEnvironmentShowsNoDevicePermissionPrompt|

这些不是全仓测试总数，且不能由方法数推导覆盖率。当前任务未运行这些测试，也没有同SHA服务端或模拟器验收证据。

## 阶段建议

1. 第一波复用上述Core/组件测试与现有fixture UI，先确保有效的本地回归基线，明确标注SYNTHETIC。不能因此推进真实E2E里程碑。
2. 双设备消息里程碑优先，玩法域在其后共用账号/设备/屏障/证据设施；不要另建一个玩法协调框架。
3. 第一条玩法live链选择答题→回执→nodes/route-state→重启恢复；第二条为同局PLAYER/CLUB命令CAS冲突及receipt恢复。采用可清理的隔离测试主题，不引入未实现的城市占领。
4. 漫游独立保留定位/传感器验收层；模拟器位置注入只验证坐标传递/规则，真机采样品质、后台、相机/陀螺仪/能耗必须另验。
5. 复杂主题必须冻结内容包hash+规则版本，定义每一步资源/体温/剧情oracle；AI生成的叙事文本不能用固定全文golden，应断言结构、范围、关联ID及授权状态变化。
6. World/Season/Quest、qmod/H5、寒冬等无法核实项进入能力待办，不编造API，不并入已实现模块覆盖率分母；应有单独“规划未验”分母。

## 文档差异

当前README还链接docs/ios-current-status.md，该文件更新于2026-10-15且固定7c21af基线；本次SHA为76ce1b。其“7种advanced games”概述已落后于TemplateAdvancedDraft明确12个case。采用当前代码而非旧计数；安全gate不因旧文档而放宽。

20条可直接合并的完整测试场景见同目录gameplay-cases.json（含12项必填字段及执行状态）。所有live场景必须先验证隔离部署、凭证、grant/契约和清理办法；不能用于生产。

## 未合并候选与基线的区别

已最小读取 open PR #121，head `3e2b83643c24973f83aafe78a9889e3ade6a428a`，base `cursor/c10-shell-binding-e504`。PR仅新增 `docs/issue5-hunks/c10-response-consumer.hunk` 21行。正文明确：AppSession没有parentOrigin/shellURL/launchTicket；H5LaunchProducer.EntryLaunch有origin/shell URL但无ticket；H5LaunchDescription只有origin/nonce；四个参数未绑定到真实持有者，hunk未应用，壳未接通，Swift/HTTP NOT_RUN。故“固定集成基线未核实H5闭环”不等于全仓无人实现；存在未合并候选，应先复用/整合这条所有者工作，不能另起重复实现，也不能计入当前已集成/已验收覆盖率。

