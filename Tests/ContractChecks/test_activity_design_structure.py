"""Activity presentation source guards. These do not compile Swift or prove UI behavior."""
import json
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def app(name):
    return (ROOT / "App" / name).read_text()


class ActivityDesignStructureTests(unittest.TestCase):
    def test_detail_sections_prioritize_real_summary_then_description_map_tickets(self):
        source = app("ActivityDetailView.swift")
        order = [source.index(value) for value in (
            "ActivityDetailHeader(summary:detail.summary)",
            'Section("activity.about")',
            "detail.summary.hasValidCoordinates",
            'Section("activity.tickets")',
        )]
        self.assertEqual(order, sorted(order))
        self.assertIn(".listStyle(.insetGrouped)", source)
        self.assertIn(".listSectionSpacing(20)", source)

    def test_primary_action_preserves_allowed_detail_and_registration_gate(self):
        source = app("ActivityDetailView.swift")
        self.assertIn("case .allowed(let detail):\n                    detailContent(detail)", source)
        self.assertIn("var registrationEnabled=false", source)
        self.assertIn(".safeAreaInset(edge:.bottom,spacing:0)", source)
        self.assertIn("if registrationEnabled { registrationAction }", source)
        self.assertEqual(source.count('accessibilityIdentifier("activity.openRegistration")'), 1)
        self.assertIn("Button { showsRegistration=true }", source)
        self.assertIn(".buttonStyle(.borderedProminent)", source)
        self.assertIn(".frame(maxWidth:.infinity,minHeight:44)", source)
        self.assertIn("if let access,case .allowed(let detail)=access { SessionRegistrationSheet(activity:detail) }", source)
        self.assertIn("creationPolicy:session.registrationCreationPolicy(activityID:activity.summary.id)", app("SessionRegistrationSheet.swift"))
        self.assertIn("registrationApproval: RegistrationProductionApproval? = nil", app("AppSession.swift"))
        self.assertIn('registrationStorefront: @escaping () -> String? = { nil }', app("AppSession.swift"))
        # The primary action must not be attached to an error/loading/club-gate root.
        self.assertLess(source.index("private func detailContent"), source.index(".safeAreaInset"))

    def test_existing_accessibility_identifiers_are_preserved(self):
        sources = "\n".join(app(name) for name in (
            "ActivityBrowserView.swift", "ActivityDetailView.swift", "ActivityPresentationComponents.swift"
        ))
        for identifier in (
            "activity.list.error", "activity.list.retry", "activity.list.empty", "activity.list.loadMore",
            "activity.list.content", "activity.row.\\(item.id)", "activity.detail.error",
            "activity.detail.retry", "activity.detail.clubGate", "activity.detail.name",
            "activity.detail.content", "activity.detail.readOnly", "activity.openPlay",
            "activity.openRegistration", "activity.ticket.price.\\(ticket.id)",
            "activity.ticket.soldOut.\\(ticket.id)", "activity.ticket.inventoryUnknown.\\(ticket.id)",
        ):
            self.assertIn('accessibilityIdentifier("' + identifier + '")', sources)

    def test_only_source_artwork_is_presented_through_shared_safe_loader(self):
        source = app("ActivityPresentationComponents.swift")
        self.assertIn("QuestifyCardArtwork.safeURL(item.imageURL)", source)
        self.assertIn("QuestifyCardArtwork.safeURL(summary.imageURL)", source)
        for forbidden in ("AsyncImage", "URLRequest", "Authorization", "Image(\"", "https://"):
            self.assertNotIn(forbidden, source)
        loader = app("QuestifyMotionComponents.swift")
        self.assertIn('parts.scheme == "https"', loader)
        self.assertIn(".accessibilityHidden(true)", loader)

    def test_nullable_ticket_values_do_not_gain_invented_availability_or_currency(self):
        source = app("ActivityPresentationComponents.swift")
        self.assertIn("AmountLabel(amount:ticket.price)", source)
        self.assertIn(".accessibilityElement(children:.combine)", source)
        self.assertIn("if ticket.isSoldOut", source)
        self.assertIn("else if ticket.remainingInventory == nil", source)
        self.assertIn('title:"activity.soldOut",systemImage:"xmark.circle"', source)
        self.assertIn('title:"activity.inventoryUnknown",systemImage:"questionmark.circle"', source)
        self.assertIn("ActivityPresentation.nonempty(ticket.description)", source)
        prices = app("ActivityBrowserView.swift")
        self.assertIn('Text("activity.currencyUnconfirmed")', prices)
        self.assertIn('Text("activity.priceUnknown")', prices)
        for forbidden in (".currency(", "remainingInventory!", "Timer", "Date()", "rating", "countdown"):
            self.assertNotIn(forbidden, source)

    def test_semantic_type_wraps_and_shared_motion_respects_reduce_motion(self):
        source = app("ActivityPresentationComponents.swift")
        self.assertEqual(source.count("dynamicTypeSize.isAccessibilitySize"), 2)
        self.assertIn(".font(.title.weight(.bold))", source)
        self.assertIn(".accessibilityAddTraits(.isHeader)", source)
        self.assertIn(".fixedSize(horizontal:false,vertical:true)", source)
        self.assertIn("QuestifyMetadataLine(label:", source)
        self.assertIn(".buttonStyle(QuestifyCardButtonStyle())", app("ActivityBrowserView.swift"))
        self.assertIn("@QuestifyReduceMotion private var reduceMotion", app("QuestifyMotion.swift"))
        for name in ("ActivityBrowserView.swift", "ActivityDetailView.swift", "ActivityPresentationComponents.swift"):
            content = app(name)
            for forbidden in ("minimumScaleFactor", ".lineLimit(", "withAnimation", "repeatForever", "sensoryFeedback", "accessibilityContrast", "environment(\\.accessibilityReduceMotion"):
                self.assertNotIn(forbidden, content)

    def test_source_metadata_is_not_reinterpreted(self):
        source = app("ActivityPresentationComponents.swift")
        self.assertIn("nonempty(summary.addressName) ?? nonempty(summary.address)", source)
        self.assertIn("ActivityPresentation.nonempty(summary.startDate)", source)
        self.assertIn("address != place", source)
        self.assertIn("Text(verbatim:name)", source)
        self.assertNotIn("DateFormatter", source)
        self.assertNotIn("TimeZone", source)

    def test_loading_search_pagination_and_map_contracts_remain(self):
        browser = app("ActivityBrowserView.swift")
        for required in ("appliedQuery = keyword", "let operation = generation", "generation == operation", "guard current()", "hasMore = result.count >= 10", "existing.insert($0.id).inserted", "try await reader.activities(page: next, keyword: appliedQuery)"):
            self.assertIn(required, browser)
        detail = app("ActivityDetailView.swift")
        self.assertIn(".task(id:id) { await loads.run { await load() } }", detail)
        self.assertIn(".onDisappear { loads.cancel();", detail)
        self.assertIn("try await reader.activityDetail(id:id)", detail)
        self.assertIn("detail.summary.hasValidCoordinates", detail)
        self.assertIn("Text(\"activity.registrationPending\")", detail)
        self.assertNotIn("Map(", app("ActivityPresentationComponents.swift"))

    def test_no_new_business_actions_or_requests_in_presentation_components(self):
        source = app("ActivityPresentationComponents.swift")
        for forbidden in ("Button", "NavigationLink", "Task", "URLSession", "URLRequest", "@State", "@EnvironmentObject", "payment", "createOrder", "submit"):
            self.assertNotIn(forbidden, source)

    def test_new_copy_is_bilingual_and_available_for_catalog_merge(self):
        additions = json.loads((ROOT / "docs/activity-design-localizations.json").read_text())
        self.assertEqual(len(additions), len({entry["key"] for entry in additions}))
        for entry in additions:
            self.assertTrue(entry["en"].strip())
            self.assertTrue(entry["zh-Hans"].strip())
        catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        known = set(catalog) | {entry["key"] for entry in additions}
        for name in ("ActivityBrowserView.swift", "ActivityDetailView.swift", "ActivityPresentationComponents.swift"):
            source = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', "", app(name))
            keys = set(re.findall(r'"((?:activity|registration)\.[A-Za-z0-9.]+)"', source))
            self.assertFalse(keys - known, (name, keys - known))


if __name__ == "__main__":
    unittest.main()
