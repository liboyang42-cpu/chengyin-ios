"""Focused source contracts; these do not run Swift or its lifecycle."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubOccurrenceReturnOwnerContracts(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_row_is_an_observer_without_presentation_or_retirement(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift').split('@MainActor struct ClubSeriesOccurrenceBrowser: View {', 1)[1]
        for part in ['@ObservedObject var host:', '@ObservedObject var model:', 'host.toggle(source, current:', 'host.open(route, source:', 'host.requestReload(source, current:']:
            self.assertIn(part, source)
        for part in ['@State', '.sheet(', '.onDisappear', '.task(', 'model.leave(', 'model.activate(', 'model.bind(']:
            self.assertNotIn(part, source)
    def test_stable_parent_owns_specific_presentation_and_lifetime(self):
        source = self.source('App/ClubGovernanceViews.swift')
        for part in ['@StateObject private var seriesOccurrences = ClubSeriesOccurrenceHost()', 'if let item = seriesOccurrences.selected', 'ClubSeriesOccurrencePresentationOwner(item: item', '}).id(item.id)', 'seriesOccurrences.depart(attachment)', 'seriesOccurrences.hide()', 'if !seriesOccurrences.retainsDestination']:
            self.assertIn(part, source)
    def test_parent_keeps_cover_but_invalidates_changed_source(self):
        source = self.source('App/ClubGovernanceViews.swift')
        for part in ['if operation == .series {', 'if snapshotContext != readContext || snapshotGeneration != generation', 'seriesOccurrences.retire(); invalidateRead(); loading = false; await load()', '.onChange(of: currentOccurrenceSource)', 'seriesOccurrences.invalidateUnlessCurrent(source)', 'if !seriesOccurrences.retainsDestination { seriesOccurrences.retire(); generation &+= 1; loading = false }']:
            self.assertIn(part, source)
    def test_source_binds_permission_reader_account_and_exact_series(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['context.operation == .series', 'context.accepts(snapshot)', 'access.identity == context.identity', 'context.authorizationGeneration == access.authorizationGeneration', 'context.accessIdentity == ObjectIdentifier(access)', 'snapshot.permissions?.allows(ClubGovernanceRead.series.permission', 'rows.filter({ $0["id"].int == seriesID }).count == 1', 'row["clubId"].int == context.scope.clubID', 'topicID > 0']:
            self.assertIn(part, source)
    def test_route_uses_existing_typed_returned_activity(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['model.canOpen(route, context: source.occurrences, access: access)', 'ClubGovernanceEventView(scope: item.route.scope', 'identity: item.source.context.identity', 'host.isCurrent(item, current: current(), access: access)']:
            self.assertIn(part, source)
        self.assertNotIn('activityID: row.id', source)
    def test_concrete_binding_and_close_cannot_target_replacement(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['selected?.id == item.id', 'attachment == item.attachment', 'self.isCurrent(item, current: current(), access: access)', 'guard !isPresented, isCurrent(item, current: current, access: access)', 'if selected?.id == item.id { retire() }', 'host.binding(item, current: current, access: access)']:
            self.assertIn(part, source)
    def test_return_is_explicit_and_only_reload(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['selected = nil; needsRefresh = true; returning = true; return true', 'if host.closed(item, current: current(), access: access) { returned() }', 'await model.load(permit, access: access', 'if model.accepted(source.occurrences, access: access) != nil { needsRefresh = false; returning = false }']:
            self.assertIn(part, source)
        for part in ['access.send(', 'coordinator.confirm(', 'retryWrite(', 'restoreApproval(']:
            self.assertNotIn(part, source)
    def test_background_and_hidden_reads_retire_without_auto_action(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['if selected == nil, readID != nil, let source', 'model.leave(source.occurrences); readID = nil; needsRefresh = true', 'func background()', 'selected = nil; isPresented = false; readID = nil', 'guard visible, active(), let attachment', 'self.readID == run && self.selected == nil']:
            self.assertIn(part, source)
        parent = self.source('App/ClubGovernanceViews.swift')
        self.assertIn('if phase != .active { seriesOccurrences.background() }', parent)
        self.assertIn('else { Task { await loadSeriesOccurrencesIfNeeded() } }', parent)
    def test_real_departure_is_attachment_scoped(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift')
        for part in ['guard attachment == expected else { return false }', 'retire(); attachment = nil; visible = false', 'current.isMovingFromParent || current.isBeingDismissed', 'else if attached { leave() }', 'controller.leave()']:
            self.assertIn(part, source)
    def test_original_scoped_reader_and_late_callback_guards_remain(self):
        source = self.source('App/ClubSeriesOccurrenceBrowser.swift').split('@MainActor final class ClubSeriesOccurrenceHost:', 1)[0]
        for part in ['read.authorizationGeneration == access.authorizationGeneration', 'read.accessIdentity == ObjectIdentifier(access)', 'context.namespace == access.storageNamespace', 'generation == request', 'current(), !Task.isCancelled', 'access.read(.occurrences, scope: permit.context.read.scope, options: [:], check: check)']:
            self.assertIn(part, source)
    def test_all_other_operation_return_owners_still_exist(self):
        source = self.source('App/ClubGovernanceViews.swift')
        for part in ['attendanceReturn.depart(attachment, reads: attendanceReads)', 'roleManagementReturn.depart(attachment, reads: roleReads)', 'CaseReadTrigger(context: readContext', 'await loadRosterIfNeeded()', 'await loadRolesIfNeeded()']:
            self.assertIn(part, source)
    def test_native_window_tests_use_production_owner_and_reader(self):
        source = self.source('Tests/AppUnitTests/ClubSeriesOccurrenceBrowserTests.swift')
        for part in ['testStableHostPreservesRealEventWhileParentIsCovered', 'testConcreteCloseRefreshesSameSeriesExactlyOnceWhenVisible', 'testHeldReturnBackgroundRestartRejectsLateOldRead', 'testHiddenReturnReadCanRestartBeforeSuspendedOldTransportReturns', 'testActualDepartureAndOldAttachmentCannotTouchNewSession', 'await host.loadIfNeeded(access:', 'access.pending[0].resume']:
            self.assertIn(part, source)

if __name__ == '__main__': unittest.main()
