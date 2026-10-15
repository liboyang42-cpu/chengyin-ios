# CY-HANDOFF: IOS — I02 原命令回执恢复错误不得清锁

更新：2026-10-15 UTC。协议 `CY-COORD-20261015-v1`。本次为 **I02 / A01 / BK-SESSION 的一个源码修复切片**，不是整卡或原生业务验收。

## 基线、归属与依赖

- iOS 仓库/分支：`liboyang42-cpu/chengyin-ios` / `migration/native-ios`；精确输入 `0f2f0eb5670ac8331ecd54b1b2c05c77cbfa7b5c`，tree `c208cd1ec94481925dc4a00e7678ebb2c587e4a9`。在该已发布快照的隔离副本修改，未收入其他未提交累计工作。
- 本文随本切片提交；提交前状态为 `SOURCE_CANDIDATE / NOT_PUSHED`，最终提交身份以包含本文的 Git 提交及远端分支为准。独立源码复核/发布由当前 iOS 协调者处理。
- 适配前重新读取 [控制记录 3783d0fd](https://github.com/liboyang42-cpu/hengyin/blob/3783d0fdeb7b102332fb72099cc3cd3f441f6b77/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)、[OWNERSHIP](https://github.com/liboyang42-cpu/hengyin/blob/3783d0fdeb7b102332fb72099cc3cd3f441f6b77/docs/plans/mini-codex-cloud-20261015/OWNERSHIP.md)、IOS_START_PROMPT、IOS_HANDOFF、COORDINATION 与 TASKS。控制提交与业务候选不是同一 SHA。
- 后端合同/源码候选固定 `1e403b135206844a34219753a36e2dee39c7dd59`；[A01 合同](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/docs/verification/mini-bug-arch-20261015/A01/CLAUDE_CONTRACT.md)已冻结，BK-SESSION 为 SOURCE_READY。读取 [PR18](https://github.com/liboyang42-cpu/hengyin/pull/18) 时仍 open/draft/UNMERGED。
- 最新控制记录签收后端候选的独立 VPS 自动化矩阵，但明确 `TEST_DEPLOYED=NO`，运行时 HTTP、真实身份、包/数据库绑定及 iOS 设备尚未验收。本次没有运行或查询 CI，不将后端测试签收移用为本 iOS 代码的测试证据。
- 唯一修改范围：`Core/PlayGameSessionRuntime.swift`、`Tests/CoreTests/PlayGameSessionRecoveryTests.swift`、本文件、`docs/ios-current-status.md` 的 I02 行。无后端、共享控制日志、App/UI、翻译、工作流、权限、端点或能力开关改动。

## 源码确认的缺口与脱敏复现

已有 `playerReceipt`、`retryExact`、完整命令及账号/epoch/namespace 检查，全部复用。原 `PlayPlayerGameCoordinator.fail` 将所有 `.rejected` / `.disabled` 清除 pending，未区分原命令结果与读取错误。

1. 虚构活动 41、节点 701、PLAYER_CHOICE、revision 2、requestId `original-request`。首次 POST 结果未知。
2. 点击既有“核对结果”，GET 原回执遇到 AjaxResult 错误；或者已经读到 APPLIED，随后 GET view 错误。
3. 原实现把读取错误当作命令失败并清 pending。下一次刷新即可进入 ready 并允许另一 requestId，尽管原结果尚未核清。
4. 直接刷新未知命令还会先替换 projection，不能证明原命令生效，并可能改变后续核对的 sessionId 基准。

[ApiGameSessionController](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiGameSessionController.java)的 command/view/receipt 都可能返回 AjaxResult error，内部异常与已知错误不能单凭业务 code 区分原命令是否生效；业务 code 不等于 HTTP 状态。command 的失败回执写入也可能失败。

[GameSessionRuntimeServiceImpl](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/GameSessionRuntimeServiceImpl.java)的 receipt 在找不到行时返回 activityId/requestId/PENDING/replayed，没有 action/revision/receiptId。recordFailure 不覆盖已有回执；重复键不同指纹抛冲突。因此不能将任意 AjaxResult 错误或找不到回执转换成安全的新命令身份。

## 本切片的完整原有流程

- 入口：保留既有动作评审和 projection.allows。取消的首次提交不创建 pending；缺 playerCommands 能力在创建 pending 之前明确 disabled，不发请求。
- 发送：冻结原命令/requestId/expectedRevision/payload；新命令开始时清除上一次命令的可见回执和错误，不将旧 APPLIED 当新命令的结果。
- 未知：传输、业务包装、鉴权、缺回执、畸形回执及读取失败均保留原 pending。来源明确的“无行 PENDING”映射 unknownResult，不伪造 action/revision。
- 恢复/重开/刷新：pending 存在时先查询原回执，不能用新 view 直接解锁或替换原 sessionId 基准。
- 确定失败：只有通过原命令身份校验的 FAILED 回执进入 rejected 并清 pending。下一动作仍须先刷新 view，沿用旧资格判断。
- 确定生效：匹配的 APPLIED 回执仍须读取同一游戏 sessionId 且 revision 不低于回执的 view。读取失败时保留 APPLIED 与 pending；继续核对或点击既有原样重试只补 GET view，不再 POST，也不把确定回执降级成缺行结果。
- 原样重试：尚无 APPLIED 时继续使用原完整信封，不生成新身份、不修改版本或 payload；本次不加入后台自动重试。
- 迟到结果：恢复读取使用 load 的既有 generation。更新一代读取、账号/realm/epoch 变化或取消后，旧回包不能发布回执或清锁。

`NO_API_CHANGE`：仍为 GET `/api/game/session/view`、GET `/api/game/session/receipt`、POST `/api/game/session/command`。不新增 requestId/version/epoch 字段，不给取消、退款、路线或其他旧接口套用 game 协议；没有创建第二份回执服务。

## 已编写的回归源码与证据边界

专属 `PlayGameSessionRecoveryTests` 有 13 个方法，直接调用真实 service/coordinator，以明确 synthetic transport 观察请求与状态：

1. command AjaxResult 错误保持未知，匹配 FAILED 终结，随后 fresh view 才可新动作
2. 回执读 400/403/409/500 均保留原信封，另一 ID 不能提交；显式原样重试 body 相同
3. 缺行 PENDING、已存 PENDING、null、未授权、disabled 与断网读失败不清锁
4. 错活动/requestId/action/终态缺 receiptId 均不能确认原结果
5. POST APPLIED 后 view 失败，重试仅读 view
6. 恢复读 APPLIED 后 view 失败，普通刷新完成读回
7. 普通刷新未知先查原回执，不消费另一个 session 的 view
8. APPLIED 后旧 revision/不同 session 均保留锁，正确投影才释放
9. 第二个命令不展示或复用第一个 APPLIED
10. 首次能力 disabled 无 POST、无 pending
11. 迟到恢复不跨账号/realm/epoch
12. 较旧 FAILED 回包不覆盖新一代 APPLIED 读回
13. 预先取消的首次提交无 pending

**按用户本轮“只做代码及推送，不跑测试”的要求：**本切片 Swift/Core XCTest、Python/结构套件、AppUnit、XCUITest、Xcode 构建、模拟器、真机、运行时后端、真实身份/provider、部署及发布全部 `NOT_RUN / NOT_VERIFIED`。13 是编写方法数，不是通过数；源码检查/补丁散列不证明可编译或业务通过。

本切片只关闭保留 coordinator 中的回执恢复错误路径。该 player coordinator 的 pending 仍是内存状态；没有宣称跨进程恢复、两设备业务验收或 I02 整卡完成。既有订单、路线及其他持久化 journal 未改。今后启用能力仍须独立验证原生执行、持久化链、合法测试部署与业务读回；当前 OFF 保持 OFF。

回退应只撤本切片源码及其专属测试/文档，不重置其他功能、旧工作、回执或未决记录。
