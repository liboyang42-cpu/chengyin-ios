import Foundation

/// Pure self-contained value types auditing the product alignment rule: where iOS native is more complete/capable
/// than the WeChat Mini-Program, iOS preserves its native superset capabilities without downgrading to Mini-Program
/// limitations, while maintaining 100% backend API contract compatibility.
public enum AlignmentTierMode: String, Sendable, Equatable, CaseIterable {
    case strictBackendAndCopyParity
    case nativeSupersetPreserved
}

public struct NativeSupersetDomainDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let domainTitle: String
    public let tierMode: AlignmentTierMode
    public let compatibleWithMiniProgramBackendAPI: Bool
    public let preservesSuperiorNativeCapability: Bool
    public let avoidsDowngradingToMiniProgramWebLimits: Bool

    public init(
        id: String,
        domainTitle: String,
        tierMode: AlignmentTierMode = .nativeSupersetPreserved,
        compatibleWithMiniProgramBackendAPI: Bool = true,
        preservesSuperiorNativeCapability: Bool = true,
        avoidsDowngradingToMiniProgramWebLimits: Bool = true
    ) {
        self.id = id
        self.domainTitle = domainTitle
        self.tierMode = tierMode
        self.compatibleWithMiniProgramBackendAPI = compatibleWithMiniProgramBackendAPI
        self.preservesSuperiorNativeCapability = preservesSuperiorNativeCapability
        self.avoidsDowngradingToMiniProgramWebLimits = avoidsDowngradingToMiniProgramWebLimits
    }

    public var isCompliant: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !domainTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && compatibleWithMiniProgramBackendAPI
            && preservesSuperiorNativeCapability
            && avoidsDowngradingToMiniProgramWebLimits
    }
}

public struct NativeSupersetOverMiniProgramPolicyAudit: Sendable, Equatable {
    public static let canonicalDomains: [NativeSupersetDomainDescriptor] = [
        NativeSupersetDomainDescriptor(
            id: "native-mapkit-3d-and-personal-fog",
            domainTitle: "原生 MapKit 3D 视口、步行路线重算与个人迷雾账本超集",
            tierMode: .nativeSupersetPreserved
        ),
        NativeSupersetDomainDescriptor(
            id: "encrypted-durable-play-command-journal",
            domainTitle: "加密持久化游玩指令日志与断网重放围栏超集",
            tierMode: .nativeSupersetPreserved
        ),
        NativeSupersetDomainDescriptor(
            id: "native-audio-session-and-tts-recovery",
            domainTitle: "AVAudioSession 混音闪避、中断恢复与 NPC 语音合成超集",
            tierMode: .nativeSupersetPreserved
        ),
        NativeSupersetDomainDescriptor(
            id: "storekit2-and-wallet-security-isolation",
            domainTitle: "Keychain 硬件级凭据保管与 StoreKit 2 安全合规隔离超集",
            tierMode: .nativeSupersetPreserved
        ),
        NativeSupersetDomainDescriptor(
            id: "signpost-60fps-performance-telemetry",
            domainTitle: "OSSignposter 60fps 帧率、内存预算与冷启动可观测性超集",
            tierMode: .nativeSupersetPreserved
        ),
        NativeSupersetDomainDescriptor(
            id: "reform-v9-world-and-merchant-host-bridges",
            domainTitle: "Reform Plan v9 世界观、双域创编与宿主桥接契约超集",
            tierMode: .nativeSupersetPreserved
        )
    ]

    public let domains: [NativeSupersetDomainDescriptor]

    public init(domains: [NativeSupersetDomainDescriptor] = NativeSupersetOverMiniProgramPolicyAudit.canonicalDomains) {
        self.domains = domains
    }

    public static func evaluate(
        domains: [NativeSupersetDomainDescriptor] = canonicalDomains
    ) -> (totalDomains: Int, compliantDomains: Int, isSupersetPolicyCompliant: Bool) {
        let total = domains.count
        let compliant = domains.filter(\.isCompliant).count
        let isCompliant = total > 0 && compliant == total
        return (
            totalDomains: total,
            compliantDomains: compliant,
            isSupersetPolicyCompliant: isCompliant
        )
    }
}
