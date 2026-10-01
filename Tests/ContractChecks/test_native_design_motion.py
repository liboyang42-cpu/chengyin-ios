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
        self.assertIn("configuration.isPressed && !reduceMotion", source)
        self.assertIn("reduceMotion ? nil", source)
        self.assertIn("duration: 0.12", source)
        self.assertIn("duration: 0.24, bounce: 0.08", source)
        self.assertIn("value: configuration.isPressed", source)
        self.assertIn("minHeight: 44", source)
        for forbidden in ("DragGesture", "Task.sleep", "asyncAfter", "repeatForever", "sensoryFeedback"):
            self.assertNotIn(forbidden, source)

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

    def test_navigation_scope_pagination_and_duplicate_rows_stay_explicit(self):
        home = app("HomeFeedView.swift")
        for required in ("onDestination(item.id)", 'homeFeed.\\(section).\\(item.accessibilityKey)', "model.loadMore(reader: reader)", "model.invalidate()"):
            self.assertIn(required, home)
        wallet = app("TicketWalletView.swift")
        self.assertIn("ForEach(Array(snapshot.tickets.enumerated()), id: \\.offset)", wallet)
        self.assertIn("if ticket.action == .detail", wallet)
        self.assertIn("TicketWalletDetailView(id: ticket.id, reader: reader)", wallet)
        self.assertIn("model.cancelPending()", wallet)
        detail = app("TicketWalletDetailView.swift")
        self.assertIn("ticket.id == id", detail)
        self.assertIn("try await reader.ticketDetail(id: id)", detail)
        self.assertIn('accessibilityIdentifier("ticketWallet.redemption.notice")', detail)

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
        self.assertIn("accessibilityContrast", source)
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
