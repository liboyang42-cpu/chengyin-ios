from pathlib import Path
import hashlib,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
APP=ROOT/'App/MerchantStationLiveCodeView.swift'
VIEW=ROOT/'App/MerchantContentViews.swift'
CORE=ROOT/'Core/MerchantStationContracts.swift'
def digest(b): return hashlib.sha256(b).hexdigest()
PROTECTED = dict(zip(
    (
        'Core/MerchantContentDomain.swift',
        'Core/MerchantContentService.swift',
        'Core/MerchantContentCoordinator.swift',
        'Core/MerchantStationServiceWindow.swift',
        'Core/MerchantAccess.swift',
        'Core/VerificationCodePresentation.swift',
        'App/VerificationCodeView.swift',
        'App/MerchantBusinessEditor.swift',
        'App/MerchantBusinessViews.swift',
        'Core/MerchantBusinessMutation.swift',
        'App/MerchantContentEditor.swift',
        'App/MerchantHomeView.swift',
        'Resources/Localizable.xcstrings',
        'Questify.xcodeproj/project.pbxproj',
        'Package.swift',
    ),
    (
        '3b0c38a01132ed9bfbb164b0b2b5e81113df6869e0afa48376df3afded7ae19f',
        'cf85b10be41628a483a5954d37b49a03a3f88c5946fe2987e224d9c0f07e1434',
        '9648d423ec3e1648ef6b764a7ca708b91f9c005f096fd2c683760c3267ee9b84',
        '62e93707db9f0bbad6e1f28477e012524b299930edfc6e03493c1a1c1d57066b',
        '1b1c35dfe2d0bc2144484bc9a73ad816d98ea89df76cf221044c6ffcbfc30443',
        '16aeaec16ac33159c2ccc60e5c2b50eb5105a69395bace30087cfbe16820c73d',
        'd5211a7933bbf10470ff62867492f212826566022262a1aa84c5eb00754eb96e',
        '87140c2bb2fe9af384af57908fa98e1186fc75dcaf273ecc66d8f78ec40fc671',
        'c4fa6f3121f7a7d69c21e27b384b2c1999fa080abacb19a6fcbdc23daa74169a',
        '4695496ea387604f10c7749f270780472f8a9a39fc20fd712def1b12a7a37b0b',
        '4caceb48edf13be3860d51faeedd9e5c89615642d7d2c1273cc1388d47dff109',
        'f03b2f272e087c91e5d2f3383049e4bc2524ccddacb60f597f605dfb027756a8',
        'f61d566505b2919e712ad64bb2dfae7fdb14a2b14d19fa9bd3b30a97907cea2a',
        'f32c26e5c63595ee5716dc618a33e32b3b58180f4ac7a9a9d5fbd5c49e070fa2',
        '89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d',
    ),
))
INVERSES = {'App/MerchantContentViews.swift': {'before': '1202668627f6c67c9ab8b065f2db9f0db6b957480cc967fa721c370df1d829b7', 'after': '334b0060952d2a927feb9e2185a413145e991f97a60e2987fafd2f60235c22a5', 'hunks': [(8814, b'        case .poster: MerchantContentCodeView(snapshot: s)\n        case .liveCode: MerchantStationLiveCodeView(owner: model, snapshot: s).id(s.observedAt)\n', b'        case .poster, .liveCode: MerchantContentCodeView(snapshot: s)\n')]}, 'Core/MerchantStationContracts.swift': {'before': '79204396dc8112e29a2d4a55589a7f1e371aa51062ae13d1cc61dd02c318eaab', 'after': '54d04df6f2f28571617f084c3c6cd7fcf1b6601b0c0fa587af88314dcad48c61', 'hunks': [(4905, b'        guard let startKey = Self.liveCodeTimeKey(start), let endKey = Self.liveCodeTimeKey(end) else { return false }\n        return startKey < endKey\n    }\n    /// Read-only compatibility with GameSessionRuntimeServiceImpl.formatDate and the\n    /// mini-program\'s dateTimeKey. Server civil time has no offset (JVM default zone);\n    /// compare minute keys without interpreting it in the phone\'s timezone.\n    private static func liveCodeTimeKey(_ value: String) -> String? {\n        guard [16, 19].contains(value.utf8.count),\n              value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} (?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?$"#, options: .regularExpression) != nil else { return nil }\n        let minute = String(value.prefix(16))\n        return MerchantStationCommand.validTime(minute) ? minute : nil\n', b'        return MerchantStationCommand.validTime(start) && MerchantStationCommand.validTime(end) && start < end\n')]}}

