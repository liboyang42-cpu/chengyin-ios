"""Offline P02 presentation/authority checks, not Swift or native-render tests."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class P02EditorPresentationCloseoutTests(unittest.TestCase):
    def source(self, leaf): return (ROOT / 'App' / (leaf + '.swift')).read_text()
    def contains(self, leaf, values):
        source = self.source(leaf)
        for value in values: self.assertIn(value, source)
    def testNormalEditorRoutesKeepOriginalSessionIdentity(self):
        self.contains('ProjectEditLaunchView', ['session.projectEditor(product: .city)', 'session.projectEditor(product: .freeExplore)', '.id(session.projectEditorContextID)', 'SessionCreatorProjectsView(session: session)'])
    def testFormSurfaceIsOnlyLayout(self):
        source = self.source('ProjectEditView').split('struct ProjectEditorFormSurface: ViewModifier {')[1].split('/// A visible label')[0]
        for value in ['.formStyle(.grouped)', '.environment(\\.defaultMinListRowHeight, 44)', '.scrollDismissesKeyboard(.interactively)']: self.assertIn(value, source)
        for value in ['@State', 'Task', 'onAppear', 'onDisappear', 'session', 'coordinator', '.disabled', '.task', '.id(']: self.assertNotIn(value, source)
    def testVisibleFieldLabelDoesNotReplaceInputAccessibility(self):
        self.contains('ProjectEditView', ['struct ProjectEditorField<Content: View>: View', 'Text(title).font(.subheadline).foregroundStyle(.secondary).accessibilityHidden(true)', 'self.title = title; self.content = content()'])
        self.contains('ProjectEditNodeDescriptionField', ['TextField("projectEdit.description", text: buffer.binding, axis: .vertical)', '.accessibilityIdentifier("projectEdit.nodeDescription")', '.disabled(source.target == nil)'])
    def testDescriptionBufferRetainsStaleWriteProtection(self):
        self.contains('ProjectEditNodeDescriptionField', ['guard active, capturedRevision == revision, let target, source.target == target else { return }', 'guard Data(current.description.utf8) == acknowledgedBytes else { synchronize(); return }', 'source.node.wrappedValue = current', '.onChange(of: source.snapshot) { _, _ in buffer.synchronize() }', '.onDisappear { buffer.invalidate() }'])
    def testEditorStillRequiresCurrentVisitAndSession(self):
        self.contains('ProjectEditView', ['loadedSession == coordinator.session', 'ownsVisit && !coordinator.isReadOnly', '!coordinator.hasUnconfirmedChapterRemoval', '!coordinator.isLocked', 'coordinator.state != .blocked', 'model.coordinator', 'draftMutationRevision += 1'])
    def testStarterKeepsLeaseAndUnconfirmedSave(self):
        self.contains('ProjectEditStarterPresentation', ['if controller.isCurrent(original)', 'ProjectEditChapterView(model: model, chapterID: original.chapterID, starterLease: original)', 'if controller.saveUnconfirmed', '.disabled(!controller.canFinish(original))', 'controller.willSaveToPending(original)', 'controller.close(original)'])
    def testNarrativeKeepsLocalPersistenceConfirmation(self):
        self.contains('ProjectNodeNarrativeFields', ['guard model.persistLocalChange(next, lease: value.lease) else { saveUnconfirmed = true; return }', '.disabled(!controller.canSave(value))', '.onDisappear { controller.retire() }', 'if controller.saveUnconfirmed'])
    def testExitActionsReflowWithoutRemovingWarnings(self):
        self.contains('ProjectEditExitGuard', ['dynamicTypeSize.isAccessibilitySize', 'AnyLayout(VStackLayout(alignment: .leading, spacing: 8))', 'Text(LocalizedStringKey(original.reason.rawValue), tableName: "ProjectEditExitGuard")', 'Button(action: owner.continueAction(original))', 'Button(action: owner.retryAction(original, dismiss: leave))', 'Button(role: .destructive, action: owner.leaveAction(original, dismiss: leave))'])
    def testExitKeepsOverlayAndForegroundProtection(self):
        self.contains('ProjectEditExitGuard', ['content.disabled(owner.review != nil).navigationBarBackButtonHidden(true).interactiveDismissDisabled(true)', 'guard canNavigate, nativeUncovered, snapshot() == before else { return }', 'original.reason == .saveFailed, self.current(original)', '.onDisappear { owner.disappear() }', 'owner.sceneChanged(active: phase == .active)', 'owner.overlayChanged()'])
    def testStoryFieldKeepsExactCurrentBindingAndSceneRetirement(self):
        self.contains('ProjectStoryTextField', ['text: controller.binding(lifetime)', '.disabled(!controller.canEdit)', '.onChange(of: model.coordinator.session)', '.onChange(of: model.canEdit)', '.onChange(of: model.editorIncarnation)', 'controller.setSceneActive(next == .active)', '.onDisappear { controller.disappear() }'])
    def testCategoryPreservesRetainedIDsAndFailureRetry(self):
        self.contains('ProjectCategoryPicker', ['controller.retainedIDs.filter { !visible.contains($0) }', 'Button("action.retry") { Task { await controller.load(original) } }', '.disabled(!canSave)', 'if current {', '.onChange(of: model.editorIncarnation) { _, _ in controller.retire() }'])
    def testPlacePickerKeepsReadAuthorizationAndExplicitApply(self):
        self.contains('ProjectNodePlacePicker', ['guard let reader, reader.isConfigured, reader.isAuthenticated else', 'controller.captureSearch(original)', 'controller.choose(row, in: original)', '.disabled(!ProjectNodePlaceSelection.permits(row))', '.disabled(!controller.canApply(original))', '.onDisappear { controller.setActive(false) }'])
    def testAlbumRemovalKeepsConfirmationAndOnlyWorkingDraftMutation(self):
        self.contains('ProjectAlbumPhotoRemovalButton', ['Button(role: .destructive)', 'guard scenePhase == .active else { return }; controller.remove(original)', '.disabled(!controller.isCurrent(original))', 'model.draft = next', '.privacySensitive()', '.onDisappear { controller.setActive(false) }'])
    def testOverviewStillUsesCapturedDestination(self):
        self.contains('ProjectDraftNodeOverview', ['controller.choose(row.id, captured: capture, in: original)', 'controller.destinationBinding(selected)', 'ProjectDraftNodeOverviewDestination(controller: controller, original: destination)', '.onDisappear { controller.retire() }'])
    def testCoverKeepsExactAssetAndClose(self):
        self.contains('OwnedTopicCoverImageView', ['Text(verbatim: original.flow.asset.sourceVersion)', 'model.close(); close()', '.navigationBarTitleDisplayMode(.inline)'])
    def testAddedHelpersHaveSingleDefinition(self):
        sources = '\n'.join(path.read_text() for path in (ROOT/'App').glob('*.swift'))
        self.assertEqual(sources.count('struct ProjectEditorFormSurface: ViewModifier'), 1)
        self.assertEqual(sources.count('struct ProjectEditorField<Content: View>'), 1)

if __name__ == '__main__': unittest.main()
