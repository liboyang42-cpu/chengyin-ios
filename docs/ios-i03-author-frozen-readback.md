# CY-HANDOFF: IOS — I03 作者冻结读回兼容

更新：2026-10-15 UTC。协议：CY-COORD-20261015-v1。**本次为源码候选，尚未独立复核或推送；不是原生运行、保存业务或整张 I03 卡验收。** 按本次指令仅编辑源码和回归用例，不执行测试、构建、App 或 CI。

## 身份、范围与当前合同

- iOS：`liboyang42-cpu/chengyin-ios`，接续 `migration/native-ios`；确切父基线 `09323a41b9ee1f19a468f62463a489711888d72f`，tree `cfe2eede60cd1f9feeed6f3db2dd65841bfabfc2`。未导入其他累计工作，也未改变能力注册表、端点或开关。
- I03 / B02 / BK-AUTHOR，**NO_API_CHANGE**。本次只消费既有 `POST /api/topic/edit-detail` 的 `SELLING_FROZEN` 枚举，不增加接口、请求身份、版本字段、草稿实体或发布政策。A03 / BK-NARRATIVE 未改动。
- 开始适配前完整读取 [IOS_START_PROMPT](https://github.com/liboyang42-cpu/hengyin/blob/b8541ad2407d0a360588ab77ad32fe3d1c9eb71e/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md)、[IOS_HANDOFF](https://github.com/liboyang42-cpu/hengyin/blob/b8541ad2407d0a360588ab77ad32fe3d1c9eb71e/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md)、[BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/b8541ad2407d0a360588ab77ad32fe3d1c9eb71e/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)，并核 COORDINATION、OWNERSHIP、TASKS 的对应范围。冻结业务候选为 `1e403b135206844a34219753a36e2dee39c7dd59` / [PR18](https://github.com/liboyang42-cpu/hengyin/pull/18)，已查为 open draft / UNMERGED。
- 交付前再次读取控制 `05346fedae227c12cff9d9ca533c3e92e62ae743` 的 [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/05346fedae227c12cff9d9ca533c3e92e62ae743/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md) 和 OWNERSHIP；新公共后续候选为 `4a943501262cb533158428d9748d8ac49aaa8950` / PR28。实际读取其 `ApiTopicController.java` 与 `TopicEditWindow.java`：前者给 edit-detail 增加只读 REPEATABLE_READ 事务，后者与冻结候选完全相同。新聚合读取合同 CONTRACT_FROZEN；该控制快照记录 Java/真实数据库结果尚待取得，不能继承旧候选的执行证据。
- 两个候选均没有本次可使用的应用部署证据；**TEST_DEPLOYED=NO**。本次未查询/启动 CI，没有真实账号、HTTP 保存、数据库或设备调用。后续控制分支会移动，以上是固定读取证据，不是实时状态承诺。

## 源码确认的缺陷与脱敏复现

来源：[B02 合同](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/docs/verification/mini-bug-arch-20261015/B02/CLAUDE_CONTRACT.md)、[TopicEditWindow](https://github.com/liboyang42-cpu/hengyin/blob/4a943501262cb533158428d9748d8ac49aaa8950/chengyinhub-system/src/main/java/com/chengyinhub/business/util/TopicEditWindow.java)、[ApiTopicController](https://github.com/liboyang42-cpu/hengyin/blob/4a943501262cb533158428d9748d8ac49aaa8950/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiTopicController.java)。`TopicEditWindow.resolve` 在已有生命周期开始售卖后返回 `SELLING_FROZEN`；控制器把它的 `.name()` 放入 `data.editScope`。原生枚举只有 FULL/WHITELIST，解码该合法响应必然抛错。

脱敏源码路径：synthetic member901/topic71 → 自有内容入口 → 读取 edit-detail；或先正常保存获确认 → 点已有续编读回 → 服务器返回 `code=200`、原 topic ID、真实章节/节点/模板绑定及 `editScope=SELLING_FROZEN`。

- 预期：展示服务器当前内容和冻结事实；不允许继续编辑或提交，已有本地草稿与未决记录保留。
- 原实际源码分支：`ProjectEditScope.init(rawValue:)` 返回 nil → `decodeEditDetail` 抛 invalidContract → loadFailed/readFailed，正常冻结被错误显示为读取失败。
- 这是源码确认与构造的回归向量，**没有在 App 或服务器运行复现**。用例中的账号、ID、URL、内容均为 synthetic。

## 修复闭环

1. **入口与读取**：接受这个已存在的枚举；未知未来枚举仍拒绝。主题/章节/节点 ID、模板绑定、顺序、版本与媒体字段仍沿原 decoder 读取，不从公开详情拼出编辑数据。
2. **保存入口**：枚举明确 `allowsEditing=false`；模型禁用输入、自动保存、退出保存、审阅与结构编辑。协调器也拒绝本地保存、恢复覆盖、丢弃草稿、审阅和确认，不只靠按钮灰态。
3. **请求边界**：payload 在校验/日期转换之前拒绝冻结；即使调用方伪称 FULL/WHITELIST，冻结 baseline 仍拒绝。既有 story/path 校验也拒绝，覆盖直接调用 HTTP service 的入口。FULL/WHITELIST 原语义保留。
4. **已确认保存后的读回**：既有明确续编动作可以读取冻结快照并显示当前 ID/内容；这一分支只更新内存，不覆盖此前本地提交草稿、不清完成 journal。按钮复用“重新加载”。若后续明确重读获得可编辑 scope，才沿原 baseline-save → exact-pending-clear 顺序续编。
5. **未知保存**：仅冻结读回不是成功证据。原 pending 身份、请求、未决锁和本地草稿不变；不按名称认领 create、不发新请求、不把 HTTP 200 当原写入完成。可从原页面再次读取；换账号/离页代际/替换 pending 的保护保留。
6. **失败与恢复**：读取失败保留旧冻结投影与原完成记录，可明确重读；迟到读取不能覆盖新账号或被替换的 pending。正常冻结读取不再进入通用 loadFailed 状态。
7. **呈现**：复用已有双语“只读记录与本地草稿”文案与锁图标，并展示确切 `SELLING_FROZEN` 服务端 scope；仅复用字符串，不引入漫游行为或小程序 UI 政策。未编辑 `Resources/Localizable.xcstrings` 或任一此前 HOLD 路径。
8. **保留 V2 回执后的独立入口**：`submissionEvidence` 继续保留，不能把删除回执当作禁写。已有封面 current/status/图片读取可用，picker/upload/select/retry 和迟到选择应用均受冻结门禁；已开启 picker 的原身份在实际调起/回调时再核。新 review 的 capture/current 门禁关闭；approved snapshot 读取仍可用，但不创建冻结 publisher，已捕获 publisher 也失去写权限。既有 Task 内在调用 mutation source 前再次核当前权限，原 durable intent 不删除。

## 精确改动路径

- `Core/ProjectEditDraft.swift`：既有 scope 枚举与验证入口
- `Core/ProjectEditContract.swift`：拒绝冻结 payload
- `Core/ProjectEditStoryContract.swift`：拒绝冻结 baseline 路由
- `Core/ProjectEditCoordinator.swift`：只读状态、保存/恢复/丢弃门禁、保留 journal 的冻结读回
- `App/ProjectEditView.swift`：只读呈现、控件门禁与原读取入口
- `App/OwnedTopicCoverAuthorPresentation.swift`：封面读取与修改权限分离、迟到选择不应用
- `App/OwnedTopicCoverAuthorView.swift`：已排队和原生 picker 权限重核
- `App/ApprovedTopicReviewPresentation.swift`：冻结新 review 入口与旧回调门禁
- `App/ApprovedReleaseAuthorPresentation.swift`：保留 approved read，禁冻结 publisher 权限
- `Core/OwnedTopicCoverAuthorFlow.swift`：原 picker 身份与排队 upload/select 权限重核
- `Core/ApprovedTopicReviewFlow.swift`：排队 review mutation 权限重核
- `Core/ApprovedTopicReleasePublicationClient.swift`：排队 publication mutation 权限重核
- `Tests/CoreTests/ProjectEditRemoteTests.swift`：9 个新增回归方法
- `Tests/AppUnitTests/ProjectOwnedEditorTests.swift`：8 个新增回归方法
- `docs/ios-i03-author-frozen-readback.md`
- `docs/ios-current-status.md`：仅本切片状态入口

以上共 16 个文件。没有改后端或共用控制日志、配置、凭据、项目工程/依赖、媒体协议/上传参数、播放器、Flutter、支付、生产能力或其他累计候选。

## 验收向量与证据等级

已编写但**全部 NOT_RUN**：个人/商家、两产品的冻结详情；canonical ID/绑定；未知枚举；部分内容与日期转换前拒绝；伪造 FULL/WHITELIST baseline；直接 HTTP service 的零写入；审阅后变冻结；本地草稿冻结重开；UNKNOWN 读回与重建协调器；已确认冻结重读/恢复可编辑；读取失败恢复；账号切换和 pending 替换；原普通入口的 FULL/WHITELIST 区别。另有真实结构的 city V2 bundle acknowledgment、existing topic7901、已配置 synthetic cover/review/release source 的四个回归方法：冻结后仍可读回、零新增 mutation；迟到 picker/upload claim；原 review/publication claim；cover selection claim 和迟到 selection acceptance；断言原 journal 字节不变。

实际工作仅源码阅读、修改、差异/文件身份整理和独立源码复核准备。Swift/Core XCTest、AppUnit、XCUITest、Python/Node 契约套件、编译/typecheck、Xcode/模拟器、App、真机/无障碍、HTTP/数据库/真实账号、CI、签名/合并/部署/发布均未执行。17 个方法是作者编写数量，不是通过数量；旧 SHA 的任何通过事实不转移到本候选。

## 依赖、剩余边界与回退

- 必须在获准测试部署和身份下再验完整 save → edit-detail → 再次编辑；本次不证明后端聚合快照运行正确，也不取代 B02/L02 的事务验收。
- 首次 create 丢响应仍无可精确查询的后端身份；UNKNOWN 不解锁。章重排、上传中关闭、旧局内容版本等 I03 其余事项未在本切片关闭。
- 不新增售卖冻结的政策，只遵守服务器已有返回；不依靠客户端判日期/售卖状态授予写权限。
- 只读呈现保证根编辑页和可进入的既有章节表单展示服务器内容；现有章节表单整体 disabled 会禁用其中的更深 node/block NavigationLink。本切片未改该表单或宣称完整嵌套内容浏览验收。
- review 是既有 mutation-oriented presentation，冻结时不打开；review/publication journals 保留但本切片不新增独立冻结状态恢复面板。封面 current/status 和 approved snapshot read 仍沿原流程可用。
- 回退只撤销上述 iOS 最小切片；保留所有既有本地草稿和 pending，不能清锁或重放写入以“恢复”。能力保持 OFF。
