# P104 参与人资料：本地校验与修正

实际基准 49c68c6420270b0a0cc7ec8d18bc8561f329d796，无前包文件叠加。
唯一总文档 P103/P104 对应 address/addressinfo。总文档“收货地址”标题不能覆盖实际 Mini 语义：pinned f859 的 addressinfo.wxml 明示用于报名联系和到场核验，不会公开、也不用于配送；仅姓名和手机号两个可见字段。默认地址 switch 已注释，不接 dormant handler。

## 缺口和交互
Mini `onSaveDisabledTap` 显示首个错误：姓名缺失优先，然后手机号；`onInputChange` / `refreshSubmitState` 在修正后重新评估。原生已有相同校验规则、保存前确认、未知结果读回锁，原先空姓名或空手机只有不可点击的保存按钮，没有解释和定位。

同一底部操作在无效输入时显示“检查填写内容”，只显示当前首个错误并聚焦该字段。修正后提示自动移到下一项或消失；有效后按钮恢复“保存参与人”，进入原有确认。确认前不会写入。键盘提交走同一入口。取消确认保留草稿；离开/重读清空本地 review 标志。

这是原生对 Mini disabledtap 的等价可访问交互，未冒充 iOS 被禁用按钮可以接收点击。原有非空无效手机的即时提示保留。只复用 ParticipantFormDraft.validation，不扩展姓名、手机号规则或归一化输入；隐藏地址/默认元数据仍按原始合同保留。

## 范围和安全
- 本地 review 仅保存一个 Bool，不缓存姓名、手机号、身份或地址，不落盘或输出日志。
- 当前 reader 身份、已加载身份、配置、coordinator 的 canPrepare 与忙碌状态共同限定检查入口。
- 无效检查、反复点击、取消均不 dispatch；有效输入只 prepare，真正写入仍需已有 confirmation。
- 本批不修改 ParticipantService、ParticipantMutationCoordinator、ProfileReading、ProfileService、AppSession、订单或报名读许可。没有真实用户资料、真实写入或权限操作。
- 普通参与人页面已有正常接线；订单/参与详情读许可阻塞与本地输入检查无关，不借用其权限。

## 接口边界（既有，不新增）
POST /api/user/address/list（空字段）→ rows；POST /api/user/address/info（id）→当前账户参与人；POST /api/user/address/action（fullName/mobilePhone 及已有隐藏元数据、编辑 id/创建 requestId）→原有回执。取消/删除/default 不在本批范围。既有 writer/session 身份门禁保持；没有新增 endpoint 或开启生产能力。

## 验收
源码检查和 exact Mini VM 用例只证明各自范围，不能替代 Swift/SwiftUI 运行。已编写 Core、App model、UI 的空表单→逐字段纠正→确认→取消/保存、重复点击、切号、失配置、未知结果锁和退出重入用例。重用已有 participants 离线 module fixture，不新增运行入口。

Apple 编译、XCTest、模拟器、真机、真实账户读取/保存：NOT_RUN（当前环境无 Swift/Apple 工具）。中央注册新 Core/测试和三条双语 key 仍需集成。
