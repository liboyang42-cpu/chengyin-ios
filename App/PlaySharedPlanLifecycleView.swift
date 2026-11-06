import SwiftUI

@MainActor struct PlaySharedPlanLifecycleView: View {
    @Bindable var model: PlaySharedPlanLifecycle
    var operationDestination: (PlaySharedPlanLifecycle, PlaySharedPlanOperationTicket) -> AnyView? = { _, _ in nil }
    @State private var selectedEnding: String?
    @State private var quantities: [String: String] = [:]
    @State private var acceptance = Set<String>()
    @State private var acceptanceDirty = false
    @State private var offered: PlaySharedPlanReview?
    @State private var shownOperation: PlaySharedPlanOperationTicket?
    private let rowActions: [PlaySharedPlanAction] = [.propose, .withdraw, .vote, .consensus, .confirm, .start, .cancel, .execute]
    private let globalActions: [PlaySharedPlanAction] = [.openVote, .nextVote, .change, .rejectAll]
    var body: some View {
        Form {
            Section("当前原场次与表决") {
                if let p = model.projection {
                    Text("活动 \(p.team.activityID) · 场次 \(p.team.sessionID) · 本队 \(p.team.teamID)")
                    Text("版本 \(p.team.revision) · 权限代次 \(p.team.authorityEpoch) · 原票轮 \(p.round)").font(.caption)
                    Text(p.team.captain ? "当前真实队长" : "当前队员只读，不能替队长签署")
                    Text("\(policy(p.policy)) · \(phase(p.phase))")
                    if !p.team.writable { Text("当前原状态不允许新签署；可读取当前状态和本人原回执。").font(.caption) }
                } else { Text("尚未确认当前本队与原方案。") }
                if model.busy { ProgressView() }
                if let message = model.message { Text(message).accessibilityIdentifier("sharedPlan.message") }
                Button(model.pending == nil ? "刷新当前原状态" : "核对同一原请求回执") { reset(); Task { await model.load() } }
                    .disabled(model.busy || !model.isCurrent).accessibilityIdentifier("sharedPlan.refresh")
                if !model.writesEnabled { Text("原 PLAYER 写能力／command 端点未批准或已撤销，当前只读。").font(.caption) }
            }
            if let command = model.pending {
                Section("待确认原命令") {
                    Text(command.action.title); Text(command.requestID).font(.caption.monospaced())
                    Text("原本队 \(command.identity.teamID) · 原版本 \(command.revision) · 原权限代次 \(command.authorityEpoch) · 原票轮 \(command.identity.round)").font(.caption)
                    Text("UNKNOWN 不是失败。离页、重启后仍核对同一请求；不换 ID、不重发，也不把当前选定或库存当作原请求成功。")
                }
            }
            if let receipt = model.receipt {
                Section("本次原回执") {
                    Text("\(receipt.action.title) · \(receipt.outcome) · 回执 \(receipt.receiptID)")
                    Text(receipt.requestID).font(.caption.monospaced())
                    if let reason = receipt.reason { Text(reason) }
                    if receipt.outcome == "APPLIED", receipt.action == .execute { result(receipt.result["result"], label: "本次原执行结果") }
                    else { Text("本次动作的回执与下方最新状态分开；意向、选定或锁定不代表执行完成。").font(.caption) }
                }
            }
            if let p = model.projection {
                Section("本队物资与原锁定") {
                    ForEach(p.team.items) { item in
                        LabeledContent(item.name, value: "可用 \(item.available.map(String.init) ?? "未发布") · 锁定 \(item.locked.map(String.init) ?? "未发布")")
                    }
                    Text("锁定仍计入背包负重；方案锁与交易锁不混用。不展示他队私有意向或臆造库存。").font(.caption)
                }
                Section("当前共同方案") {
                    ForEach(p.rows) { row in
                        Button {
                            model.invalidateReview(); selectedEnding = row.endingKey
                            quantities = Dictionary(uniqueKeysWithValues: row.cost.map { cost in (cost.itemID, String(row.ownIntent.first { $0.itemID == cost.itemID }?.quantity ?? 0)) })
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                Text(row.title).font(Theme.Font.cardTitle)
                                if row.selected { Label("已选定，尚须核对执行状态", systemImage: "checkmark.seal").font(.footnote) }
                                Text(row.summary).font(.subheadline).foregroundStyle(.secondary)
                                Text("需求：" + amounts(row.cost, p)).font(.footnote)
                                Text(row.conditionsMet ? "原公共前置已满足" : "原公共前置尚未满足").font(.footnote).foregroundStyle(.secondary)
                            }.modifier(SharedPlanSelectionMark(selected: selectedEnding == row.endingKey))
                        }.disabled(model.busy || model.pending != nil).accessibilityIdentifier("sharedPlan.row.\(row.endingKey)")
                    }
                    if p.rows.isEmpty { Text("当前原视图没有共同方案。") }
                }
                if let row = p.rows.first(where: { $0.endingKey == selectedEnding }) {
                    Section(row.title) {
                        if let proposal = row.proposalKey { Text("原提案 \(proposal) · 版本 \(row.version ?? 0)").font(.caption) }
                        Text("本队私有意向：" + amounts(row.ownIntent, p))
                        Text(row.ownConfirmed ? "本队当前队长已确认托管" : row.signatureCurrent ? "本队当前队长已签署意向，尚未托管" : row.ownIntent.isEmpty ? "尚无本队投入意向" : "队长已变更，旧意向签名无效，须改案后重新签署")
                        ForEach(row.confirmed.keys.sorted(), id: \.self) { team in Text("原公开托管 · 队伍 \(team)：" + amounts(row.confirmed[team] ?? [], p)).font(.caption) }
                        if let reason = row.reason { Text("原状态：\(reason)").font(.caption) }
                        if p.allows(.intent, row: row) {
                            ForEach(row.cost, id: \.itemID) { cost in
                                LabeledContent {
                                    TextField("0–999", text: Binding(
                                        get: { quantities[cost.itemID] ?? "0" }, set: { quantities[cost.itemID] = $0; model.invalidateReview() }))
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                        .accessibilityLabel(Text(name(cost.itemID, p) + "，本队投入数量"))
                                        .disabled(!model.canInteract || !model.writesEnabled)
                                } label: {
                                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                                        Text(name(cost.itemID, p))
                                        Text("需求 \(cost.quantity)").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Button(PlaySharedPlanAction.intent.title) { prepare(.intent, row: row) }.disabled(!enabled(.intent, p, row))
                            Text("0–999 整数；全零表示清空本队意向，不等于撤回整个提案。").font(.caption)
                        }
                        ForEach(rowActions) { action in
                            if p.allows(action, row: row) {
                                Button(action.title) { prepare(action, row: row) }.disabled(!enabled(action, p, row))
                                    .accessibilityIdentifier("sharedPlan.action.\(action.rawValue)")
                            }
                        }
                        if row.started, let node = row.operationNodeID {
                            Button("进入原操作题组 · 节点 \(node)") { Task { await model.prepareOperation(endingKey: row.endingKey) } }
                                .disabled(!model.canInteract || !model.writesEnabled || !p.team.writable).accessibilityIdentifier("sharedPlan.operation")
                            Text("使用已开始的真实 PLAN 实例及原高级玩法；题组 PASS、费用和结算仍由原 writer 决定。").font(.caption)
                        }
                    }
                }
                Section("本队签名与当前票轮") {
                    if p.ownVote != .null { Text("本队首选：" + planName(p.ownVote["planKey"].text ?? "", p)); Text(signature(p.ownVote)) }
                    if p.ownAcceptance != .null {
                        Text("本队接受：" + acceptanceText(p))
                        Text(signature(p.ownAcceptance))
                    }
                    if let vote = p.consensus[String(p.team.teamID)].text { Text("原公开共识票：" + planName(vote, p)); Text("当前签名效力与是否选定仍以原阶段及可用动作为准。").font(.caption) }
                    if p.ownRejectedAll { Text("本队当前队长已签署拒绝全部当前范围内方案。") }
                    ForEach(globalActions) { action in
                        if p.allows(action) { Button(action.title) { prepare(action) }.disabled(!enabled(action, p)) }
                    }
                    if p.allows(.vote) { Button("本轮不选任何方案（REJECT）") { prepare(.vote) }.disabled(!enabled(.vote, p)) }
                    if p.allows(.accept) {
                        Text("可选择多个，也可不接受任何方案；提交时由当前队长重新签署。")
                        ForEach(p.rows.filter { $0.proposalKey != nil }) { row in
                            Toggle(row.title, isOn: Binding(get: { acceptance.contains(row.proposalKey!) }, set: { value in
                                if value { acceptance.insert(row.proposalKey!) } else { acceptance.remove(row.proposalKey!) }; acceptanceDirty = true; model.invalidateReview()
                            })).disabled(!enabled(.accept, p, row))
                        }
                        Button("核对并签署接受清单") { prepare(.accept) }.disabled(!enabled(.accept, p))
                    }
                }
                if p.result != .null { Section("最新原公共结果") { result(p.result, label: "原结果") } }
            }
        }
        .modifier(SharedPlanFormAppearance())
        .privacySensitive()
        .task { await model.load() }
        .onChange(of: model.review) { _, value in offered = value }
        .onChange(of: model.operationTicket) { _, value in shownOperation = value }
        .onChange(of: model.projection) { previous, next in
            if previous?.round != next?.round || !acceptanceDirty {
                acceptance = Set((next?.ownAcceptance["planKeys"].array ?? []).compactMap(\.text)); acceptanceDirty = false
            }
            if previous?.round != next?.round { model.invalidateReview() }
        }
        .sheet(item: $offered, onDismiss: { model.invalidateReview() }) { review in
            NavigationStack {
                Form {
                    Section(review.command.action.title) {
                        Text(review.title); Text(review.command.action.consequence)
                        Text("本队 \(review.command.identity.teamID) · 票轮 \(review.command.identity.round) · 版本 \(review.command.revision)")
                        reviewChoices(review)
                        DisclosureGroup("原请求字段详情") {
                            Text(json(review.command.payload)).font(.footnote.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("确认前再次读取原队长、权限、版本与状态；变化则本次确认失效。")
                    }
                    Button("确认：" + review.command.action.title, role: [.withdraw, .change, .rejectAll, .cancel].contains(review.command.action) ? .destructive : nil) {
                        Task { await model.commit(review); offered = nil }
                    }.buttonStyle(.borderedProminent).disabled(!model.canInteract || !model.writesEnabled || model.review != review)
                }.modifier(SharedPlanFormAppearance()).navigationTitle("核对原动作").interactiveDismissDisabled(model.busy)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { offered = nil } } }
            }
        }
        .sheet(item: $shownOperation, onDismiss: { Task { await model.closeOperation() } }) { ticket in
            PlaySharedPlanOperationSurface(model: model, ticket: ticket, makeDestination: operationDestination)
        }
    }
    private func enabled(_ action: PlaySharedPlanAction, _ p: PlaySharedPlanProjection, _ row: PlaySharedPlanRow? = nil) -> Bool { model.canInteract && model.writesEnabled && p.allows(action, row: row) }
    private func prepare(_ action: PlaySharedPlanAction, row: PlaySharedPlanRow? = nil) {
        let funding = quantities, accepted = acceptance
        Task { await model.prepare(action, endingKey: row?.endingKey, quantities: funding, acceptance: accepted) }
    }
    private func reset() { selectedEnding = nil; quantities = [:]; acceptance = []; acceptanceDirty = false; offered = nil; model.invalidateReview() }
    @ViewBuilder private func reviewChoices(_ review: PlaySharedPlanReview) -> some View {
        let payload = review.command.payload
        if let key = payload["proposalKey"].text {
            LabeledContent("本次方案", value: planName(key, review.source)).fixedSize(horizontal: false, vertical: true)
        }
        if let choices = payload["proposalKeys"].array {
            Text(choices.isEmpty ? "本次不接受任何方案" : "本次接受：" + choices.compactMap(\.text).map { planName($0, review.source) }.joined(separator: "、"))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let amounts = payload["amounts"].array {
            if amounts.isEmpty { Text("本次清空本队投入意向。") }
            ForEach(Array(amounts.enumerated()), id: \.offset) { _, row in
                if let item = row["itemId"].text, let quantity = row["quantity"].integer {
                    LabeledContent(name(item, review.source), value: "×\(quantity)").monospacedDigit()
                }
            }
        }
    }
    private func name(_ id: String, _ p: PlaySharedPlanProjection) -> String { p.team.items.first { $0.id == id }?.name ?? id }
    private func amounts(_ values: [PlaySharedPlanAmount], _ p: PlaySharedPlanProjection) -> String { values.isEmpty ? "无" : values.map { "\(name($0.itemID, p)) × \($0.quantity)" }.joined(separator: "、") }
    private func planName(_ key: String, _ p: PlaySharedPlanProjection) -> String { key == "REJECT" ? "本轮不选任何方案" : p.rows.first { $0.proposalKey == key }?.title ?? key }
    private func acceptanceText(_ p: PlaySharedPlanProjection) -> String {
        let keys = (p.ownAcceptance["planKeys"].array ?? []).compactMap(\.text)
        return keys.isEmpty ? "不接受任何方案" : keys.map { planName($0, p) }.joined(separator: "、")
    }
    private func signature(_ value: PlayWireValue) -> String { value["ownSignatureCurrent"].bool == true ? "当前队长已签署" : "队长已变更，须重新签署" }
    private func phase(_ value: String) -> String { ["FUNDING": "讨论与投入", "VOTING": "首选表决", "TIED": "等待重投", "ACCEPTANCE": "接受方案轮", "CONSENSUS": "共识表决", "SELECTED": "方案已选定", "EXECUTED": "操作已执行", "FALLBACK": "默认结局收尾"][value] ?? value }
    private func policy(_ value: String) -> String { ["MAJORITY": "多数通过", "UNANIMOUS": "全体同意", "MAJORITY_ACCEPTANCE": "多数通过 · 接受轮恢复"][value] ?? "原策略未确认" }
    @ViewBuilder private func result(_ value: PlayWireValue, label: String) -> some View {
        Text(value["title"].text ?? label); Text(value["summary"].text ?? "")
        Text(value["terminal"].bool == true ? "本场原结局已确认" : "原共同操作已完成，继续剧情")
    }
    private func json(_ value: PlayWireValue) -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "原内容不可读取" }
}
@MainActor private struct PlaySharedPlanOperationSurface: View {
    let model: PlaySharedPlanLifecycle
    let ticket: PlaySharedPlanOperationTicket
    let makeDestination: (PlaySharedPlanLifecycle, PlaySharedPlanOperationTicket) -> AnyView?
    @Environment(\.dismiss) private var dismiss
    @State private var destination: AnyView?
    var body: some View {
        NavigationStack {
            Group {
                if model.operationIsCurrent(ticket), let destination { destination }
                else { ContentUnavailableView("当前原方案题组不可用", systemImage: "lock", description: Text("需当前真实操作实例、节点与既有高级玩法权限；过期实例不能提交。")) }
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回并回读原方案") { dismiss() } } }
        }.task {
            do { try await model.validateOperation(ticket); guard !Task.isCancelled else { return }; destination = makeDestination(model, ticket) }
            catch { destination = nil }
        }
    }
}

/// G04 content appearance only. Native Form/List rows, navigation and disabled
/// controls keep their system behavior; no authority or lifecycle is supplied here.
private struct SharedPlanFormAppearance: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .tint(Theme.Color.accent(in: domain))
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: domain))
    }
}

private struct SharedPlanSelectionMark: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
