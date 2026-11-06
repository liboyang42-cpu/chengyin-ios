import Foundation

/// Exclusive C07 projection: appointment / reschedule facts, in-store evidence,
/// refund trial, and aftercare. Evidence only — never pays, refunds, redeems, or awards.
/// In-store evidence is not a GPS fake.
public enum FulfillmentEvidenceStage: String, Equatable, Sendable {
    case orderIssue = "ORDER_ISSUE"
    case hold = "HOLD"
    case booking = "BOOKING"
    case reschedule = "RESCHEDULE"
    case inStoreRedeem = "IN_STORE_REDEEM"
    case refundEstimate = "REFUND_ESTIMATE"
    case aftercare = "AFTERCARE"
}

public enum FulfillmentEvidenceOutcome: String, Equatable, Sendable {
    case recorded = "RECORDED"
    case unknown = "UNKNOWN"
}

public struct FulfillmentAppointmentFact: Equatable, Sendable {
    public let slotID: String?
    public let newSlotID: String?
    public let slotKnown: Bool
    public init(slotID: String?, newSlotID: String?, slotKnown: Bool) {
        self.slotID = FulfillmentEvidenceProjection.parse(slotID)
        self.newSlotID = FulfillmentEvidenceProjection.parse(newSlotID)
        self.slotKnown = slotKnown
    }
}

public struct FulfillmentInStoreEvidenceFact: Equatable, Sendable {
    public let attestedInStore: Bool
    public let simulatedGPS: Bool
    public init(attestedInStore: Bool, simulatedGPS: Bool) {
        self.attestedInStore = attestedInStore
        self.simulatedGPS = simulatedGPS
    }
}

public struct FulfillmentRefundTrialFact: Equatable, Sendable {
    public let now: Date?
    public let snapshotDeadline: Date?
    public let paid: Bool?
    public init(now: Date?, snapshotDeadline: Date?, paid: Bool?) {
        self.now = now; self.snapshotDeadline = snapshotDeadline; self.paid = paid
    }
}

public struct FulfillmentAftercareFact: Equatable, Sendable {
    public let caseOpen: Bool
    public let merchantResponded: Bool
    public init(caseOpen: Bool, merchantResponded: Bool) {
        self.caseOpen = caseOpen; self.merchantResponded = merchantResponded
    }
}

public struct FulfillmentJourneyFacts: Equatable, Sendable {
    public let orderIssued: Bool
    public let holdOccupiesCapacity: Bool
    public let appointment: FulfillmentAppointmentFact?
    public let inStore: FulfillmentInStoreEvidenceFact?
    public let refundTrial: FulfillmentRefundTrialFact?
    public let aftercare: FulfillmentAftercareFact?
    public init(orderIssued: Bool, holdOccupiesCapacity: Bool,
                appointment: FulfillmentAppointmentFact?, inStore: FulfillmentInStoreEvidenceFact?,
                refundTrial: FulfillmentRefundTrialFact?, aftercare: FulfillmentAftercareFact?) {
        self.orderIssued = orderIssued; self.holdOccupiesCapacity = holdOccupiesCapacity
        self.appointment = appointment; self.inStore = inStore
        self.refundTrial = refundTrial; self.aftercare = aftercare
    }
}

public struct FulfillmentEvidenceStep: Equatable, Sendable {
    public let stage: FulfillmentEvidenceStage
    public let originalRequestID: String?
    public let outcome: FulfillmentEvidenceOutcome
    public let executedWriter: Bool
    public let detail: String?
    public func jsonObject() -> [String: Any] {
        [
            "stage": stage.rawValue,
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "outcome": outcome.rawValue,
            "executedWriter": executedWriter,
            "detail": detail.map { $0 as Any } ?? NSNull()
        ]
    }
}

