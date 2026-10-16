"""Source-only packaging regressions; not native execution or permission approval."""
import hashlib
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
class FavoriteRemovalIsolationTests(unittest.TestCase):
    def test_no_unrelated_growth_composition(self):
        source = read("App/AppCompositionRoot.swift")
        for name in ("GrowthLeaderboardReadApproval", "GrowthOverviewReadApproval", "GrowthOverviewReadRoute", "GrowthLeaderboardReadRoute", "growthLeaderboardReadApproval", "growthOverviewReadApproval"):
            self.assertNotIn(name, source)
    def test_literal_default_empty_and_no_production_assignment(self):
        declaration = "var profileFavoriteRemovalAccesses: @MainActor (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess] = { _, _ in [] }"
        self.assertIn(declaration, read("App/AppCompositionRoot.swift"))
        import re
        for path in (ROOT / "App").glob("*.swift"):
            self.assertIsNone(re.search(r"\.profileFavoriteRemovalAccesses\s*=", path.read_text()), str(path))
    def test_settings_prerequisite_hooks_incorporated(self):
        source = read("App/SettingsView.swift")
        for token in ("@State private var favoritesOwner = ProfileSettingsFavoritesOwner()", "ProfileSettingsFavoritesEntry(session: session, owner: favoritesOwner)", "ProfileSettingsFavoritesNavigation(session: session, owner: favoritesOwner)", "ProfileSettingsFavoritesLifecycle(session: session, owner: favoritesOwner)"):
            self.assertIn(token, source)
    def test_reused_settings_route_preserves_existing_navigation_fences(self):
        source = read("App/ProfileSettingsFavoritesRoute.swift")
        for token in ("route?.id == offered.id", "current?.key == offered.access.key", "posts.disappear(); topics.disappear(); route = nil", "favoriteRemoval: route.access.removal"):
            self.assertIn(token, source)
    def test_shared_cleanup_quarantine_does_not_grant_authority(self):
        source = read("App/AppSession.swift")
        self.assertIn("private let favoriteRemovalPendingState = ProfileFavoriteRemovalPendingState()", source)
        self.assertIn("pendingState: favoriteRemovalPendingState", source)
        core = read("Core/ProfileFavoriteRemoval.swift")
        self.assertIn("return durable ?? pendingState.pending", core)
        self.assertNotIn("try? journal.write(record)", core)
    def test_new_sources_and_resource_registered(self):
        project = read("Questify.xcodeproj/project.pbxproj")
        for path in ("Core/ProfileFavoriteRemovalAccess.swift", "App/ProfileSettingsFavoritesRoute.swift", "Tests/AppUnitTests/ProfileFavoriteRemovalCompositionTests.swift", "Tests/AppUnitTests/ProfileSettingsFavoritesTests.swift", "Resources/ProfileSettingsFavorites.xcstrings"):
            self.assertIn(path, project)
    def test_documentation_discloses_source_only_status(self):
        doc = read("docs/profile-favorite-removal.md")
        for token in ("SOURCE-ONLY / NOT ENABLED", "Saved TOPIC removal is NOT IMPLEMENTED", "NOT_RUN", "Settings favorites"):
            self.assertIn(token, doc)
        self.assertNotIn("no independently reviewed saved-post removal approval or composition injection", doc)
if __name__ == "__main__": unittest.main()
