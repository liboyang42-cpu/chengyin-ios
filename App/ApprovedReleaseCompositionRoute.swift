import Foundation

/// Exact author requests only. This grants no legacy creator, player-start or arbitrary business route.
enum ApprovedReleaseCompositionRoute {
    case prepare, publish, status, reviewPrepare, reviewSubmit, reviewStatus, reviewCurrent
    var feature: BusinessRuntimeFeature {
        switch self { case .reviewCurrent: return .approvedTopicReviewCurrent; case .reviewPrepare: return .approvedTopicReviewPrepare; case .reviewSubmit: return .approvedTopicReviewSubmit; case .reviewStatus: return .approvedTopicReviewStatus; case .prepare: return .approvedTopicReleasePrepare; case .publish: return .approvedTopicReleasePublish; case .status: return .approvedTopicReleaseStatus }
    }
    var path: String {
        switch self { case .reviewCurrent: return ApprovedTopicReviewPath.current; case .reviewPrepare: return ApprovedTopicReviewPath.prepare; case .reviewSubmit: return ApprovedTopicReviewPath.submit; case .reviewStatus: return ApprovedTopicReviewPath.status; case .prepare: return ApprovedTopicReleasePaths.prepare; case .publish: return ApprovedTopicReleasePublicationPath.publish; case .status: return ApprovedTopicReleasePublicationPath.status }
    }
    init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let bytes = request.httpBody, bytes.count <= 4096,
              let value = try? ApprovedTopicReleaseWire.envelope(bytes), let url = request.url else { return nil }
        if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReleasePaths.prepare).absoluteString { self = .prepare }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReleasePublicationPath.publish).absoluteString { self = .publish }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReleasePublicationPath.status).absoluteString { self = .status }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReviewPath.prepare).absoluteString { self = .reviewPrepare }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReviewPath.submit).absoluteString { self = .reviewSubmit }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReviewPath.status).absoluteString { self = .reviewStatus }
        else if url.absoluteString == baseURL.appendingPathComponent(ApprovedTopicReviewPath.current).absoluteString { self = .reviewCurrent }
        else { return nil }
        switch self {
        case .reviewPrepare, .reviewSubmit, .reviewStatus, .reviewCurrent:
            guard let topic = value["topicId"]?.integer, topic > 0, let task = value["observedAuditTaskId"]?.integer, task > 0 else { return nil }
            if case .reviewPrepare = self { guard Set(value.keys) == ["topicId", "observedAuditTaskId"] else { return nil }; return }
            guard Set(value.keys) == ["topicId", "observedAuditTaskId", "observedAuditTaskVersion", "sourceConfigVersion", "snapshotHash", "requestId"],
                  let version = value["observedAuditTaskVersion"]?.integer, version >= 0, version <= Int(Int32.max),
                  let source = value["sourceConfigVersion"]?.integer, source >= 0,
                  let hash = value["snapshotHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
                  let id = value["requestId"]?.text, UUID(uuidString: id)?.uuidString == id else { return nil }
            return
        default: break
        }
        guard let topic = value["topicId"]?.integer, topic > 0, let audit = value["auditTaskId"]?.integer, audit > 0 else { return nil }
        if case .prepare = self { guard Set(value.keys) == ["topicId", "auditTaskId"] else { return nil }; return }
        guard Set(value.keys) == ["topicId", "auditTaskId", "auditTaskVersion", "auditSnapshotHash", "expectedHeadRevision", "expectedManifestHash", "requestId"],
              let version = value["auditTaskVersion"]?.integer, version >= 0, version <= Int(Int32.max),
              let head = value["expectedHeadRevision"]?.integer, head >= 0,
              let auditHash = value["auditSnapshotHash"]?.text, ApprovedTopicReleasePreparation.validHash(auditHash),
              let manifestHash = value["expectedManifestHash"]?.text, ApprovedTopicReleasePreparation.validHash(manifestHash),
              let id = value["requestId"]?.text, UUID(uuidString: id)?.uuidString == id else { return nil }
    }
}
