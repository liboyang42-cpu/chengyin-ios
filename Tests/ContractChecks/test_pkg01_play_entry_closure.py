from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Pkg01PlayEntryClosureContracts(unittest.TestCase):
    def read(self, rel: str) -> str:
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_auxiliary_adapter_uses_existing_read_methods_and_fences_session(self):
        adapter = self.read("App/PlayThemeAuxiliaryAdapter.swift")
        self.assertIn("final class PlayThemeAuxiliaryReader: PlayThemeRecordsReading, PlayThemeBackpackReading", adapter)
        self.assertIn("service.enabled.contains(.reads)", adapter)
        self.assertIn("guard let session = current(), session == captured else { throw PlayExperienceError.staleSession }", adapter)
        self.assertIn("service.themeHistory(topicID: topicID, beforeSessionID: beforeSessionID, token: session.token)", adapter)
        self.assertIn("service.themeCard(sessionID: sessionID, token: session.token)", adapter)
        self.assertIn("service.themeState(scope: scope, topicID: topicID, token: session.token)", adapter)
        self.assertIn("final class PlayThemeAuxiliaryStore", adapter)
        for forbidden in ["URLSession", "https://", "http://", "api/play/", "enabled: [.reads]"]:
            self.assertNotIn(forbidden, adapter)

    def test_app_session_and_play_runtime_wire_theme_auxiliary_across_all_three_hosts(self):
        session = self.read("App/AppSession.swift")
        self.assertIn("func playThemeAuxiliary(scope: PlaySessionScope, topicID: Int?) -> PlayThemeAuxiliaryReader?", session)
        self.assertIn("guard scope.isValid, let id = topicID, id > 0, let api = dormantPlayRuntimeService() else { return nil }", session)
        self.assertIn("var playThemeAuxiliaryProvider: PlayThemeAuxiliaryProvider", session)

        runtime = self.read("App/SessionPlayRuntimeView.swift")
        self.assertIn("@Environment(\\.playThemeAuxiliaryProvider) private var auxiliaryProvider", runtime)
        self.assertIn("@State private var auxiliaryStore = PlayThemeAuxiliaryStore()", runtime)
        self.assertIn("provider: auxiliaryProvider ?? session.playThemeAuxiliaryProvider", runtime)
        self.assertIn("themeRecordsModel: auxiliary.records", runtime)
        self.assertIn("backpackModel: auxiliary.backpack", runtime)

    def test_all_three_play_entry_paths_inject_auxiliary_provider_and_clear_nested_play_provider_on_voucher_detail(self):
        account = self.read("App/AccountView.swift")
        roam = self.read("App/RoamEnrolledChaptersView.swift")
        journey = self.read("App/PlayerJourneyViews.swift")
        for source in (account, roam, journey):
            self.assertIn(".environment(\\.playThemeAuxiliaryProvider, session.playThemeAuxiliaryProvider)", source)
            self.assertIn("TicketWalletDetailView(id: entry.registrationID", source)
            self.assertIn(".environment(\\.ticketWalletPlayProvider, nil)", source)


if __name__ == "__main__":
    unittest.main()
