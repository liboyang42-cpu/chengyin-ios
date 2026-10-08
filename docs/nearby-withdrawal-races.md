# Nearby 申请撤销后的旧读回包防护

## 范围与基线

- 日期：2026-10-08。
- 基于实际源树 `5b0058e53f1867de900e8da00cd0ebe1f7710889`，不是副本的历史 Git HEAD。关联远端快照为 `c95737b4c54881a7492ca72bd31f68749304d1d1`；本次没有推送或读取生产接口。
- 对应主文档 U04（撤销优先）与 P129/PA05 的局部客户端缺口。不是 W16 全链验收、服务端并发修复或已成功成员退出。
- 只修改 `Core/NearbyTeamCoordinator.swift`，增加独立 Swift 回归、补充源检查及本说明。没有修改 Team 成员 retirement、AppSession/AppCompositionRoot、PBX、CI、后端、位置权限、陌生人会面或兴趣匹配。

## 已核实的缺口

原协调器收到 withdraw 成功回包后，只修改内存中当时的 teams 和 myApplications。下一次列表读取直接覆盖 teams，并把 PENDING/REJECTED 放回 myApplications，因此旧 PENDING 可以恢复旧倒计时、申请展示及有效申请计数。已有 settledActions 只能阻止再次发出同一操作，不能阻止旧数据回显。

普通请求由 busy 串行，不能把本缺口错误描述为普通读写始终并发。真实交错还包括 leave/resume：它退休旧展示 generation 并放开新读；旧写的已知成功可能随后返回。原 generation 判定已经丢弃更早导航的旧读取，本补丁保留该边界。

## 当前行为

1. 仅 `.acknowledged` 或 synthetic `.simulated` 的 withdraw 建立当前协调器、当前完整身份绑定和 teamId 下的本地屏障。取消复核、拒绝、未发出、未知结果均不会伪装成撤销成功。
2. 同一 team 的后续 PENDING nearby 行显示为“状态未确认”，清除旧申请倒计时，并使用现有 `nearby.stale` 文案要求重新核对。没有把旧 pending 当成服务器 NONE。
3. 我的申请列表只过滤屏障命中的 PENDING，不把它计为有效待申请。REJECTED 以及其他 team 不受影响。界面的隐藏不等于服务端已完成全局撤销。
4. JOINED、LEADER、REJECTED、NONE、UNKNOWN 等非 pending 源结果保留；本补丁不覆盖新的组队/成员权威事实，也不退休既有成员。
5. 同绑定内，晚到的 withdraw 成功可登记屏障、移除仍显示的 pending，但不会清掉新读的 busy 或导入已更换身份的页面。独立 bindingGeneration 区分导航与 logout/rebind，连退出后重绑完全相同的 session 值也不会接纳旧绑定回包。
6. 明确成功的新 apply 仅清除对应 team 的屏障，不影响其他 team。只有仍属当前展示 generation 的 apply 回包才写入 pending/expiry；导航后晚到的 apply 不覆盖新读的 JOINED/LEADER/其他非 pending 结果。
7. 未知结果保持既有 account-scoped unresolved lock。没有擦除 durable dispatch journal、扩大 live grants、新增服务端协议或声称跨实例保护。

## 必须保留的契约限制

现有 NearbyMyApplication 没有独立 applicationId、生命周期版本或操作收据；只有 teamId、status、expiry。expiry 不是唯一申请世代。外部设备新申请与旧 pending 缓存无法可靠区分，所以屏障命中的 pending 需要重新确认状态，不能断言是服务器终态。明确成功的本地新 apply 可以解屏障；单靠新 expiry 不会解屏障。

既有 settledActions 按 team+operation 防重，HTTP dispatch journal 也按 account/target 保留 acknowledged 记录。因此本机已 apply→withdraw 后再次 apply，或已 withdraw→apply 后再次 withdraw，仍受原有重复操作边界限制。本补丁没有单独删除本地锁以伪造完整多轮申请能力，也没有新增更严的永久防重策略。完整多轮重申请需要真实申请世代/收据与可验证的服务端契约。

屏障是易失内存，不跨协调器实例、重新绑定或 App 重启。当前模块的 joinedTeams 由既有 Team 模块提供，本补丁不重写它。服务端撤销与接受的最终并发裁决、跨设备缓存和通知一致性仍需独立接口证据与集成验收。

## 精确交错回归设计

新增 23 个 Swift XCTest，用 in-memory read/write fake 和 CheckedContinuation 控制时序，无真实网络和睡眠猜测。其中包括：

- 成功撤销→三轮旧 nearby/mine 读取；只清对应 pending，清倒计时和有效计数。
- synthetic 与 acknowledged 分开；仅 mine 来源的撤销；拒绝/未发出/未知不会建立屏障。
- 取消复核、重复 confirm、并发 duplicate confirm 只发一次；旧导航读取回来不复活。
- withdraw 悬挂→leave/resume→新读悬挂→withdraw ack→新读旧 pending：新读 busy 不被旧写清掉，返回后 pending 为未确认。
- withdraw 悬挂→leave/resume→新 mine 先回 pending→withdraw ack：移除对应 pending，不删其他行。
- withdraw 悬挂→新读 JOINED/REJECTED→withdraw ack：非 pending 保留。
- 新 apply 悬挂→leave/resume→新读 JOINED/LEADER/REJECTED/NONE→旧 apply ack：非 pending 不被降回 pending；后续 pending 读证明旧屏障已解除。
- 未知新 apply 保持锁和原撤销屏障；拒绝新 apply 不能解屏障；成功新 apply 只解自己的屏障。
- 切账号、epoch、region、namespace、logout/rebind 同值与协调器重建的边界。
- 原有 apply→withdraw→apply replay 限制明确保留，不能误报为已实现完整多轮重申请。

## 实际验证

已执行（纯离线）：

- 新补充源检查 `python3 tools/check_nearby_withdrawal_races.py`：14/14 通过。相同检查对原始源树运行得到 12 项失败，定位缺少本屏障与新回归；这是源检查前后对照，不是 Swift 行为测试。
- 既有 `check_nearby_team_module.py`：13/13 通过。
- 既有 `check_nearby_write_repair.py`：12/12 通过。二者经 unittest wrapper 合计 25 项也通过；该数字是重复执行，不额外叠加为新覆盖。
- 全部 `Tests/ContractChecks`：2211 项，46 项按已有条件跳过，执行结束为 OK。这是 Python 合同/源检查，不是 App 运行结果。
- 全部 `tools/tests`：465/465 通过，实际用时 411.847 秒。
- `git diff --check`、针对实际基线的补丁正向 dry-run 和候选上的反向 dry-run：通过。

未执行或受阻：

- 23 个新增 Swift XCTest 已写入 `Tests/CoreTests`，但实际执行为 NOT_RUN。当前 dot 云电脑没有 swift 或 xcodebuild；没有 Swift typecheck、XCTest、Xcode build、模拟器或真机结果。
- Tree-sitter preflight 受阻：缺少已锁版本的 parser dependency。该检查本身也不等于 Swift 编译。
- scaffold 未在源副本执行，因为该脚本会重新生成 PBX，本任务明确禁止修改 PBX。
- 没有生产请求、后端事务、推送、部署或完整 W16 验收。

有 Apple 工具链的独立验收可执行：

```sh
swift test --filter NearbyTeam
```

新增纯包测试由 Package.swift 的 `Tests/CoreTests` 路径发现，不需要改 PBX。本次补充 Python 脚本未接入 CI；不应把仅在本地运行的检查说成已成为 CI gate。
