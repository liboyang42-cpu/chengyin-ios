"""Exact, reversible adapter for the reviewed topic-host source evolution only.

This is not a new run130 runtime result. The historical source, UI and helper
assertions remain owned by test_run130_version_label.py.
"""
from pathlib import Path
import hashlib
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[2]
CURRENT_SHA = '4dcea018c092a8a4a44e07460e2f1e1afeacd7682e7ee14b21acb24ab508b391'
HISTORICAL_SHA = '3feee5e2ef697bf11dc109ddfe5e997a8acfa2eef14ca780d6b6280c669eac7b'
BEFORE_HUNK = (
    '                basicFields\n'
    '                ProjectEditPendingSection(model: model, controller: pending)\n'
)
AFTER_HUNK = (
    '                basicFields\n'
    '                ProjectTopicMediaHost(editor: model)\n'
    '                ProjectEditPendingSection(model: model, controller: pending)\n'
)
FEATURE_PATHS = (
    'App/ProjectTopicMediaPresentation.swift',
    'App/ProjectTopicMediaInspector.swift',
    'Core/ProjectTopicImageUpload.swift',
    'App/ProjectTopicMediaHost.swift',
    'App/AppCompositionRoot.swift',
)



# Exact chapter-removal evolution; historical topic-host and UI guards remain unchanged.
CHAPTER_VIEW_SHA = 'bd626690602d87d9c11defa0914a53f46b4f47096f7a9ee2d9d151378b763b3a'
CHAPTER_SOURCE_SHAS = {'App/ProjectChapterRemovalPresentation.swift': '5e51412a3f0ce37b6f77186cb781ec285b85347accf10e9e6e6da878dd70acdd', 'Core/ProjectChapterRemoval.swift': 'c99b2902a9d481655059ec80a3e9eb390fc06298d8a6ccb70dcecda881100120', 'Core/ProjectEditCoordinator.swift': 'b55f6e40e632b19a6af21351a72130d9b14fcfb6fe9ad99075811ae835e18f57'}
CHAPTER_HUNKS = [('            guard self.fullEdit else { return }; self.draft = value.updatingDraft(self.draft)\n        })\n    }\n    var canEdit: Bool { ownsVisit && loadedSnapshot && loadedSession == coordinator.session && coordinator.snapshot != nil && !busy && !coordinator.isLocked && coordinator.state != .simulated && coordinator.state != .acknowledged && coordinator.state != .blocked && !hasRestore }\n    var canSaveLocal: Bool { canEdit && coordinator.session != nil }\n    var fullEdit: Bool { canEdit && coordinator.snapshot?.scope == .full }\n    var hasRestore: Bool { switch coordinator.restore { case .missing: return false; default: return true } }\n', '            guard self.fullEdit else { return }; self.draft = value.updatingDraft(self.draft)\n        })\n    }\n    var canEdit: Bool { ownsVisit && !coordinator.hasUnconfirmedChapterRemoval && loadedSnapshot && loadedSession == coordinator.session && coordinator.snapshot != nil && !busy && !coordinator.isLocked && coordinator.state != .simulated && coordinator.state != .acknowledged && coordinator.state != .blocked && !hasRestore }\n    var canSaveLocal: Bool { canEdit && coordinator.session != nil }\n    var fullEdit: Bool { canEdit && coordinator.snapshot?.scope == .full }\n    var hasRestore: Bool { switch coordinator.restore { case .missing: return false; default: return true } }\n'), ('    @StateObject private var model: ProjectEditModel\n    @StateObject private var starter: ProjectEditStarterController\n    @StateObject private var pending: ProjectEditPendingController\n    @StateObject private var modeReview: ProjectEditModeReviewController\n    private let ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)?\n    @StateObject private var ownedCover: OwnedTopicCoverAuthorPresentation\n', '    @StateObject private var model: ProjectEditModel\n    @StateObject private var starter: ProjectEditStarterController\n    @StateObject private var pending: ProjectEditPendingController\n    @StateObject private var chapterRemoval: ProjectChapterRemovalController\n    @StateObject private var modeReview: ProjectEditModeReviewController\n    private let ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)?\n    @StateObject private var ownedCover: OwnedTopicCoverAuthorPresentation\n'), ('    init(coordinator: ProjectEditCoordinator, sessionRevision: UInt64, seed: ProjectEditDraft? = nil, publisherClient: PublisherLifecycleHTTP? = nil, publisherHost: ((PublishedResource) -> AnyView)? = nil, ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyImagePicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyAudioPicker: (() -> any ProjectStoryAudioSelecting)? = nil) {\n        self.publisherClient = publisherClient; self.publisherHost = publisherHost; self.ownedCoverPicker = ownedCoverPicker\n        let value = ProjectEditModel(coordinator: coordinator, seed: seed, storyImagePicker: storyImagePicker, storyAudioPicker: storyAudioPicker)\n        _model = StateObject(wrappedValue: value); _starter = StateObject(wrappedValue: .init(model: value)); _pending = StateObject(wrappedValue: .init(model: value)); _modeReview = StateObject(wrappedValue: .init(model: value)); _ownedCover = StateObject(wrappedValue: .init(model: value)); _approvedRelease = StateObject(wrappedValue: .init(model: value)); _reviewRequest = StateObject(wrappedValue: .init(model: value)); self.sessionRevision = sessionRevision\n    }\n    var body: some View {\n        let opening = model.captureStarterLease()\n', '    init(coordinator: ProjectEditCoordinator, sessionRevision: UInt64, seed: ProjectEditDraft? = nil, publisherClient: PublisherLifecycleHTTP? = nil, publisherHost: ((PublishedResource) -> AnyView)? = nil, ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyImagePicker: (() -> any OwnedTopicCoverSelecting)? = nil, storyAudioPicker: (() -> any ProjectStoryAudioSelecting)? = nil) {\n        self.publisherClient = publisherClient; self.publisherHost = publisherHost; self.ownedCoverPicker = ownedCoverPicker\n        let value = ProjectEditModel(coordinator: coordinator, seed: seed, storyImagePicker: storyImagePicker, storyAudioPicker: storyAudioPicker)\n        _model = StateObject(wrappedValue: value); _starter = StateObject(wrappedValue: .init(model: value)); _pending = StateObject(wrappedValue: .init(model: value)); _chapterRemoval = StateObject(wrappedValue: .init(model: value)); _modeReview = StateObject(wrappedValue: .init(model: value)); _ownedCover = StateObject(wrappedValue: .init(model: value)); _approvedRelease = StateObject(wrappedValue: .init(model: value)); _reviewRequest = StateObject(wrappedValue: .init(model: value)); self.sessionRevision = sessionRevision\n    }\n    var body: some View {\n        let opening = model.captureStarterLease()\n'), ('                handledSubmission = next.id; submission = next\n            }\n        }\n        .onChange(of: sessionRevision) { _, _ in if let modePresentation { modeReview.dismiss(modePresentation) }; showingCopy = false; copiedCoordinator = nil; submission = nil; submittedResource = nil; handledSubmission = nil }\n        .navigationDestination(isPresented: Binding(get: { showingCopy && copiedCoordinator === copiedTarget }, set: { showing in\n            guard let copiedTarget, copiedCoordinator === copiedTarget else { return }; showingCopy = showing\n        })) {\n', '                handledSubmission = next.id; submission = next\n            }\n        }\n        .onChange(of: sessionRevision) { _, _ in chapterRemoval.retire(); if let modePresentation { modeReview.dismiss(modePresentation) }; showingCopy = false; copiedCoordinator = nil; submission = nil; submittedResource = nil; handledSubmission = nil }\n        .navigationDestination(isPresented: Binding(get: { showingCopy && copiedCoordinator === copiedTarget }, set: { showing in\n            guard let copiedTarget, copiedCoordinator === copiedTarget else { return }; showingCopy = showing\n        })) {\n'), ('        }\n        .modifier(ProjectEditStarterPresentation(model: model, controller: starter))\n        .modifier(ProjectEditPendingPresentation(model: model, controller: pending))\n        .onDisappear { if let coverPresentation { ownedCover.close(coverPresentation) }; reviewRequest.retire(); approvedRelease.retire(); starter.retire(); pending.retire(); model.leave() }\n        .modifier(ProjectEditPreparedReviewPresentation(model: model))\n        .alert("projectEdit.discardTitle", isPresented: $discardConfirmation) {\n            Button("projectEdit.discardLocal", role: .destructive) { model.discard() }\n', '        }\n        .modifier(ProjectEditStarterPresentation(model: model, controller: starter))\n        .modifier(ProjectEditPendingPresentation(model: model, controller: pending))\n        .modifier(ProjectChapterRemovalPresentation(model: model, controller: chapterRemoval))\n        .onDisappear { if let coverPresentation { ownedCover.close(coverPresentation) }; reviewRequest.retire(); approvedRelease.retire(); chapterRemoval.retire(); starter.retire(); pending.retire(); model.leave() }\n        .modifier(ProjectEditPreparedReviewPresentation(model: model))\n        .alert("projectEdit.discardTitle", isPresented: $discardConfirmation) {\n            Button("projectEdit.discardLocal", role: .destructive) { model.discard() }\n'), ('        }\n    }\n    private func chapterStructure(opening: ProjectEditStarterController.Lease?) -> some View {\n        Section("projectEdit.structure") {\n            ForEach(model.draft.chapters) { chapter in\n                NavigationLink {\n                    ProjectEditChapterView(model: model, chapterID: chapter.id)\n                } label: {\n                    chapterLabel(chapter)\n                }.accessibilityIdentifier("projectEdit.chapter." + chapter.id)\n            }\n            .onDelete { if model.fullEdit { model.draft.chapters.remove(atOffsets: $0) } }\n            .onMove { if model.fullEdit { model.draft.chapters.move(fromOffsets: $0, toOffset: $1) } }\n            Button("projectStarter.createChapter", systemImage: "plus") {\n                let ordinal = model.draft.chapters.filter { $0.preserved["opening"] != .bool(true) }.count + 1\n', '        }\n    }\n    private func chapterStructure(opening: ProjectEditStarterController.Lease?) -> some View {\n        let removalCapture = chapterRemoval.capture()\n        return Section("projectEdit.structure") {\n            if chapterRemoval.saveUnconfirmed {\n                ProjectChapterRemovalStatus(controller: chapterRemoval)\n            }\n            ForEach(model.draft.chapters) { chapter in\n                NavigationLink {\n                    ProjectEditChapterView(model: model, chapterID: chapter.id)\n                } label: {\n                    chapterLabel(chapter)\n                }.accessibilityIdentifier("projectEdit.chapter." + chapter.id)\n                    .deleteDisabled(removalCapture == nil)\n            }\n            .onDelete { chapterRemoval.open(offsets: $0, captured: removalCapture) }\n            .onMove { if model.fullEdit { model.draft.chapters.move(fromOffsets: $0, toOffset: $1) } }\n            Button("projectStarter.createChapter", systemImage: "plus") {\n                let ordinal = model.draft.chapters.filter { $0.preserved["opening"] != .bool(true) }.count + 1\n')]

