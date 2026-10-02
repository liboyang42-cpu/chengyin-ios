import Foundation

/// Synthetic records only; deliberately equal numeric IDs prove domain separation.
public enum SearchMapSyntheticFixtures {
    public static let categories = #"[{"id":7,"categoryName":"Synthetic culture","type":1}]"#
    public static let topics = #"[{"id":71,"name":"Synthetic route","introduction":"An offline route","startDate":"2030-05-04"}]"#
    public static let activities = #"[{"id":71,"name":"Synthetic walk","addressName":"Example plaza","minAmout":25,"startDate":"2030-05-04","latitude":"1.001","longitude":"1.002","topicId":72},{"id":73,"name":"Synthetic indoor activity","minAmout":null}]"#
    public static let clubs = #"[{"id":71,"name":"Synthetic club","description":"Offline community"}]"#
    public static let merchants = #"[{"id":71,"memberId":999,"name":"Synthetic shop","cityRole":"Example gathering place","tags":"Coffee;Culture;Third"}]"#
    public static let cityNodes = #"[{"poiId":71,"name":"Synthetic city node","description":"Offline point description","lat":1.003,"lng":1.002,"merchantId":71,"merchantName":"Synthetic shop","templateId":905,"templateTitle":"Synthetic template","radiusM":50,"validationMethod":5,"favorited":false}]"#
    public static let nearby = #"[{"id":71,"nodeId":909,"topicId":72,"addressName":"Synthetic route stop","address":"Example lane","latitude":"1.002","longitude":"1.004","distance":350}]"#
    public static let merchant = #"{"data":{"id":71,"name":"Synthetic shop","description":"Offline public description","tags":"[\"Coffee\",\"Culture\"]","address":"Example lane","businessTime":"10:00–18:00"},"featured":{"name":"Synthetic featured route","featuredType":4,"featuredId":72}}"#
}