class MerchantStationLiveCodeContracts(unittest.TestCase):
    def test_exact_two_shared_file_inverse_proves_no_unrelated_edits(self):
        for p,proof in INVERSES.items():
            raw=(ROOT/p).read_bytes(); self.assertEqual(digest(raw),proof['after'])
            for offset,after,before in reversed(proof['hunks']):
                self.assertEqual(raw[offset:offset+len(after)],after); raw=raw[:offset]+before+raw[offset+len(after):]
            self.assertEqual(digest(raw),proof['before'])
    def test_existing_requests_grants_writes_journal_and_other_authors_are_byte_exact(self):
        for p,expected in PROTECTED.items(): self.assertEqual(digest((ROOT/p).read_bytes()),expected,p)
    def test_only_live_code_mount_changes_and_static_poster_stays(self):
        text=VIEW.read_text();self.assertIn('case .poster: MerchantContentCodeView(snapshot: s)',text)
        self.assertIn('case .liveCode: MerchantStationLiveCodeView(owner: model, snapshot: s).id(s.observedAt)',text)
        self.assertEqual(text.count('MerchantStationLiveCodeView('),1)
    def test_exact_payload_local_qr_has_no_network_storage_copy_or_share_surface(self):
        text=APP.read_text();self.assertIn('filter.message = Data(code.utf8)',text)
        self.assertIn('CIFilter.qrCodeGenerator()',text);self.assertIn('.cacheIntermediates: false',text)
        self.assertIn('.interpolation(.none)',text)
        for forbidden in ['URLSession','AsyncImage','qrcodeUrl','ShareLink','UIPasteboard','FileManager','UserDefaults','UIImageWriteToSavedPhotosAlbum','Text(verbatim: receipt.code)','accessibilityValue','Logger']:
            self.assertNotIn(forbidden,text)
        self.assertNotRegex(text,r'\bprint\s*\(')
    def test_receipt_checks_exact_node_type_signed_nonce_and_absolute_expiry(self):
        text=APP.read_text()
        for fragment in ['snapshot.value["nodeId"].safeInteger == nodeID','parts[1] == String(nodeID)','parts[2] == "play_checkin"','String(nonce) == parts[4]','parts.count == 6','expiry > now','expiry <= snapshot.observedAt.addingTimeInterval','(1...60_000).contains(ttl)','deadlineUptime = uptime + expiry.timeIntervalSince(now)','min(expiresAt.timeIntervalSince(now), deadlineUptime - uptime)']:
            self.assertIn(fragment,text)
    def test_owner_and_auth_are_dynamic_render_fences(self):
        text=APP.read_text()
        for fragment in ['owner.revision == ownerRevision','owner.coordinator.isCurrent','owner.coordinator.service.isAuthenticated','owner.coordinator.service.scope == baseline.scope','owner.coordinator.query == baseline.query','owner.coordinator.snapshot == baseline','owner.coordinator.snapshot?.observedAt == baseline.observedAt','baseline.access.active','!owner.coordinator.busy','!owner.coordinator.locked','owner.coordinator.review == nil']:
            self.assertIn(fragment,text)
    def test_scene_and_departure_retire_without_automatic_request(self):
        text=APP.read_text();self.assertIn('if scenePhase == .active, let receipt = lease.display',text)
        self.assertIn('.onDisappear { lease.retire(clearOwnedSnapshot: true) }',text)
        self.assertIn('if phase != .active { lease.retire(clearOwnedSnapshot: true) }',text)
        self.assertIn('receipt = nil; baseline = nil; retired = true',text)
        for forbidden in ['await owner.load','await model.load','service.load','service.perform','Task.detached','Timer.publish']:
            self.assertNotIn(forbidden,text)
    def test_cleanup_does_not_clear_newer_receipt(self):
        text=APP.read_text().split('func retire(clearOwnedSnapshot: Bool = false)')[1].split('@MainActor struct')[0]
        self.assertIn('cleanupIdentity.matches(current)',text)
        self.assertIn('self.cleanupIdentity = nil',text)
        self.assertEqual(text.count('owner.invalidate()'),1)
    def test_seconds_compatibility_is_read_only_and_has_no_timezone_guess(self):
        text=CORE.read_text();self.assertEqual(text.count('Self.liveCodeTimeKey('),2)
        helper=text.split('private static func liveCodeTimeKey')[1].split('public struct MerchantStationCommand')[0]
        for fragment in ['[16, 19].contains(value.utf8.count)','String(value.prefix(16))','MerchantStationCommand.validTime(minute)']:
            self.assertIn(fragment,helper)
        for forbidden in ['DateFormatter','TimeZone.current','Calendar.current','Asia/Shanghai','ISO8601']:
            self.assertNotIn(forbidden,helper)
    def test_four_localized_titles_are_complete_and_collision_free(self):
        values=json.loads((ROOT/'Resources/MerchantStationLiveCodeLocalizations.fragment.json').read_text())
        existing=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        self.assertEqual(len(values),4);self.assertFalse(set(values)&set(existing))
        for key,row in values.items():
            self.assertIn('"'+key+'"',APP.read_text())
            for lang in ['en','zh-Hans']: self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
    def test_authored_swift_tests_cover_negative_receipts_and_stale_lifecycle(self):
        app=(ROOT/'Tests/AppUnitTests/MerchantStationLiveCodeTests.swift').read_text()
        core=(ROOT/'Tests/CoreTests/MerchantStationLiveCodeTimeTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',app)),23);self.assertEqual(len(re.findall(r'func test',core)),6)
        for fragment in ['BeforeRetirementCallback','ChangedObservedAt','ClockRollback','RetiringOldLease','AbsoluteExpiry','MismatchedReceiptScope','SignedOut','ScopeChange']:
            if fragment=='SignedOut':fragment='SignOut'
            self.assertIn(fragment,app)
    def test_retirement_retains_only_fingerprinted_receipt_identity_for_deferred_cleanup(self):
        text=APP.read_text(); identity=text.split('private struct MerchantStationLiveCodeCleanupIdentity')[1].split('/// Binds')[0]
        for fragment in ['let valueFingerprint: SHA256.Digest','snapshot.scope == scope','snapshot.query == query','snapshot.access == access','snapshot.observedAt == observedAt','Self.fingerprint(snapshot.value) == valueFingerprint','encoder.outputFormatting = [.sortedKeys]','SHA256.hash(data: data)']:
            self.assertIn(fragment,identity)
        self.assertNotIn('let code:',identity);self.assertNotIn('let value: MerchantContentValue',identity)
        tests=(ROOT/'Tests/AppUnitTests/MerchantStationLiveCodeTests.swift').read_text()
        for fragment in ['ExpiredLeaseStillClearsOriginalSnapshot','InvalidInitialReceiptStillClearsOriginalSnapshot','ExpiredOldLeaseCannotClearNewReceiptEvenWithSameObservationTime']:
            self.assertIn(fragment,tests)
    def test_display_does_not_expose_raw_code_as_accessibility_or_fields(self):
        text=APP.read_text();self.assertIn('.privacySensitive()',text)
        self.assertIn('.accessibilityLabel("merchant.stationLiveCode.image")',text)
        self.assertNotIn('MerchantContentFields',text)
        self.assertNotIn('.textSelection',text)
if __name__=='__main__': unittest.main()
