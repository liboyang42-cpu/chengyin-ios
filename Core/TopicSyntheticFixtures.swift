#if DEBUG
/// Synthetic offline data only. No backend records, credentials, coordinates or remote assets.
public enum TopicSyntheticFixtures {
    public static let detailJSON = #"""
    {"id":7,"name":"Synthetic route","subtitle":"Offline example","description":"A sample route for native browsing checks.","betaFlag":1,"selfPlay":1,"selfPlayPrice":null,"storyLocked":true,"totalChapterCount":4,"merchantClosed":false,"chaptersList":[{"id":11,"title":"Sample first chapter","description":"A sample chapter story.","totalTime":"90","nodes":[{"id":21,"nodeName":"Sample first stop","description":"Read-only stop story.","address":"Example meeting place","businessTime":"Example hours","imgUrl":" one, two;three ","cmsMemberTemplate":{"id":31,"title":"Sample challenge","difficulty":"Easy","players":"2–4","duration":20,"validationMethodStr":"Ask the host"},"registrationMerchantList":[{"memberId":41,"mmsMerchant":{"name":"Synthetic cafe","businessTime":"Example cafe hours"}}]},{"id":22,"name":"Sample second stop"}]},{"id":12,"title":"Sample second chapter","nodes":[]}],"omsTicketList":[{"id":51,"name":"Sample session","startTime":"2030-01-01 10:00:00","endTime":"2030-01-01 12:00:00","price":null,"remainingInventory":-2,"meetingPoint":"Example plaza","refundRule":"Synthetic example refund terms","cmsRegistrationList":[{"memberId":61,"nickname":"Example player"}]}],"commentList":[{"memberNickname":"Example reviewer","createTime":"2030-01-02","rating":4,"contents":"Synthetic review"}]}
    """#
}
#endif
