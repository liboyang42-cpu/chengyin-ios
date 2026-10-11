import SwiftUI
import UIKit

/// Local rendering only. Sharing never fetches an image, uploads a card or starts a walk.
@MainActor struct RoamMedalShareView: View {
    let selection: RoamMedalShareSelection
    let reader: any RoamExperienceReading
    private let authority: RoamMedalShareAuthority?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var photoSave = RoamSharePhotoSaveModel()
    @State private var image: UIImage?
    @State private var visible = false
    @State private var sourceChanged = false
    @State private var renderFailed = false
    @State private var systemShare: ShareImage?
    private struct ShareImage: Identifiable { let id = UUID(); let image: UIImage }
    init(selection: RoamMedalShareSelection, reader: any RoamExperienceReading) {
        self.selection = selection; self.reader = reader
        authority = RoamMedalShareAuthority(selection: selection, reader: reader)
    }
    private var ownerMatches: Bool { authority?.matchesOwner(reader) == true }
    private var sourceIsCurrent: Bool { visible && authority?.isCurrent(reader) == true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("roam.medalShare.privacy").font(.subheadline).foregroundStyle(.secondary)
                if ownerMatches && !sourceChanged {
                    Text(verbatim: selection.card.name).font(.title2).bold().textSelection(.enabled)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel(Text("roam.medalShare.preview"))
                            .accessibilityIdentifier("roam.medalShare.preview")
                        saveControls(image)
                        Button {
                            guard sourceIsCurrent else { invalidate(); sourceChanged = true; return }
                            systemShare = ShareImage(image: image)
                        } label: {
                            Label("roam.share.system", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.bordered)
                            .disabled(photoSave.inFlight || photoSave.state.phase == .sourceChanged)
                            .accessibilityIdentifier("roam.medalShare.system")
                    } else {
                        if renderFailed { Text("roam.share.renderFailed") }
                        Button("roam.medalShare.prepare", systemImage: "medal") { prepare() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("roam.medalShare.prepare")
                    }
                } else {
                    Text("roam.share.photoSaveSourceChanged").foregroundStyle(.secondary)
                        .accessibilityIdentifier("roam.medalShare.sourceChanged")
                }
                Text("roam.share.saveHint").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("roam.medalShare.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("action.done") { dismiss() }.accessibilityIdentifier("roam.medalShare.done")
            } }
            .onAppear { visible = true; sourceChanged = !sourceIsCurrent }
            .onChange(of: RoamHistoryLiveOwner(reader: reader)) { _, _ in invalidate(); sourceChanged = true }
            .onDisappear {
                // A full-screen system share presentation may cover its presenting view.
                // Keep that one user-requested export alive; owner changes still retire it.
                if systemShare == nil { visible = false; invalidate() }
            }
            .sheet(item: $systemShare) { item in
                if sourceIsCurrent { RoamMedalSystemShare(image: item.image) }
            }
    }
    private func prepare() {
        guard sourceIsCurrent else { invalidate(); sourceChanged = true; return }
        photoSave.invalidate()
        image = RoamMedalShareRenderer.render(selection.card)
        renderFailed = image == nil
    }
    private func invalidate() { photoSave.invalidate(); systemShare = nil; image = nil; renderFailed = false }
    @ViewBuilder private func saveControls(_ image: UIImage) -> some View {
        let phase = photoSave.state.phase
        Button {
            photoSave.save(image, selection: .init(record: selection.record, includeRoute: false)) { sourceIsCurrent }
        } label: {
            Label(LocalizedStringKey(saveButtonKey), systemImage: "square.and.arrow.down")
        }.buttonStyle(.borderedProminent)
            .disabled(photoSave.inFlight || phase == .saved || phase == .sourceChanged)
            .accessibilityIdentifier("roam.medalShare.savePhotos")
        if photoSave.inFlight { ProgressView("roam.share.savingPhotos") }
        else if let key = saveStatusKey {
            Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("roam.medalShare.saveStatus")
        }
        if phase == .permissionDenied, !photoSave.inFlight {
            Button("roam.share.openPhotoSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.accessibilityIdentifier("roam.medalShare.openPhotoSettings")
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
}

@MainActor private struct RoamMedalSystemShare: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Preview and both export actions use this same image. No asset URL or mutable live result.
@MainActor enum RoamMedalShareRenderer {
    static func render(_ card: RoamMedalShareSelection.Card) -> UIImage? {
        let renderer = ImageRenderer(content: RoamMedalShareCard(card: card)
            .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
        renderer.scale = 2.5 // 300×400 points -> the retained Mini's 750×1000 portrait card.
        return renderer.uiImage
    }
}

private struct RoamMedalShareCard: View {
    let card: RoamMedalShareSelection.Card
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.3), .clear], center: .center, startRadius: 10, endRadius: 95))
                Circle().fill(LinearGradient(colors: [.white, .gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                Image(systemName: "medal.fill").font(.system(size: 42)).foregroundStyle(.black.opacity(0.75))
            }.frame(height: 120).accessibilityHidden(true)
            Text("roam.medalShare.earned").font(.caption).tracking(4).foregroundStyle(.white.opacity(0.75))
            Text(verbatim: card.name).font(.title3.bold()).multilineTextAlignment(.center)
                .lineLimit(3).minimumScaleFactor(0.5)
            Text(LocalizedStringKey(card.kind == .journey ? "roam.medalShare.journey" : "roam.medalShare.shop"))
                .font(.caption).foregroundStyle(.white.opacity(0.75))
            if let date = card.recordedAt { Text(date, style: .date).font(.caption).foregroundStyle(.white.opacity(0.7)) }
            Spacer(minLength: 0)
            Text("roam.medalShare.brand").font(.caption2).foregroundStyle(.white.opacity(0.5))
        }.padding(24).frame(width: 300, height: 400)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(white: 0.13), .black], startPoint: .top, endPoint: .bottom))
    }
}
