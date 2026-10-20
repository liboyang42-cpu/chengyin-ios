import XCTest
@testable import QuestifyCore

final class PrivacyAndSecurityRedactionAuditTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testW19PrivateHomeReturnCheckRedactsCoordinatesAndDetectsRawLeaks() throws {
        let homeJSON = #"{"homeId":"home-1","version":3,"status":"ACTIVE","updatedAtMillis":1700000000000}"#
        let home = try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(homeJSON.utf8))
        let policyJSON = #"{"policyVersion":"v1","maxAccuracyMeters":50,"maxFixAgeSeconds":60}"#
        let policy = try JSONDecoder().decode(HomeReturnPolicy.self, from: Data(policyJSON.utf8))

        let check = try HomeReturnCheck.preflight(
            home: home,
            status: .fix(accuracyMeters: 12, capturedAt: t0.addingTimeInterval(-5)),
            policy: policy,
            scope: .global(resourceType: "ENERGY"),
            now: t0,
            requestId: "req-home-0001"
        )

        let cleanEval = PrivacyAndSecurityRedactionAudit.auditPrivateHomeCheck(check)
        XCTAssertTrue(cleanEval.isCompliant)
        XCTAssertTrue(cleanEval.hasRedactedMarker)
        XCTAssertFalse(cleanEval.containsRawCoordinateOrPII)
        XCTAssertEqual(cleanEval.checkDescription, "HomeReturnCheck[redacted]")
        XCTAssertTrue(cleanEval.violations.isEmpty)

        let leakedEval = PrivacyAndSecurityRedactionAudit.auditPrivateHomeCheck(
            check,
            additionalDiagnosticSamples: ["lat: 31.2304, lng: 121.4737", "phone=13800138000"]
        )
        XCTAssertFalse(leakedEval.isCompliant)
        XCTAssertTrue(leakedEval.containsRawCoordinateOrPII)
        XCTAssertEqual(leakedEval.violations.count, 2)
    }

    func testW13LocationSharingRequiresAllSixDisclosuresAndDecouplesOSPermission() {
        var partialDraft = LocationShareDraft()
        partialDraft.choose(audience: .team(42))
        partialDraft.acknowledge(.audience)

        let partialEval = PrivacyAndSecurityRedactionAudit.auditLocationSharingConsent(
            draft: partialDraft,
            osPermissionGranted: true,
            treatsOSPermissionAsSharingConsent: true
        )
        XCTAssertFalse(partialEval.isCompliant)
        XCTAssertEqual(partialEval.acknowledgedDisclosureCount, 1)
        XCTAssertEqual(partialEval.missingDisclosureKeys.count, 5)
        XCTAssertFalse(partialEval.canFormShareGrantRequest)
        XCTAssertTrue(partialEval.violations.contains(.osPermissionTreatedAsSharingConsent))
        XCTAssertTrue(partialEval.violations.contains(.incompleteLocationShareDisclosures(missingCount: 5)))

        var completeDraft = LocationShareDraft()
        completeDraft.choose(audience: .team(42))
        for disclosure in LocationShareDisclosure.allCases {
            completeDraft.acknowledge(disclosure)
        }
        let compliantEval = PrivacyAndSecurityRedactionAudit.auditLocationSharingConsent(
            draft: completeDraft,
            osPermissionGranted: true,
            treatsOSPermissionAsSharingConsent: false
        )
        XCTAssertTrue(compliantEval.isCompliant)
        XCTAssertEqual(compliantEval.acknowledgedDisclosureCount, LocationSharingConsentEvaluation_requiredCount)
        XCTAssertTrue(compliantEval.preciseGrantDefaultDisabled)
        XCTAssertFalse(compliantEval.canFormShareGrantRequest, "Feature stays default-disabled even when all 6 disclosures are acknowledged")
    }

    private var LocationSharingConsentEvaluation_requiredCount: Int {
        PrivacyAndSecurityRedactionAudit.LocationSharingConsentEvaluation.requiredDisclosureCount
    }

    func testGW04AndI08NPCAIDataClassIsolationAndDeleteFence() throws {
        let compliantEval = PrivacyAndSecurityRedactionAudit.auditNPCAIPrivacyAndDeleteFence()
        XCTAssertTrue(compliantEval.isCompliant)
        XCTAssertTrue(compliantEval.allScenariosDisjoint)
        XCTAssertTrue(compliantEval.universalForbiddenClassesBlocked)
        XCTAssertTrue(compliantEval.remoteDeleteDefaultDisabled)
        XCTAssertTrue(compliantEval.unknownOutcomeRequiresExportReadback)
        XCTAssertEqual(compliantEval.deleteEndpointPath, "api/ai/npc/chat/data/delete")

        let unknownOutcome = try NPCChatLogDeletion.decode(Data("{}".utf8))
        XCTAssertEqual(unknownOutcome, .unknown)

        let violatedEval = PrivacyAndSecurityRedactionAudit.auditNPCAIPrivacyAndDeleteFence(
            remoteDeleteEnabledWithoutApproval: true,
            autoRetriesUnknownDelete: true
        )
        XCTAssertFalse(violatedEval.isCompliant)
        XCTAssertTrue(violatedEval.violations.contains(.npcRemoteDeleteEnabledWithoutApproval))
        XCTAssertTrue(violatedEval.violations.contains(.npcUnknownDeleteRetriedAutomatically))
    }

    func testI05SquareWorkspaceMediaEvictionOn404AndDeletedLifecycle() throws {
        let mediaStrings = [
            "https://cdn.example.invalid/post/1/a.jpg",
            "https://cdn.example.invalid/post/1/b.jpg",
            "relative/object/key.jpg"
        ]
        let urlA = try XCTUnwrap(URL(string: "https://cdn.example.invalid/post/1/a.jpg"))
        let urlB = try XCTUnwrap(URL(string: "https://cdn.example.invalid/post/1/b.jpg"))

        let retainedOn404 = PrivacyAndSecurityRedactionAudit.auditSquareMediaEviction(
            httpOrBusinessCode: 404,
            postLifecycle: "NORMAL",
            rawMediaURLStrings: mediaStrings,
            evictedURLs: [urlA]
        )
        XCTAssertTrue(retainedOn404.isRevocationEvent)
        XCTAssertFalse(retainedOn404.isCompliant)
        XCTAssertEqual(retainedOn404.violations, [.revokedPostMediaRetainedInCache(urlCount: 1)])

        let evictedOnDeleted = PrivacyAndSecurityRedactionAudit.auditSquareMediaEviction(
            httpOrBusinessCode: 200,
            postLifecycle: "DELETED",
            rawMediaURLStrings: mediaStrings,
            evictedURLs: [urlA, urlB]
        )
        XCTAssertTrue(evictedOnDeleted.isRevocationEvent)
        XCTAssertTrue(evictedOnDeleted.isCompliant)
        XCTAssertEqual(evictedOnDeleted.candidateAbsoluteURLs.count, 2)

        let transientTimeout = PrivacyAndSecurityRedactionAudit.auditSquareMediaEviction(
            httpOrBusinessCode: 504,
            postLifecycle: "NORMAL",
            rawMediaURLStrings: mediaStrings,
            evictedURLs: []
        )
        XCTAssertFalse(transientTimeout.isRevocationEvent)
        XCTAssertTrue(transientTimeout.isCompliant)
    }
}
