import Foundation

public enum ProfileEditReviewField: String, CaseIterable {
    case name, introduction, caseIntroduction, preferences, avatar, contactQR, casePictures
}
/// Raw image references never enter the review presentation model.
public enum ProfileEditReviewValue: Equatable {
    case text(String), selection(String), imageCount(Int), present(Bool), newAvatar
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)), let (.selection(a), .selection(b)): return a.utf8.elementsEqual(b.utf8)
        case let (.imageCount(a), .imageCount(b)): return a == b
        case let (.present(a), .present(b)): return a == b
        case (.newAvatar, .newAvatar): return true
        default: return false
        }
    }
}
public struct ProfileEditReviewChange: Identifiable, Equatable {
    public let field: ProfileEditReviewField
    public let before: ProfileEditReviewValue
    public let after: ProfileEditReviewValue
    public var id: String { field.rawValue }
}
public struct ProfileEditReviewSummary: Equatable {
    public let changes: [ProfileEditReviewChange]
    public init(snapshot: ProfileEditSnapshot, payload: ProfileEditPayload) {
        var result: [ProfileEditReviewChange] = []
        func text(_ field: ProfileEditReviewField, _ before: String, _ after: String) {
            if !before.utf8.elementsEqual(after.utf8) { result.append(.init(field: field, before: .text(before), after: .text(after))) }
        }
        text(.name, snapshot.nickname, payload.name)
        text(.introduction, snapshot.introduction, payload.introduction)
        if let after = payload.caseIntroduction, let before = snapshot.caseIntroduction { text(.caseIntroduction, before, after) }
        if !snapshot.tagIds.utf8.elementsEqual(payload.tagIds.utf8) {
            result.append(.init(field: .preferences, before: .selection(snapshot.tagIds), after: .selection(payload.tagIds)))
        }
        if payload.avatarReplacement != nil {
            result.append(.init(field: .avatar, before: .present(!snapshot.avatar.isEmpty), after: .newAvatar))
        }
        if payload.removesContactQR {
            result.append(.init(field: .contactQR, before: .present(!snapshot.wechat.isEmpty), after: .present(false)))
        }
        if payload.removesCasePictures {
            result.append(.init(field: .casePictures, before: .imageCount(ProfileCasePortfolio(casePics: snapshot.casePics).imageCount), after: .imageCount(0)))
        }
        changes = result
    }
}
