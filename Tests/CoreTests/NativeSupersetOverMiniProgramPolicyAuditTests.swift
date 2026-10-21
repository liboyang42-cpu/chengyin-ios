import XCTest
@testable import QuestifyCore

final class NativeSupersetOverMiniProgramPolicyAuditTests: XCTestCase {
    func testCanonicalSixDomainsPassNativeSupersetPolicyAudit() {
        let result = NativeSupersetOverMiniProgramPolicyAudit.evaluate()
        XCTAssertEqual(result.totalDomains, 6)
        XCTAssertEqual(result.compliantDomains, 6)
        XCTAssertTrue(result.isSupersetPolicyCompliant)
        XCTAssertEqual(
            NativeSupersetOverMiniProgramPolicyAudit.canonicalDomains.map(\.id),
            [
                "native-mapkit-3d-and-personal-fog",
                "encrypted-durable-play-command-journal",
                "native-audio-session-and-tts-recovery",
                "storekit2-and-wallet-security-isolation",
                "signpost-60fps-performance-telemetry",
                "reform-v9-world-and-merchant-host-bridges"
            ]
        )
    }

    func testBackendAPIIncompatibilityIsDetected() {
        var domains = NativeSupersetOverMiniProgramPolicyAudit.canonicalDomains
        domains[0] = NativeSupersetDomainDescriptor(
            id: "native-mapkit-3d-and-personal-fog",
            domainTitle: "原生 MapKit 3D 与迷雾",
            tierMode: .nativeSupersetPreserved,
            compatibleWithMiniProgramBackendAPI: false,
            preservesSuperiorNativeCapability: true,
            avoidsDowngradingToMiniProgramWebLimits: true
        )
        let result = NativeSupersetOverMiniProgramPolicyAudit.evaluate(domains: domains)
        XCTAssertFalse(result.isSupersetPolicyCompliant)
        XCTAssertEqual(result.compliantDomains, 5)
    }

    func testAccidentalDowngradeToMiniProgramLimitsIsDetected() {
        let downgradedCapability = NativeSupersetDomainDescriptor(
            id: "encrypted-durable-play-command-journal",
            domainTitle: "游玩指令日志",
            tierMode: .nativeSupersetPreserved,
            compatibleWithMiniProgramBackendAPI: true,
            preservesSuperiorNativeCapability: false,
            avoidsDowngradingToMiniProgramWebLimits: true
        )
        XCTAssertFalse(downgradedCapability.isCompliant)

        let downgradedWebLimit = NativeSupersetDomainDescriptor(
            id: "native-audio-session-and-tts-recovery",
            domainTitle: "音频会话恢复",
            tierMode: .nativeSupersetPreserved,
            compatibleWithMiniProgramBackendAPI: true,
            preservesSuperiorNativeCapability: true,
            avoidsDowngradingToMiniProgramWebLimits: false
        )
        XCTAssertFalse(downgradedWebLimit.isCompliant)

        let result = NativeSupersetOverMiniProgramPolicyAudit.evaluate(domains: [downgradedCapability, downgradedWebLimit])
        XCTAssertFalse(result.isSupersetPolicyCompliant)
        XCTAssertEqual(result.compliantDomains, 0)
    }

    func testEmptyDomainsOrBlankFieldsAreRejected() {
        let emptyResult = NativeSupersetOverMiniProgramPolicyAudit.evaluate(domains: [])
        XCTAssertEqual(emptyResult.totalDomains, 0)
        XCTAssertFalse(emptyResult.isSupersetPolicyCompliant)

        let blankDescriptor = NativeSupersetDomainDescriptor(
            id: "   ",
            domainTitle: "Valid Title"
        )
        XCTAssertFalse(blankDescriptor.isCompliant)
    }
}
