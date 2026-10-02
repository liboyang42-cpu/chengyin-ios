import Foundation

/// Local-only forms. Wire-only review anchors are immutable and cannot be edited.
public struct ClubGovernanceFormDraft {
    public let operation: ClubGovernanceMutation
    public let scope: ClubGovernanceScope
    public private(set) var anchors: [String: ClubGovernanceValue]
    public var text: [String: String] = [:] { didSet { if text != oldValue { requestID = "club-native-" + UUID().uuidString } } }
    public var flags: [String: Bool] = [:] { didSet { if flags != oldValue { requestID = "club-native-" + UUID().uuidString } } }
    public private(set) var requestID = "club-native-" + UUID().uuidString
    public init(operation: ClubGovernanceMutation, scope: ClubGovernanceScope, seed: [String: ClubGovernanceValue] = [:]) {
        self.operation = operation; self.scope = scope
        let anchorKeys: [String]
        switch operation {
        case .ban, .transferOwner: anchorKeys = ["targetMemberId"]
        case .unban: anchorKeys = ["banId", "version"]
        case .revokeRole: anchorKeys = ["assignmentId", "version"]
        case .correctAttendance: anchorKeys = ["expectedVersion"]
        default: anchorKeys = []
        }
        anchors = seed.filter { anchorKeys.contains($0.key) }
        switch operation {
        case .hostApply:
            for key in ["leaderName", "phone", "identity", "coFounders", "maxEventSize", "avgEventSize", "certImages"] { text[key] = "" }
            text["experience"] = "没有经验"
            for key in ["canDesignRoute", "canDesignTask", "canNpc", "canMerchantCoop", "hasGuideCert"] { flags[key] = false }
        case .saveCustomer:
            text["remark"] = seed["remark"]?.string ?? ""
            text["tags"] = (seed["tags"]?.array ?? []).compactMap { $0.string ?? $0["name"].string }.joined(separator: ",")
        case .createSeries, .updateSeries:
            text = ["recurrenceType": seed["recurrenceType"]?.string ?? "ONCE", "startDate": "", "startTime": "09:00", "occurrenceCount": "1", "customDates": (seed["futureDates"]?.array ?? []).compactMap(\.string).joined(separator: ","), "capacity": seed["defaultCapacity"]?.text ?? "", "defaultLeadMemberId": seed["defaultLeadMemberId"]?.text ?? "", "offerMinutes": seed["offerMinutes"]?.text ?? "1440"]
            flags["waitlistEnabled"] = seed["waitlistEnabled"]?.bool ?? false
            if operation == .updateSeries { anchors["expectedVersion"] = seed["version"] }
        case .ban: text = ["reason": "", "expiresAt": ""]
        case .unban, .transferOwner, .cancelOccurrence, .revokeRole, .appeal: text["reason"] = ""
        case .correctAttendance: text["reason"] = ""; flags["arrived"] = false
        case .report: text = ["targetType": "CLUB", "targetId": scope.clubID.map(String.init) ?? "", "reason": ""]
        case .assignRole: text = ["targetMemberId": "", "roleCode": scope.activityID == nil ? "CLUB_OPERATOR" : "EVENT_CHECKIN"]
        case .sendNotification: text = ["audienceType": scope.activityID == nil ? "ALL_MEMBERS" : "REGISTERED", "title": "", "content": ""]
        case .saveTopicSettings: for key in ["coopOpen", "pinned", "memberOnly"] { flags[key] = seed[key]?.bool ?? false }
        case .chapterRecruit: flags["enabled"] = false
        case .reportHours: text = ["hourKind": "PREP", "actualHours": ""]
        case .submitEvidence: text = ["dimension": "DELIVERY_SAFETY", "evidenceHash": ""]
        case .dissolve: flags = ["dissolveConfirmed": false, "memberConsequencesConfirmed": false]
        default: break
        }
    }
    public func choices(_ key: String) -> [String]? {
        switch key {
        case "experience": return ["没有经验", "1-5场", "5-20场", "20场以上"]
        case "recurrenceType": return ["ONCE", "WEEKLY", "CUSTOM_DATES"]
        case "targetType": return ["CLUB", "ACTIVITY", "MEMBER"]
        case "roleCode": return scope.activityID == nil ? ClubGovernancePermissions.assignableClubRoles : ClubGovernancePermissions.assignableEventRoles
        case "audienceType": return scope.activityID == nil ? ["ALL_MEMBERS", "ADMINS", "INACTIVE"] : ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"]
        case "hourKind": return ["PREP", "CONTENT", "ONSITE", "REVIEW"]
        case "dimension": return ["DELIVERY_SAFETY", "PLAYER_EXPERIENCE", "CONTENT_REPORT"]
        default: return nil
        }
    }
    public func command() throws -> ClubGovernanceCommand {
        var values = anchors
        let integers = Set(["maxEventSize", "avgEventSize", "occurrenceCount", "capacity", "defaultLeadMemberId", "offerMinutes", "targetMemberId", "targetId"])
        let nullable = Set(["maxEventSize", "avgEventSize", "capacity"])
        for (key, raw) in text {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if integers.contains(key) {
                if nullable.contains(key), value.isEmpty { values[key] = .null }
                else { guard let number = Int(value) else { throw ClubGovernanceFailure.invalidRequest }; values[key] = .integer(number) }
            } else if ["tags", "customDates"].contains(key) {
                var seen = Set<String>()
                values[key] = .array(value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.map(ClubGovernanceValue.string))
            } else if key == "actualHours" { guard let number = Double(value), number.isFinite else { throw ClubGovernanceFailure.invalidRequest }; values[key] = .decimal(number) }
            else { values[key] = .string(key == "evidenceHash" ? value.lowercased() : value) }
        }
        for (key, flag) in flags { values[key] = operation == .hostApply || key == "enabled" ? .integer(flag ? 1 : 0) : .bool(flag) }
        if operation == .hostApply { values["hasExperience"] = .integer(text["experience"] == "没有经验" ? 0 : 1) }
        if [.createSeries, .updateSeries].contains(operation) {
            if text["recurrenceType"] != "CUSTOM_DATES" { values["customDates"] = .null }
            if text["recurrenceType"] == "ONCE" { values["occurrenceCount"] = .integer(1) }
        }
        if [.saveCustomer, .createSeries, .cancelOccurrence, .correctAttendance, .ban, .unban, .transferOwner, .report, .appeal, .assignRole, .revokeRole, .sendNotification].contains(operation) { values["requestId"] = .string(requestID) }
        return try ClubGovernanceCommand(operation: operation, scope: scope, values: values)
    }
}
