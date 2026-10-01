import SwiftUI

extension SquareFeedMode {
    var labelKey: LocalizedStringKey {
        switch self {
        case .latest: return "square.mode.latest"
        case .following: return "square.mode.following"
        case .nearby: return "square.mode.nearby"
        case .topic: return "square.mode.topic"
        case .community: return "square.mode.community"
        case .featured: return "square.mode.featured"
        case .trending: return "square.mode.trending"
        case .forYou: return "square.mode.forYou"
        }
    }
}
struct SquareIssueView: View {
    let error: Error
    var retry: (() -> Void)? = nil
    private var key: LocalizedStringKey {
        if error as? APIError == .notConfigured { return "square.notConfigured" }
        if error as? APIError == .unauthorized { return "square.unauthorized" }
        switch error as? SquareReadFailure {
        case .signInRequired: return "square.signInRequired"
        case .cityRequired: return "square.cityRequired"
        case .topicRequired: return "square.topicRequired"
        case .communityRequired: return "square.communityRequired"
        case .unavailable: return "square.unavailable"
        default: return "square.failed"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(key, systemImage: "exclamationmark.circle")
            if let failure = error as? SquareReadFailure, case let .server(_, message) = failure, let message, !message.isEmpty {
                // Backend messages remain verbatim, including unavailable/moderation responses.
                Text(verbatim: message).font(.caption).textSelection(.enabled)
            }
            if let retry { Button("square.retry", action: retry).accessibilityIdentifier("square.retry") }
        }.accessibilityIdentifier("square.error")
    }
}
struct SquareImage: View {
    let source: String
    var body: some View {
        if let url = URL(string: source), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else if phase.error != nil { Label("square.imageUnavailable", systemImage: "photo.badge.exclamationmark") }
                else { ProgressView("square.imageLoading") }
            }.frame(maxWidth: .infinity, maxHeight: 240)
                .accessibilityLabel(Text("square.postImage"))
        } else {
            // Source media can contain object keys. No storage host or signed URL is invented.
            Label("square.imageUnavailable", systemImage: "photo")
        }
    }
}
struct SquarePostContent: View {
    let post: SquarePost
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "person.crop.circle").font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let name = post.nickname, !name.isEmpty { Text(verbatim: name).font(.headline) }
                    else { Text("square.unknownAuthor").font(.headline) }
                    if post.verified { Label("square.verified", systemImage: "checkmark.seal").font(.caption) }
                    if post.memberLevel > 0 { LabeledContent("square.level", value: String(post.memberLevel)).font(.caption) }
                    if let badge = post.authorBadge { Text(verbatim: badge).font(.caption) }
                    if let badge = post.noticeBadge { Text(verbatim: badge).font(.caption).bold() }
                }
            }
            if let contents = post.contents { Text(verbatim: contents).lineLimit(compact ? 5 : nil).textSelection(.enabled) }
            if !compact {
                ForEach(Array(post.images.enumerated()), id: \.offset) { _, source in SquareImage(source: source) }
                if let routeImage = post.routeImage { SquareImage(source: routeImage) }
            } else if let image = post.images.first { SquareImage(source: image) }
            if let address = post.address, !address.isEmpty { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin") } }
            if let club = post.clubName { LabeledContent("square.club", value: club) }
            if let title = post.referenceTitle { LabeledContent("square.reference", value: title) }
            else if let type = post.referenceType, let id = post.referenceID {
                LabeledContent("square.reference", value: "\(type) #\(id)")
            }
            if post.nodeTotal > 0 {
                LabeledContent("square.routeProgress", value: "\(post.nodeDoneCount) / \(post.nodeTotal)")
            }
            if post.completed { Label("square.completed", systemImage: "checkmark.circle") }
            if !post.createTime.isEmpty { Text(verbatim: post.createTime).font(.caption).foregroundStyle(.secondary) }
            LabeledContent("square.likes", value: String(max(0, post.likeCount)))
            LabeledContent("square.comments", value: String(max(0, post.commentCount)))
            if post.disclosureType != "NONE" { LabeledContent("square.disclosure", value: post.disclosureType) }
            ForEach(Array(post.safetyLabels.enumerated()), id: \.offset) { _, label in
                Label { SquareSafetyLabel(value: label) } icon: { Image(systemName: "exclamationmark.triangle") }
            }
        }
    }
}

struct SquareSafetyLabel: View {
    let value: String
    private var key: LocalizedStringKey? {
        switch value {
        case "DANGEROUS_ACTIVITY": return "square.safety.dangerous"
        case "SENSITIVE_CONTENT": return "square.safety.sensitive"
        case "FLASHING_IMAGES": return "square.safety.flashing"
        case "SPOILER": return "square.safety.spoiler"
        case "TEMPORARY_CLOSURE": return "square.safety.closure"
        case "ACCESSIBILITY_LIMIT": return "square.safety.accessibility"
        case "WEATHER_RISK": return "square.safety.weather"
        default: return nil
        }
    }
    var body: some View {
        if let key { Text(key) } else { Text(verbatim: value) }
    }
}
