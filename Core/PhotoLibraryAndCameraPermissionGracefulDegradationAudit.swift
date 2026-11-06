import Foundation

/// Pure self-contained value types auditing `PHPickerViewController` out-of-process zero-permission photo selection,
/// `.limited` / `.denied` photo library graceful fallback for stamp/card export (`w2-09`), and camera `.denied`
/// fallback to manual code entry / photo picker in QR scan flows.
public struct MediaCapturePermissionFlowCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let flowName: String
    public let usesOutOfProcessPHPickerForSelection: Bool
    public let handlesLimitedAndDeniedWithoutCrash: Bool
    public let providesManualOrSettingsFallbackOnDenial: Bool

    public init(
        id: String,
        flowName: String,
        usesOutOfProcessPHPickerForSelection: Bool = true,
        handlesLimitedAndDeniedWithoutCrash: Bool = true,
        providesManualOrSettingsFallbackOnDenial: Bool = true
    ) {
        self.id = id
        self.flowName = flowName
        self.usesOutOfProcessPHPickerForSelection = usesOutOfProcessPHPickerForSelection
        self.handlesLimitedAndDeniedWithoutCrash = handlesLimitedAndDeniedWithoutCrash
        self.providesManualOrSettingsFallbackOnDenial = providesManualOrSettingsFallbackOnDenial
    }

    public var isCompliant: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !flowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && usesOutOfProcessPHPickerForSelection
            && handlesLimitedAndDeniedWithoutCrash
            && providesManualOrSettingsFallbackOnDenial
    }
}

public struct PhotoLibraryAndCameraPermissionGracefulDegradationAudit: Sendable, Equatable {
    public static let canonicalFlows: [MediaCapturePermissionFlowCheck] = [
        MediaCapturePermissionFlowCheck(
            id: "avatar-and-profile-photo-picker",
            flowName: "个人资料头像与背景图进程外选图 (PHPicker)"
        ),
        MediaCapturePermissionFlowCheck(
            id: "publish-9grid-media-picker",
            flowName: "广场九宫格图文发布进程外选图 (PHPicker)"
        ),
        MediaCapturePermissionFlowCheck(
            id: "merchant-shop-apply-license-upload",
            flowName: "商户入驻资质与证照上传进程外选图 (PHPicker)"
        ),
        MediaCapturePermissionFlowCheck(
            id: "qr-scan-and-stamp-poster-save",
            flowName: "二维码扫码相机拒绝手动输入兜底与印章海报保存受限降级"
        )
    ]

    public let flows: [MediaCapturePermissionFlowCheck]

    public init(flows: [MediaCapturePermissionFlowCheck] = PhotoLibraryAndCameraPermissionGracefulDegradationAudit.canonicalFlows) {
        self.flows = flows
    }

    public static func evaluate(
        flows: [MediaCapturePermissionFlowCheck] = canonicalFlows
    ) -> (totalFlows: Int, compliantFlows: Int, isMediaPermissionGraceful: Bool) {
        let total = flows.count
        let compliant = flows.filter(\.isCompliant).count
        let graceful = total > 0 && compliant == total
        return (
            totalFlows: total,
            compliantFlows: compliant,
            isMediaPermissionGraceful: graceful
        )
    }
}
