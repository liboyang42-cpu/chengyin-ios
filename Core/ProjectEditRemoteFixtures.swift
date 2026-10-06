#if DEBUG
import Foundation

/// Synthetic edit-detail bytes for the real decoder/HTTP adapter. No network is used.
public enum ProjectEditRemoteFixtures {
    public static func detail(product: ProjectEditProduct, revision: String = "fixture-r2", scope: ProjectEditScope = .full) throws -> Data {
        let node: [String: ProjectEditJSON] = ["id": .number(22), "name": .string("Owned fixture stop"),
            "description": .string("  Raw e\u{301}\n"), "address": .string("Synthetic boardwalk"),
            "longitude": .string("121.5"), "latitude": .string("31.2"), "imgUrl": .string("fixture:owned-reference"),
            "nodeTime": .number(45), "templateId": .number(73)]
        var chapter: [String: ProjectEditJSON] = ["id": .number(11), "name": .string("Owned fixture chapter"),
            "description": .string("Original story"), "cmsTopicNodeList": .array([.object(node)])]
        if product == .city {
            chapter["blocks"] = .array([.object(["key": .string("story"), "type": .string("text"), "content": .string("Original story")]),
                .object(["key": .string("stop"), "type": .string("node"), "nodeId": .number(22)])])
        }
        let topic: [String: ProjectEditJSON] = ["id": .number(71), "productType": .number(Decimal(product.rawValue)),
            "name": .string("Owned fixture route"), "description": .string("Source-backed readback fixture"),
            "updateTime": .string(revision), "imgUrl": .string("fixture:cover"), "categoryIds": .string("7"),
            "startDate": .string("2030-05-01"), "endDate": .string("2030-05-30"), "recruitDeadline": .string("2030-04-20")]
        let ticket: [String: ProjectEditJSON] = ["name": .string("Free fixture ticket"), "price": .number(0), "totalInventory": .number(15),
            "startTime": .string("2030-05-02 10:00"), "endTime": .string("2030-05-02 12:00"), "meetingPoint": .string("Synthetic boardwalk")]
        let body: [String: ProjectEditJSON] = ["topic": .object(topic), "editScope": .string(scope.rawValue),
            "chapters": .array([.object(chapter)]), "tickets": .array([.object(ticket)])]
        return try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(body)])
    }
}
#endif
