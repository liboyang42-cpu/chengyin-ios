import SwiftUI
import ImageIO

@MainActor struct NativeChannelAttachmentPreviewEntry: View {
    @State private var retainedFlow: NativeChannelAttachmentPreviewFlow
    private var flow: NativeChannelAttachmentPreviewFlow { retainedFlow }
    let current: () -> Bool
    init(flow:NativeChannelAttachmentPreviewFlow,current:@escaping ()->Bool) {
        _retainedFlow=State(initialValue:flow);self.current=current
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var revision = 0
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var screenActive = false
    var body: some View {
        // Refresh in place: changing a ScrollView identity on every state update
        // resets its position and assistive-technology focus during large-text use.
        let _ = revision
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    if !current() || !flow.isCurrent {
                        status("preview.changed")
                    } else {
                        switch flow.visibleState {
                        case .idle: status("preview.idle")
                        case .loading:
                            ProgressView { Text("preview.loading", tableName: "NativeChannelAttachmentPreview") }
                                .accessibilityIdentifier("attachmentPreview.loading")
                        case .pending: status("preview.pending")
                        case .rejected: status("preview.rejected")
                        case .expired: status("preview.expired")
                        case .unsupported: status("preview.unsupported")
                        case .sourceUnconfirmed: status("preview.sourceUnconfirmed")
                        case .unavailable: status("preview.unavailable")
                        case .unknown: status("preview.unknown")
                        case .displayed:
                            if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxWidth: 1200, maxHeight: 1200)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(Text("preview.image", tableName: "NativeChannelAttachmentPreview"))
                                    .accessibilityIdentifier("attachmentPreview.image")
                            }
                        }
                        if !flow.enabled { status("preview.notConfigured") }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if current() && flow.isCurrent {
                    if flow.enabled && flow.visibleState != .loading && flow.visibleState != .displayed {
                        Button {
                            loadTask?.cancel()
                            loadTask = Task {
                                guard screenActive, scenePhase == .active, current(), flow.isCurrent,
                                      !Task.isCancelled else { return }
                                await flow.load()
                            }
                        } label: {
                            Text("preview.load", tableName: "NativeChannelAttachmentPreview")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }.nativeChannelPrimaryAction()
                            .accessibilityIdentifier("attachmentPreview.load")
                    }
                    Button { clear() } label: {
                        Text("preview.clear", tableName: "NativeChannelAttachmentPreview")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }.font(Theme.Font.button).buttonStyle(.borderless).accessibilityIdentifier("attachmentPreview.clear")
                }
            }.font(Theme.Font.body).padding()
        }.nativeChannelScreen().privacySensitive()
        .navigationTitle(Text("preview.title", tableName: "NativeChannelAttachmentPreview"))
        .onAppear { screenActive = true; flow.onChange = { updateImage();revision += 1 };updateImage() }
        .onDisappear { screenActive = false; clear();flow.onChange=nil }
        .onChange(of: current()) { _,value in if !value {clear()} }
        .onChange(of: flow.isCurrent) { _,value in if !value {clear()} }
        .onChange(of: scenePhase) { _,phase in if phase != .active {clear()} }
    }
    private func status(_ key: LocalizedStringKey) -> some View {
        Text(key, tableName: "NativeChannelAttachmentPreview")
            .fixedSize(horizontal: false, vertical: true)
            .nativeChannelNotice(systemImage: "photo")
            .accessibilityIdentifier("attachmentPreview.status")
    }
    private func updateImage() {
        guard current(),flow.isCurrent,flow.visibleState == .displayed,let data=flow.bytes else{image=nil;return}
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue>0,height.doubleValue>0,width.doubleValue*height.doubleValue<=32_000_000,
              let decoded=UIImage(data:data) else {image=nil;flow.unsupportedBytes();return}
        image=decoded
    }
    private func clear() { loadTask?.cancel(); loadTask = nil; image=nil;flow.clear() }
}
