import Foundation

public enum SquareWorkspaceFixtures {
    public static func draft() -> SquareWorkspaceDraft {
        var value = SquareWorkspaceDraft(workflowID: "synthetic-square-001", body: "Synthetic square draft / 合成广场草稿")
        value.reference = .init(type: "ACTIVITY", id: 901); value.address = "Example city / 示例城市"; return value
    }
    public static let post = Data(#"{"post":{"id":701,"authorId":81,"version":3,"lifecycle":"DRAFT","body":"Synthetic draft","audience":"PUBLIC","commentPolicy":"EVERYONE"},"media":[],"references":[]}"#.utf8)
    /// Source-shaped ViewCreativeSquare. It has status, never version/lifecycle.
    public static let legacyPost = Data(#"{"id":701,"memberId":81,"contents":"Synthetic legacy post","pics":"one.jpg;two.jpg","address":"Example city","dataId":901,"dataType":1,"status":1,"delFlag":0,"updateTime":"2026-01-01 10:00:00"}"#.utf8)
    public static let guideline = Data(#"{"id":4,"title":"Synthetic guidelines","body":"Offline fixture only"}"#.utf8)
}