def verify_chapter_sources(sources):
    assert set(sources) == set(CHAPTER_SOURCE_SHAS)
    for path, sha in CHAPTER_SOURCE_SHAS.items():
        assert hashlib.sha256(sources[path].encode('utf-8')).hexdigest() == sha



CLUB_VIEW_SHA = 'e545ca2551d36cd3f745e0505f80f6bb7203e75575bac2af2f0a050bcac6861f'
CLUB_MOUNT = '                ProjectClubLeadFields(model: model)\n'
CLUB_SOURCE_SHAS = {'App/ProjectClubLeadFields.swift': 'd30db038f00f3253b9d52245d7794820c143ba6dcc859c16f70eb2286dd4ceb9', 'Core/ProjectClubLead.swift': '8fe39f9acea7191c7e43c3fb17bd80e495d3677faaa700c6407844167bcb2be1', 'Core/ProjectEditDraft.swift': '168ccabb57d686287a803f4d82aaec8bb0b09ca65d89a083c30c3cf13cb936f1', 'Core/ProjectEditContract.swift': '218b5964d8d4137f34805c11d8543c480b3773d0195ac65e65d2b1dcfe7cd3d4', 'App/ProjectEditDetailForms.swift': '34a74acb440c215d88a41fd9909684d566b139c71f3d72c7e671a6b910e86d85'}

