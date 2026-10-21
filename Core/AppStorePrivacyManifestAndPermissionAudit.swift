import Foundation

/// Pure self-contained value-type contract auditing iOS 17+ App Store privacy manifest
/// (`PrivacyInfo.xcprivacy`), `Info.plist` permission usage descriptions, and `W13.5`
/// OS location permission decoupling rules.
public enum AppStorePrivacyManifestAndPermissionAudit {
    public enum RequiredReasonAPICategory: String, CaseIterable, Equatable, Hashable, Sendable {
        case userDefaults = "NSPrivacyAccessedAPICategoryUserDefaults"
        case fileTimestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
        case systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
        case diskSpace = "NSPrivacyAccessedAPICategoryDiskSpace"
    }

    public enum RequiredUsageDescriptionKey: String, CaseIterable, Equatable, Hashable, Sendable {
        case locationWhenInUse = "NSLocationWhenInUseUsageDescription"
        case camera = "NSCameraUsageDescription"
        case microphone = "NSMicrophoneUsageDescription"
        case photoLibrary = "NSPhotoLibraryUsageDescription"
        case photoLibraryAdd = "NSPhotoLibraryAddUsageDescription"
    }

    public static let forbiddenAlwaysLocationKeys: Set<String> = [
        "NSLocationAlwaysUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription"
    ]

    public enum BlockerCode: String, CaseIterable, Equatable, Hashable, Sendable {
        case trackingEnabled = "PRIVACY_TRACKING_ENABLED"
        case nonEmptyTrackingDomains = "NON_EMPTY_TRACKING_DOMAINS"
        case missingOrEmptyRequiredReasonAPI = "MISSING_OR_EMPTY_REQUIRED_REASON_API"
        case missingOrBlankUsageDescription = "MISSING_OR_BLANK_USAGE_DESCRIPTION"
        case forbiddenBackgroundLocationKeyPresent = "FORBIDDEN_BACKGROUND_LOCATION_KEY_PRESENT"
        case w135LocationPermissionCoupledToSharing = "W13_5_LOCATION_PERMISSION_COUPLED_TO_SHARING"
    }

    public struct PrivacyManifestDeclaration: Equatable, Sendable {
        public let nsPrivacyTracking: Bool
        public let nsPrivacyTrackingDomains: [String]
        public let declaredAPICategories: [RequiredReasonAPICategory: [String]]

        public init(
            nsPrivacyTracking: Bool = false,
            nsPrivacyTrackingDomains: [String] = [],
            declaredAPICategories: [RequiredReasonAPICategory: [String]] = Self.standardAPIDeclarations
        ) {
            self.nsPrivacyTracking = nsPrivacyTracking
            self.nsPrivacyTrackingDomains = nsPrivacyTrackingDomains
            self.declaredAPICategories = declaredAPICategories
        }

        public static let standardAPIDeclarations: [RequiredReasonAPICategory: [String]] = [
            .userDefaults: ["CA92.1"],
            .fileTimestamp: ["C617.1"],
            .systemBootTime: ["35F9.1"],
            .diskSpace: ["E174.1"]
        ]

        public static let verifiedDefault = PrivacyManifestDeclaration()

        public var isTrackingCompliant: Bool {
            !nsPrivacyTracking && nsPrivacyTrackingDomains.isEmpty
        }

