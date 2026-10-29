# Questify iOS 工具选型只读核验（2026-10-28，America/Los_Angeles）

## 建议

主方案：保留 XCTest/XCUITest；用 agent-device 作为唯一交互执行层；一段项目自有的确定性 Node 协调器管理 Run、账号、屏障、断言和证据。MobileBuildMCP 仅给构建/诊断 Agent 使用，首期只启用构建、测试、诊断相关工具，关闭其 UI 自动化组，避免两个自动化驱动争用设备。稳定 CI 直接运行现有 xcodebuild/Swift 测试入口，不强制每次经过 AI 或 MCP。必要备用方案是直接 XCUITest + simctl；agent-device 不兼容时先用已存在测试继续推进，不立即再装另一个框架。

这是一项基于官方合同的架构判断，尚未在用户 Mac 运行任何工具兼容性实测，不构成速度或稳定性排名。

## 已核实版本与能力

| 工具 | 官方最新/本次核实 | SwiftUI、AX 与接口 | 并行和远程 | 回放/同步结论 | 决策 |
|---|---|---|---|---|---|
| agent-device | v0.21.33，2026-10-27；tag 文档与SDK示例另外核实 | 原生iOS支持；AX snapshot；CLI、stdio MCP、typed Node API | session+UDID，worktree作用域，host device claim；proxy在Mac，远程HTTP调用 | .ad确定性回放；业务屏障、账号锁、服务端断言仍自建 | 主交互层 |
| MobileBuildMCP | v2.7.1，2026-09-23；正式由XcodeBuildMCP更名 | xcodebuild封装；CLI/MCP；AXe snapshot_ui有label/id/role/frame | simulatorId；workspace daemon；未找到原生两Mac调度器或跨工具设备锁证明 | 构建/运行/测试/LLDB/日志；不负责跨账号状态机 | 主方案中限定构建诊断职责 |
| Maestro MCP/CLI | CLI 2.12.0，2026-10-26 | 原生iOS、compact hierarchy、CLI/YAML/MCP | 2.6.0已修iOS多进程，per-device锁和driver-host-port；两Mac仍需主控/SSH或服务包装 | 稳定YAML，shard是用例分发，非共享业务屏障 | 不安装；后续有大量YAML维护需求再评估 |
| Mobile MCP | 1.0.14，2026-10-26（CHANGELOG） | 原生iOS，结构化AX/坐标，MCP；依赖mobilecli/DeviceKit | device参数；自有两Mac完整lease隔离未核实；厂商Cloud不等于自托管两Mac | 主要探索工具，非本项目业务协调器 | 与agent-device重叠，不安装 |
| Mobilewright | 0.0.67，2026-10-18（官方Changelog） | TypeScript SDK/CLI、locator、自等待、expect、report | worker=一个设备，pool、shard；自有双Mac远程代理完整路径待验证 | 适合确定性套件；worker并行不是一次test同时拥有A/B/C | 不替换已有XCUITest，暂不安装 |
| Appium + XCUITest driver | 当前官方12.x driver文档活跃；未锁定Appium核心精确最新版本 | 原生iOS、page source/AX、WebDriver HTTP、多语言SDK | unique UDID/wdaLocalPort/derivedDataPath/mjpegServerPort；Mac上的server可被远程client调用 | 成熟确定性脚本；业务协调自建；WDA/driver/server多层维护成本 | 无现成Appium资产，不引入 |
| Xcode/XCTest/XCUITest/simctl | 当前用户主机26.6；Apple27文档另核实 | SwiftUI原生，XCUITest元素查询，CLI测试/结果；27新增Agent操控Simulator | 指定destination/UDID、测试并行；远程需SSH/worker | build-for-testing/test-without-building；业务屏障自建 | 必留基础；不为MCP升级Xcode |

所有工具对Canvas、地图、自定义绘制视图的语义支持都依赖App实际accessibility树。不要把“支持SwiftUI”推导为任意控件均可稳定定位。必须在城瘾导航、聊天输入、地图、游戏页跑能力探针。

## 影响实施的已验证限制

