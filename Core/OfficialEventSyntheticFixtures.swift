#if DEBUG
/// Synthetic records only: no real accounts, remote artwork, coordinates or credentials.
public enum OfficialEventSyntheticFixtures {
    public static let eventJSON = #"""
    {"id":71,"title":"Synthetic city lights","subtitle":"Offline official event","city":"Example city","status":3,"story":"An original synthetic event story for native UI verification.","participants":12,"signed":true,"myProgress":2,"contractVersion":2,"activityStart":"2030-01-01 10:00:00","activityEnd":1893549600000,"paused":false,"eligible":false,"roamEnabled":true,"bannerEnabled":"1","rewardJson":"{\"settleBadge\":\"synthetic-badge\",\"settleXp\":25}","missions":[{"missionCode":"sample-arrival","title":"Sample arrival task","description":"Arrival verification is unavailable in this read-only module.","missionType":"ARRIVAL","complete":false,"canVerifyArrival":true},{"missionCode":"sample-theme","title":"Sample theme task","missionType":"THEME_VERIFIED_FINISH","complete":true}],"collective":{"enabled":true,"current":12,"threshold":100,"pct":12,"reached":false}}
    """#
    public static let eventsJSON = #"""
    [{"id":71,"title":"Synthetic city lights","subtitle":"Offline official event","city":"Example city","status":3},{"id":72,"title":"Synthetic next chapter","status":1},{"id":73,"title":"Synthetic past event","status":5},{"id":74,"title":"Synthetic registration event","status":2}]
    """#
    public static let inboxJSON = #"""
    [{"partyId":81,"title":"Synthetic organizer invitation","partyType":"OFFICIAL","eventTitle":"Synthetic city lights","status":"INVITED"},{"partyId":82,"partyName":"Synthetic merchant invitation","partyType":"MERCHANT","status":"ACCEPTED"},{"partyId":83,"responsibilitySummary":"Synthetic club invitation","partyType":"CLUB","status":"ACTIVE"},{"partyId":84,"title":"Synthetic unknown invitation","partyType":"FUTURE","state":"INVITED"}]
    """#
    public static let publishedJSON = #"""
    {"events":[{"id":71,"title":"Synthetic published event","status":3}],"broadcasts":[{"id":91,"title":"Synthetic notice","content":"A synthetic notice for read-only inspection.","reach":7}]}
    """#
    public static let statsJSON = #"""
    {"reach":7,"reads":4,"clicks":2,"sourceLabel":"Synthetic","enabled":true,"unmappedMetric":9,"internalObject":{"ignored":true},"history":[1,2],"nullValue":null}
    """#
}
#endif
