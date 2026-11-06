import Foundation

/// Distinguishes scopes that require strict 1:1 Mini-Program API/copy alignment from scopes
/// where the native iOS App is a richer superset that must never be downgraded to Mini-Program web limits.
public enum MiniProgramVsNativeAlignmentMode: String, Sendable, Equatable, CaseIterable {
    case strictAPIAndCopyAlignment
    case nativeEnhancedSuperset
}

/// Classification entry for a single Wave-2 (`w2-01`..`w2-21`) or Reform v9 (`W02`..`W20`) scope.
public struct ScopeAlignmentClassification: Sendable, Equatable, Identifiable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let alignmentMode: MiniProgramVsNativeAlignmentMode
    public let preservesBackendAPIContract: Bool
    public let protectsNativeSupersetFromDowngrade: Bool

    public init(
        id: String? = nil,
        scopeCode: String,
        title: String,
        alignmentMode: MiniProgramVsNativeAlignmentMode,
        preservesBackendAPIContract: Bool = true,
        protectsNativeSupersetFromDowngrade: Bool = true
    ) {
        self.id = id ?? scopeCode
        self.scopeCode = scopeCode
        self.title = title
        self.alignmentMode = alignmentMode
        self.preservesBackendAPIContract = preservesBackendAPIContract
        self.protectsNativeSupersetFromDowngrade = protectsNativeSupersetFromDowngrade
    }

    public var isCompliant: Bool {
        guard !scopeCode.isEmpty, preservesBackendAPIContract else {
            return false
        }
        switch alignmentMode {
        case .strictAPIAndCopyAlignment:
            return true
        case .nativeEnhancedSuperset:
            return protectsNativeSupersetFromDowngrade
        }
    }
}

/// Pure classifier across Wave-2 (`w2-01`..`w2-21`) and Reform v9 (`W02`..`W20`) scopes
/// enforcing backend API contract compatibility while protecting native iOS superset capabilities
/// from being downgraded to Mini-Program web limitations.
public struct MiniProgramVsNativeSupersetPageClassifier: Sendable, Equatable {
    public static let canonicalClassifications: [ScopeAlignmentClassification] = [
        ScopeAlignmentClassification(
            scopeCode: "w2-01",
            title: "Auth Bootstrap & AccountSessionGate Role Admission",
            alignmentMode: .strictAPIAndCopyAlignment
        ),
        ScopeAlignmentClassification(
            scopeCode: "w2-02",
            title: "Profile Self-Edit & AccountProfile.career Contract",
            alignmentMode: .strictAPIAndCopyAlignment
        ),
        ScopeAlignmentClassification(
            scopeCode: "w2-05",
            title: "Club Access /api/club/access/me Form & Settlement",
            alignmentMode: .strictAPIAndCopyAlignment
        ),
        ScopeAlignmentClassification(
            scopeCode: "w2-08",
            title: "Roam Subpages & Received Stamps Readback",
            alignmentMode: .strictAPIAndCopyAlignment
        ),
        ScopeAlignmentClassification(
            scopeCode: "w2-12",
            title: "Merchant Decor /api/merchant/decor/save & /api/merchant/insight",
            alignmentMode: .strictAPIAndCopyAlignment
        ),
        ScopeAlignmentClassification(
            scopeCode: "W02-W03",
            title: "Encrypted <key>:game Durable Command Journal & Offline Recovery",
            alignmentMode: .nativeEnhancedSuperset
        ),
        ScopeAlignmentClassification(
            scopeCode: "W05-W08",
            title: "StoreKit 2 Digital Entitlements & Native Audio Interruption Recovery",
            alignmentMode: .nativeEnhancedSuperset
        ),
        ScopeAlignmentClassification(
            scopeCode: "W14-W15",
            title: "Native 3D MapKit, Personal Fog & MV01..MV41 Visual Layers",
            alignmentMode: .nativeEnhancedSuperset
        ),
        ScopeAlignmentClassification(
            scopeCode: "W17-W20",
            title: "ReformWorldHostWorkbenchView & OSSignposter 60fps Instrumentation",
            alignmentMode: .nativeEnhancedSuperset
        )
    ]

    public init() {}

    public static func evaluate(
        classifications: [ScopeAlignmentClassification] = canonicalClassifications
    ) -> (totalScopes: Int, apiCompatibleScopes: Int, nativeSupersetScopes: Int, isClassificationReady: Bool) {
        let totalScopes = classifications.count
        let apiCompatibleScopes = classifications.filter(\.preservesBackendAPIContract).count
        let nativeSupersetScopes = classifications.filter {
            $0.alignmentMode == .nativeEnhancedSuperset && $0.protectsNativeSupersetFromDowngrade
        }.count
        let hasStrictScope = classifications.contains { $0.alignmentMode == .strictAPIAndCopyAlignment }
        let hasNativeSupersetScope = classifications.contains { $0.alignmentMode == .nativeEnhancedSuperset }
        let isClassificationReady = totalScopes > 0 &&
            hasStrictScope &&
            hasNativeSupersetScope &&
            classifications.allSatisfy(\.isCompliant)

        return (
            totalScopes: totalScopes,
            apiCompatibleScopes: apiCompatibleScopes,
            nativeSupersetScopes: nativeSupersetScopes,
            isClassificationReady: isClassificationReady
        )
    }
}
