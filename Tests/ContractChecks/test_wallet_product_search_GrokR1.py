"""Product-search source contracts only; not Swift compilation or App runtime tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VIEW = ROOT / "App/WalletCommerceViews.swift"


def products_section(source):
    return source.split("@MainActor struct WalletProductsView: View {", 1)[1].split(
        "@MainActor struct WalletProductView: View {", 1)[0]


def defects(section):
    found = []
    load = section.split("private func load()", 1)[1]
    if "let search = submittedKeyword; let order = sort" not in load:
        found.append("draft_query_used")
    schedule = section.split("private func scheduleLoad()", 1)[1].split("private func load()", 1)[0]
    required_order = ["guard isVisible else { return }", "pendingLoad?.cancel()",
                      "model.clear()", "model.loading = true", "let scope = reader.scope", "pendingLoad = Task {"]
    offsets = [schedule.find(token) for token in required_order]
    if -1 in offsets or offsets != sorted(offsets):
        found.append("replacement_not_synchronously_loading")
    task = schedule.split("pendingLoad = Task {", 1)[-1]
    guard = "guard !Task.isCancelled, isVisible, scope == reader.scope else { return }"
    if guard not in task or task.find(guard) > task.find("await load()"):
        found.append("queued_task_not_scoped")
    disappear = section.split(".onDisappear {", 1)[1].split("}.refreshable", 1)[0]
    if not all(x in disappear for x in ["isVisible = false", "pendingLoad?.cancel()", "model.cancel()"]):
        found.append("departure_not_retired")
    scoped = section.split(".task(id: reader.scope) {", 1)[1].split(".onDisappear", 1)[0]
    if not all(x in scoped for x in ["pendingLoad?.cancel()", "isVisible = true", "model.clear()", "await load()"]):
        found.append("scope_not_retired")
    if "guard isVisible, !Task.isCancelled else { return }" not in load:
        found.append("direct_load_not_guarded")
    return found


class WalletProductSearchGrokR1Tests(unittest.TestCase):
    def setUp(self):
        self.section = products_section(VIEW.read_text())

    def test_loading_and_lifecycle_contracts(self):
        self.assertEqual(defects(self.section), [])

    def test_missing_synchronous_loading_is_detected(self):
        self.assertIn("replacement_not_synchronously_loading", defects(
            self.section.replace("model.loading = true", "", 1)))

    def test_draft_request_regression_is_detected(self):
        self.assertIn("draft_query_used", defects(
            self.section.replace("let search = submittedKeyword", "let search = keyword", 1)))

    def test_missing_scope_guard_is_detected(self):
        self.assertIn("queued_task_not_scoped", defects(
            self.section.replace(", scope == reader.scope", "", 1)))

    def test_missing_task_cancellation_guard_is_detected(self):
        self.assertIn("queued_task_not_scoped", defects(
            self.section.replace("!Task.isCancelled, isVisible,", "isVisible,", 1)))

    def test_departure_must_cancel_queued_task(self):
        start = self.section.index(".onDisappear {")
        mutated = self.section[:start] + self.section[start:].replace("pendingLoad?.cancel()", "", 1)
        self.assertIn("departure_not_retired", defects(mutated))

    def test_scope_restart_must_cancel_queued_task(self):
        start = self.section.index(".task(id: reader.scope) {")
        mutated = self.section[:start] + self.section[start:].replace("pendingLoad?.cancel()", "", 1)
        self.assertIn("scope_not_retired", defects(mutated))

    def test_lifecycle_cancellation_precedes_side_effects(self):
        scoped = self.section.split(".task(id: reader.scope) {", 1)[1].split(".onDisappear", 1)[0]
        self.assertLess(scoped.index("guard !Task.isCancelled"), scoped.index("pendingLoad?.cancel()"))
        refresh = self.section.split("}.refreshable {", 1)[1].split("private func submitSearch", 1)[0]
        self.assertLess(refresh.index("guard isVisible, !Task.isCancelled"), refresh.index("pendingLoad?.cancel()"))
        self.assertLess(refresh.index("pendingLoad?.cancel()"), refresh.index("await load()"))

    def test_cancelled_read_is_not_reported_as_business_failure(self):
        self.assertIn("else if model.failed || !reader.isConfigured || reader.scope == nil", self.section)
        self.assertIn('Button("wallet.retry") { scheduleLoad() }.frame(minHeight: 44)', self.section)

    def test_existing_search_navigation_and_errors_preserved(self):
        for token in [
            "submittedKeyword = keyword",  # Preserve existing whitespace semantics.
            "guard value.isEmpty, !submittedKeyword.isEmpty else { return }",
            '.onChange(of: sort) { _, _ in scheduleLoad() }',
            "unavailable: model.unavailable) { scheduleLoad() }",
            'else if model.failed || !reader.isConfigured || reader.scope == nil',
            "NavigationLink { WalletProductView(reader: reader, productID: item.id) }",
            'if page.rows.isEmpty { Text("wallet.empty") }',
        ]:
            self.assertIn(token, self.section)
        self.assertNotIn("trimmingCharacters", self.section)
        self.assertEqual(self.section.count("try await $0.products("), 1)


if __name__ == "__main__":
    unittest.main()
