#if DEBUG
import Foundation

/// Offline synthetic records only. No real people, endpoints, images or credentials.
public enum GrowthCenterSyntheticFixtures {
    public static let centerJSON = #"{"code":200,"data":{"growth":{"levelNo":3,"expValue":2450},"points":700,"badges":[{"badgeName":"Sample explorer badge","badgeCode":"SAMPLE_EXPLORER","obtainTime":"2026-09-01 00:15:00"},{"badgeName":"Sample collector badge","badgeCode":"SAMPLE_COLLECTOR"}],"missions":[{"missionName":"Sample exploration mission","missionDesc":"Read-only synthetic mission","expReward":20}]}}"#
    public static let progressJSON = #"{"code":200,"data":{"level":3,"totalCheckins":12,"totalMileage":13.45,"streakDays":2}}"#
    public static let completedJSON = #"{"code":200,"data":[{"activityId":11,"topicId":31,"name":"Sample route A","total":4,"doneCount":4},{"activityId":12,"topicId":31,"name":"Sample route B","total":2,"doneCount":2},{"activityId":13,"topicId":32,"name":"Sample route C","total":3,"doneCount":3},{"activityId":14,"topicId":0,"name":"Sample activity","total":1,"doneCount":1}]}"#
    public static let boardJSON = #"{"code":200,"data":{"metric":"point","period":"total","list":[{"rank":1,"memberId":101,"nickname":"Sample North","score":900},{"rank":2,"memberId":102,"nickname":"Sample South","score":850},{"rank":3,"memberId":103,"nickname":"Sample East","score":800},{"rank":4,"memberId":104,"nickname":"Sample West","score":750}],"me":{"rank":12,"memberId":999,"nickname":"Sample me","score":640,"rankPercentage":"TOP20%"}}}"#
    public static let emptyCenterJSON = #"{"code":200,"data":{"growth":{"levelNo":1,"expValue":0},"points":0,"badges":[],"missions":[]}}"#
    public static let emptyBoardJSON = #"{"code":200,"data":{"metric":"point","period":"total","list":[],"me":{"rank":null,"memberId":999,"nickname":"Sample me","score":0}}}"#
}
#endif
