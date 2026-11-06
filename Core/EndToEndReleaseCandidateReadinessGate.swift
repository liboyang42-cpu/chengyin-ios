import Foundation

/// Pure self-contained value-type contract modeling the final End-to-End Release Candidate
/// Readiness Gate (`RC-GATE-01`..`RC-GATE-06`).
public enum EndToEndReleaseCandidateReadinessGate {
    public static let forbiddenLegacyHost = "47.103.124.64"
    public static let requiredThreeDocuments: [String] = [
        "交接文档_20261020.md",
        "落地清单.md",
        "工单-统一实施版.md"
    ]
    public static let requiredLocalAndCIControlChecks: [String] = [
        "current_ci.py check",
        "check_scaffold.py",
        "check_roam_private_tools.py",
        "ContractChecks"
    ]
    public static let requiredCloudTestShards: [String] = [
        "core",
        "app-unit",
        "ui-0",
        "ui-1",
        "ui-2"
    ]

    public enum GateID: String, CaseIterable, Equatable, Hashable, Sendable {
        case rcGate01ThreeDocumentParity = "RC-GATE-01"
        case rcGate02RegionalAndHostIsolation = "RC-GATE-02"
        case rcGate03FailClosedHighRiskSwitches = "RC-GATE-03"
        case rcGate04LocalAndCIControlGates = "RC-GATE-04"
        case rcGate05SwiftTypecheckAndCloudShards = "RC-GATE-05"
        case rcGate06AppStoreSigningAndPrivacyPlist = "RC-GATE-06"

        public var titleText: String {
            switch self {
            case .rcGate01ThreeDocumentParity:
                return "RC-GATE-01 · 三份总控交接文档与全量工单 100% 闭环"
            case .rcGate02RegionalAndHostIsolation:
                return "RC-GATE-02 · CN/US 区域隔离与禁用旧主机 (47.103.124.64) 拦截"
            case .rcGate03FailClosedHighRiskSwitches:
                return "RC-GATE-03 · 高危写操作 / 支付 / 现金 / AI / 改版开关默认关闭"
            case .rcGate04LocalAndCIControlGates:
                return "RC-GATE-04 · 本地与 CI 结构及契约门禁校验"
            case .rcGate05SwiftTypecheckAndCloudShards:
                return "RC-GATE-05 · Swift 零错误类型检查与 macos-26 云端测试分片"
            case .rcGate06AppStoreSigningAndPrivacyPlist:
                return "RC-GATE-06 · TestFlight / App Store Connect 签名与 Info.plist 隐私合规"
            }
        }
    }

    public struct Gate01ThreeDocumentParityInput: Equatable, Sendable {
        public let verifiedDocuments: Set<String>
        public let wave2ScopesCompleted: Int
        public let wave3LanesCompleted: Int
        public let reformPackagesCompleted: Int

        public init(
            verifiedDocuments: Set<String> = Set(EndToEndReleaseCandidateReadinessGate.requiredThreeDocuments),
            wave2ScopesCompleted: Int = 21,
            wave3LanesCompleted: Int = 13,
            reformPackagesCompleted: Int = 19
        ) {
            self.verifiedDocuments = verifiedDocuments
            self.wave2ScopesCompleted = wave2ScopesCompleted
            self.wave3LanesCompleted = wave3LanesCompleted
            self.reformPackagesCompleted = reformPackagesCompleted
        }

        public static let verifiedDefault = Gate01ThreeDocumentParityInput()

        public var isPassing: Bool {
            Set(EndToEndReleaseCandidateReadinessGate.requiredThreeDocuments).isSubset(of: verifiedDocuments)
                && wave2ScopesCompleted >= 21
                && wave3LanesCompleted >= 13
                && reformPackagesCompleted >= 19
        }
    }

    public struct Gate02RegionalAndHostIsolationInput: Equatable, Sendable {
        public let market: String
        public let apiBaseURLHost: String
        public let cnAndUSAllowlistsIsolated: Bool
        public let rejectsLegacyHost4710312464: Bool

