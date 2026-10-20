import SwiftUI
import QuestifyCore

/// Self-contained safety row for `G-W04` Scene AI guard and `I08` NPC chat deletion fence status.
public struct NPCSceneAISafetyRow: Identifiable, Equatable, Sendable {
    public let guardID: String
    public let title: String
    public let detail: String
    public let isEnforced: Bool

    public var id: String { guardID }

    public init(
        guardID: String,
        title: String,
        detail: String,
        isEnforced: Bool
    ) {
        self.guardID = guardID
        self.title = title
        self.detail = detail
        self.isEnforced = isEnforced
    }
}

/// Self-contained snapshot for `G-W04` Scene AI guard (default non-generative kill switch,
/// scope isolation, narrative action whitelist) and `I08` NPC chat deletion re-read fence.
public struct NPCChatAndSceneAISafetySnapshot: Equatable, Sendable {
    public static let canonicalGuardIDs: [String] = [
        "SceneAIKillSwitch",
        "SceneAIScopeIsolation",
        "NPCNarrativeEffectWhitelist",
        "NPCChatDeletionFence"
    ]

    public let globalGenerationEnabled: Bool
    public let streamingDisplayAllowed: Bool
    public let enforcesScopeEchoAndIsolation: Bool
    public let dropsForbiddenBusinessEffects: Bool
    public let enforcesNPCChatDeletionReReadFence: Bool
    public let rows: [NPCSceneAISafetyRow]

    public init(
        globalGenerationEnabled: Bool = false,
        streamingDisplayAllowed: Bool = false,
        enforcesScopeEchoAndIsolation: Bool = true,
        dropsForbiddenBusinessEffects: Bool = true,
        enforcesNPCChatDeletionReReadFence: Bool = true,
        customRows: [NPCSceneAISafetyRow]? = nil
    ) {
        self.globalGenerationEnabled = globalGenerationEnabled
        self.streamingDisplayAllowed = streamingDisplayAllowed
        self.enforcesScopeEchoAndIsolation = enforcesScopeEchoAndIsolation
        self.dropsForbiddenBusinessEffects = dropsForbiddenBusinessEffects
        self.enforcesNPCChatDeletionReReadFence = enforcesNPCChatDeletionReReadFence

        let killSwitchCompliant = !globalGenerationEnabled && !streamingDisplayAllowed
        if let customRows {
            self.rows = customRows
        } else {
            self.rows = [
                NPCSceneAISafetyRow(
                    guardID: "SceneAIKillSwitch",
                    title: "G-W04 生成式总闸与流式开关",
                    detail: killSwitchCompliant
                        ? "默认非生成式兜底已生效 · 流式输出已关闭"
                        : "生成式开关或流式展示未处于默认关闭状态",
                    isEnforced: killSwitchCompliant
                ),
                NPCSceneAISafetyRow(
                    guardID: "SceneAIScopeIsolation",
                    title: "G-W04 场景作用域与审计回显隔离",
                    detail: enforcesScopeEchoAndIsolation
                        ? "跨主题/跨场次/跨门店隔离键与审计回显校验已启用"
                        : "缺少作用域隔离键或审计版本回显校验",
                    isEnforced: enforcesScopeEchoAndIsolation
                ),
                NPCSceneAISafetyRow(
                    guardID: "NPCNarrativeEffectWhitelist",
                    title: "G-W04 叙事动作白名单与禁区拦截",
                    detail: dropsForbiddenBusinessEffects
                        ? "发奖、扣库存、改价、完赛、支付等业务副作用一律丢弃"
                        : "业务副作用白名单拦截未生效",
                    isEnforced: dropsForbiddenBusinessEffects
                ),
                NPCSceneAISafetyRow(
                    guardID: "NPCChatDeletionFence",
                    title: "I08 NPC 对话与记忆删除重读围栏",
                    detail: enforcesNPCChatDeletionReReadFence
                        ? "已删除会话与记忆条目禁止被陈旧回读恢复"
                        : "NPC 删除重读围栏未启用",
                    isEnforced: enforcesNPCChatDeletionReReadFence
                )
            ]
        }
    }

    public var hasCanonicalGuards: Bool {
        rows.map(\.guardID) == Self.canonicalGuardIDs
    }

    public var isAllCompliant: Bool {
        !globalGenerationEnabled
            && !streamingDisplayAllowed
            && enforcesScopeEchoAndIsolation
            && dropsForbiddenBusinessEffects
            && enforcesNPCChatDeletionReReadFence
            && hasCanonicalGuards
            && rows.allSatisfy(\.isEnforced)
    }
}

/// SwiftUI section rendering `G-W04` Scene AI guard and `I08` NPC chat deletion fence status
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct NPCChatAndSceneAISafetySectionView: View {
    public let snapshot: NPCChatAndSceneAISafetySnapshot

    public init(snapshot: NPCChatAndSceneAISafetySnapshot = NPCChatAndSceneAISafetySnapshot()) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.globalGenerationEnabled || snapshot.streamingDisplayAllowed {
            return "G-W04 门控告警：Scene AI 默认必须保持非生成式且关闭流式展示"
        }
        if !snapshot.enforcesScopeEchoAndIsolation || !snapshot.dropsForbiddenBusinessEffects {
            return "G-W04 边界告警：缺少作用域回显校验或叙事动作白名单拦截"
        }
        if !snapshot.enforcesNPCChatDeletionReReadFence {
            return "I08 围栏告警：NPC 对话与记忆删除重读围栏未启用"
        }
        if !snapshot.isAllCompliant {
            return "NPC 对话与 Scene AI 安全门控存在未达标项"
        }
        return "G-W04 场景 AI 安全门控（默认关闭）与 I08 NPC 删除围栏全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("npcSceneAISafety.statusHeadline")
                Text(verbatim: "生成式总闸：\(snapshot.globalGenerationEnabled ? "开启" : "默认关闭") · 流式展示：\(snapshot.streamingDisplayAllowed ? "开启" : "默认关闭") · I08 删除围栏：\(snapshot.enforcesNPCChatDeletionReReadFence ? "已生效" : "未生效")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("npcSceneAISafety.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isEnforced ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isEnforced ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.medium))
                        Text(verbatim: row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isEnforced ? "已生效" : "未生效")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isEnforced ? .green : .red)
                }
                .accessibilityIdentifier("npcSceneAISafety.row." + row.guardID)
            }
        } header: {
            Text(verbatim: "G-W04 场景 AI 门控与 I08 NPC 删除围栏")
        }
        .accessibilityIdentifier("npcSceneAISafety.section")
    }
}
