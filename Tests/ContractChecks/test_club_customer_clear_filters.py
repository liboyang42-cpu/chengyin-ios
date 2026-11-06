"""Focused customer-list source contracts; these do not execute Swift or UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VIEW = ROOT / "App/ClubGovernanceViews.swift"


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def require_clear_action_fences(source):
    action = span(source, "private func clearCustomerFilters(", "private func loadCustomersNow()")
    for gate in [
        "operation == .customers", "!loading", "failure == nil",
        "identity?.isSignedIn == true", "identity == access.identity",
        "scenePhase == .active", "readContext == context", "snapshotContext == context",
        "snapshot == source", "snapshotGeneration == sourceGeneration",
        "generation == sourceGeneration", "customerFilters == filters",
        "snapshotCustomerFilters == filters", "filters.isFiltered",
        'source.value["items"].array?.isEmpty == true',
        "revision == generation", "identity == expected", "access.identity == expected",
        "customerFilters == ClubCustomerFilters()", "!Task.isCancelled",
    ]:
        if gate not in action:
            raise AssertionError("Missing customer clear-filters gate: " + gate)
    ordered = [
        "customerKeywordDebounce.cancel()", "guard customerFilters.clear()",
        "generation &+= 1", "snapshot = nil; snapshotContext = nil",
        "let revision = generation", "Task {", "await load()",
    ]
    positions = [action.index(token) for token in ordered]
    if positions != sorted(positions):
        raise AssertionError("Customer reset/read order changed")
    if action.count("Task {") != 1 or action.count("await load()") != 1:
        raise AssertionError("Expected one immediate replacement read")


class ClubCustomerClearFiltersContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = VIEW.read_text()

    def test_reset_value_clears_both_fields_and_is_idempotent(self):
        model = span(self.source, "struct ClubCustomerFilters: Equatable {", "struct ClubGovernanceEntryButton")
        self.assertIn('var filter = "all"', model)
        self.assertIn('var keyword = ""', model)
        self.assertIn('filter != "all" || !keyword.isEmpty', model)
        clear = model.split("mutating func clear()", 1)[1]
        for token in ["guard isFiltered else { return false }", 'filter = "all"', 'keyword = ""', "return true"]:
            self.assertIn(token, clear)
        self.assertNotIn("trimmingCharacters", model)

    def test_normal_customer_inputs_keep_all_four_filters_and_explicit_search(self):
        controls = span(self.source, "if operation == .customers {\n                Section {", "if operation == .topicCustomers")
        self.assertIn('["all", "repeat", "new", "remark"]', controls)
        self.assertIn('Picker("club.gov.filter", selection: customerFilterBinding)', controls)
        self.assertIn('TextField("club.gov.keyword", text: customerKeywordBinding)', controls)
        self.assertIn(".onSubmit { loadCustomersNow() }", controls)
        self.assertIn('Button("club.gov.search") { loadCustomersNow() }.disabled(loading)', controls)
        self.assertNotIn(".onChange", controls)

    def test_input_bindings_schedule_only_actual_user_value_changes(self):
        filter_binding = span(self.source, "private var customerFilterBinding:", "private var customerKeywordBinding:")
        keyword_binding = span(self.source, "private var customerKeywordBinding:", "private func clearCustomerFilters(")
        for block, field, action in [(filter_binding, "filter", "loadCustomersNow()"),
                                     (keyword_binding, "keyword", "scheduleCustomerKeywordRead()")]:
            self.assertIn(f"guard customerFilters.{field} != value else {{ return }}", block)
            self.assertLess(block.index(f"customerFilters.{field} = value"), block.index(action))
            self.assertEqual(block.count(action), 1)

    def test_empty_action_is_scoped_to_a_successful_matching_customer_query(self):
        display = span(self.source, "if operation == .customers, !loading, failure == nil,", "if operation == .topicSettings")
        for token in ['value["items"].array?.isEmpty == true', "customerFilters.isFiltered",
                      "snapshotCustomerFilters == customerFilters", "let sourceFilters = customerFilters",
                      "sourceGeneration = snapshotGeneration", 'Button("discovery.clearFilters")',
                      "source: snapshot, context: sourceContext", "filters: sourceFilters",
                      '.accessibilityIdentifier("club.gov.customers.clearFilters")']:
            self.assertIn(token, display)
        self.assertIn('if let snapshot, snapshotContext == readContext, identity == access.identity { content(snapshot) }', self.source)
        self.assertIn(".buttonStyle(.borderless)", display)
        self.assertNotIn("?? []", display)

    def test_clear_action_rejects_old_or_unavailable_state_and_dispatches_once(self):
        require_clear_action_fences(self.source)

    def test_response_remembers_the_query_that_was_actually_read(self):
        load = span(self.source, "private func load() async {", "private func invalidateRead()")
        self.assertIn("let customerQuery = customerFilters", load)
        self.assertIn('options = ["filter": .string(customerQuery.filter), "keyword": .string(customerQuery.keyword)]', load)
        self.assertIn("snapshotCustomerFilters = operation == .customers ? customerQuery : nil", load)
        self.assertLess(load.index("let customerQuery = customerFilters"), load.index("try await access.read"))
        self.assertLess(load.index("guard context.accepts(result)"), load.index("snapshotCustomerFilters ="))

    def test_existing_delay_and_late_result_fences_are_retained(self):
        self.assertIn("delayNanoseconds: UInt64 = 300_000_000", self.source)
        self.assertIn("guard !Task.isCancelled, self.revision == expected else { return }", self.source)
        scheduling = span(self.source, "private func scheduleCustomerKeywordRead()", "private func load() async")
        for token in ["keywordRevision == generation", "context == readContext", "access.identity == expected",
                      "customerFilters.filter == expectedFilter", "customerFilters.keyword == expectedKeyword"]:
            self.assertIn(token, scheduling)
        self.assertIn("guard revision == generation, context == readContext, expected == identity, access.identity == expected, !Task.isCancelled else { return }", self.source)
        self.assertIn(".task(id: readContext) { invalidateRead(); await load() }", self.source)
        self.assertIn(".onDisappear { generation &+= 1 }", self.source)

    def test_lost_reset_fences_are_detected_by_negative_controls(self):
        start = self.source.index("private func clearCustomerFilters(")
        end = self.source.index("private func loadCustomersNow()", start)
        action = self.source[start:end]
        for token in ["customerKeywordDebounce.cancel()", "generation &+= 1",
                      "snapshot == source", "snapshotCustomerFilters == filters",
                      "readContext == context", "generation == sourceGeneration",
                      "customerFilters == filters", "filters.isFiltered",
                      'source.value["items"].array?.isEmpty == true', "revision == generation",
                      "access.identity == expected", "!Task.isCancelled"]:
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                require_clear_action_fences(self.source[:start] + action.replace(token, "true") + self.source[end:])

    def test_native_query_and_cancelled_delay_regressions_are_authored(self):
        tests = (ROOT / "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift").read_text()
        for name in ["testClearFiltersRestoresEverySupportedFilterToTheDefaultQuery",
                     "testClearFiltersHandlesKeywordOnlyAndFilterOnlyQueries",
                     "testClearFiltersDoesNotTrimOrPreserveWhitespaceInTheResetKeyword",
                     "testClearFiltersIsIdempotentForAnAlreadyUnfilteredQuery",
                     "testClearFiltersCancelsAnOlderKeywordDelayBeforeTheUnfilteredRead"]:
            self.assertIn("func " + name + "(", tests)
        self.assertIn("XCTAssertEqual(reads, [ClubCustomerFilters()])", tests)
        self.assertIn("gate.release()\n        await pending.value", tests)


if __name__ == "__main__":
    unittest.main()
