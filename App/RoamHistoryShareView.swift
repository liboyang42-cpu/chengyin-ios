import SwiftUI
import UIKit

/// The user can save the rendered card to Photos or choose a system-sheet recipient.
/// No app upload, public-feed post, private URL or tracking token is generated here.
@MainActor struct RoamHistoryShareView: View {
    let record: RoamHistoryRecord
    let reader: any RoamExperienceReading
    private let presentationOwner: RoamHistoryLiveOwner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openURL) private var openURL
    @StateObject private var photoSave: RoamSharePhotoSaveModel
    @StateObject private var presentation: RoamSharePresentationLifetime
    @State private var includeRoute = false
    @State private var channelPolicy = RoamShareChannelPolicy()
    @State private var image: UIImage?
    @State private var renderingFailed = false
    @State private var renderedRecord: RoamHistoryRecord?
    @State private var renderedIncludeRoute = false
    @State private var renderedOwner: RoamHistoryLiveOwner?
    @State private var albumGuide = RoamShareAlbumGuideState()
    @State private var guideSourceChanged = false
    @State private var systemShare: RoamHistorySystemShareRequest?
    init(record: RoamHistoryRecord, reader: any RoamExperienceReading, photoSaveModel: RoamSharePhotoSaveModel? = nil) {
        let model = photoSaveModel ?? RoamSharePhotoSaveModel()
        _photoSave = StateObject(wrappedValue: model)
        _presentation = StateObject(wrappedValue: .init(photoSave: model))
        self.record = record; self.reader = reader
        presentationOwner = RoamHistoryLiveOwner(reader: reader)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("roam.share.privacy").foregroundStyle(.secondary)
                if !record.track.isEmpty {
                    Toggle("roam.share.includeRoute", isOn: $includeRoute).onChange(of: includeRoute) { _, _ in invalidateImage() }
                }
                RoamShareChannelPicker(mode: Binding(get: { channelPolicy.mode }, set: { mode in
                    if channelPolicy.select(mode, operationInFlight: photoSave.inFlight || albumGuide.pending != nil) {
                        // Retire guide callbacks synchronously. The image has not changed, so keep
                        // any completed save receipt rather than writing the same card twice.
                        albumGuide.invalidate(); guideSourceChanged = false
                    }
                }), isBusy: photoSave.inFlight || albumGuide.pending != nil)
                card
                RoamShareLinkDormantNotice()
                if renderingFailed { Text("roam.share.renderFailed").foregroundStyle(.secondary) }
                if guideSourceChanged { Text("roam.share.photoSaveSourceChanged").foregroundStyle(.secondary) }
                if let image, renderedRecord == record, renderedIncludeRoute == includeRoute,
                   renderedOwner == RoamHistoryLiveOwner(reader: reader) {
                    photoSaveControls(image)
                    if !allowedAlbumDestinations.isEmpty { albumGuideControls(image) }
                    if channelPolicy.permits(.systemShare) {
                        Button { beginSystemShare(image) } label: {
                            Label("roam.share.system", systemImage: "square.and.arrow.up")
                        }.disabled(photoSave.inFlight || albumGuide.pending != nil || systemShare != nil || photoSave.state.phase == .sourceChanged)
                            .accessibilityIdentifier("roam.share.system")
                    }
                } else {
                    Button("roam.share.prepare", systemImage: "photo") {
                        guard sourceIsCurrent else { invalidateImage(); return }
                        let renderer = ImageRenderer(content: card.frame(width: 320).padding(24).background(Color(uiColor: .systemBackground)))
                        renderer.scale = min(3, displayScale)
                        image = renderer.uiImage; renderingFailed = image == nil
                        renderedRecord = image == nil ? nil : record
                        renderedIncludeRoute = includeRoute
                        renderedOwner = image == nil ? nil : presentationOwner
                    }.accessibilityIdentifier("roam.share.prepare")
                }
            }.padding()
        }.navigationTitle("roam.share.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { presentation.retire(); invalidateImage(); dismiss() } } }
            .background(RoamShareNativeLifetime(presentation: presentation).frame(width: 0, height: 0))
            .onAppear { presentation.appear() }
            .onChange(of: record) { _, _ in includeRoute = false; channelPolicy.reset(); invalidateImage() }
            .onChange(of: RoamHistoryLiveOwner(reader: reader)) { _, _ in includeRoute = false; channelPolicy.reset(); invalidateImage() }
            .onChange(of: photoSave.state.phase) { _, phase in receiveAlbumGuide(phase) }
            .sheet(item: Binding(get: { albumGuide.guide }, set: { if $0 == nil { albumGuide.dismissGuide() } })) { guide in
                if permitsAlbumGuide(guide.destination) { RoamShareAlbumGuideView(guide: guide) }
            }
            .sheet(item: $systemShare) { request in
                // Recheck after the tap as well: a local record or owner may have
                // changed before SwiftUI actually presents the system sheet.
                if channelPolicy.permits(.systemShare), image === request.image,
                   preparedSelection == request.selection, request.isCurrent(reader: reader) {
                    RoamHistorySystemShareSheet(request: request, reader: reader)
                } else {
                    Text("roam.share.photoSaveSourceChanged").foregroundStyle(.secondary)
                }
            }
            // Cover/permission alerts are not departures. The native attachment owns true
            // removal even when a guide or system sheet already covers this presenter.
    }
    private func invalidateImage() {
        photoSave.invalidate()
        albumGuide.invalidate()
        systemShare = nil
        guideSourceChanged = false
        image = nil; renderedRecord = nil; renderingFailed = false
        renderedOwner = nil
    }
    private func beginSystemShare(_ image: UIImage) {
        guard channelPolicy.permits(.systemShare), !photoSave.inFlight,
              albumGuide.pending == nil, albumGuide.guide == nil, systemShare == nil else { return }
        guard self.image === image, let selection = preparedSelection,
              let request = RoamHistorySystemShareRequest(image: image, selection: selection,
                  owner: presentationOwner, reader: reader, presentation: presentation) else {
            invalidateImage(); guideSourceChanged = true; return
        }
        systemShare = request
    }
    private var sourceIsCurrent: Bool {
        guard presentation.isActive, presentationOwner == RoamHistoryLiveOwner(reader: reader), presentationOwner.isAuthorized else { return false }
        return (try? reader.history().first { $0.ts == record.ts }) == record
    }
    private var preparedSelection: RoamSharePhotoSaveState.Selection? {
        guard image != nil, renderedRecord == record, renderedIncludeRoute == includeRoute,
              renderedOwner == presentationOwner else { return nil }
        return .init(record: record, includeRoute: includeRoute)
    }
    private func permitsAlbumGuide(_ destination: RoamShareAlbumGuideState.Destination) -> Bool {
        channelPolicy.permits(destination == .moments ? .momentsGuide : .xiaohongshuGuide)
    }
    private var allowedAlbumDestinations: [RoamShareAlbumGuideState.Destination] {
        RoamShareAlbumGuideState.Destination.allCases.filter(permitsAlbumGuide)
    }
    private func albumGuideControls(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("roam.albumGuide.choose").font(.headline)
            Text("roam.albumGuide.beforeSave").font(.caption).foregroundStyle(.secondary)
            ForEach(allowedAlbumDestinations) { destination in
                Button {
                    beginAlbumGuide(destination, image: image)
                } label: {
                    Label(LocalizedStringKey(destination == .moments ? "roam.albumGuide.momentsAction" : "roam.albumGuide.xiaohongshuAction"), systemImage: "photo.on.rectangle")
                }.buttonStyle(.bordered)
                    .disabled(photoSave.inFlight || albumGuide.pending != nil || photoSave.state.phase == .sourceChanged)
                    .accessibilityIdentifier("roam.albumGuide.open." + destination.rawValue)
            }
        }
    }
    private func beginAlbumGuide(_ destination: RoamShareAlbumGuideState.Destination, image: UIImage) {
        guard permitsAlbumGuide(destination) else { return }
        guard let selection = preparedSelection, sourceIsCurrent else {
            invalidateImage(); guideSourceChanged = true; return
        }
        guard let request = albumGuide.begin(destination: destination, selection: selection, saveInFlight: photoSave.inFlight) else { return }
        if photoSave.state.phase == .saved, photoSave.state.selection == selection {
            // The identical prepared card was already saved in this presentation.
            // Reuse its receipt rather than writing a duplicate just to show instructions.
            albumGuide.receive(request, phase: .saved, current: selection, sourceIsCurrent: sourceIsCurrent)
            return
        }
        photoSave.save(image, selection: selection) {
            permitsAlbumGuide(destination) && albumGuide.accepts(request) && preparedSelection == selection && sourceIsCurrent
        }
    }
    private func receiveAlbumGuide(_ phase: RoamSharePhotoSaveState.Phase) {
        guard let request = albumGuide.pending else { return }
        guard permitsAlbumGuide(request.destination) else { albumGuide.invalidate(); return }
        guard let selection = preparedSelection else { albumGuide.invalidate(); return }
        albumGuide.receive(request, phase: phase, current: selection, sourceIsCurrent: sourceIsCurrent)
    }
    @ViewBuilder private func photoSaveControls(_ image: UIImage) -> some View {
        let phase = photoSave.state.phase
        Button {
            let selection = RoamSharePhotoSaveState.Selection(record: record, includeRoute: includeRoute)
            photoSave.save(image, selection: selection) {
                // Read the existing local history again after permission, before writing.
                // A matching timestamp alone does not authorize an edited record.
                guard renderedRecord == record, renderedIncludeRoute == includeRoute,
                      selection.includeRoute == includeRoute, renderedOwner == presentationOwner else { return false }
                return sourceIsCurrent
            }
        } label: {
            Label(LocalizedStringKey(saveButtonKey), systemImage: "square.and.arrow.down")
        }.disabled(photoSave.inFlight || phase == .saved || phase == .sourceChanged)
            .accessibilityIdentifier("roam.share.savePhotos")
        if photoSave.inFlight {
            ProgressView("roam.share.savingPhotos").accessibilityIdentifier("roam.share.savingPhotos")
        } else if let key = saveStatusKey {
            Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("roam.share.photoSaveStatus")
        }
        if phase == .permissionDenied, !photoSave.inFlight {
            Button("roam.share.openPhotoSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.accessibilityIdentifier("roam.share.openPhotoSettings")
        }
    }
    private var saveButtonKey: String {
        switch photoSave.state.phase {
        case .permissionDenied, .restricted, .failed: return "roam.share.retrySavePhotos"
        case .saved: return "roam.share.savedPhotos"
        default: return "roam.share.savePhotos"
        }
    }
    private var saveStatusKey: String? {
        switch photoSave.state.phase {
        case .saved: return "roam.share.savedPhotos"
        case .permissionDenied: return "roam.share.photoPermissionDenied"
        case .restricted: return "roam.share.photoPermissionRestricted"
        case .unavailable: return "roam.share.photoSaveUnavailable"
        case .sourceChanged: return "roam.share.photoSaveSourceChanged"
        case .failed: return "roam.share.photoSaveFailed"
        default: return nil
        }
    }
    private var privateRoute: some View {
        let sketch = RoamShareRoutePrivacy.sketch(for: record)
        return ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.09))
            if sketch.track.isEmpty {
                Label("roam.experience.noTrack", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption).padding()
            } else {
                Canvas { context, size in
                    var path = Path()
                    for (index, point) in sketch.track.enumerated() {
                        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                    }
                    context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }.padding(8).accessibilityHidden(true)
            }
        }.frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sketch.track.isEmpty ? "roam.experience.noTrack" : "roam.experience.routeSketch"))
            .accessibilityIdentifier("roam.share.clippedRoute")
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("roam.experience.cityWalk", systemImage: "figure.walk.circle.fill").font(.title).bold()
            if let date = record.recordedAt { Text(date, style: .date).foregroundStyle(.secondary) }
            RoamRecordedStats(record: record)
            if includeRoute { privateRoute }
            RoamShareCardParityFooter(record: record)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// A system export uses the same prepared image, but not a stale local-history