1. agent-device 的 iOS `network dump` 解析 App 日志，可能漏掉未记录请求，不是全量网络代理。日志为空不能证明未发送请求；业务读回和服务端事件须独立建立。
2. `settings airplane on/off` 当前只支持Android，不能用于本次iOS单设备断网。不得关闭整台Mac网络影响A/B或其他工作。设计每会话测试代理/测试构建transport故障注入，分别标记“真实后端+传输故障注入”和“真实设备物理断网”。恢复后继续真实后端读回。
3. 官网首页仍宣传 `replay -u` 自动修复，但 v0.21.33 的 `website/docs/docs/replay-e2e.md` 明确该flag是no-op，仅提供suggestions，不自动改.ad。采用tag文档与代码合同；任何selector更改要review并重新完整回放，不能改验收断言让测试变绿。
4. `.ad --save-script` 在远程daemon上被拒绝；首期在Mac本地记录，远程执行已审脚本/Node协调器。不得承诺云Agent随时录制远端.ad。
5. proxy默认loopback，Bearer token能控制背后的daemon；单共享token不提供每Agent安全隔离。首期由可信本地主控独占token；云AI仅提交受校验任务，或用具独立鉴权的代理包装。两Mac走已有SSH/Tailscale私网，保持loopback隧道，不公开端口。
6. 远程 `open` lease默认5分钟无命令到期（直接RPC未设ttl则1分钟）；长屏障须协调器续约并记录lease，不能靠AI持续聊天保活。设备失联后该run进入INFRA_ERROR/UNKNOWN；先收证据和核实写入结果，禁止盲目再发送。
7. agent-device claim不约束绕过它的xcodebuild/其他驱动，因此主控还需统一UDID ownership。XCUITest测试与agent-device不可同时操作同一UDID。
8. agent-device `perf frames` 不提供可信iOS Simulator hitch数据。模拟器可做趋势性启动/内存检查，耗电、真实热降频/无线网络、AR/GPS真实性、APNs和相机扫码最终仍需真机。
9. MobileBuildMCP有共享session defaults，必须显式传simulatorId，不依赖“第一个booted设备”。自有DerivedData按工具链/commit/build配置分区；重用编译产物与串行写build cache。
10. 公开chengyin-ios不应让任意PR执行个人Mac runner。GitHub官方建议自托管runner用于私有仓。保留公开仓GitHub-hosted标准CI；独立私有控制工作流/本地拉取队列执行已审核精确SHA。私有控制面仍不能使不可信被测源码变安全：编译脚本/宏依旧可执行，应只收可信SHA、限制本机权限、不给测试job生产密钥。

## 经官方核实的安装与探针命令（仅计划，未执行）

前置：Node >=22.12，macOS/Xcode可用。建议锁定release，别用每次变化的latest。

```sh
npm install -g agent-device@0.21.33
agent-device doctor
agent-device help workflow
agent-device devices --platform ios
agent-device capabilities --platform ios --udid "$SIM_A" --json
agent-device open "$APP_BUNDLE_ID" --platform ios --udid "$SIM_A" --session "$RUN_ID-A"
agent-device snapshot -i --session "$RUN_ID-A" --json
agent-device close --session "$RUN_ID-A"

npm install -g mobilebuildmcp@2.7.1
mobilebuildmcp-doctor
mobilebuildmcp simulator build --help
mobilebuildmcp simulator list --output json
```

`RUN_ID`、`SIM_A`、`APP_BUNDLE_ID`应由清单提供，不是硬编码假值。SDK项目依赖锁在测试工具package-lock，运行时使用同版本本地binary；全局CLI安装仅是官方支持的初始探针方案。

MCP通用启动是 `agent-device mcp` 和 `mobilebuildmcp mcp`，各厂商只配置自己的stdio客户端，不把Agent编排绑到某厂商。MobileBuildMCP官方另提供 `brew tap getsentry/xcodebuildmcp` + `brew install mobilebuildmcp`；若需要精确复现优先固定npm版本。Maestro官方安装支持Homebrew或安装脚本，Appium官方 `npm install -g appium` 后 `appium driver install xcuitest`；本方案不执行这些备用安装。

远端Mac上：`agent-device proxy --port 4310`。连接侧从秘密存储注入 `AGENT_DEVICE_DAEMON_AUTH_TOKEN`，运行 `agent-device connect proxy --daemon-base-url http://127.0.0.1:4310/agent-device`（此localhost必须是已建立的私有隧道出口）。不要把token放命令参数、报告或仓库。每Mac独立proxy profile/端口与显式UDID。

SDK已核实的最小语法（不是城瘾测试已实现）：