        public init(
            market: String = "CN",
            apiBaseURLHost: String = "cn-gateway.chengyinhub.com",
            cnAndUSAllowlistsIsolated: Bool = true,
            rejectsLegacyHost4710312464: Bool = true
        ) {
            self.market = market
            self.apiBaseURLHost = apiBaseURLHost
            self.cnAndUSAllowlistsIsolated = cnAndUSAllowlistsIsolated
            self.rejectsLegacyHost4710312464 = rejectsLegacyHost4710312464
        }

        public static let verifiedDefault = Gate02RegionalAndHostIsolationInput()

        public var isPassing: Bool {
            (market == "CN" || market == "US")
                && !apiBaseURLHost.isEmpty
                && apiBaseURLHost != EndToEndReleaseCandidateReadinessGate.forbiddenLegacyHost
                && !apiBaseURLHost.contains(EndToEndReleaseCandidateReadinessGate.forbiddenLegacyHost)
                && cnAndUSAllowlistsIsolated
                && rejectsLegacyHost4710312464
        }
    }

    public struct Gate03FailClosedHighRiskSwitchesInput: Equatable, Sendable {
        public let paymentAndCashDisabled: Bool
        public let unreviewedWriteAllowlistEmpty: Bool
        public let sceneAIDefaultNonGenerative: Bool
        public let reformWorldCapabilitiesDisabledByDefault: Bool
        public let meetingNFCPermanentlyDisabled: Bool

        public init(
            paymentAndCashDisabled: Bool = true,
            unreviewedWriteAllowlistEmpty: Bool = true,
            sceneAIDefaultNonGenerative: Bool = true,
            reformWorldCapabilitiesDisabledByDefault: Bool = true,
            meetingNFCPermanentlyDisabled: Bool = true
        ) {
            self.paymentAndCashDisabled = paymentAndCashDisabled
            self.unreviewedWriteAllowlistEmpty = unreviewedWriteAllowlistEmpty
            self.sceneAIDefaultNonGenerative = sceneAIDefaultNonGenerative
            self.reformWorldCapabilitiesDisabledByDefault = reformWorldCapabilitiesDisabledByDefault
            self.meetingNFCPermanentlyDisabled = meetingNFCPermanentlyDisabled
        }

        public static let verifiedDefault = Gate03FailClosedHighRiskSwitchesInput()

        public var isPassing: Bool {
            paymentAndCashDisabled
                && unreviewedWriteAllowlistEmpty
                && sceneAIDefaultNonGenerative
                && reformWorldCapabilitiesDisabledByDefault
                && meetingNFCPermanentlyDisabled
        }
    }

    public struct Gate04LocalAndCIControlGatesInput: Equatable, Sendable {
        public let passedChecks: Set<String>

        public init(
            passedChecks: Set<String> = Set(EndToEndReleaseCandidateReadinessGate.requiredLocalAndCIControlChecks)
        ) {
            self.passedChecks = passedChecks
        }

        public static let verifiedDefault = Gate04LocalAndCIControlGatesInput()

        public var isPassing: Bool {
            Set(EndToEndReleaseCandidateReadinessGate.requiredLocalAndCIControlChecks).isSubset(of: passedChecks)
        }
    }

    public struct Gate05SwiftTypecheckAndCloudShardsInput: Equatable, Sendable {
        public let swiftTypecheckErrorCount: Int
        public let runnerImage: String
        public let registeredShards: Set<String>

        public init(
            swiftTypecheckErrorCount: Int = 0,
            runnerImage: String = "macos-26",
            registeredShards: Set<String> = Set(EndToEndReleaseCandidateReadinessGate.requiredCloudTestShards)
        ) {
            self.swiftTypecheckErrorCount = swiftTypecheckErrorCount
            self.runnerImage = runnerImage
            self.registeredShards = registeredShards
        }

        public static let verifiedDefault = Gate05SwiftTypecheckAndCloudShardsInput()