/// receipt. This is read-only and retains the share surface's existing owner gate.
@MainActor struct RoamHistorySystemShareRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let selection: RoamSharePhotoSaveState.Selection
    private let owner: RoamHistoryLiveOwner
    private weak var presentation: RoamSharePresentationLifetime?
    private let requiresPresentation: Bool
    private var presentationIsCurrent: Bool { !requiresPresentation || presentation?.isActive == true }

    init?(image: UIImage, selection: RoamSharePhotoSaveState.Selection,
          owner: RoamHistoryLiveOwner, reader: any RoamExperienceReading,
          presentation: RoamSharePresentationLifetime? = nil) {
        self.image = image; self.selection = selection; self.owner = owner
        self.presentation = presentation; requiresPresentation = presentation != nil
        guard isCurrent(reader: reader) else { return nil }
    }
    func isCurrent(reader: any RoamExperienceReading) -> Bool {
        guard presentationIsCurrent, owner.isAuthorized, owner == RoamHistoryLiveOwner(reader: reader),
              let records = try? reader.history(), owner == RoamHistoryLiveOwner(reader: reader), presentationIsCurrent else { return false }
        let matching = records.filter { $0.ts == selection.record.ts }
        return matching.count == 1 && matching.first == selection.record
    }
    func makeActivityController(reader: any RoamExperienceReading) -> UIActivityViewController? {
        // UIKit may create the controller after SwiftUI evaluated the sheet body.
        guard isCurrent(reader: reader) else { return nil }
        return UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
}

@MainActor private struct RoamHistorySystemShareSheet: UIViewControllerRepresentable {
    let request: RoamHistorySystemShareRequest
    let reader: any RoamExperienceReading
    func makeUIViewController(context: Context) -> UIViewController {
        if let controller = request.makeActivityController(reader: reader) { return controller }
        return UIViewController()
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
