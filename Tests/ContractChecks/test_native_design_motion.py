"""Offline source guards only. These do not compile Swift or prove rendered accessibility."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def app(name):
    return (ROOT / "App" / name).read_text()


class NativeDesignMotionGuards(unittest.TestCase):
    def test_press_is_interruptible_native_feedback_and_respects_reduce_motion(self):
        source = app("QuestifyMotion.swift")
        self.assertIn("struct QuestifyCardButtonStyle: ButtonStyle", source)
        self.assertIn("accessibilityReduceMotion", source)
        self.assertIn("@propertyWrapper", source)
        self.assertIn("configuration.isPressed && !reduceMotion", source)
        self.assertIn("reduceMotion ? nil", source)
        self.assertIn("duration: 0.12", source)
        self.assertIn("duration: 0.24, bounce: 0.08", source)
        self.assertIn("value: configuration.isPressed", source)
        self.assertIn("minHeight: 44", source)
        for forbidden in ("DragGesture", "Task.sleep", "asyncAfter", "repeatForever", "sensoryFeedback"):
            self.assertNotIn(forbidden, source)

    def test_reduce_motion_composes_system_local_and_debug_only_fixture(self):
        source = app("QuestifyMotion.swift")
        # Check each build branch, not merely the presence of a DEBUG directive.
        fixture = re.search(r"#if DEBUG\s+(private static let fixtureValue[^\n]+)\s+#endif", source)
        self.assertIsNotNone(fixture)
        self.assertIn('ProcessInfo.processInfo.arguments.contains("--uitesting-reduce-motion")', fixture[1])
        wrapped = re.search(r"var wrappedValue\s*:\s*Bool\s*\{\s*#if DEBUG\s+(.*?)\s*#else\s+(.*?)\s*#endif\s*\}", source, re.S)
        self.assertIsNotNone(wrapped)
        effective = "ReducedMotionPreference.effective(system: systemValue, local: localValue)"
        self.assertEqual(wrapped[1].strip(), "return " + effective + " || Self.fixtureValue")
        self.assertEqual(wrapped[2].strip(), "return " + effective)
        outside_fixture = source.replace(fixture[0], "").replace(wrapped[0], "")
        for token in ("fixtureValue", "--uitesting-reduce-motion", "ProcessInfo"):
            self.assertNotIn(token, outside_fixture)
        self.assertIn(r"@Environment(\.accessibilityReduceMotion) private var systemValue", source)
        self.assertIn("@AppStorage(ReducedMotionPreference.storageKey) private var localValue = ReducedMotionPreference.defaultValue", source)
        preference = (ROOT / "Core/ReducedMotionPreference.swift").read_text()
        self.assertRegex(preference, r"func effective\(system: Bool, local: Bool\) -> Bool\s*\{\s*system \|\| local\s*\}")
        self.assertIn("static let defaultValue = false", preference)

    def test_content_animation_is_local_and_not_a_refresh_success(self):
        source = app("QuestifyMotionComponents.swift")
        self.assertIn("contentTransition(.opacity)", source)
        self.assertIn("value: stateKey", source)
        self.assertIn("Transaction(animation: reduceMotion ? nil", source)
        for name in ("HomeFeedView.swift", "TicketWalletView.swift", "TicketWalletDetailView.swift"):
            self.assertNotIn("withAnimation", app(name))
            self.assertNotIn("sensoryFeedback", app(name))

    def test_artwork_does_not_invent_content_or_send_account_headers(self):
        source = app("QuestifyMotionComponents.swift")
        for required in ('parts.scheme == "https"', "parts.user == nil", "parts.password == nil", "!host.isEmpty"):
            self.assertIn(required, source)
        self.assertIn("AsyncImage(url: url", source)
        self.assertNotIn("URLRequest", source)
        self.assertNotIn("Authorization", source)
        self.assertIn("if let url = QuestifyCardArtwork.safeURL(item.imageURL)", app("HomeFeedView.swift"))

    def test_home_live_updates_only_at_a_verified_boundary(self):
        source = app("HomeFeedView.swift")
        self.assertNotIn(".periodic(", source)
        self.assertIn("if case .activity = item", source)
        self.assertIn("HomeFeedDate.parse(item.startDate, sourceTimeZone: sourceTimeZone)", source)
        self.assertIn("start > date ? [date, start] : [date]", source)
        self.assertIn("if start <= context.date", source)
        self.assertNotIn("TimeZone.current", source)

    def test_home_navigation_preserves_results_and_retires_scoped_reads(self):
        home = app("HomeFeedView.swift")
        for required in ("onDestination(item.id)", 'homeFeed.\\(section).\\(item.accessibilityKey)', "model.schedule(.page, reader: reader, permit: permit)", "model.suspend()", "model.canOpen(reader)"):
            self.assertIn(required, home)
        model = app("HomeFeedModel.swift")
        suspend = model.split("func suspend()", 1)[1].split("func resume(", 1)[0]
        self.assertIn("cancelScheduledReads()", suspend)
        self.assertIn("active = false; generation = UUID(); pageGeneration = UUID()", suspend)
        self.assertNotIn("pagination =", suspend)
        self.assertIn("if let existing = scheduled[slot] { return existing.task }", model)
        self.assertIn("expectedPage: pageTicket", model)
    def test_navigation_scope_pagination_and_duplicate_rows_stay_explicit(self):
        wallet = app("TicketWalletView.swift")
        self.assertIn("ForEach(Array(snapshot.tickets.enumerated()), id: \\.offset)", wallet)
        self.assertIn("if ticket.action == .detail", wallet)
        # Check the native destination and arguments inside the detail-only branch.
        route = re.search(r"if ticket.action == \.detail\s*\{\s*NavigationLink\s*\{\s*TicketWalletDetailView\(([^()]*)\)\s*\} label:", wallet)
        self.assertIsNotNone(route)
        arguments = dict(part.strip().split(":", 1) for part in route[1].split(","))
        self.assertEqual({key: value.strip() for key, value in arguments.items()}, {
            "id": "ticket.id", "reader": "reader",
            "lifecycleCoordinator": "orderLifecycleCoordinator",
            "makeTeamCoordinator": "makeTeamCoordinator",
        })
        detail = app("TicketWalletDetailView.swift")
        self.assertIn("ticket.id == id", detail)
        self.assertIn("try await reader.ticketDetail(id: id)", detail)
        self.assertIn('accessibilityIdentifier("ticketWallet.redemption.notice")', detail)

    def test_wallet_departure_retires_presentation_and_cancels_owned_reads(self):
        for name in ("TicketWalletView.swift", "TicketWalletDetailView.swift"):
            source = app(name)
            self.assertRegex(source, r"\.onDisappear\s*\{[^{}]*model\.endPresentation\(\)")
            self.assertIn("if phase == .background { refreshOnActive = true; model.endPresentation() }", source)
        adapter = app("TicketWalletModel.swift").split("func endPresentation(", 1)[1].split("func accepts(", 1)[0]
        self.assertIn("task?.cancel(); task = nil", adapter)
        self.assertIn("state.endPresentation(preservingValues: preservingValues)", adapter)
        core = (ROOT / "Core/TicketWalletReading.swift").read_text()
        end = core.split("public func endPresentation(", 1)[1].split("public func accepts(", 1)[0]
        self.assertIn("presentation = nil", end)
        self.assertIn("if preservingValues { cancelPending() } else { invalidate() }", end)
        accepts = core.split("public func accepts(", 1)[1].split("public func load(", 1)[0]
        self.assertIn("presentation == permit && permit.owner == currentOwner && currentOwner.canRead", accepts)

    def test_optional_wallet_providers_do_not_create_unguarded_destinations(self):
        wallet = app("TicketWalletView.swift")
        detail = app("TicketWalletDetailView.swift")
        pending = app("TicketWalletPendingOrderNavigation.swift")
        self.assertIn("static let defaultValue: TicketWalletPendingOrderProvider? = nil", pending)
        self.assertIn("static let defaultValue: TicketWalletPlayProvider? = nil", detail)
        for source, provider, entry, owner in (
            (wallet, "pendingOrderProvider", "pendingOrderEntry", "pendingOrderReadOwner"),
            (detail, "playProvider", "playEntry", "playReadOwner"),
        ):
            destination = source.split(".navigationDestination(item: $" + entry + ".target)", 1)[1].split(".refreshable", 1)[0].split(".onChange(of: scenePhase)", 1)[0]
            bound = "provider" if provider == "pendingOrderProvider" else "playProvider"
            binding = "if let provider = pendingOrderProvider" if bound == "provider" else "if let playProvider"
            self.assertIn(binding, destination)
            self.assertIn(owner + " == " + bound + ".owner", destination)
            self.assertIn("!model.isLoading", destination)
            self.assertIn(entry + ".matches(target,", destination)
            self.assertIn("let destination = " + bound + ".destination(target: target, reader: reader)", destination)
        self.assertRegex(detail, r"if let lifecycleCoordinator\s*\{\s*Section\s*\{\s*NavigationLink\s*\{\s*OrderLifecycleView")
        self.assertRegex(detail, r"if let makeTeamCoordinator\s*\{\s*TicketWalletTeamEntrySection")
        self.assertIn("guard owner == target.owner, matches(reader: reader) else { return nil }", detail)
        self.assertIn("matches(reader: reader) else { return nil }", pending)

    def test_source_price_and_read_only_disclosures_remain(self):
        home = app("HomeFeedView.swift")
        self.assertIn('Text("homeFeed.currencyUnknown")', home)
        self.assertIn("amount >= 0", home)
        self.assertNotIn(".currency(code:", home)
        self.assertIn('Text("ticketWallet.readOnly")', app("TicketWalletView.swift"))
        self.assertIn('Text("ticketWallet.noCode")', app("TicketWalletDetailView.swift"))

    def test_dynamic_type_and_semantic_color_are_explicit(self):
        for name in ("HomeFeedView.swift", "TicketWalletDetailView.swift", "TicketWalletModel.swift"):
            self.assertIn("dynamicTypeSize.isAccessibilitySize", app(name))
            self.assertNotIn("minimumScaleFactor", app(name))
        source = app("QuestifyMotionComponents.swift")
        self.assertIn(".secondarySystemGroupedBackground", source)
        self.assertIn("colorSchemeContrast", source)
        self.assertIn("accessibilityLabel(Text(label)", source)
        for status in ("ready", "pending", "verified", "cancelled", "expired", "unknown"):
            self.assertIn("case ." + status + ":", source)

    def test_titles_resolve_explicit_locale(self):
        for filename, key in (("HomeFeedView.swift", "homeFeed.title"), ("TicketWalletView.swift", "ticketWallet.title"), ("TicketWalletDetailView.swift", "ticketWallet.detail")):
            self.assertIn('.appNavigationTitle("' + key + '")', app(filename))

    def test_new_copy_is_bilingual_and_does_not_require_catalog_write(self):
        additions = json.loads((ROOT / "docs/native-design-motion-localizations.json").read_text())
        self.assertEqual(len(additions), len({row["key"] for row in additions}))
        for row in additions:
            self.assertTrue(row["en"].strip())
            self.assertTrue(row["zh-Hans"].strip())
        catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        known = set(catalog) | {row["key"] for row in additions}
        for filename in ("HomeFeedView.swift", "TicketWalletView.swift", "TicketWalletDetailView.swift", "TicketWalletModel.swift", "QuestifyMotionComponents.swift"):
            source = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', "", app(filename))
            keys = {key for key in re.findall(r'"((?:homeFeed|ticketWallet)\.[A-Za-z0-9.]+)"', source) if not key.endswith(".")}
            self.assertFalse(keys - known, (filename, keys - known))


if __name__ == "__main__":
    unittest.main()
