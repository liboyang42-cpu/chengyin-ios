import XCTest
@testable import QuestifyCore

final class H5SessionCapabilityGateTests: XCTestCase {
    private let hash = String(repeating: "ab", count: 32)
    private func frozen() throws -> H5FrozenCapability {
        try XCTUnwrap(H5FrozenCapability(signedDomains: ["play.chengyin.example"],
                                         sdkCapabilities: ["camera.scan", "location.once"],
                                         packageVersion: "1.0.0", contentHash: hash))
    }
    func testSignedDomainAndSDKCapabilityAdmitWithoutOpeningH5() throws {
        var gate = H5SessionCapabilityGate()
        try gate.admitDeclaredSurface(host: "play.chengyin.example", capability: "camera.scan",
                                      sdkVersion: "1.0.0", frozen: try frozen())
        XCTAssertEqual(gate.phase, .admitted)
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertEqual(waiting { try gate.openH5Session() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.h5SdkOriginal))
        XCTAssertEqual(gate.phase, .waitingSource)
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        try gate.admitDeclaredSurface(host: "play.chengyin.example", capability: "camera.scan",
                                      sdkVersion: "1.0.0", frozen: try frozen())
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "play.chengyin.example",
                                                           capability: "location.once",
                                                           sdkVersion: "1.0.0", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .requestMismatch)
        }
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertEqual(gate.admittedCapability, "camera.scan")
    }
    func testArbitraryH5UnsignedDomainAndVersionMismatchReject() throws {
        var gate = H5SessionCapabilityGate()
        XCTAssertThrowsError(try gate.openArbitraryH5("https://evil.example/game")) { error in
            XCTAssertEqual(error as? H5SessionFailure, .arbitraryH5Forbidden)
        }
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "evil.example", capability: "camera.scan",
                                                           sdkVersion: "1.0.0", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .unsignedDomain)
        }
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "play.chengyin.example",
                                                           capability: "wallet.charge",
                                                           sdkVersion: "1.0.0", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .capabilityNotGranted)
        }
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "play.chengyin.example",
                                                           capability: "camera.scan",
                                                           sdkVersion: "9.9.9", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .versionIncompatible)
        }
        XCTAssertFalse(WorkshopModuleSourceInventory.h5SdkOriginalPresent)
        XCTAssertFalse(WorkshopModuleSourceInventory.h5ContainerOriginalPresent)
        gate = H5SessionCapabilityGate()
        XCTAssertEqual(waiting { try gate.consumeH5SDKOriginal() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.h5SdkOriginal))
        gate = H5SessionCapabilityGate()
        XCTAssertEqual(waiting { try gate.consumeH5ContainerOriginal() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.h5ContainerOriginal))
    }
    func testRejectedAdmitDoesNotOccupyThenUniqueAdmitApplies() throws {
        var gate = H5SessionCapabilityGate()
        XCTAssertNil(gate.admittedHost)
        XCTAssertEqual(gate.phase, .idle)
        XCTAssertThrowsError(try gate.openArbitraryH5("https://evil.example/game")) { error in
            XCTAssertEqual(error as? H5SessionFailure, .arbitraryH5Forbidden)
        }
        XCTAssertNil(gate.admittedHost)
        XCTAssertEqual(gate.phase, .idle)
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "evil.example", capability: "camera.scan",
                                                           sdkVersion: "1.0.0", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .unsignedDomain)
        }
        XCTAssertNil(gate.admittedHost)
        XCTAssertEqual(gate.phase, .idle)
        try gate.admitDeclaredSurface(host: "play.chengyin.example", capability: "camera.scan",
                                      sdkVersion: "1.0.0", frozen: try frozen())
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertEqual(gate.admittedCapability, "camera.scan")
        XCTAssertEqual(gate.phase, .admitted)
        try gate.admitDeclaredSurface(host: "play.chengyin.example", capability: "camera.scan",
                                      sdkVersion: "1.0.0", frozen: try frozen())
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertThrowsError(try gate.admitDeclaredSurface(host: "play.chengyin.example",
                                                           capability: "location.once",
                                                           sdkVersion: "1.0.0", frozen: try frozen())) { error in
            XCTAssertEqual(error as? H5SessionFailure, .requestMismatch)
        }
        XCTAssertEqual(gate.admittedHost, "play.chengyin.example")
        XCTAssertEqual(gate.admittedCapability, "camera.scan")
    }
    private func waiting(_ body: () throws -> Never) -> H5SessionFailure? {
        do { try body(); return nil } catch let error as H5SessionFailure { return error } catch { return nil }
    }
}
