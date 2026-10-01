# 城瘾原生 iOS 迁移覆盖核对

核对日期：2026-10-01 UTC。只读检查保留的源代码；没有连接业务后端，也没有重新验证远端 CI。

## 阅读口径：下文为固定历史快照

下方“6 个 View、3 条部分 UI、126 条无 UI”等数字只描述原生提交 `a17b4ff`（2026-10-01 11:05 UTC），不是当前迁移分支状态。保留它们用于审计追踪，不应继续用于汇报剩余量。源代码分母仍固定为 Flutter `a63e9e9`；当前分支更新看 `PROGRESS.md` 和各模块文档。

截至原生 `b596b6b`，已追加发现/模板、个人订单/参与人/徽章、商家权限后台、俱乐部浏览与加入退出、手动区域漫游、消息历史与文本发送、手机号登录、参与人编辑、活动任务与报名表单等部分能力。479 项领域测试及两种无签名构建已通过；该提交模拟器测试仍待结果。商家申请代码是此后的未验收批次。

这些增量不能直接换算成完成页面数：支付、区域身份适配、完整业务端到端、真机与逐状态视觉验收仍没有完成证据。报名创建、Apple 登录和真实玩法提交仍有生产门禁，未连接已批准的隔离测试后端。

## 历史快照结论

**整体仍处于基础能力和第一个活动只读切片阶段，绝大多数业务尚未迁移。当前不能称为“已迁完 7 页，剩 121 页”，也没有依据给出按工作量计算的百分比。**

- 正常生产导航下有 **6 个屏幕级 SwiftUI View**：入口、登录、语言设置、基础账号、活动列表、活动详情
- 这 6 个 View 只对应 **5 个已有 Flutter 页面承载件的部分能力**：入口和登录共同对应原 LoginPage 的不同状态；其余为 SettingsPage、ProfilePage、ActivityListPage、ActivityDetailPage
- **完整源页面/业务闭环对等完成数：本次没有发现可认定完成的条目**。已经实现的代码和已通过的测试有价值，但不能据此把整个原页面标为完成
- 报名有模型、网络服务和内存协调器；还没有报名表单、用户同意、支付、结果确认的完整原生闭环
- 原生扫码组件已存在，但正常生产导航还没有接入；不能算商家核销/游玩扫码完成

## 分母先核准

| 指标 | 当前保留源代码中的实际数量 | 可以说明什么 |
|---|---:|---|
| 小程序主映射条目 | **130** | 小程序 → Flutter 的历史承载关系；不是原生页面数 |
| 追加 App 拆分路由条目 | **6** | 与上述小程序页面重复关联的独立 App 子路由 |
| manifest 总行数 | **136** | 124 route + 5 component + 1 system + 6 appRoute |
| Flutter 路由声明 | **178** | 源代码 path 声明；含别名、带参和嵌套路由，不等于独立页面 |
| Flutter feature 目录 | **36** | 组织模块的目录数量，含支持性目录 |
| `*_page.dart` 文件 | **172** | 文件名口径；不含 `team_pages.dart` 等其他命名，也不等于页面数 |
| 视觉/状态台账条目 | **当前无法核实** | 所引用的 `tool/visual_parity/pairs.json` 不在这份保留 checkout 中 |

`tool/page_parity.py` 在第 324–338 行保留了历史：曾是 129，后为 128，2026-09-22 又加入/恢复页面，当前常量是 `EXPECTED_XCX_PAGE_COUNT = 130`。manifest 确认正好有 130 个不同 `miniPage`。

所以 128/129 是历史口径。脚本中的旧“292 状态”等叙述，或者历史提到的 293 状态，不能作为当前已逐条核实的原生验收分母。本次未读取或推定小程序/私有后端的实时 master；130 只代表本次固定 Flutter 快照中的映射基线。

## 对这 130 条主映射逐条归类

| 原生覆盖级别 | 数量 | 具体条目 |
|---|---:|---|
| 完整源页面/业务能力对等 | **0** | 没有足够证据认定完整迁移 |
| 已有部分原生 UI | **3** | `pages/member/index/index`、`pages/shezhi/shezhi`、`pages/activity/detail/index` |
| 只有领域/服务基础代码，未接 UI | **1** | `pages/activity/baoming/baoming` |
| 没有对应原生 UI | **126** | 其余主映射，包括 1 条系统承载裁剪项 |

这不是“完成率”。原生登录、入口、普通活动列表不在该小程序主映射表的独立条目中；同一源页可能拆成多个 View，而一个 View 也只覆盖原页一部分。126 条中也有应由系统能力承载或需要合并的条目，不是必须照造 126 张屏幕。额外 6 条 App 子路由（俱乐部流/排行榜/期次/解散阻塞、票详情、通行码）均没有对应原生业务 UI。

## 已有原生屏幕的真实边界

