import Foundation

/// Synthetic offline public projections with no hosts, accounts or credentials.
public enum PublicTopicTemplateFixtures {
    public static func content(id: Int = 801, merchant: Bool = false) -> String {
        """
        {"id":\(id),"name":"A neighborhood in three chapters","subtitle":"A synthetic walking preview",
        "description":"Notice the everyday details along a public route.","totalTime":5400,"locationCount":6,"templateCount":3,
        "viewerIsMerchant":\(merchant),"viewerIsPublisher":false,
        "chapters":[{"id":901,"name":"The first corner","nodeCount":6,
        "nodes":[{"name":"A welcoming square","addressName":"Example neighborhood","hookTeaser":"Look for a familiar shape.","interactionType":"OBSERVE"}],
        "routeShape":[{"x":0.1,"y":0.2},{"x":0.5,"y":0.8},{"x":0.9,"y":0.3}],
        "recruitStatus":{"state":"OPEN","isOpen":true,"remainingMerchantCount":2}}],
        "games":[{"id":701,"title":"Notice the city","players":"2–6","duration":45,"difficulty":"Easy","interactionType":"OBSERVE"}]}
        """
    }
}