def verify_club_sources(sources):
    from tools.run138_current_source_projection import description_sources_before_buffer
    try:
        sources = description_sources_before_buffer(sources, ROOT)
    except ValueError as error:
        raise AssertionError("Unreviewed current node-description bytes") from error
    assert set(sources) == set(CLUB_SOURCE_SHAS)
    for path, sha in CLUB_SOURCE_SHAS.items():
        assert hashlib.sha256(sources[path].encode('utf-8')).hexdigest() == sha


def restore_club_lead_source(source):
    if (ROOT / "App/ProjectRemoteVersionRow.swift").exists():
        from test_ci138_version_row_source import restore_version_row
        source = restore_version_row(source)
    assert hashlib.sha256(source.encode('utf-8')).hexdigest() == CLUB_VIEW_SHA
    verify_club_sources({path: (ROOT / path).read_bytes().decode('utf-8')
                         for path in CLUB_SOURCE_SHAS})
    assert source.count(CLUB_MOUNT) == 1
    restored = source.replace(CLUB_MOUNT, '', 1)
    assert hashlib.sha256(restored.encode('utf-8')).hexdigest() == CHAPTER_VIEW_SHA
    return restored


def restore_chapter_removal_source(source):
    if (ROOT / 'App/ProjectClubLeadFields.swift').exists():
        source = restore_club_lead_source(source)
    assert hashlib.sha256(source.encode('utf-8')).hexdigest() == CHAPTER_VIEW_SHA
    verify_chapter_sources({path: (ROOT / path).read_bytes().decode('utf-8')
                            for path in CHAPTER_SOURCE_SHAS})
    for before, after in CHAPTER_HUNKS:
        assert source.count(after) == 1
        source = source.replace(after, before, 1)
    assert hashlib.sha256(source.encode('utf-8')).hexdigest() == CURRENT_SHA
    return source