| 原生屏幕 | 源代码对照 | 目前已有 | 主要缺口 |
|---|---|---|---|
| WelcomeView | auth/LoginPage 的意向选择状态 | 玩家/商家意向入口、设置入口 | 创建新账号和后续身份审批未实现；不是 `DoorEntryPage` 门口码冷启动解析 |
| LoginView | auth/LoginPage / phone_login_sheet | 既有账号密码、取消、错误/未配置阻断 | 手机号/验证码、Apple/微信、完整授权同意/注册和真实后端验收 |
| SettingsView | settings/SettingsPage | 跟随系统/中文/英文的保存选择 | 关于、隐私/定位、声音触感、注销、其他业务入口 |
| AccountView | profile/ProfilePage | 服务端身份基本字段、角色、退出确认、设置 | 完整个人主页、订单/项目/资产/成就、资料编辑和商家档案 |
| ActivityBrowserView | activity/ActivityListPage | 搜索、分页、去重、刷新、加载/空/失败/重试 | 源页的时间状态分段、我的报名、官方活动入口、封面等；不是原首页 Feed |
| ActivityDetailView | activity/ActivityDetailPage | 名称/描述/日期/地点、有效坐标地图、票种价格/库存、俱乐部门槛 | 票种选择、报价/报名、支付、候补、评论/互动、主办方操作、丰富内容 |

另外，源 Flutter 路由明确允许游客浏览活动等公开页面，而当前原生 `SessionRootView` 仅在已有 account 时显示 Activities/Account 两个 Tab；游客浏览、深链落地和登录后回到原目标也仍需迁移。

特别注意：小程序 `pages/activity/list/index` 的主映射是 `official/OfficialEventsPage`（官方活动），不是普通 `ActivityListPage`。因此不能把新原生普通活动列表也登记成“官方活动已迁移”。

## 模块明细

“主映射”按 manifest 中 source 文件的 Flutter feature 目录归属，每个小程序页面只计一次；6 个 appRoute 不重复计入。路由列按各 route 的实际业务页面类归属，别名仍分别计数。“无对应 UI”不否认共享基础代码，只是不把它等同于模块可用。

| Flutter 模块 | 主映射页 | 路由声明 | `*_page.dart` | 原生覆盖 |
|---|---:|---:|---:|---|
| `account` | 8 | 11 | 10 | 无对应原生业务 UI |
| `activity` | 2 | 2 | 2 | 部分 UI：列表、只读详情；报名仅契约/服务/协调器，尚未接入 UI |
| `assets` | 1 | 1 | 1 | 无对应原生业务 UI |
| `auth` | 0 | 2 | 2 | 部分 UI：WelcomeView + LoginView；既有账号密码登录；新账号、手机号/短信、Apple/微信和完整同意链路待迁 |
| `club` | 19 | 23 | 23 | 无对应业务 UI；详情的会员门槛提示不等于俱乐部页 |
| `coop` | 8 | 12 | 11 | 无对应原生业务 UI |
| `coupon` | 4 | 3 | 3 | 无对应原生业务 UI |
| `creator` | 0 | 1 | 1 | 无对应原生业务 UI |
| `feed` | 1 | 1 | 1 | 无对应原生业务 UI |
| `im` | 2 | 2 | 2 | 无对应原生业务 UI |
| `legal` | 2 | 1 | 1 | 无对应原生业务 UI |
| `mall` | 0 | 3 | 3 | 无对应原生业务 UI |
| `map` | 0 | 1 | 1 | 无独立地图页；活动详情中有 MapKit 位置块，不能抵扣本模块 |
| `merchant` | 26 | 48 | 44 | 无对应业务 UI；商家入口意向和账号角色显示不等于商家工作台 |
| `npc` | 0 | 0 | 0 | 无对应原生业务 UI |
| `official` | 4 | 5 | 5 | 无对应原生业务 UI |
| `orders` | 2 | 1 | 1 | 无对应原生业务 UI |
| `p3` | 4 | 5 | 5 | 无对应原生业务 UI |
| `participation` | 2 | 1 | 1 | 无对应原生业务 UI |
| `payment` | 0 | 0 | 0 | 无支付 UI/SDK 执行；报名报价/原始状态代码不能证明支付完成 |
| `play` | 3 | 6 | 12 | 无对应原生业务 UI |
| `points` | 0 | 1 | 1 | 无对应原生业务 UI |
| `prefab` | 1 | 1 | 1 | 无对应原生业务 UI |
| `profile` | 3 | 4 | 3 | 部分 UI：AccountView 仅基础账号资料、角色和退出；个人主页业务、编辑资料等待迁 |
| `publish` | 6 | 5 | 5 | 无对应原生业务 UI |
| `publisher` | 0 | 0 | 0 | 无对应原生业务 UI |
| `roam` | 9 | 10 | 9 | 无对应原生业务 UI |
| `search` | 3 | 3 | 3 | 无对应原生业务 UI |
| `settings` | 2 | 2 | 2 | 部分 UI：语言选择；完整设置菜单、关于、声音触感、隐私等待迁 |
| `shell` | 0 | 0 | 0 | 有新建两 Tab 容器；原玩家/商家主导航未迁 |
| `square` | 2 | 5 | 5 | 无对应原生业务 UI |
| `team` | 2 | 3 | 1 | 无对应原生业务 UI |
| `template` | 5 | 7 | 5 | 无对应原生业务 UI |
| `tickets` | 1 | 3 | 3 | 无票夹/票详情/通行核销码 UI；活动详情票种价格不等于持有票券 |
| `topic` | 3 | 3 | 3 | 无对应原生业务 UI |
| `withdrawal` | 4 | 2 | 2 | 无对应原生业务 UI |
| 系统承载 crop | 1 | 0 | 0 | 无已接入原生选图/裁剪业务证据；不要求复制独立页面 |
| 合计 | **130** | **178** | **172** | 所有模块仍有未迁范围 |

