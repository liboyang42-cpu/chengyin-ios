# 本人订单预览：独立组件完成，普通页挂接与生产读取仍阻塞

基准 5dd3e53c1de104735b26d75811cb4ff46b2a340f，tree cfc74d0dda3e9d80ec06203ba42ce5599bb7f376。没有前包叠加，10 个新文件；所有现有 App/Core 文件不改。

## 真源和本次功能
唯一总文档 P004/P108 的 cy-profile：loadOrderPreview/reloadOrders/onOrderPreviewTap/goOrder。pinned f859 JS blob 99008cdb、WXML a955ea31：orders tab 预览前8条，失败与成功空集合分开；点卡片传本单 id，完整列表继续原订单页面。本批不重复第13本人项目或第17全量订单筛选。

组件完成：读取获准全量订单→保留返回顺序的前8条→打开该单新鲜详情；查看全部进入既有 ProfileOrdersView。初始失败可重试，刷新失败保留旧卡片并标明旧数据、禁止点击，成功空集合替换旧卡片；登录/配置错误清掉旧数据。不开新支付/退款/取消入口。

ProfileSelfOrdersAccess(session:) 明确只选 session.ownedOrderReader，绝不使用 legacy profileReader。原详情和全量列表接同一窄 reader；现有 ticketReader 是独立可选依赖，其许可仍由原票夹组件判断。

## 实际接线状态
按本批“独立新文件、接线交 fragment”的边界，没有修改 AccountView/SocialPublicProfileView。registration.fragment.json 包含可复核的两文件增量 patch，并绑定第13包 afterimages 精确 SHA。中央应在8→10→11→12→13后像上增量合并，保留其后中央变化，不用旧整页替换。

只有 context 有效才出现 orders tab；未挂接或生产订单许可未批准时不会放一个空可点入口。当前交付是独立可挂接组件和完整合成流程，不是已在普通账号个人页上线。DEBUG fixture 直接承载同一 Entry，无需前包公共页代码，可完整进入真实原生订单列表/详情组件。

## 安全与来源差异
- 捕获当前社交 owner、展示 revision、reader 对象，以及订单 owner 的 epoch/viewerRevision/approvalRevision。本人 id 必须同时匹配两方，配置有效且父页面仍 current。
- dispatch、success、error 都核对当前 context；列表必须全部同成员、正 id 且不重复，详情必须同 id/成员。其它 ProfileReading 方法始终拒绝，不能借这层读参与人或勋章。
- 只在内存保留已批准的结果，组件标记 privacySensitive；没有持久化、日志、token、HTTP、图片加载或写服务。
- Mini 请求带 pageNum/pageSize/status，但现有原生允许路由只收 owner_type=3；按已获准完整集合截8，不扩请求。仍沿用原读服务完整 rows/total 校验。
- 只展示现有 ProfileOrder 的标题和 createTime 前16字符。不新接封面图片 reader，也不声称有图片预览；DTO没有源 topicName 备用字段，缺主标题时沿用现有“未命名订单”提示。

## 生产依赖（原样保留）
POST /api/registration/list：multipart owner_type=3；完整 rows/total、当前 memberId、唯一 id。
POST /api/registration/info：multipart id 正整数；回包 id/memberId 匹配当前本人。
OwnedOrderReadApproval 仍为独立 CN context/有效期/撤销租约；AppCompositionRoot 默认 nil，独立后端 null-principal guard 的验收/部署证据未由本批建立。Pinned 后端已经有 guard 源码不代表可发生产租约。AppSession、ProfileService、OwnedOrderRead、现有门禁和共享注册均未变。

## 验收和交付边界
定向源码检查、静态变异、exact Mini 受控回包实验分别留证，不能替代 Swift 行为执行。已编写 Core、App、UI 的首8条、空/错/恢复、前后读作用域、切号/撤销、精确详情和全量列表测试。
Apple 编译、XCTest、模拟器/真机、真实账户读写：NOT_RUN，当前环境没有 Swift/Apple 工具。8条双语 key、新源/测试/DEBUG fixture注册，以及公共个人页fragment挂接均待中央集成。前17包保持字节不变。