```ts
import { createAgentDeviceClient } from 'agent-device';
const a = createAgentDeviceClient({
  session: `${runId}-A`, lockPolicy: 'reject', lockPlatform: 'ios'
});
await a.apps.open({ app: bundleId, platform: 'ios', udid: leasedUDID });
const snapshot = await a.capture.snapshot({ interactiveOnly: true });
// 从本次snapshot中按已审查的accessibilityIdentifier定位唯一节点。
// press/fill/wait并不能代替业务API断言；多设备屏障由项目协调器提供。
await a.sessions.close();
```

## 官方证据目录（给主控引用）

- agent-device release v0.21.33: https://github.com/callstack/agent-device/releases/tag/v0.21.33 — web ref turn3view1。
- agent-device README: https://github.com/callstack/agent-device/blob/main/README.md — turn5view2；Native/SwiftUI基础、CLI/MCP/Node、Node22.12、session claim。
- 版本SDK示例: https://github.com/callstack/agent-device/blob/v0.21.33/examples/sdk/client-session.ts — GitHub connector直接读到 `lockPolicy`、`lockPlatform`、`udid`、snapshot语法。
- 版本回放文档: https://github.com/callstack/agent-device/blob/v0.21.33/website/docs/docs/replay-e2e.md — GitHub connector核实no-op和远程录制限制；当前页面 https://agent-device.dev/docs/replay-e2e — turn6view6 / turn7view5。
- 版本会话文档: https://github.com/callstack/agent-device/blob/v0.21.33/website/docs/docs/sessions.md — connector核实。
- Remote Proxy: https://agent-device.dev/docs/remote-proxy — turn6view3 / turn7view0 / turn7view1。
- Commands: https://github.com/callstack/agent-device/blob/main/website/docs/docs/commands.md — turn2view2 / turn4view4 / turn4view5 / turn4view6，iOS network与airplane/perf限制。
- Node API: https://agent-device.dev/docs/client-api — turn6view4 / turn11view0。
- MobileBuildMCP v2.7.1: https://github.com/getsentry/MobileBuildMCP/releases/tag/v2.7.1 — turn3view2，更名与env/testRunnerEnv输入改为key/value数组。
- 安装 https://www.mobilebuildmcp.com/docs/installation — turn2view3；CLI https://www.mobilebuildmcp.com/docs/cli — turn2view4；配置 https://www.mobilebuildmcp.com/docs/configuration — turn12view1；AX https://www.mobilebuildmcp.com/docs/demos — turn14view1；工具 https://www.mobilebuildmcp.com/docs/tools — turn13view0。
- Maestro release https://github.com/mobile-dev-inc/Maestro/releases/tag/cli-2.12.0 — turn8view2；MCP https://docs.maestro.dev/get-started/maestro-mcp — turn6view0；iOS并行修复 https://maestro.dev/blog/maestro-cli-v2-6-0 — turn8view1；安装 https://docs.maestro.dev/maestro-cli/how-to-install-maestro-cli — turn8view0。
- Mobile MCP https://github.com/mobile-next/mobile-mcp — turn1search6；版本 https://github.com/mobile-next/mobile-mcp/blob/main/CHANGELOG.md — turn1search7。
- Mobilewright https://mobilewright.dev/docs/ — turn6view1；并行 https://mobilewright.dev/docs/test/parallelism — turn11view1；版本 https://mobilewright.dev/docs/changelog — turn11view2。
- Appium install https://appium.io/docs/en/latest/quickstart/install/ — turn9view0；并行 https://appium.github.io/appium-xcuitest-driver/latest/guides/parallel-tests/ — turn9view1；driver安装 https://appium.github.io/appium-xcuitest-driver/12.15/getting-started/installation/ — turn13search3。
- Apple build/testing https://developer.apple.com/library/archive/technotes/tn2339/_index.html — turn11view3；Xcode27 Agent能力 https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes?changes=l_2_3&language=objc — turn13search0，当前主机不是27，不建议因此升级。
- GitHub自托管安全 https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners — turn12view3；workflow不可信代码 https://docs.github.com/en/actions/reference/security/secure-use — turn9view2。

未经实测：工具在用户macOS26.6.1/Xcode26.6上的AX/交互稳定性、双模拟器资源阈值、两Mac连接、第三方核心Appium精确最新版本。均不得写为通过。
