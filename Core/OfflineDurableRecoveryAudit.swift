import Foundation

public enum OfflineDurableRecoveryPillarID: String, CaseIterable, Sendable, Equatable {
    case i02GameCommandJournal = "I02"
    case i06PlatformAudioAndTempSweep = "I06"
    case hw03RunAuthorityHostCoordinator = "H-W03"
}

public struct OfflineDurableRecoveryPillarDescriptor: Sendable, Equatable, Identifiable {
    public let pillarID: OfflineDurableRecoveryPillarID
    public let title: String
    public let primaryContractType: String
    public let storageSlotPattern: String
    public let encryptionAlgorithm: String?
    public let requiresAccountRealmFencing: Bool
    public let preservesIdempotencyKeyAcrossRestart: Bool
    public let enforcesUnknownOutcomeLockBeforeRetry: Bool
    public let sweepsStaleTempArtifactsOnBoot: Bool
    public let detectsCASStateVersionConflict: Bool

    public var id: String { pillarID.rawValue }

    public init(
        pillarID: OfflineDurableRecoveryPillarID,
        title: String,
        primaryContractType: String,
        storageSlotPattern: String,
        encryptionAlgorithm: String?,
        requiresAccountRealmFencing: Bool,
        preservesIdempotencyKeyAcrossRestart: Bool,
        enforcesUnknownOutcomeLockBeforeRetry: Bool,
        sweepsStaleTempArtifactsOnBoot: Bool,
        detectsCASStateVersionConflict: Bool
    ) {
        self.pillarID = pillarID
        self.title = title
        self.primaryContractType = primaryContractType
        self.storageSlotPattern = storageSlotPattern
        self.encryptionAlgorithm = encryptionAlgorithm
        self.requiresAccountRealmFencing = requiresAccountRealmFencing
        self.preservesIdempotencyKeyAcrossRestart = preservesIdempotencyKeyAcrossRestart
        self.enforcesUnknownOutcomeLockBeforeRetry = enforcesUnknownOutcomeLockBeforeRetry
        self.sweepsStaleTempArtifactsOnBoot = sweepsStaleTempArtifactsOnBoot
        self.detectsCASStateVersionConflict = detectsCASStateVersionConflict
    }
}

public enum OfflineRecoverySlotFenceVerdict: Sendable, Equatable {
    case accepted(slotKey: String, preservedRequestID: String)
    case rejectedAccountMismatch(expectedAccountID: Int, actualAccountID: Int)
    case rejectedRealmMismatch(expectedRealm: String, actualRealm: String)
    case rejectedMalformedSlotKey(String)
}

public enum OfflineUnknownOutcomeRetryVerdict: Sendable, Equatable {
    case allowFreshDispatch
    case lockedPendingAuthoritativeReadback(preservedRequestID: String, expectedStateVersion: Int)
    case requiresAuthoritativeSnapshotRecovery(localStateVersion: Int, remoteStateVersion: Int)
}

public struct OfflineDurableRecoveryAudit: Sendable, Equatable {
    public static let pillars: [OfflineDurableRecoveryPillarDescriptor] = [
        OfflineDurableRecoveryPillarDescriptor(
            pillarID: .i02GameCommandJournal,
            title: "PlayGameCommandJournal Durable Encrypted Slot & Account/Realm Fencing",
            primaryContractType: "PlayGameCommandJournal",
            storageSlotPattern: "<key>:game",
            encryptionAlgorithm: "AES.GCM",
            requiresAccountRealmFencing: true,
            preservesIdempotencyKeyAcrossRestart: true,
            enforcesUnknownOutcomeLockBeforeRetry: true,
            sweepsStaleTempArtifactsOnBoot: false,
            detectsCASStateVersionConflict: true
        ),
        OfflineDurableRecoveryPillarDescriptor(
            pillarID: .i06PlatformAudioAndTempSweep,
            title: "PlatformAudioLifecycle Interruption/Route Fail-Safe & Stale .tmp File Sweep",
            primaryContractType: "PlatformAudioLifecyclePolicy",
            storageSlotPattern: "*.tmp",
            encryptionAlgorithm: nil,
            requiresAccountRealmFencing: false,
            preservesIdempotencyKeyAcrossRestart: false,
            enforcesUnknownOutcomeLockBeforeRetry: false,
            sweepsStaleTempArtifactsOnBoot: true,
            detectsCASStateVersionConflict: false
        ),
        OfflineDurableRecoveryPillarDescriptor(
            pillarID: .hw03RunAuthorityHostCoordinator,
            title: "RunAuthorityHostCoordinator CAS stateVersion Conflict & Unknown-Outcome Lock",
            primaryContractType: "RunAuthorityHostCoordinator",
            storageSlotPattern: "<account>:<realm>:<activity>:authority",
            encryptionAlgorithm: "AES.GCM",
            requiresAccountRealmFencing: true,
            preservesIdempotencyKeyAcrossRestart: true,
            enforcesUnknownOutcomeLockBeforeRetry: true,
            sweepsStaleTempArtifactsOnBoot: false,
            detectsCASStateVersionConflict: true
        )
    ]

    public static func descriptor(for pillarID: OfflineDurableRecoveryPillarID) -> OfflineDurableRecoveryPillarDescriptor? {
        pillars.first { $0.pillarID == pillarID }
    }

    public static func makeGameRecoverySlotKey(baseKey: String) -> String {
        "\(baseKey):game"
    }

    public static func evaluateSlotFence(
        slotKey: String,
        slotAccountID: Int,
        slotRealm: String,
        activeAccountID: Int,
        activeRealm: String,
        preservedRequestID: String
    ) -> OfflineRecoverySlotFenceVerdict {
        guard slotKey.hasSuffix(":game"), slotKey.count > 5 else {
            return .rejectedMalformedSlotKey(slotKey)
        }
        guard slotAccountID == activeAccountID else {
            return .rejectedAccountMismatch(expectedAccountID: activeAccountID, actualAccountID: slotAccountID)
        }
        guard slotRealm == activeRealm else {
            return .rejectedRealmMismatch(expectedRealm: activeRealm, actualRealm: slotRealm)
        }
        return .accepted(slotKey: slotKey, preservedRequestID: preservedRequestID)
    }

    public static func evaluateUnknownOutcomeRetry(
        hasUnresolvedPendingSlot: Bool,
        preservedRequestID: String,
        localStateVersion: Int,
        authoritativeRemoteStateVersion: Int?
    ) -> OfflineUnknownOutcomeRetryVerdict {
        if let remoteVersion = authoritativeRemoteStateVersion, remoteVersion != localStateVersion {
            return .requiresAuthoritativeSnapshotRecovery(
                localStateVersion: localStateVersion,
                remoteStateVersion: remoteVersion
            )
        }
        if hasUnresolvedPendingSlot {
            return .lockedPendingAuthoritativeReadback(
                preservedRequestID: preservedRequestID,
                expectedStateVersion: localStateVersion
            )
        }
        return .allowFreshDispatch
    }

    public static func evaluateAudioInterruptionAndTempSweep(
        signal: PlatformAudioLifecycleSignal,
        ownsConfiguration: Bool,
        candidateFileNames: [String]
    ) -> (audioAction: PlatformAudioLifecycleAction, staleTempFilesToSweep: [String]) {
        let action = PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: ownsConfiguration)
        let staleFiles = candidateFileNames.filter { $0.hasSuffix(".tmp") }
        return (action, staleFiles)
    }
}
