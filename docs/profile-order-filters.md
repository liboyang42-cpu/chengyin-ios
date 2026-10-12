# 本地订单状态筛选完成，生产订单读取仍阻塞

基准 49c68c6420270b0a0cc7ec8d18bc8561f329d796，无前16包文件叠加。唯一总文档 P120/P121 委托真实 scene-member-order-history；pinned Mini f859 JS blob 9dab87c1、WXML c96a13ba。原生已有详情、时间线和独立票夹导航，但没有订单列表的状态筛选，本批仅补这一链。

## 完成交互
已读取的全部订单可切换 Mini 九类：全部、待支付、未开始、进行中、已完成、退款中、已退款、不可退款、人工售后。筛选结果保持原序；有订单但当前筛选无结果时可返回全部，与真正无订单区分。原有详情 NavigationLink 和请求 id 不变。

取消、过期、未知没有 Mini 独立筛选项，仍保留在“全部”。分类行与选项使用同一状态投影；不把取消归到已退款。账号/reader/配置变化后旧筛选无效；进入详情不清空选择。每60秒仅重算本机显示，不触发网络。

## 来源与模型
`utils/order-status.js summarizeOrderState` 优先级：人工售后→退款回执→报名状态→核销→已支付且首扫成功→非免费且明确不可退→活动起止时间。退款终态仅 payoutStatus 1/4，2/3 仍为处理；零金额或驳回回落原状态，空退款对象与缺失对象不同。

`isFreeOrder` 必须 totalAmount/payableAmount 明确零且积分/微信实付不存在或零；不能用现金为零冒充免费。CmsRegistration 已有 BigDecimal totalAmount 与带 JsonFormat 的 Date firstSuccessfulScanAt，不新增响应字段或接口。ProfileOrder 仅新增只读 historyFacts 的声明/解码两行；原字段解析和原订单/付款/退款逻辑不动。补充事实容错读取不新增全单解析失败。起止兼容 startDate/startTime/endDate/endTime，以活动对象优先、主题其次，使用既有 OrderLifecycleTime 上海时区解析。

不将此分类用于付款、退款、取消、核销或任何资格。旧 OrderLifecycleDetail.summary/timeline 未修改，本批不是历史状态机修复。列表分类与旧详情说明可能采用不同历史展示逻辑，按新功能范围保留并记录。

## 明确适配差异
Mini switchTab 会重新拉全量后本地过滤；原生已经持有同一份获准全量结果，切换只过滤内存，不新增请求或字段。手动刷新仍走原 ProfileReadScreen。退款文案细分保持原详情，不复制到分类按钮。

源 totalAmount 为 BigDecimal JSON 数值；额外兼容完整零字符串。不把 malformed 数字前缀、十六进制或非零数值的下溢字符串推断为免费；相较 JavaScript Number 的宽松转换是保守显示差异。没有真实金额运算、汇率或币种推断。

## 生产接线阻塞
- POST /api/registration/list，原生 multipart `owner_type=3`，响应完整 rows/total、成员相关性和唯一 id 校验保留。Mini 的 pageNum/pageSize/status 不添加到严格允许请求。
- POST /api/registration/info，multipart `id` 正整数，响应 matching registration id/memberId。详情沿用旧 reader。
- AppCompositionRoot.ownedOrderReadApproval 默认返回 nil；OwnedOrderReadApproval 的 CN context、有效期、撤销与独立后端 null-principal guard 验收/部署依赖不变。AppSession、ProfileService、OwnedOrderReadRoute 未动，不能借旧 Profile reader 绕过。
- P116/P117 PlayerJourneyService.readsEnabled 不变，与本项分离。

因此交付只称本地筛选和模型完成，不能声称普通账号生产订单列表已完整可用。DEBUG fixture 为内存合成行，无 transport/token/live grant；正常批准链尚未开启。

## 验收和交付
新增 Core/模型/界面测试覆盖九类、优先级、首扫、免费单、时间边界、未知全量保留、无额外读取、筛选空态恢复、原 id 详情、切号/撤销。源码检查、受控静态变异与 exact Mini synthetic tests 不替代 Swift 执行。

Apple 编译、XCTest、模拟器/真机、真实账户读取：NOT_RUN。中央仅按 fragment 注册新源/测试/离线 fixture 和5条双语 key，保留中央对两个共享文件的后续变更。前16个封包不可覆盖。