## 还剩的工作，按能交付的结果排序

1. **完成第一条活动交易闭环**：选票 → 参与人/同意 → 报价确认 → 报名创建 → 已知订单状态读取 → 支付/失败/未知结果恢复；补受保护的跨重启幂等记录和真实服务验证。当前协调器明确只有内存记录，重启后不能据此保证不重复下单
2. **补身份和完整用户入口**：真正新账号注册、需要的第三方/手机号登录、原玩家/商家主导航、完整设置和个人中心；不能把“选择商家”当作商家权限已获得
3. **玩家内容和游玩**：首页、搜索、官方活动、模板/广场、漫游/定位、游玩/签到/地理围栏、组队、成长/资产/票券
4. **商家与俱乐部**：入驻/审核、发布、库存定价、合作/邀请、客户/权限、票券核销、账单/退款状态、俱乐部运营和治理。商家目录有 48 条源路由、俱乐部有 23 条；目前均没有对应原生业务 UI
5. **剩余沟通、创作和交易能力**：IM 发送/失败/重试、发布/编辑/草稿/附件、协作、商城、优惠券、积分等；补深链和通知恢复
6. **交付验收**：逐场景视觉/状态对照、文案翻译、人机无障碍、真机相机/定位、受控测试账号与后端、隐私/法务/素材授权、签名和分发。现在没有可证明全业务等价或可上架的依据

页面复杂度差异很大：一个玩法或报名页的状态机/失败恢复远重于一个静态设置项，因此这些数量也不能直接换算工期。

## 测试证据与实现范围分开看

- 保留的 `PROGRESS.md` 明确记录 **1860c28** 的 run 36848589415：94 个 Swift 单元测试、6 个 Python 测试、9 个模拟器 UI 测试、无签名 Debug/Release 构建与 Gitleaks 通过
- 9 个 UI 测试是 5 个入口/语言/取消/未配置/扫描器不支持状态，加 4 个离线活动场景；没有真实账号、真实业务数据、相机识别或支付成功的证明
- 当前检查代码 HEAD 已到 **a17b4ff**，新增报名协调器及 21 个合成 XCTest 场景。测试代码存在不等于此 HEAD 已通过。后续核验 run 36851561783：代码测试与两种编译通过，9 项 UI 中 8 项通过、搜索框定位 1 项超时；不能把 1860c28 的结果无条件写成 a17b4ff 的完整通过结果
- 报名服务/协调器未从 App 页面接入；`ActivityDetailView` 显式显示报名尚未开放，UI 测试也断言详情无订票/付款操作
- 真实 API 默认仍未配置。静态实现、模拟器离线测试和真实用户业务验收是三种不同证据

## 固定源版本和复核依据

- Flutter：`a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`
- Native iOS：`a17b4ff40fa4f75a12f21c76f0f10f89232f5c36`
- 本次未修改两个仓库；只在仓库之外生成报告及计数明细
- 同目录 `migration-coverage-data.json` 含 130 条主映射的分类、6 条附加映射、178 条路由/源文件/行号和下列源文件 SHA-256，可逐项复核

- Flutter: `tool/page_parity_manifest.json`
- Flutter: `tool/page_parity.py`
- Flutter: `tool/migration_plan.py`
- Flutter: `lib/core/router/app_router.dart`
- Flutter: `lib/feature/auth/login_page.dart`
- Flutter: `lib/feature/account/door_entry_page.dart`
- Flutter: `lib/feature/settings/settings_page.dart`
- Flutter: `lib/feature/profile/profile_page.dart`
- Flutter: `lib/feature/activity/activity_list_page.dart`
- Flutter: `lib/feature/activity/activity_detail_page.dart`
- Native: `App/QuestifyApp.swift`
- Native: `App/WelcomeView.swift`
- Native: `App/LoginView.swift`
- Native: `App/SettingsView.swift`
- Native: `App/AccountView.swift`
- Native: `App/ActivityBrowserView.swift`
- Native: `App/ActivityDetailView.swift`
- Native: `App/NativeQRScanner.swift`
- Native: `Core/RegistrationContracts.swift`
- Native: `Core/RegistrationService.swift`
- Native: `Core/RegistrationCoordinator.swift`
- Native: `docs/registration-coordinator.md`
- Native: `docs/source-inventory.json`
- Native: `PROGRESS.md`
