import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class WorldEnvironmentProjectionTests: XCTestCase {
    private func env(_ values: [String: PlayWireValue], wrapped: Bool = true) -> PlayWireValue {
        wrapped ? .object(["rpg": .object(["enabled": .bool(true), "environment": .object(values)])]) : .object(["environment": .object(values)])
    }
    func testSignedWeatherAndCycleKeysStayExact() {
        let projection = WorldEnvironmentProjection.read(env([
            "weather": .string("rain"), "daypart": .string("afternoon"),
            "weekpart": .string("weekday"), "season": .string("autumn")
        ]))
        XCTAssertEqual(projection.availability, .ready)
        XCTAssertEqual(projection.weather, .known("rain"))
        XCTAssertEqual(projection["daypart"], .known("afternoon"))
        XCTAssertEqual(projection["weekpart"], .known("weekday"))
        XCTAssertEqual(projection["season"], .known("autumn"))
    }
    func testMissingEnvironmentBlockIsWaitingSourceNotClearSkies() {
        XCTAssertEqual(WorldEnvironmentProjection.read(.object(["rpg": .object(["enabled": .bool(true)])])), .waitingSource)
        XCTAssertEqual(WorldEnvironmentProjection.read(.object(["topicId": .int(71)])), .waitingSource)
        XCTAssertNil(WorldEnvironmentProjection.waitingSource.weather)
        XCTAssertNotEqual(WorldEnvironmentProjection.waitingSource.weather, .known("clear"))
    }
    func testServerUnknownWeatherIsNotInventedAndMalformedIsUnknown() {
        let unknown = WorldEnvironmentProjection.read(env(["weather": .string("unknown")]))
        XCTAssertEqual(unknown.availability, .ready)
        XCTAssertEqual(unknown.weather, .unknown)
        XCTAssertEqual(WorldEnvironmentProjection.read(.string("rain")), .unknown)
        XCTAssertEqual(WorldEnvironmentProjection.read(env(["weather": .int(1)])).weather, .unknown)
    }
    func testAbsentKeysAreOmittedRatherThanFilled() {
        let projection = WorldEnvironmentProjection.read(env(["weather": .string("fog")]))
        XCTAssertEqual(projection.values.count, 1)
        XCTAssertNil(projection["season"])
        XCTAssertEqual(WorldEnvironmentProjection.read(env([:], wrapped: false)).availability, .unknown)
    }
    func testBareCharacterCardAndStatusShareTheSameDecoder() {
        let card = WorldEnvironmentProjection.read(env(["weather": .string("snow")]))
        let status = WorldEnvironmentProjection.read(env(["weather": .string("snow")], wrapped: false))
        XCTAssertEqual(card.weather, status.weather)
        XCTAssertEqual(card.availability, .ready)
    }
}

final class EnvironmentExpiryClockTests: XCTestCase {
    func testServerAsOfVersusExpiresAtIsTheOnlyValidComparison() {
        let live = EnvironmentExpiryClock.read(.object(["asOf": .integer(1_000), "expiresAt": .integer(2_000)]))
        XCTAssertTrue(live.isValid); XCTAssertFalse(live.expired)
        let expired = EnvironmentExpiryClock.read(.object(["serverNow": .integer(3_000), "expiresAtMs": .integer(2_000)]))
        XCTAssertTrue(expired.expired); XCTAssertFalse(expired.isValid)
    }
    func testClientClockCannotMintSuccessFromExpiresAt() {
        let future = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        let clock = EnvironmentExpiryClock.read(.object(["expiresAt": .integer(future)]), clientNow: Date())
        XCTAssertEqual(clock.availability, .waitingSource)
        XCTAssertFalse(clock.isValid)
        XCTAssertEqual(clock.expiresAt, future)
    }
    func testExplicitServerFlagsDoNotNeedLocalNow() {
        XCTAssertTrue(EnvironmentExpiryClock.read(.object(["status": .string("VALID")])).isValid)
        XCTAssertTrue(EnvironmentExpiryClock.read(.object(["expired": .bool(true)])).expired)
        XCTAssertFalse(EnvironmentExpiryClock.read(.object(["expired": .bool(true)])).isValid)
        XCTAssertEqual(EnvironmentExpiryClock.read(.object(["validity": .string("WAITING_SOURCE")])).availability, .waitingSource)
        XCTAssertEqual(EnvironmentExpiryClock.read(.null), .waitingSource)
        XCTAssertEqual(EnvironmentExpiryClock.read(.string("VALID")).availability, .unknown)
    }
    func testUnknownStatusNeverBecomesValid() {
        XCTAssertEqual(EnvironmentExpiryClock.read(.object(["status": .string("STILL_GOOD")])).availability, .unknown)
        XCTAssertFalse(EnvironmentExpiryClock.read(.object(["status": .string("STILL_GOOD")])).isValid)
        XCTAssertEqual(EnvironmentExpiryClock.read(.object(["status": .string("EXPIRED")])).expired, true)
    }
}