public struct FulfillmentEvidenceProjection: Equatable {
    public private(set) var originalStepsByRequestID: [String: [FulfillmentEvidenceStep]] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    public mutating func recordJourney(originalRequestID: String?,
                                       facts: FulfillmentJourneyFacts?) -> [FulfillmentEvidenceStep] {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalStepsByRequestID[requestID] {
            return original
        }
        let steps = compute(requestID: requestID, facts: facts)
        if let requestID, steps.contains(where: { $0.outcome == .recorded }) {
            originalStepsByRequestID[requestID] = steps
        }
        return steps
    }
    public mutating func requery(originalRequestID: String?,
                                 facts: FulfillmentJourneyFacts?) -> [FulfillmentEvidenceStep] {
        recordJourney(originalRequestID: originalRequestID, facts: facts)
    }
    public func recoverOriginal(originalRequestID: String) -> [FulfillmentEvidenceStep] {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalStepsByRequestID[requestID] {
            return original
        }
        return [unknown(.orderIssue, requestID, "original intent unknown")]
    }
    private func compute(requestID: String?, facts: FulfillmentJourneyFacts?) -> [FulfillmentEvidenceStep] {
        guard let requestID else {
            return [unknown(.orderIssue, nil, "originalRequestID missing")]
        }
        guard let facts else {
            return [unknown(.orderIssue, requestID, "journey facts missing")]
        }
        var steps: [FulfillmentEvidenceStep] = []
        steps.append(facts.orderIssued
                     ? recorded(.orderIssue, requestID, "actual issue already attributed to original request")
                     : unknown(.orderIssue, requestID, "order issue missing"))
        steps.append(facts.holdOccupiesCapacity
                     ? recorded(.hold, requestID, "held entitlement occupies capacity")
                     : unknown(.hold, requestID, "hold missing"))
        let appointment = facts.appointment ?? FulfillmentAppointmentFact(slotID: nil, newSlotID: nil, slotKnown: false)
        if !appointment.slotKnown || appointment.slotID == nil {
            steps.append(unknown(.booking, requestID, "booking slot missing"))
            steps.append(unknown(.reschedule, requestID, "no original booking to reschedule"))
        } else {
            steps.append(recorded(.booking, requestID, "slot \(appointment.slotID!)"))
            if appointment.newSlotID == nil {
                steps.append(unknown(.reschedule, requestID, "reschedule target missing"))
            } else {
                steps.append(recorded(.reschedule, requestID,
                                      "same requestId moved to slot \(appointment.newSlotID!)"))
            }
        }
        steps.append(inStore(requestID, facts.inStore))
        steps.append(refundTrial(requestID, facts.refundTrial))
        let aftercare = facts.aftercare ?? FulfillmentAftercareFact(caseOpen: false, merchantResponded: false)
        if !aftercare.caseOpen {
            steps.append(unknown(.aftercare, requestID, "aftercare case missing"))
        } else if aftercare.merchantResponded {
            steps.append(FulfillmentEvidenceStep(stage: .aftercare, originalRequestID: requestID,
                                                 outcome: .recorded, executedWriter: false,
                                                 detail: "aftercare already responded; respond writer not called"))
        } else {
            steps.append(recorded(.aftercare, requestID, "aftercare open; no respond writer"))
        }
        return steps
    }
    private func inStore(_ requestID: String, _ fact: FulfillmentInStoreEvidenceFact?) -> FulfillmentEvidenceStep {
        guard let fact else {
            return unknown(.inStoreRedeem, requestID, "in-store evidence missing")
        }
        if fact.simulatedGPS {
            return unknown(.inStoreRedeem, requestID, "in-store evidence required; GPS fake rejected")
        }
        guard fact.attestedInStore else {
            return unknown(.inStoreRedeem, requestID, "in-store evidence not attested")
        }
        return FulfillmentEvidenceStep(stage: .inStoreRedeem, originalRequestID: requestID,
                                       outcome: .recorded, executedWriter: false,
                                       detail: "in-store redeem evidence only; redeem/award not called")
    }
    private func refundTrial(_ requestID: String, _ fact: FulfillmentRefundTrialFact?) -> FulfillmentEvidenceStep {
        guard let fact, fact.now != nil, fact.paid != nil else {
            return unknown(.refundEstimate, requestID, "refund estimate inputs missing")
        }
        return FulfillmentEvidenceStep(stage: .refundEstimate, originalRequestID: requestID,
                                       outcome: .recorded, executedWriter: false,
                                       detail: "refund trial; no payout")
    }
    private func recorded(_ stage: FulfillmentEvidenceStage, _ requestID: String, _ detail: String)
        -> FulfillmentEvidenceStep {
        FulfillmentEvidenceStep(stage: stage, originalRequestID: requestID,
                                outcome: .recorded, executedWriter: false, detail: detail)
    }
    private func unknown(_ stage: FulfillmentEvidenceStage, _ requestID: String?, _ detail: String)
        -> FulfillmentEvidenceStep {
        FulfillmentEvidenceStep(stage: stage, originalRequestID: requestID,
                                outcome: .unknown, executedWriter: false, detail: detail)
    }
}
