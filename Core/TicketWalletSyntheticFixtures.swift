#if DEBUG
import Foundation

/// Inert synthetic records. No endpoint, token, dynamic code, QR payload or personal data.
public enum TicketWalletSyntheticFixtures {
    public static let routeListJSON = #"{"code":200,"data":[{"id":901,"ownerType":1,"ownerId":101,"registrationStatus":2,"verificationStatus":1,"registrationNo":"EXAMPLE-ROUTE-901","participateDate":"2030-04-20","cmsTopic":{"name":"Sample exploration ticket","productType":2}},{"id":902,"ownerType":1,"ownerId":102,"registrationStatus":4,"verificationStatus":0,"cmsTopic":{"name":"Sample expired ticket"}},{"id":903,"ownerType":1,"ownerId":103,"registrationStatus":99,"cmsTopic":{"name":"Sample unknown ticket"}}]}"#
    public static let activityListJSON = #"{"code":200,"data":[{"id":904,"ownerType":2,"ownerId":104,"registrationStatus":2,"verificationStatus":0,"registrationNo":"EXAMPLE-ACTIVITY-904","cmsActivity":{"name":"Sample activity ticket","productType":1}},{"id":905,"ownerType":2,"ownerId":105,"registrationStatus":1,"cmsActivity":{"name":"Sample unpaid ticket"}}]}"#
    public static let detailJSON = #"{"id":901,"ownerType":1,"ownerId":101,"registrationStatus":2,"verificationStatus":1,"registrationNo":"EXAMPLE-ROUTE-901","participateDate":"2030-04-20","purchaseKind":3,"cmsTopic":{"name":"Sample exploration ticket","productType":2},"entitlements":[{"id":31,"status":1,"chapterId":11,"chapterName":"Sample completed chapter","redeemedAt":"2030-04-20 10:00:00"},{"id":32,"status":0,"chapterId":12,"chapterName":"Sample pending chapter"},{"id":33,"status":2,"chapterId":13,"chapterName":"Sample invalid chapter","invalidReason":"Synthetic invalidation reason"}]}"#
}

#endif
