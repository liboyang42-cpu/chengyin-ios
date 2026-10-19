import SwiftUI

/// Reform plan v9 U01: each media stage is reported separately; remote stages never read as done.
@MainActor struct ProjectTopicMediaStageSummary: View {
    @Environment(\.locale) private var locale
    private func text(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
    private func name(_ stage: ProjectTopicMediaStage) -> String {
        switch stage {
        case .selection: return text("选择", "Selection")
        case .processing: return text("处理", "Processing")
        case .upload: return text("上传", "Upload")
        case .moderation: return text("审核", "Moderation")
        case .save: return text("保存", "Save")
        case .recovery: return text("恢复", "Recovery")
        case .read: return text("读取", "Read")
        case .playback: return text("播放", "Playback")
        }
    }
    private func status(_ value: ProjectTopicMediaStageStatus) -> String {
        switch value {
        case .localOnly: return text("仅本机", "On this device only")
        case .disabled: return text("未开放", "Not enabled")
        case .noContract: return text("服务端未接通", "No server contract")
        }
    }
    var body: some View {
        DisclosureGroup(text("图片与视频进度", "Image and video stages")) {
            ForEach(ProjectTopicMediaStage.allCases, id: \.self) { stage in
                LabeledContent(name(stage), value: status(ProjectTopicMediaUploadPlan.status(of: stage)))
                    .accessibilityIdentifier("projectTopicMedia.stage." + stage.rawValue)
            }
            Text(text("选择成功不代表已上传、已审核或已发布。", "A local selection is not an upload, review or publish."))
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("projectTopicMedia.stages")
    }
}
