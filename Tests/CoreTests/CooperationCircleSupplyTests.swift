import XCTest
@testable import QuestifyCore

final class CooperationCircleSupplyTests: XCTestCase {
    private func profile(price: Decimal = 0, duration: Int = 30, min: Int = 1, max: Int = 2, split: Bool = false,
                         benefit: String = "", benefitRules: String = "", rules: String = "Ask staff") throws -> CoopFlowCircleSupplyProfile {
        try .init(supplyName: "  Local service  ", supplyKind: .service, regularPrice: price, durationMinutes: duration,
            availableHours: "09:00-18:00", minPeople: min, maxPeople: max, splitBookingAllowed: split,
            actionType: .navigate, actionValue: "Store entrance", optionalBenefit: benefit, benefitRules: benefitRules, merchantRules: rules)
    }
    func testCompleteThirteenFieldProfileRoundTripsWithoutGeneratingServerIDs() throws {
        let p = try profile(benefit: "Tea", benefitRules: "One per booking")
        XCTAssertEqual(try CoopFlowCircleSupplyProfile(fields: p.fields), p)
        guard case .object(let fields) = p.fields else { return XCTFail() }
        XCTAssertEqual(fields.count, 13); XCTAssertEqual(p.supplyName, "Local service")
        XCTAssertNil(fields["merchantId"]); XCTAssertNil(fields["status"]); XCTAssertNil(fields["quotaUsed"])
    }
    func testAllOriginalTermsModesKeepTheirOriginalFieldsWithExplicitProfile() throws {
        let p = try profile()
        for mode in [CoopFlowOfferContext.TermsMode.traffic, .perk, .revshare] {
            let context = try CoopFlowOfferContext(chapterID: 7, termsMode: mode)
            let draft = try CoopFlowOfferDraft(context: context, templateID: mode == .perk ? 8 : nil,
                quota: mode == .perk ? 2 : nil, perHeadFee: mode == .revshare ? 0 : nil, circleSupplyProfile: p)
            let body = try draft.mutation.body()
            XCTAssertEqual(body["circleSupplyProfile"], p.fields); XCTAssertEqual(body["chapterId"], .id(7))
            XCTAssertEqual(body["termsMode"], .string(mode.rawValue))
            XCTAssertEqual(body["perkTemplateId"], mode == .perk ? .id(8) : .null)
        }
    }
    func testAbsentProfilePreservesOriginalTrafficBodyExactly() throws {
        let draft = try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .traffic))
        XCTAssertEqual(try draft.mutation.body(), .object(["chapterId": .id(7), "termsMode": .string("TRAFFIC")]))
    }
    func testCapacityDurationPriceAndBenefitRulesRejectInvalidPromise() throws {
        XCTAssertThrowsError(try profile(price: -1)); XCTAssertThrowsError(try profile(price: .nan))
        XCTAssertThrowsError(try profile(duration: 0)); XCTAssertThrowsError(try profile(min: 0))
        XCTAssertThrowsError(try profile(min: 3, max: 2)); XCTAssertThrowsError(try profile(max: 1))
        XCTAssertNoThrow(try profile(max: 1, split: true)); XCTAssertThrowsError(try profile(benefit: "Tea"))
        XCTAssertThrowsError(try profile(rules: "  "))
    }
    func testRawProfileRejectsUnknownKeysMissingFieldsAndWrongScalarTypes() throws {
        guard case .object(let fields) = try profile().fields else { return XCTFail() }
        for (key, value) in [("merchantId", CoopFlowJSON.id(99)), ("supplyKind", .string("UNKNOWN")), ("actionType", .string("SEND")),
                             ("splitBookingAllowed", .id(2)), ("regularPrice", .string("10garbage")), ("merchantRules", .null)] {
            var mutated = fields; mutated[key] = value
            XCTAssertThrowsError(try CoopFlowMutation.enrollOffer(fields: ["chapterId": .id(7), "termsMode": .string("TRAFFIC"), "circleSupplyProfile": .object(mutated)]).body())
        }
        var missing = fields; missing.removeValue(forKey: "availableHours")
        XCTAssertThrowsError(try CoopFlowCircleSupplyProfile(fields: .object(missing)))
    }
    func testOriginalCrossModeAndActiveOfferRestrictionsStillApply() throws {
        let p = try profile()
        XCTAssertThrowsError(try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .traffic), templateID: 8, circleSupplyProfile: p))
        XCTAssertThrowsError(try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .perk), quota: 2, circleSupplyProfile: p))
        XCTAssertThrowsError(try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .traffic, offerID: 4), circleSupplyProfile: p))
    }
}

extension CooperationCircleSupplyTests {
    func testFrozenPreviewShowsEveryProfileFieldWithActualLabelsAndValues() throws {
        let p = try profile(benefit: "Tea", benefitRules: "One per booking")
        let operation = try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .traffic), circleSupplyProfile: p).mutation
        let review = try CoopFlowRequestReviewContext(operation: operation)
        XCTAssertEqual(review.requestBody, try operation.body())
        let rows = review.rows.filter { $0.id.hasPrefix("circleSupplyProfile.") }
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let field = String(row.id.dropFirst("circleSupplyProfile.".count)), raw = try XCTUnwrap(p.fields[field].text)
            XCTAssertTrue(row.labelKey.hasPrefix("coopflow.circle."))
            if field == "supplyKind" { XCTAssertEqual(row.value, .localized(key: "coopflow.circle.kind.SERVICE", rawValue: raw)) }
            else if field == "actionType" { XCTAssertEqual(row.value, .localized(key: "coopflow.circle.action.NAVIGATE", rawValue: raw)) }
            else { XCTAssertEqual(row.value, .text(raw)) }
            XCTAssertNotEqual(row.value, .notProvided)
        }
    }
    func testPlainOfferPreviewHasNoFabricatedSupplyAndInvalidObjectCannotBeReviewed() throws {
        let old = try CoopFlowOfferDraft(context: .init(chapterID: 7, termsMode: .traffic)).mutation
        XCTAssertFalse(try CoopFlowRequestReviewContext(operation: old).rows.contains { $0.id.hasPrefix("circleSupplyProfile.") })
        XCTAssertThrowsError(try CoopFlowRequestReviewContext(operation: .enrollOffer(fields: ["chapterId": .id(7), "termsMode": .string("TRAFFIC"), "circleSupplyProfile": .object(["supplyName": .string("Incomplete")])])))
    }
}
