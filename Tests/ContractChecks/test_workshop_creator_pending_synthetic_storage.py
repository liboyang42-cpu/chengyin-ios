"""DEBUG fixture composition checks; not Swift compilation or real Keychain acceptance."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def without_debug_block(text):
    """Project the exact simple DEBUG block used by this seam, not a Swift compiler."""
    return re.sub(r"(?ms)^#if DEBUG\n.*?^#endif\n", "", text)


class CreatorPendingSyntheticStorageContracts(unittest.TestCase):
    def test_override_is_optional_nil_default_and_debug_only(self):
        factory = between(read("App/AppCompositionRoot.swift"),
                          "@MainActor struct AppScopedStorageFactory {", "@MainActor struct AppCompositionRoot {")
        declaration = "var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil"
        self.assertIn(declaration, factory)
        self.assertNotIn("syntheticWorkshopCreatorPendingRecoveryStorage", without_debug_block(factory))
        self.assertNotIn("TemplateAuthoringMemoryStorage", factory)

    def test_resolver_chooses_explicit_override_before_any_system_operation(self):
        session = read("App/AppSession.swift")
        resolver = between(session, "private var workshopCreatorPendingRecoveryStorage: any TemplateAuthoringStorage {",
                           "    func makeWorkshopCreatorPendingController")
        self.assertIn("if let storage = composition.storage.syntheticWorkshopCreatorPendingRecoveryStorage { return storage }", resolver)
        self.assertEqual(without_debug_block(resolver).strip(), "return templateAuthoringSecureStorage\n    }")
        for forbidden in ("catch", "try?", "TemplateAuthoringMemoryStorage", ".read(", ".write("):
            self.assertNotIn(forbidden, resolver)

    def test_only_three_pending_creator_stores_use_resolver(self):
        session = read("App/AppSession.swift")
        pending = between(session, "func makeWorkshopCreatorPendingController(", "    func makeWorkshopCreatorConsentController(")
        self.assertEqual(pending.count("storage: workshopCreatorPendingRecoveryStorage"), 2)
        self.assertEqual(pending.count("storage: self.workshopCreatorPendingRecoveryStorage"), 1)
        self.assertNotIn("templateAuthoringSecureStorage", pending)
        self.assertEqual(session.count("workshopCreatorPendingRecoveryStorage"), 4)
        standalone = session.split("    func makeWorkshopCreatorConsentController(", 1)[1]
        self.assertIn("WorkshopCreatorConsentPendingStore(storage: templateAuthoringSecureStorage", standalone)
        self.assertNotIn("workshopCreatorPendingRecoveryStorage", standalone)

    def test_one_existing_memory_store_per_debug_harness_is_injected_before_session(self):
        fixture = read("App/WorkshopCreatorPendingFixtureSupport.swift")
        self.assertTrue(fixture.startswith("#if DEBUG\n"))
        self.assertTrue(fixture.rstrip().endswith("#endif"))
        harness = fixture.split("@MainActor final class WorkshopCreatorPendingFixtureHarness:", 1)[1]
        self.assertEqual(harness.count("TemplateAuthoringMemoryStorage()"), 1)
        self.assertIn("let recoveryStorage = TemplateAuthoringMemoryStorage()", harness)
        self.assertNotIn("static let recoveryStorage", harness)
        self.assertLess(harness.index("storage.syntheticWorkshopCreatorPendingRecoveryStorage = recoveryStorage"),
                        harness.index("session = AppCompositionRoot("))
        self.assertIn("storage: storage, makeTransport:", harness)
        self.assertNotIn("TemplateAuthoringSecureStorage", fixture)
        self.assertNotIn("URLSession", fixture)

    def test_cleanup_is_the_only_fixture_memory_clear(self):
        fixture = read("App/WorkshopCreatorPendingFixtureSupport.swift")
        self.assertEqual(fixture.count("recoveryStorage.values.removeAll()"), 1)
        self.assertIn("func clean() {\n        recoveryStorage.values.removeAll()", fixture)
        self.assertNotIn("recoveryStorage.values =", fixture)
        self.assertNotIn("recoveryStorage.failWrites =", fixture)

    def test_real_store_validation_and_readback_are_still_required(self):
        pending = read("Core/WorkshopCreatorPendingController.swift")
        self.assertIn("try WorkshopCreatorWire.encode(record) == data", pending)
        self.assertIn("WorkshopCreatorWire.same(record.ownerKey, ownerKey), record.command.sourceTemplateId == source", pending)
        for source in (pending, read("Core/WorkshopCreatorConsentController.swift")):
            self.assertIn("guard let saved = try load(), try saved.data() == command.data()", source)
            self.assertIn("catch { throw WorkshopCreatorConsentIssue.storage }", source)
        memory = read("Core/TemplateAuthoringSyntheticFixtures.swift")
        self.assertTrue(memory.startswith("#if DEBUG\n"))
        self.assertIn("guard !failWrites else { throw TemplateAuthoringError.storageUnavailable }", memory)

    def test_explicit_runtime_regressions_remain_authored(self):
        source = read("Tests/AppUnitTests/WorkshopCreatorPendingSyntheticStorageTests.swift")
        for method in (
            "DefaultFactoryHasNoSyntheticOverride", "EmptySyntheticStorageLoadsEditableSourceWithoutWrites",
            "AuthorReviewBackAndReopenPreserveOneHarnessStorage",
            "UnknownAuthorReconstructionRetriesIdenticalBytesWithoutAutomaticDispatch",
            "FailedAuthorRetentionSuppressesDispatch", "FailedNestedDeclarationRetentionSuppressesDispatch",
            "NestedDeclarationHistoryUsesSameStorageAfterReconstruction",
            "MalformedAndNoncanonicalAuthorBytesFailClosedWithoutDispatchOrRepair",
            "ForeignOwnerAndSourceAuthorBytesFailClosedWithoutDispatchOrRepair",
            "MalformedDeclarationHistoryFailsClosedBeforeAnyReadOrWriteRequest", "HarnessInstancesAndCleanupAreIsolated",
        ):
            self.assertIn("func test" + method + "(", source)
        self.assertNotIn("XCTSkip", source)
        self.assertNotIn("SecItem", source)

    def test_existing_generator_discovers_the_new_appunit_file(self):
        generator = read("tools/generate_project.py")
        self.assertIn("ROOT.glob('Tests/AppUnitTests/**/*.swift')", generator)
        self.assertIn("Tests/AppUnitTests/WorkshopCreatorPendingSyntheticStorageTests.swift", read("Questify.xcodeproj/project.pbxproj"))


if __name__ == "__main__":
    unittest.main()