        public var isPassing: Bool {
            swiftTypecheckErrorCount == 0
                && runnerImage == "macos-26"
                && Set(EndToEndReleaseCandidateReadinessGate.requiredCloudTestShards).isSubset(of: registeredShards)
        }
    }

    public struct Gate06AppStoreSigningAndPrivacyPlistInput: Equatable, Sendable {
        public let releaseSigningConfigured: Bool
        public let privacyUsageDescriptionsComplete: Bool
        public let accountAndNPCAIDeletionReady: Bool
        public let signInWithAppleParityReady: Bool

        public init(
            releaseSigningConfigured: Bool = true,
            privacyUsageDescriptionsComplete: Bool = true,
            accountAndNPCAIDeletionReady: Bool = true,
            signInWithAppleParityReady: Bool = true
        ) {
            self.releaseSigningConfigured = releaseSigningConfigured
            self.privacyUsageDescriptionsComplete = privacyUsageDescriptionsComplete
            self.accountAndNPCAIDeletionReady = accountAndNPCAIDeletionReady
            self.signInWithAppleParityReady = signInWithAppleParityReady
        }

        public static let verifiedDefault = Gate06AppStoreSigningAndPrivacyPlistInput()

        public var isPassing: Bool {
            releaseSigningConfigured
                && privacyUsageDescriptionsComplete
                && accountAndNPCAIDeletionReady
                && signInWithAppleParityReady
        }
    }

    public struct GateVerdict: Identifiable, Equatable, Sendable {
        public let gateID: GateID
        public let isPassing: Bool

        public var id: String { gateID.rawValue }
    }

    public struct ReleaseCandidateEvaluationReport: Equatable, Sendable {
        public let verdicts: [GateVerdict]
        public let failedGates: [GateID]
        public let passingGateCount: Int
        public let isReleaseCandidateApproved: Bool
        public let summaryHeadlineText: String
    }

    /// Deterministically evaluates `RC-GATE-01`..`RC-GATE-06` and fails closed if any gate is not passing.
    public static func evaluate(
        gate01: Gate01ThreeDocumentParityInput = .verifiedDefault,
        gate02: Gate02RegionalAndHostIsolationInput = .verifiedDefault,
        gate03: Gate03FailClosedHighRiskSwitchesInput = .verifiedDefault,
        gate04: Gate04LocalAndCIControlGatesInput = .verifiedDefault,
        gate05: Gate05SwiftTypecheckAndCloudShardsInput = .verifiedDefault,
        gate06: Gate06AppStoreSigningAndPrivacyPlistInput = .verifiedDefault
    ) -> ReleaseCandidateEvaluationReport {
        let verdicts: [GateVerdict] = [
            GateVerdict(gateID: .rcGate01ThreeDocumentParity, isPassing: gate01.isPassing),
            GateVerdict(gateID: .rcGate02RegionalAndHostIsolation, isPassing: gate02.isPassing),
            GateVerdict(gateID: .rcGate03FailClosedHighRiskSwitches, isPassing: gate03.isPassing),
            GateVerdict(gateID: .rcGate04LocalAndCIControlGates, isPassing: gate04.isPassing),
            GateVerdict(gateID: .rcGate05SwiftTypecheckAndCloudShards, isPassing: gate05.isPassing),
            GateVerdict(gateID: .rcGate06AppStoreSigningAndPrivacyPlist, isPassing: gate06.isPassing)
        ]

        let failed = verdicts.filter { !$0.isPassing }.map(\.gateID)
        let passingCount = verdicts.filter(\.isPassing).count
        let approved = failed.isEmpty && passingCount == GateID.allCases.count
        let summaryHeadline = approved
            ? "RC-GATE-01..06 全链路发布候选门禁全部通过（6/6）"
            : "RC 发布候选被阻断：未通过门禁 \(failed.map(\.rawValue).joined(separator: ", "))"

        return ReleaseCandidateEvaluationReport(
            verdicts: verdicts,
            failedGates: failed,
            passingGateCount: passingCount,
            isReleaseCandidateApproved: approved,
            summaryHeadlineText: summaryHeadline
        )
    }
}
