import Foundation

public enum BackendSyncAndContractGatePillarID: String, CaseIterable, Sendable, Equatable {
    case bkBackendSync = "BK"
    case w221MapCoreEntry = "w2-21"
    case contractChecksSuite = "Tests/ContractChecks"
    case currentCIManifestGate = "tools/current_ci.py"
}

public struct BackendSyncAndContractGatePillarDescriptor: Sendable, Equatable, Identifiable {
    public let pillarID: BackendSyncAndContractGatePillarID
    public let title: String
    public let verifiedContracts: [String]
    public let gateScriptsOrSuites: [String]
    public let isFailClosedByDefault: Bool

    public var id: String { pillarID.rawValue }

    public init(
        pillarID: BackendSyncAndContractGatePillarID,
        title: String,
        verifiedContracts: [String],
        gateScriptsOrSuites: [String],
        isFailClosedByDefault: Bool = true
    ) {
        self.pillarID = pillarID
        self.title = title
        self.verifiedContracts = verifiedContracts
        self.gateScriptsOrSuites = gateScriptsOrSuites
        self.isFailClosedByDefault = isFailClosedByDefault
    }
}

public struct BackendSyncAndContractGateEvaluation: Sendable, Equatable {
    public let isPassing: Bool
    public let missingBKContracts: [String]
    public let missingContractCheckSuites: [String]
    public let hasManifestDrift: Bool
    public let hasScaffoldViolation: Bool
    public let mapCoreEntryLaunchFlagVerified: Bool

    public init(
        isPassing: Bool,
        missingBKContracts: [String],
        missingContractCheckSuites: [String],
        hasManifestDrift: Bool,
        hasScaffoldViolation: Bool,
        mapCoreEntryLaunchFlagVerified: Bool
    ) {
        self.isPassing = isPassing
        self.missingBKContracts = missingBKContracts
        self.missingContractCheckSuites = missingContractCheckSuites
        self.hasManifestDrift = hasManifestDrift
        self.hasScaffoldViolation = hasScaffoldViolation
        self.mapCoreEntryLaunchFlagVerified = mapCoreEntryLaunchFlagVerified
    }
}

public struct BackendSyncAndContractGateAudit: Sendable, Equatable {
    public static let requiredBKContracts: [String] = [
        "GET /api/config/public",
        "AccountProfile.career",
        "RoamSubpagePresentation:E06-17",
        "ClubSeriesScheduleReadback:BK-SCHEDULE",
        "PlayArrivalAccuracy:BK-GPS"
    ]

    public static let requiredMapCoreEntryFlag = "--uitesting-map-core-entry"

    public static let requiredPythonContractCheckSuites: [String] = [
        "test_merchant_ai_commerce_contracts",
        "test_city_game_base",
        "test_bk_backend_sync",
        "test_roam_experience_contracts",
        "test_play_durable_recovery",
        "test_reform_world_contracts",
        "test_wave_unified_parity_inventory",
        "test_release_and_audit_contracts"
    ]

    public static let requiredManifestGateCommands: [String] = [
        "current_ci.py check",
        "check_scaffold.py"
    ]

    public static let pillars: [BackendSyncAndContractGatePillarDescriptor] = [
        BackendSyncAndContractGatePillarDescriptor(
            pillarID: .bkBackendSync,
            title: "Wave-3 BK Backend Sync Contracts (Config, Career, E06-17, BK-SCHEDULE, BK-GPS)",
            verifiedContracts: requiredBKContracts,
            gateScriptsOrSuites: ["BackendSyncContractTests", "test_bk_backend_sync.py"]
        ),
        BackendSyncAndContractGatePillarDescriptor(
            pillarID: .w221MapCoreEntry,
            title: "w2-21 MapCoreEntryHostRouter & Launch Flag Deterministic Route Resolution",
            verifiedContracts: ["MapCoreEntryHostRouter", requiredMapCoreEntryFlag],
            gateScriptsOrSuites: ["MapCoreEntryHostRouterTests"]
        ),
        BackendSyncAndContractGatePillarDescriptor(
            pillarID: .contractChecksSuite,
            title: "Python Source & Parity ContractChecks Suite",
            verifiedContracts: requiredPythonContractCheckSuites,
            gateScriptsOrSuites: requiredPythonContractCheckSuites.map { "Tests/ContractChecks/\($0).py" }
        ),
        BackendSyncAndContractGatePillarDescriptor(
            pillarID: .currentCIManifestGate,
            title: "Manifest Drift & Scaffold Integrity Gate",
            verifiedContracts: ["tools/current_ci_manifest.json", "Questify.xcodeproj/project.pbxproj"],
            gateScriptsOrSuites: requiredManifestGateCommands
        )
    ]

    public static func descriptor(
        for pillarID: BackendSyncAndContractGatePillarID
    ) -> BackendSyncAndContractGatePillarDescriptor? {
        pillars.first { $0.pillarID == pillarID }
    }

    public static func evaluate(
        verifiedBKContracts: Set<String>,
        executedPythonSuites: Set<String>,
        currentCICheckPassed: Bool,
        checkScaffoldPassed: Bool,
        mapCoreEntryLaunchFlagSupported: Bool
    ) -> BackendSyncAndContractGateEvaluation {
        let missingBK = requiredBKContracts.filter { !verifiedBKContracts.contains($0) }
        let missingSuites = requiredPythonContractCheckSuites.filter { !executedPythonSuites.contains($0) }
        let hasDrift = !currentCICheckPassed
        let hasScaffoldIssue = !checkScaffoldPassed

        let passing = missingBK.isEmpty
            && missingSuites.isEmpty
            && !hasDrift
            && !hasScaffoldIssue
            && mapCoreEntryLaunchFlagSupported

        return BackendSyncAndContractGateEvaluation(
            isPassing: passing,
            missingBKContracts: missingBK,
            missingContractCheckSuites: missingSuites,
            hasManifestDrift: hasDrift,
            hasScaffoldViolation: hasScaffoldIssue,
            mapCoreEntryLaunchFlagVerified: mapCoreEntryLaunchFlagSupported
        )
    }
}
