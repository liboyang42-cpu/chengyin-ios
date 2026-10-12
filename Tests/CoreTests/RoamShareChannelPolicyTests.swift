import XCTest
@testable import QuestifyCore

final class RoamShareChannelPolicyTests: XCTestCase {
    func testDefaultPreservesExistingNativeOptionsWithoutPublicPosting() {
        let policy = RoamShareChannelPolicy()
        XCTAssertEqual(policy.mode, .allOptions)
        XCTAssertEqual(policy.allowedChannels, [.savePhoto, .momentsGuide, .xiaohongshuGuide, .systemShare])
        XCTAssertEqual(RoamShareChannelPolicy.Channel.allCases.count, 4)
    }
    func testSaveOnlyBlocksEveryOutboundGuidanceAndSystemShare() {
        var policy = RoamShareChannelPolicy(); XCTAssertTrue(policy.select(.saveOnly, operationInFlight: false))
        XCTAssertEqual(policy.allowedChannels, [.savePhoto])
        XCTAssertFalse(policy.permits(.momentsGuide)); XCTAssertFalse(policy.permits(.xiaohongshuGuide)); XCTAssertFalse(policy.permits(.systemShare))
    }
    func testMomentsChoiceAllowsOnlyExistingSaveAndMomentsGuide() {
        var policy = RoamShareChannelPolicy(); policy.select(.momentsGuide, operationInFlight: false)
        XCTAssertTrue(policy.permits(.savePhoto)); XCTAssertTrue(policy.permits(.momentsGuide))
        XCTAssertFalse(policy.permits(.xiaohongshuGuide)); XCTAssertFalse(policy.permits(.systemShare))
    }
    func testAllOptionsCanBeRestoredByExplicitSelection() {
        var policy = RoamShareChannelPolicy(); policy.select(.saveOnly, operationInFlight: false)
        XCTAssertTrue(policy.select(.allOptions, operationInFlight: false)); XCTAssertTrue(policy.permits(.systemShare))
    }
    func testSameChoiceDoesNotInvalidatePreparedOutputAgain() {
        var policy = RoamShareChannelPolicy(); XCTAssertFalse(policy.select(.allOptions, operationInFlight: false))
        policy.select(.saveOnly, operationInFlight: false); XCTAssertFalse(policy.select(.saveOnly, operationInFlight: false))
    }
    func testInFlightSaveBlocksEveryModeTransition() {
        for source in RoamShareChannelPolicy.Mode.allCases {
            for target in RoamShareChannelPolicy.Mode.allCases {
                var policy = RoamShareChannelPolicy(); policy.select(source, operationInFlight: false)
                XCTAssertFalse(policy.select(target, operationInFlight: true)); XCTAssertEqual(policy.mode, source)
            }
        }
    }
    func testModeCanChangeOnceRequestedOperationSettles() {
        var policy = RoamShareChannelPolicy()
        XCTAssertFalse(policy.select(.saveOnly, operationInFlight: true))
        XCTAssertTrue(policy.select(.saveOnly, operationInFlight: false)); XCTAssertFalse(policy.permits(.systemShare))
    }
    func testEveryModeKeepsTheExistingSaveAction() {
        for mode in RoamShareChannelPolicy.Mode.allCases {
            var policy = RoamShareChannelPolicy(); policy.select(mode, operationInFlight: false)
            XCTAssertTrue(policy.permits(.savePhoto))
        }
    }
    func testModeAndChannelIdentifiersRemainDistinct() {
        XCTAssertEqual(Set(RoamShareChannelPolicy.Mode.allCases.map(\.rawValue)).count, 3)
        XCTAssertEqual(Set(RoamShareChannelPolicy.Channel.allCases.map(\.rawValue)).count, 4)
    }
    func testNewPresentationDoesNotInheritPreviousChoice() {
        var prior = RoamShareChannelPolicy(); prior.select(.saveOnly, operationInFlight: false)
        XCTAssertEqual(RoamShareChannelPolicy().mode, .allOptions)
        XCTAssertEqual(prior.mode, .saveOnly)
    }
    func testSourceResetClearsOnlyTheEphemeralPolicy() {
        var policy = RoamShareChannelPolicy(); policy.select(.momentsGuide, operationInFlight: false)
        policy.reset(); XCTAssertEqual(policy, RoamShareChannelPolicy())
    }
    func testAllModeTransitionsProduceExactChannelSets() {
        let expected: [RoamShareChannelPolicy.Mode: [RoamShareChannelPolicy.Channel]] = [
            .allOptions: [.savePhoto, .momentsGuide, .xiaohongshuGuide, .systemShare],
            .momentsGuide: [.savePhoto, .momentsGuide], .saveOnly: [.savePhoto]]
        var policy = RoamShareChannelPolicy()
        for mode in [.saveOnly, .momentsGuide, .allOptions, .momentsGuide, .saveOnly] as [RoamShareChannelPolicy.Mode] {
            policy.select(mode, operationInFlight: false); XCTAssertEqual(policy.allowedChannels, expected[mode])
        }
    }
}
