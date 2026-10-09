"""Bounded source assertions only; these do not execute Swift or prove an iOS runtime."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ExploreCompletionSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contracts = (ROOT / 'Core/ExploreCompletionContracts.swift').read_text()
        cls.read = (ROOT / 'Core/ExploreCompletionRead.swift').read_text()
        cls.ui = (ROOT / 'App/ExploreCompletionView.swift').read_text()
        cls.orders = (ROOT / 'App/ProfileOrdersView.swift').read_text()
        cls.profile = (ROOT / 'Core/ProfileContracts.swift').read_text()

    def test_purchase_kind_is_only_a_projection_and_eligibility_requires_fresh_owned_paid_explore_order(self):
        self.assertIn('public let purchaseKind: Int?', self.profile)
        self.assertIn('purchaseKind = (try? c.decodeIfPresent(ProfileOrderStatusInteger.self, forKey: .purchaseKind))?.value', self.profile)
        gate = self.contracts.split('public struct ExploreCompletionTarget:', 1)[1].split('/// Pinned', 1)[0]
        for value in ['accountID > 0', 'requestedID > 0', 'order.id == requestedID', 'order.memberID == accountID',
                      'order.purchaseKind == 3', 'order.paymentStatus == 2 || order.registrationStatus == 2']:
            self.assertIn(value, gate)
        for forbidden in ['productType', 'ownerType', 'ticketID', 'title', 'expiresAt']:
            self.assertNotIn(forbidden, gate)

    def test_nil_default_separate_approval_does_not_adopt_existing_grant(self):
        self.assertIn('approval: ExploreCompletionReadApproval? = nil', self.read)
        self.assertIn('static let defaultValue: ExploreCompletionProvider? = nil', self.ui)
        approval = self.read.split('public final class ExploreCompletionReadApproval {', 1)[1].split('/// Canonical', 1)[0]
        for value in ['context.market == .china', 'duration <= 86_400', 'public let revision = UUID()', 'isRevoked = true',
                      'now < expiresAt && ContentDraftContextFence.matches(context, current)', 'let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))']:
            self.assertIn(value, approval)
        self.assertNotIn('OwnedOrderReadApproval', self.read)
        self.assertNotIn('RuntimeDependencyConfiguration(', self.read)

    def test_single_read_endpoint_exact_id_only_request_and_canonical_route(self):
        self.assertEqual(set(re.findall(r'"(api/[^" ]+)"', self.read)), {'api/registration/explore-completion'})
        self.assertIn('fields: ["id": String(target.registrationID)], token: captured.session.token', self.read)
        for value in ['request.httpMethod == "POST"', 'request.httpBodyStream == nil', 'url.query == nil', 'url.fragment == nil',
                      'request.value(forHTTPHeaderField: "Accept") == "application/json"', 'canonical.httpBody == body', 'String(id) == raw', 'body.count <= 1_024']:
            self.assertIn(value, self.read)
        self.assertNotIn('public func send(', self.read)

    def test_transport_checks_context_origin_and_lease_before_and_after_await(self):
        client = self.read.split('public final class ExploreCompletionSessionReader:', 1)[1].split('private struct CompletionEnvelope', 1)[0]
        for value in ['guard isConfigured, let captured = current(), let approval', 'target.accountID == captured.session.accountID',
                      'guard isCurrent() else { throw CancellationError() }', 'approval.matches(now)',
                      'ContentDraftContextFence.matches(captured, now)', 'guard active() else { throw CancellationError() }']:
            self.assertIn(value, client)
        self.assertGreaterEqual(client.count('guard active() else'), 4)
        self.assertLess(client.index('guard active() else'), client.index('try await http.send(request)'))
        self.assertIn('request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(captured.session.token.utf8) == true', client)

    def test_explicit_http_and_business_auth_codes_do_not_relabel_error500_prose(self):
        for value in ['if status == 401 { throw APIError.unauthorized }', 'throw APIError.httpStatus(status)',
                      'if envelope.code == 401 { throw APIError.unauthorized }', 'if envelope.code == 403 { throw APIError.businessCode(403) }',
                      'ExploreCompletionFailure.rejected(code: envelope.code, message: envelope.message)']:
            self.assertIn(value, self.read)
        self.assertNotIn('请先登录', self.read)
        self.assertNotIn('message.contains', self.read)
        catch = self.read.split('if error as? APIError == .unauthorized { onUnauthorized(captured) }')[0]
        self.assertIn('guard active() else { throw CancellationError() }', catch.rsplit('} catch {', 1)[1])

    def test_strict_response_identity_types_and_resource_limits(self):
        for value in ['data.count <= Self.maximumResponseBytes', 'value.registrationID == target.registrationID',
                      'code == 200 ? try c.decodeIfPresent(ExploreCompletionSnapshot.self, forKey: .data) : nil']:
            self.assertIn(value, self.read)
        for value in ['registrationID = try c.decode(Int.self', 'completed = try c.decode(Bool.self',
                      'stamps = try c.decode([Stamp].self', 'awards = try c.decode(Awards.self',
                      '(0...requiredChapterCount).contains(redeemedChapterCount)', 'stamps.count <= Self.maximumRows', 'text.utf8.count <= maximum']:
            self.assertIn(value, self.contracts)

    def test_missing_optional_rewards_and_next_edition_never_default_to_zero(self):
        for value in ['points = try c.decodeIfPresent(Int.self', 'earnedXP = try c.decodeIfPresent(Int.self',
                      'couponGranted = try c.decodeIfPresent(Bool.self', 'nextEdition = try c.decodeIfPresent(NextEdition.self']:
            self.assertIn(value, self.contracts)
        for value in ['if let points = value.awards.points', 'if let xp = value.awards.earnedXP',
                      'if let coupon = value.awards.couponGranted', 'if let amount = award.amount']:
            self.assertIn(value, self.ui)
        self.assertNotIn('?? 0', self.contracts)
        self.assertNotIn('?? 0', self.ui)

    def test_missing_topic_shell_does_not_render_progress_or_rewards(self):
        self.assertIn('public var hasTopic: Bool { topicID != nil }', self.contracts)
        self.assertIn('if value.hasTopic { facts(value) }', self.ui)
        self.assertIn('ContentUnavailableView("exploreCompletion.noTopic"', self.ui)
        self.assertIn('if value.requiredChapterCount > 0', self.ui)

    def test_current_owned_order_and_completion_contexts_are_bound_before_mounting(self):
        provider = self.ui.split('struct ExploreCompletionProvider {', 1)[1].split('/// The parent', 1)[0]
        for value in ['origin.identity == originSession.identity', 'currentOrigin() == originSession',
                      'reader.matches(context: originSession.context)', 'readIdentity.accountID == originSession.identity.accountID',
                      'readIdentity.epoch == originSession.identity.epoch', 'ObjectIdentifier(origin) == owner.originID',
                      'reader.identity == owner.readIdentity']:
            self.assertIn(value, provider)
        self.assertIn('ExploreCompletionEntry(order: order, requestedID: id, origin: reader)', self.orders)
        self.assertEqual(self.orders.count('ExploreCompletionEntry('), 1)

    def test_navigation_is_explicit_scope_checked_and_does_not_create_approval(self):
        entry = self.ui.split('@MainActor struct ExploreCompletionEntry:', 1)[1].split('@MainActor struct ExploreCompletionView:', 1)[0]
        for value in ['Button("exploreCompletion.open"', 'guard visible, selected == nil, renderedPresentation == presentationID',
                      '.navigationDestination(item: $selected)', 'target.owner == provider.owner', 'provider.matches(origin: origin)',
                      '.onChange(of: provider?.reader.identity)', 'private func retire() { selected = nil; presentationID = UUID() }']:
            self.assertIn(value, entry)
        self.assertNotIn('reader.read(', entry)
        self.assertNotIn('ExploreCompletionReadApproval(', self.ui)

    def test_model_and_view_retire_stale_overlapping_or_departed_reads(self):
        for value in ['generation = UUID(); acceptedIdentity = nil; snapshot = nil', 'acceptedIdentity == reader.identity',
                      'reader.identity == expectedIdentity', 'self.generation == ticket && self.matchesPresentation(presentationID) && isCurrent()',
                      'guard !Task.isCancelled, generation == ticket', 'if generation == ticket { isLoading = false }']:
            self.assertIn(value, self.read)
        self.assertIn('.onDisappear { model.endPresentation() }', self.ui)
        self.assertIn('guard isCurrent(), reader.identity == identity else { model.invalidate(); return }', self.ui)

    def test_rendered_presentation_is_captured_before_retry_and_checked_before_generation_and_receipt(self):
        for value in ['let renderedPresentation = model.presentationID', 'guard let ticket = renderedPresentation else { return }',
                      'Task { await load(presentationID: ticket) }', '.task(id: renderedPresentation)',
                      '.onAppear { model.beginPresentation() }', '.onDisappear { model.endPresentation() }',
                      'guard !Task.isCancelled, model.matchesPresentation(presentationID) else { return }']:
            self.assertIn(value, self.ui)
        model_load = self.read.split('public func load(_ target:', 1)[1]
        self.assertLess(model_load.index('matchesPresentation(presentationID)'), model_load.index('invalidate()'))
        self.assertGreaterEqual(model_load.count('matchesPresentation(presentationID)'), 4)
        self.assertIn('presentationID = nil; invalidate()', self.read)
        self.assertNotIn('Task { await load() }', self.ui)
        tests = (ROOT / 'Tests/CoreTests/ExploreCompletionReadTests.swift').read_text()
        for name in ['testQueuedRetryAfterDepartureWithSameAuthorityMakesNoRequestOrFacts',
                     'testOldQueuedRetryCannotDispatchOrClearNewPresentationFactsAfterReopen',
                     'testDepartureAtReceiptRetiresFactsWithoutChangingAuthority']:
            self.assertIn('func ' + name, tests)

    def test_completion_is_read_only_and_does_not_download_images_or_persist_secrets(self):
        for forbidden in ['grantOnce(', 'api/club/join', 'api/user/follow', 'URLSession', 'AsyncImage(', 'UserDefaults',
                          'Keychain', 'FileManager', 'requestWhenInUseAuthorization', 'ShareLink(', 'print(', 'Logger(']:
            self.assertNotIn(forbidden, self.read + self.ui)
        self.assertIn('Text("exploreCompletion.readOnly")', self.ui)
        self.assertIn('.privacySensitive()', self.ui)

    def test_localizations_are_complete_bilingual_and_do_not_claim_missing_rewards_are_zero(self):
        fragment = json.loads((ROOT / 'Resources/ExploreCompletionLocalizations.fragment.json').read_text())
        rendered = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', self.ui)
        keys = set(re.findall(r'"(exploreCompletion\.[A-Za-z]+)"', rendered))
        self.assertEqual(keys, set(fragment))
        for key in keys:
            self.assertEqual(set(fragment[key]['localizations']), {'en', 'zh-Hans'})
            for language in ['en', 'zh-Hans']:
                self.assertTrue(fragment[key]['localizations'][language]['stringUnit']['value'])


if __name__ == '__main__':
    unittest.main()
