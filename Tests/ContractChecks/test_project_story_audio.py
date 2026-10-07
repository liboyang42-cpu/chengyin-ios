"""Supplementary source fences. Swift methods are authored coverage, not executed evidence."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ProjectStoryAudioSourceContract(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text()

    def test_existing_coordinated_reader_is_reused_without_microphone_or_decoder(self):
        reader = self.read("App/ProjectStoryAudioSelectedDocumentReader.swift")
        capture = self.read("Core/ProjectStorySelectedAudio.swift")
        picker = self.read("App/ProjectStoryAudioDocumentPicker.swift")
        self.assertIn("TemplateAudioDocumentReadCoordinating", reader)
        self.assertIn("coordination.coordinateRead(selectedURL:", reader)
        self.assertIn("O_RDONLY | O_NOFOLLOW | O_NONBLOCK", reader)
        self.assertIn("S_IFREG", reader)
        self.assertIn("initial.st_mtimespec", reader)
        self.assertIn("capture.clear()", reader)
        self.assertIn("TemplateAudioDocumentInspection.inspect", capture)
        self.assertIn("maximumBytes - chunk.count", capture)
        self.assertIn("reader.read(selectedURL:", picker)
        self.assertIn("reading == nil else { return }; cancel()", picker)
        for source in (reader, capture, picker):
            self.assertNotIn("AVAudioRecorder", source)
            self.assertNotIn("requestRecordPermission", source)
            self.assertNotIn("AVPlayer(", source)

    def test_default_off_audio_capability_is_independent_and_current_on_outer_clone(self):
        composition = self.read("App/AppCompositionRoot.swift")
        session = self.read("App/AppSession.swift")
        self.assertIn("projectStoryAudioUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectStoryAudioUploadApproval? = { _ in nil }", composition)
        self.assertIn("ProjectStoryAudioCompositionRoute.accepts", composition)
        self.assertIn("transport.projectStoryAudioUploadApproval = { self.projectStoryAudioUploadApproval($0) }", composition)
        self.assertIn("projectEditConfigurationRevision() == revision && projectStoryAudioUploadApproval(context) == issued", composition)
        self.assertIn("makeProjectStoryAudioSource", session)
        self.assertIn("context.market == .china", session)
        tests = self.read("Tests/AppUnitTests/ProjectStoryAudioCompositionTests.swift")
        for name in ("testImageOnlyApprovalCannotAuthorizeAudioFactoryOrOuterBody", "testHeldCloneResponseAfterConfigurationABAIsRejectedWithoutBorrowingNewGrant", "testRoleABARetiresOriginalFactoryAndPreservesDurableOwnerNamespace"):
            self.assertIn(name, tests)

    def test_upload_uses_existing_exact_document_multipart_and_bounded_reference(self):
        client = self.read("Core/ProjectStoryAudioUpload.swift")
        route = self.read("App/ProjectStoryAudioCompositionRoute.swift")
        self.assertIn('"api/common/uploadOSS"', client)
        self.assertIn('name=\\"fileType\\"', client)
        self.assertIn('name=\\"fileName\\"', client)
        self.assertIn("audio.bytes", client)
        self.assertIn("request.httpBodyStream == nil", route)
        self.assertIn("body.count <= TemplateAudioDocumentInspection.maximumBytes + 4096", route)
        self.assertIn("ProjectStorySelectedAudio.validFilename", route)
        self.assertIn("bytes.range(of:", route)
        self.assertIn("RetainedImageOrigin.accepts", client)
        self.assertNotIn('"api/topic/cover/', client)
        self.assertNotIn("image_free", client)

    def test_actual_editor_inserts_local_empty_block_and_only_original_target_can_apply(self):
        host = self.read("App/ProjectEditDetailForms.swift")
        controller = self.read("App/ProjectStoryAudioPresentation.swift")
        target = self.read("Core/ProjectStoryAudioTarget.swift")
        self.assertIn("storyAudios.insertEmpty(chapterID:", host)
        self.assertIn("storyImages.presentation == nil, storyAudios.presentation == nil", host)
        self.assertIn("model.storyAudioPicker?()", host)
        self.assertIn("ProjectEditBlock(kind: .audio)", controller)
        self.assertIn("editor.persistLocalChange(next, lease: lease)", controller)
        self.assertIn("editor.storyTopologyRevision == original.topology", controller)
        self.assertIn("presentation?.id == original.id", controller)
        self.assertIn("original.target.matches", controller)
        self.assertIn("next.chapters[ci].blocks?[bi].url = receipt.reference", target)
        self.assertNotIn(".append(", target)
        self.assertIn("receipt.reference.utf16.count <= 500", target)

    def test_unknown_has_no_automatic_retry_and_unstored_receipt_is_independent(self):
        flow = self.read("Core/ProjectStoryAudioFlow.swift")
        view = self.read("App/ProjectStoryAudioAuthorView.swift")
        self.assertLess(flow.index("journal.begin("), flow.index("public func upload("))
        self.assertIn("snapshot != nil && isCurrent", flow)
        self.assertIn("hasUnstoredReceipt:Bool{unstoredReceipt != nil}", flow)
        self.assertIn("journal.remember(received,identity:identity);unstoredReceipt=received", flow)
        self.assertIn("if flow.hasUnstoredReceipt", view)
        self.assertIn("flow.claimUpload(original)", view)
        self.assertNotIn("retryUpload", flow)
        self.assertNotIn("statusPath", flow)
        self.assertIn("new explicitly selected upload creates another attempt", view)

    def test_local_filename_does_not_enter_wire_and_prepared_view_uses_captured_payload(self):
        draft = self.read("Core/ProjectEditDraft.swift")
        serializer = self.read("Core/ProjectEditStoryContract.swift")
        view = self.read("App/ProjectStoryAudioAuthorView.swift")
        self.assertIn("localAudio: ProjectStoryAudioLocalMetadata? = nil", draft)
        self.assertNotIn("localAudio", serializer)
        prepared = view.split("struct ProjectStoryAudioPreparedReferences", 1)[1]
        self.assertIn('payload["chapters"]', prepared)
        self.assertNotIn("model.draft", prepared)
        self.assertNotIn("AsyncImage", prepared)

    def test_bilingual_keys_are_in_real_catalog_and_fixture_is_explicit(self):
        catalog = json.loads(self.read("Resources/Localizable.xcstrings"))["strings"]
        keys = [k for k in catalog if k.startswith("projectStoryAudio.")]
        self.assertEqual(len(keys), 23)
        for key in keys:
            for locale in ("en", "zh-Hans"):
                self.assertTrue(catalog[key]["localizations"][locale]["stringUnit"]["value"])
        fixture = self.read("App/ProjectEditFixtureSupport.swift")
        self.assertIn('arguments.contains("--project-story-audio")', fixture)
        self.assertIn("Test-only generated audio bytes", fixture)
        self.assertIn('"storyAudioUploadCount": audio?.uploadCount ?? 0', fixture)
        self.assertIn('for (key, count) in ProjectStoryMediaFixtureCounters.snapshot(image: storyImageSource, audio: storyAudioSource) { payload[key] = count }', fixture)
        self.assertIn("storyAudioPicker: context.storyAudioPicker", fixture)

    def test_authored_regressions_cover_actual_cancel_recovery_topology_and_complete_journeys(self):
        unit = self.read("Tests/AppUnitTests/ProjectStoryAudioPresentationTests.swift")
        for name in ("testInsertSavesEmptyBlockBeforePickerAndCancellationKeepsIt", "testRealReorderThenRestoreAndDeleteThenRestoreRetireOldPresentation", "testReceiptFailureReopenSavesOriginalReceiptLocallyWithoutSecondUpload", "testOldDismissAndQueuedUploadCannotAffectNewPresentation"):
            self.assertIn(name, unit)
        for name in ("ProjectStoryAudioFlowTests", "ProjectStoryAudioRecoveryFlowTests"):
            ui = self.read("Tests/AppUITests/" + name + ".swift")
            self.assertIn("assertFixtureEnvironment", ui)
            self.assertIn("UNMEASURED complete-method estimate: 900 seconds", ui)
            self.assertIn("projectEdit.fixture.reopen", ui)
            self.assertIn("projectStoryAudio.remove.", ui)
            self.assertIn('value["submissionCount"] as? Int, 0', ui)


if __name__ == "__main__":
    unittest.main()
