import SwiftUI

/// Mini-program topic-story answer sheet: 题面 / 答案 / 提示 / 玩家答错时的反馈 and the club-only notice.
/// Values come from the already validated `.nodeAnswer` read; nothing is cached or sent.
struct ClubNodeAnswerContent: View {
    let value: ClubGovernanceValue
    var body: some View {
        Section {
            if let question = nonEmpty(value["question"]) {
                LabeledContent("club.gov.field.question") { Text(verbatim: question).textSelection(.enabled) }
            }
            LabeledContent("club.gov.field.answerReveal") {
                if let answer = nonEmpty(value["answerReveal"]) { Text(verbatim: answer).bold().textSelection(.enabled) }
                else { Text("club.story.answer.none").foregroundStyle(.secondary) }
            }.accessibilityIdentifier("club.story.answer.reveal")
            let hints = (value["hints"].array ?? []).compactMap { nonEmpty($0) }
            if !hints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("club.story.answer.hints").font(.subheadline.bold())
                    ForEach(Array(hints.enumerated()), id: \.offset) { index, hint in
                        Text(verbatim: "\(index + 1) · \(hint)")
                    }
                }.accessibilityIdentifier("club.story.answer.hints")
            }
            if let feedback = nonEmpty(value["feedbackText"]) {
                LabeledContent("club.gov.field.feedbackText") { Text(verbatim: feedback).foregroundStyle(.secondary) }
            }
            Text("club.story.answer.notice").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func nonEmpty(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