        public var missingOrEmptyAPICategories: [RequiredReasonAPICategory] {
            RequiredReasonAPICategory.allCases.filter { category in
                guard let reasons = declaredAPICategories[category], !reasons.isEmpty else {
                    return true
                }
                return reasons.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
    }

    public struct InfoPlistPermissionPosture: Equatable, Sendable {
        public let usageDescriptions: [String: String]

        public init(usageDescriptions: [String: String] = Self.standardUsageDescriptions) {
            self.usageDescriptions = usageDescriptions
        }

        public static let standardUsageDescriptions: [String: String] = [
            RequiredUsageDescriptionKey.locationWhenInUse.rawValue: "在前台进行城市漫游、路线导航或返家核验时使用当前位置（不等于向他人共享位置）。",
            RequiredUsageDescriptionKey.camera.rawValue: "在您选择扫描二维码或拍摄凭证照片时使用相机。",
            RequiredUsageDescriptionKey.microphone.rawValue: "在您选择录制语音消息或语音互动时使用麦克风。",
            RequiredUsageDescriptionKey.photoLibrary.rawValue: "在您选择上传动态、路线或售后图片时访问相册。",
            RequiredUsageDescriptionKey.photoLibraryAdd.rawValue: "在您选择保存生成的海报或纪念卡时写入相册。"
        ]

        public static let verifiedDefault = InfoPlistPermissionPosture()

        public var missingOrBlankRequiredKeys: [RequiredUsageDescriptionKey] {
            RequiredUsageDescriptionKey.allCases.filter { key in
                guard let value = usageDescriptions[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else {
                    return true
                }
                return false
            }
        }

        public var hasForbiddenBackgroundLocationKeys: Bool {
            !AppStorePrivacyManifestAndPermissionAudit.forbiddenAlwaysLocationKeys
                .intersection(usageDescriptions.keys)
                .isEmpty
        }
    }

    /// Audits `W13.5`: granting OS location permission (`whenInUse`) must never auto-enable
    /// peer location sharing or approximate roam presence without explicit in-app disclosure consent.
    public struct W135LocationPermissionDecouplingState: Equatable, Sendable {
        public let osLocationAuthorizedWhenInUse: Bool
        public let peerPreciseLocationShareEnabledByDefault: Bool
        public let roamApproximatePresenceEnabledByDefault: Bool
        public let requiresExplicitSixDisclosureConsentToShare: Bool

        public init(
            osLocationAuthorizedWhenInUse: Bool = true,
            peerPreciseLocationShareEnabledByDefault: Bool = false,
            roamApproximatePresenceEnabledByDefault: Bool = false,
            requiresExplicitSixDisclosureConsentToShare: Bool = true
        ) {
            self.osLocationAuthorizedWhenInUse = osLocationAuthorizedWhenInUse
            self.peerPreciseLocationShareEnabledByDefault = peerPreciseLocationShareEnabledByDefault
            self.roamApproximatePresenceEnabledByDefault = roamApproximatePresenceEnabledByDefault
            self.requiresExplicitSixDisclosureConsentToShare = requiresExplicitSixDisclosureConsentToShare
        }

        public static let verifiedDefault = W135LocationPermissionDecouplingState()

        public var isDecoupled: Bool {
            !peerPreciseLocationShareEnabledByDefault
                && !roamApproximatePresenceEnabledByDefault
                && requiresExplicitSixDisclosureConsentToShare
        }
    }

    public struct AuditReport: Equatable, Sendable {
        public let manifest: PrivacyManifestDeclaration
        public let infoPlistPermissions: InfoPlistPermissionPosture
        public let w135Decoupling: W135LocationPermissionDecouplingState
        public let blockerCodes: [BlockerCode]
        public let missingAPICategories: [RequiredReasonAPICategory]
        public let missingUsageDescriptionKeys: [RequiredUsageDescriptionKey]
        public let isCompliant: Bool
        public let summaryHeadlineText: String
    }

    /// Deterministically evaluates privacy manifest, `Info.plist` usage descriptions,
    /// and `W13.5` location permission decoupling.
    public static func evaluate(
        manifest: PrivacyManifestDeclaration = .verifiedDefault,
        infoPlistPermissions: InfoPlistPermissionPosture = .verifiedDefault,
        w135Decoupling: W135LocationPermissionDecouplingState = .verifiedDefault
    ) -> AuditReport {
        var blockers: [BlockerCode] = []

        if manifest.nsPrivacyTracking {
            blockers.append(.trackingEnabled)
        }
        if !manifest.nsPrivacyTrackingDomains.isEmpty {
            blockers.append(.nonEmptyTrackingDomains)
        }

        let missingAPIs = manifest.missingOrEmptyAPICategories
        if !missingAPIs.isEmpty {
            blockers.append(.missingOrEmptyRequiredReasonAPI)
        }

        let missingKeys = infoPlistPermissions.missingOrBlankRequiredKeys
        if !missingKeys.isEmpty {
            blockers.append(.missingOrBlankUsageDescription)
        }

        if infoPlistPermissions.hasForbiddenBackgroundLocationKeys {
            blockers.append(.forbiddenBackgroundLocationKeyPresent)
        }

        if !w135Decoupling.isDecoupled {
            blockers.append(.w135LocationPermissionCoupledToSharing)
        }

        let isCompliant = blockers.isEmpty
        let summaryHeadline = isCompliant
            ? "App Store 隐私清单 (PrivacyInfo) 与 W13.5 权限隔离校验全部通过"
            : "App Store 隐私清单或权限合规存在 \(blockers.count) 项阻塞"

        return AuditReport(
            manifest: manifest,
            infoPlistPermissions: infoPlistPermissions,
            w135Decoupling: w135Decoupling,
            blockerCodes: blockers,
            missingAPICategories: missingAPIs,
            missingUsageDescriptionKeys: missingKeys,
            isCompliant: isCompliant,
            summaryHeadlineText: summaryHeadline
        )
    }
}
