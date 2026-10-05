import Foundation

/// Fixed synthetic content only; no real account, geographic location, photo or redeemable code.
public enum RoamExperienceSyntheticFixtures {
    public static let history = #"[{"ts":1700000000000,"serverSessionID":901,"zone":"Sample district","distance":"1.4","shops":2,"durSec":1230,"track":[{"lat":"1","lng":"1"},{"lat":1.002,"lng":1.004},{"lat":1.003,"lng":1.007}],"pois":[{"id":902,"name":"Sample courtyard","cat":"park","lat":1.002,"lng":1.004}],"photos":[]},{"ts":1700086400000,"zone":"Sample record with missing stats","photos":[],"pois":[],"track":[]}]"#
    public static let settled = #"{"state":"FINISHED","sessionId":"901","clientSessionKey":"sample-key","resultComplete":true,"result":{"tileXp":12,"poiXp":20,"totalXp":32,"newTiles":6,"newPois":1,"tilesEver":46,"sessionShops":2}}"#
    public static let active = #"{"state":"ACTIVE","sessionId":901,"clientSessionKey":"sample-key"}"#
    public static let missing = #"{"state":"NOT_FOUND"}"#
    public static let incomplete = #"{"state":"FINISHED","sessionId":901,"resultComplete":false,"result":{"totalXp":32}}"#
    public static let album = #"{"list":[{"id":901,"picUrl":"","caption":"Synthetic city stamp","checkState":0,"createTime":"2026-01-01 12:00"},{"id":902,"picUrl":"","caption":"Synthetic reviewed stamp","checkState":1,"createTime":"2026-01-02 12:00"},{"id":903,"picUrl":"","caption":"Hidden synthetic moderation fixture","checkState":2}],"total":3,"pageNum":1,"pageSize":20}"#
    public static let tiles = #"{"tiles":["s00twy0","s00twy1"],"nextAfterId":2,"hasMore":false}"#
    public static let badge = #"{"code":"sample-badge","name":"Synthetic shop badge","threshold":3}"#
}