def restore_topic_host_source(source):
    """Require the entire exact current postimage before reversing its one hunk."""
    if (ROOT / 'App/ProjectChapterRemovalPresentation.swift').exists():
        source = restore_chapter_removal_source(source)
    assert hashlib.sha256(source.encode('utf-8')).hexdigest() == CURRENT_SHA
    assert source.count(AFTER_HUNK) == 1
    historical = source.replace(AFTER_HUNK, BEFORE_HUNK, 1)
    assert hashlib.sha256(historical.encode('utf-8')).hexdigest() == HISTORICAL_SHA
    return historical


def verify_current_feature_sources(sources):
    """Run the existing feature contract on current sources, never reversed ones.

    Only its helper function is invoked; no TestCase is imported into this module,
    avoiding duplicate unittest discovery/counting.
    """
    path = ROOT / 'Tests/ContractChecks/test_project_topic_media_app.py'
    spec = importlib.util.spec_from_file_location('_run130_current_topic_contract', path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.contracts(*sources)


class Run130TopicMediaSourceAdapterTests(unittest.TestCase):
    def current_source(self):
        return (ROOT / 'App/ProjectEditView.swift').read_bytes().decode('utf-8')

    def feature_sources(self):
        return tuple((ROOT / path).read_bytes().decode('utf-8') for path in FEATURE_PATHS)

    def test_exact_current_feature_contract_precedes_reversal(self):
        verify_current_feature_sources(self.feature_sources())
        historical = restore_topic_host_source(self.current_source())
        self.assertEqual(hashlib.sha256(historical.encode()).hexdigest(), HISTORICAL_SHA)
        self.assertNotIn('ProjectTopicMediaHost(editor: model)', historical)

    def test_new_host_hunk_change_removal_duplication_or_relocation_is_rejected(self):
        source = self.current_source()
        line = '                ProjectTopicMediaHost(editor: model)\n'
        candidates = [
            source.replace(line, '', 1),
            source.replace(line, line + line, 1),
            source.replace(line, line.replace('model)', 'otherModel)'), 1),
            source.replace(line, '', 1) + line,
            source.replace(AFTER_HUNK, AFTER_HUNK.replace('basicFields', 'basicFields.disabled(true)'), 1),
        ]
        for candidate in candidates:
            with self.subTest(candidate_sha=hashlib.sha256(candidate.encode()).hexdigest()):
                with self.assertRaises(AssertionError):
                    restore_topic_host_source(candidate)

    def test_original_accessibility_and_unrelated_bytes_remain_exact(self):
        source = self.current_source()
        line = ('                        ProjectRemoteVersionRow(revision: model.draft.baseRevision)\n'
                if (ROOT / 'App/ProjectRemoteVersionRow.swift').exists() else
                '                                .accessibilityLabel(Text(verbatim: model.draft.baseRevision))\n')
        self.assertEqual(source.count(line), 1)
        for candidate in [source.replace(line, '', 1), source.replace(line, line.replace('model.draft.baseRevision', '"fixture-r2"'), 1),
                          source.replace('import SwiftUI', 'import Foundation', 1), source + '\n', source.replace('\n', '\r\n')]:
            with self.subTest(candidate_sha=hashlib.sha256(candidate.encode()).hexdigest()):
                with self.assertRaises(AssertionError):
                    restore_topic_host_source(candidate)

    def test_chapter_feature_mutation_cannot_hide_behind_historical_reversal(self):
        sources = {path: (ROOT / path).read_bytes().decode('utf-8')
                   for path in CHAPTER_SOURCE_SHAS}
        verify_chapter_sources(sources)
        for path in sources:
            changed = dict(sources); changed[path] += '\n'
            with self.subTest(path=path), self.assertRaises(AssertionError):
                verify_chapter_sources(changed)
        source = self.current_source()
        for token in ['!coordinator.hasUnconfirmedChapterRemoval',
                      '.onDelete { chapterRemoval.open(offsets: $0, captured: removalCapture) }',
                      '.deleteDisabled(removalCapture == nil)',
                      'chapterRemoval.retire(); starter.retire(); pending.retire(); model.leave()']:
            self.assertIn(token, source)
            with self.subTest(token=token), self.assertRaises(AssertionError):
                restore_topic_host_source(source.replace(token, 'REMOVED', 1))
        original = restore_chapter_removal_source(source)
        with self.assertRaises(AssertionError):
            restore_topic_host_source(original)

    def test_club_lead_feature_cannot_hide_behind_historical_reversal(self):
        source = self.current_source()
        restored = restore_club_lead_source(source)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), CHAPTER_VIEW_SHA)
        # Issue navigation adds this exact approved anchor to the same mount.
        # Each negative must alter real bytes before the unchanged strict guard.
        forms = {CLUB_MOUNT.strip(), CLUB_MOUNT.strip() + '.id("project-issue-anchor-clubLead")'}
        mounts = [line for line in source.splitlines(keepends=True) if line.strip() in forms]
        self.assertEqual(len(mounts), 1)
        mount = mounts[0]
        for altered in [source.replace(mount, '', 1),
                        source.replace(mount, mount + mount, 1),
                        source.replace(mount, mount.replace('model: model', 'model: other'), 1),
                        source.replace(mount, '', 1) + mount]:
            self.assertNotEqual(altered, source)
            with self.subTest(digest=hashlib.sha256(altered.encode()).hexdigest()), self.assertRaises(AssertionError):
                restore_topic_host_source(altered)
        sources = {path: (ROOT / path).read_bytes().decode('utf-8') for path in CLUB_SOURCE_SHAS}
        verify_club_sources(sources)
        for path in sources:
            changed = dict(sources); changed[path] += '\n'
            with self.subTest(path=path), self.assertRaises(AssertionError):
                verify_club_sources(changed)

    def test_current_feature_mutation_cannot_hide_behind_historical_reversal(self):
        current = self.feature_sources()
        for index, token in [(0, 'editor.topicMediaContext == original.context'),
                             (1, 'O_NOFOLLOW'), (2, 'currentApproval() == approval'),
                             (3, 'RetainedImagePresenterHost'), (4, 'issued.fields.contains(field)')]:
            changed = list(current); self.assertIn(token, changed[index]); changed[index] = changed[index].replace(token, 'REMOVED')
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_current_feature_sources(tuple(changed))


if __name__ == '__main__':
    unittest.main()
