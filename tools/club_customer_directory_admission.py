"""Exact P044 directory-only admission and historical scanner input.

This adapter is newly scoped to the published baseline. It never broadens scanner
ignores, renumbers a historical finding, or skips an original assertion.
"""
from pathlib import Path
import copy
import hashlib
import json

BASE_CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
BASE_READINESS_SHA256 = 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f'
CONTRACT_PATH = 'tools/run138_editor_readiness_contract.json'
HELPER_PATH = 'tools/club_customer_directory_admission.py'
HELPER_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
SOURCE_EDITS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27', 'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2', 'hunks': [{'before': '        return (1...maximum).contains(id) ? id : nil\n    }\n}\n', 'after': '        return (1...maximum).contains(id) ? id : nil\n    }\n}\n\n/// Mirrors CRM list/count/detail requireGovernable using current access/me evidence.\n/// Contact-list visibility and event-only grants cannot authorize this club-wide read.\npublic extension ClubGovernancePermissions {\n    func allowsCustomerDirectory(scope: ClubGovernanceScope) -> Bool {\n        guard active, clubID == scope.clubID, (scope.clubID ?? 0) > 0 else { return false }\n        do { try scope.validate() } catch { return false }\n        return roleCodes.contains("CLUB_OWNER") || roleCodes.contains("CLUB_LEGACY_ADMIN") ||\n            permissions.contains("club:member:manage")\n    }\n}\n'}]}, 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264', 'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32', 'hunks': [{'before': '        if permission == "ROLES" { return canManageRoles }\n', 'after': '        if permission == "ROLES" { return canManageRoles }\n        if permission == "CUSTOMER_DIRECTORY" { return allowsCustomerDirectory(scope: scope) }\n'}, {'before': '        case .customers, .customer, .customerCount, .checkin, .topicCustomers, .registrations: return "club:member:list:read"', 'after': '        case .customers, .customer, .customerCount: return "CUSTOMER_DIRECTORY" // Local preflight, never an API grant.\n        case .checkin, .topicCustomers, .registrations: return "club:member:list:read"'}]}, 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f', 'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a', 'hunks': [{'before': '                payload = "{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed ? (chapterFlow ? "[\\"club:content:manage\\"]" : (banFlow ? "[\\"club:member:manage\\"]" : "[\\"club:member:list:read\\"]")) : "[]"),\\"canManageRoles\\":false}"\n', 'after': '                payload = "{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed ? (chapterFlow ? "[\\"club:content:manage\\"]" : (banFlow ? "[\\"club:member:manage\\"]" : "[\\"club:member:list:read\\",\\"club:member:manage\\"]")) : "[]"),\\"canManageRoles\\":false}"\n'}]}, 'tools/tests/test_gitleaks_configuration.py': {'before_sha256': 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c', 'after_sha256': 'e6c0f1cb301fa8a762040ad4ed81c3ab8e5493ca1bfb99329bbbceb395b0c868', 'hunks': [{'before': 'import unittest\n', 'after': 'import unittest\nfrom tools.club_customer_directory_admission import historical_scan_contract\n'}, {'before': '        raw = (ROOT / FILE_DIGEST_PATH).read_text()', 'after': '        raw = historical_scan_contract(ROOT)'}]}}
ADDED_SUPPORT = ('Tests/CoreTests/ClubCustomerPermissionTests.swift', 'Tests/ContractChecks/test_club_customer_permissions.py', 'docs/club-customer-permissions.md', 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py', 'tools/club_customer_directory_admission.py')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def restore_product_source(relative, raw):
    """Require the complete exact current file, then restore its complete baseline."""
    row = SOURCE_EDITS[relative]
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unknown P044 current source: ' + relative)
    text = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if text.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated P044 source span: ' + relative)
        text = text.replace(hunk['after'], hunk['before'], 1)
    restored = text.encode('utf-8')
    if digest(restored) != row['before_sha256']:
        raise ValueError('P044 baseline was not restored exactly: ' + relative)
    return restored


def historical_scan_contract(root):
    """Admit every new input before returning the exact full historical contract.

    The original baseline domain is also accepted, but a baseline contract mixed
    with any new product/checker bytes is rejected. The existing scanner test
    still runs all original assertions against this independently validated input.
    """
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == BASE_CONTRACT_SHA256:
        if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != BASE_READINESS_SHA256:
            raise ValueError('Hybrid baseline and current readiness reader')
        for relative in ADDED_SUPPORT:
            file = root / relative
            if file.exists() or file.is_symlink():
                raise ValueError('Baseline domain contains new support: ' + relative)
        for relative, row in SOURCE_EDITS.items():
            if digest((root / relative).read_bytes()) != row['before_sha256']:
                raise ValueError('Hybrid baseline and P044 source: ' + relative)
        return raw.decode('utf-8')
    from tools import run138_editor_readiness as current
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    contract = current.contract(root)  # Requires the exact reviewed raw bytes.
    if digest((root / HELPER_PATH).read_bytes()) != HELPER_SHA256:
        raise ValueError('Current P044 scanner input reader changed')
    for relative, expected in SOURCE_EDITS.items():
        if contract['feature_batch_sources'].get(relative) != expected:
            raise ValueError('P044 source admission row changed: ' + relative)
        restore_product_source(relative, (root / relative).read_bytes())
    for relative in ADDED_SUPPORT:
        expected = contract['feature_batch_support_sha256'].get(relative)
        if not expected or digest((root / relative).read_bytes()) != expected:
            raise ValueError('P044 support input changed: ' + relative)
    restored = copy.deepcopy(contract)
    for relative in SOURCE_EDITS:
        del restored['feature_batch_sources'][relative]
    for relative in ADDED_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    baseline = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete historical scanner contract not restored')
    return baseline.decode('utf-8')

# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.

FROZEN_PERMISSION_CONTRACT_SHA256 = 'f2a58dbe3aaa71a13ae0f7ab45505afdea5f02360164c3c697e4e392ac8db41d'
FROZEN_PERMISSION_READINESS_SHA256 = '0fd831ef72293c21ab8b2af505214585a6a1509acbcc61c9f60015b3e815ef28'
FROZEN_PERMISSION_HELPER_SHA256 = '244f9353c0a31a19b11bfb74054ba454756940a64238974d946ef59cce5ad8cd'
FROZEN_TEST_PATH = 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py'
EVOLUTION_SOURCES = {'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a', 'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff', 'hunks': [{'before': 'import SwiftUI\n\n/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.\nstruct ClubGovernanceEntryButton: View {\n', 'after': 'import SwiftUI\n\n/// P044 keyword-only scheduling. The view still owns authorization and response fences.\n@MainActor final class ClubCustomerKeywordDebounce {\n    static let delayNanoseconds: UInt64 = 300_000_000\n    private var pending: Task<Void, Never>?\n    private var revision: UInt64 = 0\n    private let sleep: @MainActor @Sendable () async throws -> Void\n    nonisolated init(sleep: @escaping @MainActor @Sendable () async throws -> Void = {\n        try await Task.sleep(nanoseconds: ClubCustomerKeywordDebounce.delayNanoseconds)\n    }) { self.sleep = sleep }\n    func cancel() {\n        revision &+= 1\n        pending?.cancel()\n        pending = nil\n    }\n    @discardableResult func schedule(_ action: @escaping @MainActor () async -> Void) -> Task<Void, Never> {\n        cancel()\n        let expected = revision\n        let task = Task { @MainActor [weak self] in\n            guard let self else { return }\n            do { try await self.sleep() } catch { return }\n            guard !Task.isCancelled, self.revision == expected else { return }\n            // Release the handle before load() cancels any still-pending timer.\n            self.pending = nil\n            await action()\n        }\n        pending = task\n        return task\n    }\n}\n\n/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.\nstruct ClubGovernanceEntryButton: View {\n'}, {'before': '    @State private var filter = "all"\n    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all\n    @State private var keyword = ""\n    @State private var sort = "composite"\n    @State private var page = 1\n    @State private var editor: ClubGovernanceFormRoute?\n', 'after': '    @State private var filter = "all"\n    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all\n    @State private var keyword = ""\n    @State private var customerKeywordDebounce = ClubCustomerKeywordDebounce()\n    @State private var sort = "composite"\n    @State private var page = 1\n    @State private var editor: ClubGovernanceFormRoute?\n'}, {'before': '                    Picker("club.gov.filter", selection: $filter) {\n                        ForEach(["all", "repeat", "new", "remark"], id: \\.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }\n                    }\n                    .onChange(of: filter) { _, _ in Task { await load() } }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search).onSubmit { Task { await load() } }\n                    Button("club.gov.search") { Task { await load() } }.disabled(loading)\n                }\n            }\n            if operation == .topicCustomers {\n', 'after': '                    Picker("club.gov.filter", selection: $filter) {\n                        ForEach(["all", "repeat", "new", "remark"], id: \\.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }\n                    }\n                    .onChange(of: filter) { _, _ in loadCustomersNow() }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search)\n                        .onChange(of: keyword) { _, _ in scheduleCustomerKeywordRead() }\n                        .onSubmit { loadCustomersNow() }\n                    Button("club.gov.search") { loadCustomersNow() }.disabled(loading)\n                }\n            }\n            if operation == .topicCustomers {\n'}, {'before': '        .task(id: readContext) { snapshot = nil; editor = nil; customerTopic = nil; feedClub = nil; coordinator.cancelReview(); await load() }\n        .onChange(of: readContext) { _, _ in invalidateRead() }\n        .onChange(of: identity) { _, _ in invalidateRead() }\n        .onDisappear { generation &+= 1 }\n        .refreshable { await load() }\n    }\n    private func load() async {\n        generation &+= 1; let revision = generation; let expected = identity; let context = readContext\n        snapshot = nil; failure = nil; loading = true\n        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()\n', 'after': '        .task(id: readContext) { snapshot = nil; editor = nil; customerTopic = nil; feedClub = nil; coordinator.cancelReview(); await load() }\n        .onChange(of: readContext) { _, _ in invalidateRead() }\n        .onChange(of: identity) { _, _ in invalidateRead() }\n        .onDisappear {\n            if operation == .customers {\n                customerKeywordDebounce.cancel()\n                generation &+= 1\n            }\n        }\n        .onDisappear { generation &+= 1 }\n        .refreshable { await load() }\n    }\n    @MainActor private func loadCustomersNow() {\n        customerKeywordDebounce.cancel()\n        Task { await load() }\n    }\n    @MainActor private func scheduleCustomerKeywordRead() {\n        guard operation == .customers else { return }\n        let context = readContext; let expected = identity\n        let expectedFilter = filter; let expectedKeyword = keyword\n        // Invalidate an older response immediately, including the 300ms wait.\n        generation &+= 1\n        snapshot = nil; snapshotContext = nil; failure = nil; loading = false\n        let keywordRevision = generation\n        customerKeywordDebounce.schedule {\n            guard operation == .customers, context == readContext, expected == identity,\n                  access.identity == expected, keywordRevision == generation,\n                  filter == expectedFilter, keyword == expectedKeyword,\n                  !Task.isCancelled else { return }\n            await load()\n        }\n    }\n    @MainActor private func load() async {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n        generation &+= 1; let revision = generation; let expected = identity; let context = readContext\n        snapshot = nil; failure = nil; loading = true\n        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()\n'}, {'before': '        }\n        if revision == generation { loading = false }\n    }\n    private func invalidateRead() {\n        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()\n    }\n    private func current(_ target: ClubFeedClubRoute) -> Bool {\n', 'after': '        }\n        if revision == generation { loading = false }\n    }\n    @MainActor private func invalidateRead() {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()\n    }\n    private func current(_ target: ClubFeedClubRoute) -> Bool {\n'}]}, 'Questify.xcodeproj/project.pbxproj': {'before_sha256': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552', 'after_sha256': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50', 'hunks': [{'before': '\t\t"791E6BF02CD332B0299A3459" = {\n', 'after': '\t\t"2A4F7E878F7689C47FE34583" = {\n\t\t\t"isa" = "PBXFileReference";\n\t\t\t"lastKnownFileType" = "sourcecode.swift";\n\t\t\t"path" = "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift";\n\t\t\t"sourceTree" = "<group>";\n\t\t};\n\t\t"4FF7D0B5D5B04E3FAAE97D5A" = {\n\t\t\t"isa" = "PBXBuildFile";\n\t\t\t"fileRef" = "2A4F7E878F7689C47FE34583";\n\t\t};\n\t\t"791E6BF02CD332B0299A3459" = {\n'}, {'before': '\t\t\t\t"791E6BF02CD332B0299A3459",\n', 'after': '\t\t\t\t"2A4F7E878F7689C47FE34583",\n\t\t\t\t"791E6BF02CD332B0299A3459",\n'}, {'before': '\t\t\t\t"19EC95F64576113ABFA6995C",\n', 'after': '\t\t\t\t"4FF7D0B5D5B04E3FAAE97D5A",\n\t\t\t\t"19EC95F64576113ABFA6995C",\n'}]}}
EVOLUTION_SUPPORT = ('Tests/ContractChecks/test_club_customer_keyword_debounce.py', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift', 'docs/club-customer-keyword-debounce.md')
TEST_EVOLUTION = {'before_sha256': '262656eb7032755d32ccca9496bfbc1fa1407c8673c45cf1028ff6a589a4af54', 'after_sha256': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5', 'hunks': [{'before': "ROOT = Path(__file__).resolve().parents[2]\nINPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n\n\ndef digest(raw):\n", 'after': "ROOT = Path(__file__).resolve().parents[2]\nINPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\nCOMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | set(admission.EVOLUTION_SUPPORT)\n\n\ndef digest(raw):\n"}, {'before': '\n@contextmanager\ndef copied_admission_inputs():\n    """Only the eleven admission files, never a repository or historical checkout."""\n    with tempfile.TemporaryDirectory(prefix=\'club-directory-admission-\') as temporary:\n        root = Path(temporary)\n        for relative in sorted(INPUTS):\n            target = root / relative\n            target.parent.mkdir(parents=True, exist_ok=True)\n            target.write_bytes((ROOT / relative).read_bytes())\n', 'after': '\n@contextmanager\ndef copied_admission_inputs():\n    """Only the sixteen admission files, never a repository or historical checkout."""\n    with tempfile.TemporaryDirectory(prefix=\'club-directory-admission-\') as temporary:\n        root = Path(temporary)\n        for relative in sorted(COMBINED_INPUTS):\n            target = root / relative\n            target.parent.mkdir(parents=True, exist_ok=True)\n            target.write_bytes((ROOT / relative).read_bytes())\n'}, {'before': '            \'Questify.xcodeproj/project.pbxproj\': \'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552\',\n            \'Package.swift\': \'89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d\',\n        }.items():\n            self.assertEqual(digest((ROOT / relative).read_bytes()), expected)\n        project = (ROOT / \'Questify.xcodeproj/project.pbxproj\').read_text()\n        for relative in [\'Core/ClubGovernanceContracts.swift\', \'Core/ClubCustomerHistoryTopicRoute.swift\']:\n            self.assertEqual(project.count(\'"path" = "\' + relative + \'";\'), 1)\n', 'after': '            \'Questify.xcodeproj/project.pbxproj\': \'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552\',\n            \'Package.swift\': \'89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d\',\n        }.items():\n            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, relative)), expected)\n        project = (ROOT / \'Questify.xcodeproj/project.pbxproj\').read_text()\n        for relative in [\'Core/ClubGovernanceContracts.swift\', \'Core/ClubCustomerHistoryTopicRoute.swift\']:\n            self.assertEqual(project.count(\'"path" = "\' + relative + \'";\'), 1)\n'}, {'before': "    def test_whole_contract_is_exact_baseline_with_only_new_admission_rows(self):\n        restored = admission.historical_scan_contract(ROOT).encode()\n        self.assertEqual(digest(restored), admission.BASE_CONTRACT_SHA256)\n        old, new = json.loads(restored), readiness.contract(ROOT)\n        self.assertEqual(len(old['feature_batch_sources']), 122)\n        self.assertEqual(len(old['feature_batch_support_sha256']), 498)\n        self.assertEqual(set(new['feature_batch_sources']) - set(old['feature_batch_sources']), set(admission.SOURCE_EDITS))\n", 'after': "    def test_whole_contract_is_exact_baseline_with_only_new_admission_rows(self):\n        restored = admission.historical_scan_contract(ROOT).encode()\n        self.assertEqual(digest(restored), admission.BASE_CONTRACT_SHA256)\n        old, new = json.loads(restored), json.loads(admission.frozen_permission_contract(ROOT))\n        self.assertEqual(len(old['feature_batch_sources']), 122)\n        self.assertEqual(len(old['feature_batch_support_sha256']), 498)\n        self.assertEqual(set(new['feature_batch_sources']) - set(old['feature_batch_sources']), set(admission.SOURCE_EDITS))\n"}, {'before': "            'App/ClubGovernanceCommandForm.swift': '28dcfc08ed90e072e51c7a28202a9af925907c9edbe8a296cf5092678f32174f',\n            '.gitleaksignore': 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0',\n        }.items():\n            self.assertEqual(digest((ROOT / path).read_bytes()), expected)\n\n    def test_all_eleven_physical_inputs_reject_same_size_mtime_crlf_and_cr_edits(self):\n        with copied_admission_inputs() as root:\n            admission.historical_scan_contract(root)  # Warm call cannot authorize later bytes.\n            for relative in sorted(INPUTS):\n                file = root / relative\n                saved, metadata = file.read_bytes(), file.stat()\n                for name, value in [('same-size-mtime', bytes([saved[0] ^ 1]) + saved[1:]),\n", 'after': "            'App/ClubGovernanceCommandForm.swift': '28dcfc08ed90e072e51c7a28202a9af925907c9edbe8a296cf5092678f32174f',\n            '.gitleaksignore': 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0',\n        }.items():\n            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, path)), expected)\n\n    def test_all_eleven_physical_inputs_reject_same_size_mtime_crlf_and_cr_edits(self):\n        with copied_admission_inputs() as root:\n            admission.historical_scan_contract(root)  # Warm call cannot authorize later bytes.\n            for relative in sorted(COMBINED_INPUTS):\n                file = root / relative\n                saved, metadata = file.read_bytes(), file.stat()\n                for name, value in [('same-size-mtime', bytes([saved[0] ^ 1]) + saved[1:]),\n"}, {'before': '\n    def test_missing_support_and_equivalent_json_are_rejected(self):\n        with copied_admission_inputs() as root:\n            for relative in admission.ADDED_SUPPORT:\n                file = root / relative\n                saved = file.read_bytes()\n                file.unlink()\n', 'after': '\n    def test_missing_support_and_equivalent_json_are_rejected(self):\n        with copied_admission_inputs() as root:\n            for relative in admission.ADDED_SUPPORT + admission.EVOLUTION_SUPPORT:\n                file = root / relative\n                saved = file.read_bytes()\n                file.unlink()\n'}, {'before': '                admission.historical_scan_contract(root)\n            for relative in admission.ADDED_SUPPORT:\n                (root / relative).unlink()\n            self.assertEqual(admission.historical_scan_contract(root), baseline)\n            (root / admission.CONTRACT_PATH).write_bytes((ROOT / admission.CONTRACT_PATH).read_bytes())\n            with self.assertRaises(ValueError):\n', 'after': '                admission.historical_scan_contract(root)\n            for relative in admission.ADDED_SUPPORT:\n                (root / relative).unlink()\n            for relative in admission.EVOLUTION_SOURCES:\n                file = root / relative\n                file.write_bytes(admission.restore_evolution_source(relative, file.read_bytes()))\n            for relative in admission.EVOLUTION_SUPPORT:\n                (root / relative).unlink()\n            self.assertEqual(admission.historical_scan_contract(root), baseline)\n            (root / admission.CONTRACT_PATH).write_bytes((ROOT / admission.CONTRACT_PATH).read_bytes())\n            with self.assertRaises(ValueError):\n'}]}

_FROZEN_READER = historical_scan_contract


def _inverse_row(relative, raw, row):
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unreviewed complete evolution input: ' + relative)
    text = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if text.count(hunk['after']) != 1:
            raise ValueError('Missing/repeated exact evolution span: ' + relative)
        text = text.replace(hunk['after'], hunk['before'], 1)
    restored = text.encode('utf-8')
    if digest(restored) != row['before_sha256']:
        raise ValueError('Evolution did not restore frozen file: ' + relative)
    return restored


def restore_evolution_source(relative, raw):
    if relative == 'Questify.xcodeproj/project.pbxproj':
        from Tests.ContractChecks.test_category_roam_registration import native_predecessor_source
        try:
            raw = native_predecessor_source(relative, raw)
        except AssertionError as error:
            raise ValueError(str(error)) from error
    return _inverse_row(relative, raw, EVOLUTION_SOURCES[relative])


def _require_old_evolution_domain(root):
    for relative, row in EVOLUTION_SOURCES.items():
        if digest((root / relative).read_bytes()) != row['before_sha256']:
            raise ValueError('Hybrid baseline and keyword/PBX source: ' + relative)
    for relative in EVOLUTION_SUPPORT:
        file = root / relative
        if file.exists() or file.is_symlink():
            raise ValueError('Baseline domain contains new support: ' + relative)


def frozen_permission_contract(root):
    """Validate the whole sixteen-file set, then return exact frozen eleven-file JSON."""
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == FROZEN_PERMISSION_CONTRACT_SHA256:
        if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != FROZEN_PERMISSION_READINESS_SHA256:
            raise ValueError('Hybrid frozen permission reader')
        if digest((root / HELPER_PATH).read_bytes()) != FROZEN_PERMISSION_HELPER_SHA256:
            raise ValueError('Hybrid frozen permission helper')
        _require_old_evolution_domain(root)
        contract = json.loads(raw)
        for relative in SOURCE_EDITS:
            restore_product_source(relative, (root / relative).read_bytes())
        for relative in ADDED_SUPPORT:
            if digest((root / relative).read_bytes()) != contract['feature_batch_support_sha256'][relative]:
                raise ValueError('Hybrid frozen permission support: ' + relative)
        return raw.decode('utf-8')
    from tools import run138_editor_readiness as current
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    contract = current.contract(root)
    if digest((root / HELPER_PATH).read_bytes()) != HELPER_SHA256:
        raise ValueError('Current combined admission reader changed')
    for relative, expected in SOURCE_EDITS.items():
        if contract['feature_batch_sources'].get(relative) != expected:
            raise ValueError('Original permission source row changed: ' + relative)
        restore_product_source(relative, (root / relative).read_bytes())
    for relative in ADDED_SUPPORT + EVOLUTION_SUPPORT:
        expected = contract['feature_batch_support_sha256'].get(relative)
        if not expected or digest((root / relative).read_bytes()) != expected:
            raise ValueError('Combined support input changed: ' + relative)
    for relative in EVOLUTION_SOURCES:
        restore_evolution_source(relative, (root / relative).read_bytes())
    # Both changed original support files must also restore actual frozen bytes.
    _inverse_row(FROZEN_TEST_PATH, (root / FROZEN_TEST_PATH).read_bytes(), TEST_EVOLUTION)
    marker = '\n# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.\n'
    helper = (root / HELPER_PATH).read_bytes().split(marker.encode(), 1)[0]
    if digest(helper) != FROZEN_PERMISSION_HELPER_SHA256:
        raise ValueError('Original permission reader was not retained exactly')
    restored = copy.deepcopy(contract)
    app = 'App/ClubGovernanceViews.swift'
    pbx = 'Questify.xcodeproj/project.pbxproj'
    if restored['feature_batch_sources'].pop(app, None) != EVOLUTION_SOURCES[app]:
        raise ValueError('Keyword source inverse row changed')
    pbx_row = restored['feature_batch_sources'][pbx]
    new_hunks = EVOLUTION_SOURCES[pbx]['hunks']
    if pbx_row['after_sha256'] != EVOLUTION_SOURCES[pbx]['after_sha256'] or pbx_row['hunks'][-len(new_hunks):] != new_hunks:
        raise ValueError('PBX exact extension row changed')
    pbx_row['after_sha256'] = EVOLUTION_SOURCES[pbx]['before_sha256']
    del pbx_row['hunks'][-len(new_hunks):]
    for relative in EVOLUTION_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    restored['feature_batch_support_sha256'][FROZEN_TEST_PATH] = TEST_EVOLUTION['before_sha256']
    restored['feature_batch_support_sha256'][HELPER_PATH] = FROZEN_PERMISSION_HELPER_SHA256
    frozen = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(frozen) != FROZEN_PERMISSION_CONTRACT_SHA256:
        raise ValueError('Complete frozen eleven-file contract not restored')
    return frozen.decode('utf-8')


def permission_boundary_bytes(root, relative):
    raw = (Path(root) / relative).read_bytes()
    if relative not in EVOLUTION_SOURCES:
        return raw
    frozen_permission_contract(root)
    row = EVOLUTION_SOURCES[relative]
    if digest(raw) == row['before_sha256']:
        return raw  # Only reached after exact frozen-domain validation.
    return restore_evolution_source(relative, raw)


def historical_scan_contract(root):
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == BASE_CONTRACT_SHA256:
        # Keep the original baseline rejection order and all its checks.
        baseline = _FROZEN_READER(root)
        _require_old_evolution_domain(root)
        return baseline
    frozen = frozen_permission_contract(root)
    restored = json.loads(frozen)
    for relative in SOURCE_EDITS:
        del restored['feature_batch_sources'][relative]
    for relative in ADDED_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    baseline = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete historical scanner contract not restored')
    return baseline.decode('utf-8')

# Finite club layer on the exact creator/fixed45 floor. Frozen reader above retained.
CLUB_PRECONTRACT_SHA256 = 'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053'
CLUB_PREADMISSION_SHA256 = 'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271'
CLUB_PREADMISSION_PATH = 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
CLUB_SOURCE_ROWS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27',
                                              'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
                                              'hunks': [{'before': '        return '
                                                                   '(1...maximum).contains(id) ? id : nil\n'
                                                                   '    }\n'
                                                                   '}\n',
                                                         'after': '        return (1...maximum).contains(id) '
                                                                  '? id : nil\n'
                                                                  '    }\n'
                                                                  '}\n'
                                                                  '\n'
                                                                  '/// Mirrors CRM list/count/detail '
                                                                  'requireGovernable using current access/me '
                                                                  'evidence.\n'
                                                                  '/// Contact-list visibility and '
                                                                  'event-only grants cannot authorize this '
                                                                  'club-wide read.\n'
                                                                  'public extension '
                                                                  'ClubGovernancePermissions {\n'
                                                                  '    func allowsCustomerDirectory(scope: '
                                                                  'ClubGovernanceScope) -> Bool {\n'
                                                                  '        guard active, clubID == '
                                                                  'scope.clubID, (scope.clubID ?? 0) > 0 '
                                                                  'else { return false }\n'
                                                                  '        do { try scope.validate() } catch '
                                                                  '{ return false }\n'
                                                                  '        return '
                                                                  'roleCodes.contains("CLUB_OWNER") || '
                                                                  'roleCodes.contains("CLUB_LEGACY_ADMIN") '
                                                                  '||\n'
                                                                  '            '
                                                                  'permissions.contains("club:member:manage")\n'
                                                                  '    }\n'
                                                                  '}\n'}]},
 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264',
                                        'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
                                        'hunks': [{'before': '        if permission == "ROLES" { return '
                                                             'canManageRoles }\n',
                                                   'after': '        if permission == "ROLES" { return '
                                                            'canManageRoles }\n'
                                                            '        if permission == "CUSTOMER_DIRECTORY" { '
                                                            'return allowsCustomerDirectory(scope: scope) '
                                                            '}\n'},
                                                  {'before': '        case .customers, .customer, '
                                                             '.customerCount, .checkin, .topicCustomers, '
                                                             '.registrations: return "club:member:list:read"',
                                                   'after': '        case .customers, .customer, '
                                                            '.customerCount: return "CUSTOMER_DIRECTORY" // '
                                                            'Local preflight, never an API grant.\n'
                                                            '        case .checkin, .topicCustomers, '
                                                            '.registrations: return '
                                                            '"club:member:list:read"'}]},
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f',
                                                         'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
                                                         'hunks': [{'before': '                payload = '
                                                                              '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                              '? (chapterFlow ? '
                                                                              '"[\\"club:content:manage\\"]" '
                                                                              ': (banFlow ? '
                                                                              '"[\\"club:member:manage\\"]" '
                                                                              ': '
                                                                              '"[\\"club:member:list:read\\"]")) '
                                                                              ': '
                                                                              '"[]"),\\"canManageRoles\\":false}"\n',
                                                                    'after': '                payload = '
                                                                             '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                             '? (chapterFlow ? '
                                                                             '"[\\"club:content:manage\\"]" '
                                                                             ': (banFlow ? '
                                                                             '"[\\"club:member:manage\\"]" : '
                                                                             '"[\\"club:member:list:read\\",\\"club:member:manage\\"]")) '
                                                                             ': '
                                                                             '"[]"),\\"canManageRoles\\":false}"\n'}]},
 'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a',
                                   'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
                                   'hunks': [{'before': 'import SwiftUI\n'
                                                        '\n'
                                                        '/// Mount independently of legacy '
                                                        'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                        'struct ClubGovernanceEntryButton: View {\n',
                                              'after': 'import SwiftUI\n'
                                                       '\n'
                                                       '/// P044 keyword-only scheduling. The view still '
                                                       'owns authorization and response fences.\n'
                                                       '@MainActor final class ClubCustomerKeywordDebounce '
                                                       '{\n'
                                                       '    static let delayNanoseconds: UInt64 = '
                                                       '300_000_000\n'
                                                       '    private var pending: Task<Void, Never>?\n'
                                                       '    private var revision: UInt64 = 0\n'
                                                       '    private let sleep: @MainActor @Sendable () async '
                                                       'throws -> Void\n'
                                                       '    nonisolated init(sleep: @escaping @MainActor '
                                                       '@Sendable () async throws -> Void = {\n'
                                                       '        try await Task.sleep(nanoseconds: '
                                                       'ClubCustomerKeywordDebounce.delayNanoseconds)\n'
                                                       '    }) { self.sleep = sleep }\n'
                                                       '    func cancel() {\n'
                                                       '        revision &+= 1\n'
                                                       '        pending?.cancel()\n'
                                                       '        pending = nil\n'
                                                       '    }\n'
                                                       '    @discardableResult func schedule(_ action: '
                                                       '@escaping @MainActor () async -> Void) -> Task<Void, '
                                                       'Never> {\n'
                                                       '        cancel()\n'
                                                       '        let expected = revision\n'
                                                       '        let task = Task { @MainActor [weak self] in\n'
                                                       '            guard let self else { return }\n'
                                                       '            do { try await self.sleep() } catch { '
                                                       'return }\n'
                                                       '            guard !Task.isCancelled, self.revision '
                                                       '== expected else { return }\n'
                                                       '            // Release the handle before load() '
                                                       'cancels any still-pending timer.\n'
                                                       '            self.pending = nil\n'
                                                       '            await action()\n'
                                                       '        }\n'
                                                       '        pending = task\n'
                                                       '        return task\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// Mount independently of legacy '
                                                       'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                       'struct ClubGovernanceEntryButton: View {\n'},
                                             {'before': '    @State private var filter = "all"\n'
                                                        '    @State private var topicCustomerFilter: '
                                                        'ClubTopicCustomerFilter = .all\n'
                                                        '    @State private var keyword = ""\n'
                                                        '    @State private var sort = "composite"\n'
                                                        '    @State private var page = 1\n'
                                                        '    @State private var editor: '
                                                        'ClubGovernanceFormRoute?\n',
                                              'after': '    @State private var filter = "all"\n'
                                                       '    @State private var topicCustomerFilter: '
                                                       'ClubTopicCustomerFilter = .all\n'
                                                       '    @State private var keyword = ""\n'
                                                       '    @State private var customerKeywordDebounce = '
                                                       'ClubCustomerKeywordDebounce()\n'
                                                       '    @State private var sort = "composite"\n'
                                                       '    @State private var page = 1\n'
                                                       '    @State private var editor: '
                                                       'ClubGovernanceFormRoute?\n'},
                                             {'before': '                    Picker("club.gov.filter", '
                                                        'selection: $filter) {\n'
                                                        '                        ForEach(["all", "repeat", '
                                                        '"new", "remark"], id: \\.self) { '
                                                        'Text(LocalizedStringKey("club.gov.filter." + '
                                                        '$0)).tag($0) }\n'
                                                        '                    }\n'
                                                        '                    .onChange(of: filter) { _, _ in '
                                                        'Task { await load() } }\n'
                                                        '                    TextField("club.gov.keyword", '
                                                        'text: $keyword).submitLabel(.search).onSubmit { '
                                                        'Task { await load() } }\n'
                                                        '                    Button("club.gov.search") { '
                                                        'Task { await load() } }.disabled(loading)\n'
                                                        '                }\n'
                                                        '            }\n'
                                                        '            if operation == .topicCustomers {\n',
                                              'after': '                    Picker("club.gov.filter", '
                                                       'selection: $filter) {\n'
                                                       '                        ForEach(["all", "repeat", '
                                                       '"new", "remark"], id: \\.self) { '
                                                       'Text(LocalizedStringKey("club.gov.filter." + '
                                                       '$0)).tag($0) }\n'
                                                       '                    }\n'
                                                       '                    .onChange(of: filter) { _, _ in '
                                                       'loadCustomersNow() }\n'
                                                       '                    TextField("club.gov.keyword", '
                                                       'text: $keyword).submitLabel(.search)\n'
                                                       '                        .onChange(of: keyword) { _, '
                                                       '_ in scheduleCustomerKeywordRead() }\n'
                                                       '                        .onSubmit { '
                                                       'loadCustomersNow() }\n'
                                                       '                    Button("club.gov.search") { '
                                                       'loadCustomersNow() }.disabled(loading)\n'
                                                       '                }\n'
                                                       '            }\n'
                                                       '            if operation == .topicCustomers {\n'},
                                             {'before': '        .task(id: readContext) { snapshot = nil; '
                                                        'editor = nil; customerTopic = nil; feedClub = nil; '
                                                        'coordinator.cancelReview(); await load() }\n'
                                                        '        .onChange(of: readContext) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onChange(of: identity) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onDisappear { generation &+= 1 }\n'
                                                        '        .refreshable { await load() }\n'
                                                        '    }\n'
                                                        '    private func load() async {\n'
                                                        '        generation &+= 1; let revision = '
                                                        'generation; let expected = identity; let context = '
                                                        'readContext\n'
                                                        '        snapshot = nil; failure = nil; loading = '
                                                        'true\n'
                                                        '        snapshotContext = nil; customerTopic = nil; '
                                                        'feedClub = nil; feedMediaScope = UUID()\n',
                                              'after': '        .task(id: readContext) { snapshot = nil; '
                                                       'editor = nil; customerTopic = nil; feedClub = nil; '
                                                       'coordinator.cancelReview(); await load() }\n'
                                                       '        .onChange(of: readContext) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onChange(of: identity) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onDisappear {\n'
                                                       '            if operation == .customers {\n'
                                                       '                customerKeywordDebounce.cancel()\n'
                                                       '                generation &+= 1\n'
                                                       '            }\n'
                                                       '        }\n'
                                                       '        .onDisappear { generation &+= 1 }\n'
                                                       '        .refreshable { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func loadCustomersNow() {\n'
                                                       '        customerKeywordDebounce.cancel()\n'
                                                       '        Task { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func '
                                                       'scheduleCustomerKeywordRead() {\n'
                                                       '        guard operation == .customers else { return '
                                                       '}\n'
                                                       '        let context = readContext; let expected = '
                                                       'identity\n'
                                                       '        let expectedFilter = filter; let '
                                                       'expectedKeyword = keyword\n'
                                                       '        // Invalidate an older response immediately, '
                                                       'including the 300ms wait.\n'
                                                       '        generation &+= 1\n'
                                                       '        snapshot = nil; snapshotContext = nil; '
                                                       'failure = nil; loading = false\n'
                                                       '        let keywordRevision = generation\n'
                                                       '        customerKeywordDebounce.schedule {\n'
                                                       '            guard operation == .customers, context '
                                                       '== readContext, expected == identity,\n'
                                                       '                  access.identity == expected, '
                                                       'keywordRevision == generation,\n'
                                                       '                  filter == expectedFilter, keyword '
                                                       '== expectedKeyword,\n'
                                                       '                  !Task.isCancelled else { return }\n'
                                                       '            await load()\n'
                                                       '        }\n'
                                                       '    }\n'
                                                       '    @MainActor private func load() async {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; let revision = generation; '
                                                       'let expected = identity; let context = readContext\n'
                                                       '        snapshot = nil; failure = nil; loading = '
                                                       'true\n'
                                                       '        snapshotContext = nil; customerTopic = nil; '
                                                       'feedClub = nil; feedMediaScope = UUID()\n'},
                                             {'before': '        }\n'
                                                        '        if revision == generation { loading = false '
                                                        '}\n'
                                                        '    }\n'
                                                        '    private func invalidateRead() {\n'
                                                        '        generation &+= 1; snapshot = nil; '
                                                        'snapshotContext = nil; failure = nil; editor = nil; '
                                                        'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                        '= UUID(); coordinator.cancelReview()\n'
                                                        '    }\n'
                                                        '    private func current(_ target: '
                                                        'ClubFeedClubRoute) -> Bool {\n',
                                              'after': '        }\n'
                                                       '        if revision == generation { loading = false '
                                                       '}\n'
                                                       '    }\n'
                                                       '    @MainActor private func invalidateRead() {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; snapshot = nil; '
                                                       'snapshotContext = nil; failure = nil; editor = nil; '
                                                       'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                       '= UUID(); coordinator.cancelReview()\n'
                                                       '    }\n'
                                                       '    private func current(_ target: '
                                                       'ClubFeedClubRoute) -> Bool {\n'}]}}
CLUB_PBX_PRE_ROW_SHA256 = 'ff594b1b5a61984d047d5b807ee2d3a4c596df75e3537a397abe82cf5054dd71'
CLUB_SUPPORT_PATHS = ('Tests/CoreTests/ClubCustomerPermissionTests.swift',
 'Tests/ContractChecks/test_club_customer_permissions.py',
 'docs/club-customer-permissions.md',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py',
 'tools/club_customer_directory_admission.py',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift',
 'docs/club-customer-keyword-debounce.md',
 'tools/tests/test_creator_shelf_state_history.py')
CLUB_RAW_SHA256 = {'Core/ClubCustomerHistoryTopicRoute.swift': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
 'Core/ClubGovernanceContracts.swift': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
 'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590',
 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba',
 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'App/ClubGovernanceViews.swift': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5',
 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e',
 'Questify.xcodeproj/project.pbxproj': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'tools/tests/test_creator_shelf_state_history.py': 'baa95d45430a19f2a7c472dcd269150197617f45d50735aa84b142ca2973d33c'}
FLOOR_INPUTS = ('Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift',
 'App/SocialGuideTemplateSection.swift',
 'App/ProjectEditNodeDescriptionField.swift',
 'tools/run138_current_source_projection.py',
 'App/ProjectEditIssueNavigation.swift',
 'App/ProjectThoughtDefinitionsEditor.swift',
 'App/ProjectEndingConditionPicker.swift',
 'App/MerchantBusinessEditor.swift',
 'App/MerchantOperationsEditor.swift',
 'App/ProjectNodeImageCrop.swift',
 'App/TemplateAuthoringMineView.swift',
 'Core/ProfileEditCoordinator.swift',
 'Core/TemplateAuthoringShelf.swift',
 'Resources/Localizable.xcstrings',
 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py',
 'Tests/ContractChecks/test_merchant_review_draft_return.py',
 'Tests/ContractChecks/test_profile_avatar.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_profile_reload_discard.py',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift',
 'Tests/CoreTests/ProfileEditTests.swift',
 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift',
 'docs/merchant-decor-tag-picker/implementation.md',
 'docs/profile-read-failure-recovery.md',
 'tools/check_profile_read_failure_contract.py',
 'tools/run_static_checks.py',
 'tools/tests/creator_shelf_refresh_history.py',
 'tools/tests/creator_shelf_state_history.py',
 'tools/tests/test_creator_pending_synthetic_storage_history.py',
 'tools/tests/test_creator_shelf_refresh_history.py',
 'tools/tests/test_creator_shelf_state_history.py',
 'tools/tests/test_gitleaks_configuration.py',
 'tools/tests/test_native_static_checks.py')
CURRENT_SCANNER_SHA256 = 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30'
CLUB_HISTORY_PATH = 'tools/tests/test_creator_shelf_state_history.py'
CLUB_HISTORY_INVERSE = {'before_sha256': '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924',
 'after_sha256': '2632c0f052be7dd29c5981c0c27c1a074b82203463cd177ae21bb69881c8cea7',
 'hunks': [{'before': '        from tools import run138_editor_readiness as planning\n'
                      '        projection.validate_feature_batch_sources(ROOT)\n'
                      '        contract=planning.contract(ROOT)\n'
                      "        self.assertEqual(len(contract['feature_batch_support_sha256']),502)\n"
                      '        original=Path.read_bytes\n'
                      '        # Read actual inputs once; mutations are isolated read substitutions,\n'
                      '        # never copies of the repository or historical acceptance expectations.\n',
            'after': '        from tools import run138_editor_readiness as planning\n'
                     '        projection.validate_feature_batch_sources(ROOT)\n'
                     '        contract=planning.contract(ROOT)\n'
                     '        from Tests.ContractChecks import test_profile_read_failure_remote_admission as '
                     'admission\n'
                     '        current_contract=contract\n'
                     '        '
                     'contract=admission._club_directory_contract(json.loads(json.dumps(contract)),ROOT)\n'
                     "        self.assertEqual(len(contract['feature_batch_support_sha256']),502)\n"
                     '        contract=current_contract\n'
                     '        original=Path.read_bytes\n'
                     '        # Read actual inputs once; mutations are isolated read substitutions,\n'
                     '        # never copies of the repository or historical acceptance expectations.\n'},
           {'before': 'class CreatorFixed45TestPreservation(unittest.TestCase):\n'
                      '    def test_original_reviewed_creator_history_test_restores_complete_bytes(self):\n'
                      "        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n"
                      '        data=_restore_premerchant_history_test(data)\n'
                      "        first=b'\\n# CREATOR_FIXED45_PORT_BEGIN\\n';last=b'# "
                      "CREATOR_FIXED45_PORT_END\\n'\n"
                      '        self.assertEqual(data.count(first),1);self.assertEqual(data.count(last),1)\n'
                      '        start=data.index(first);end=data.index(last,start)+len(last)\n',
            'after': 'class CreatorFixed45TestPreservation(unittest.TestCase):\n'
                     '    def test_original_reviewed_creator_history_test_restores_complete_bytes(self):\n'
                     "        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n"
                     '        data=_restore_premerchant_history_test(_restore_preclub_history_test(data))\n'
                     "        first=b'\\n# CREATOR_FIXED45_PORT_BEGIN\\n';last=b'# "
                     "CREATOR_FIXED45_PORT_END\\n'\n"
                     '        self.assertEqual(data.count(first),1);self.assertEqual(data.count(last),1)\n'
                     '        start=data.index(first);end=data.index(last,start)+len(last)\n'}]}
FROZEN16_HELPER_SHA256 = 'bf14068e7dd7c8193c88121064168935b88c608ef0def7730e9eb878bc264cea'
FROZEN16_CONTRACT_SHA256 = '2ad2b32bd6063a28f4d1acce78c600c2e0285565032b9ae6ab833bc01581b54a'
FROZEN16_TEST_INVERSE = {'before_sha256': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5',
 'after_sha256': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'hunks': [{'before': 'ROOT = Path(__file__).resolve().parents[2]\n'
                      'INPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n'
                      "    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n"
                      'COMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | '
                      'set(admission.EVOLUTION_SUPPORT)\n'
                      '\n'
                      '\n'
                      'def digest(raw):\n',
            'after': 'ROOT = Path(__file__).resolve().parents[2]\n'
                     'INPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n'
                     "    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n"
                     'COMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | '
                     'set(admission.EVOLUTION_SUPPORT) | set(admission.FLOOR_INPUTS)\n'
                     '\n'
                     '\n'
                     'def digest(raw):\n'},
           {'before': '\n'
                      '@contextmanager\n'
                      'def copied_admission_inputs():\n'
                      '    """Only the sixteen admission files, never a repository or historical '
                      'checkout."""\n'
                      "    with tempfile.TemporaryDirectory(prefix='club-directory-admission-') as "
                      'temporary:\n'
                      '        root = Path(temporary)\n'
                      '        for relative in sorted(COMBINED_INPUTS):\n',
            'after': '\n'
                     '@contextmanager\n'
                     'def copied_admission_inputs():\n'
                     '    """Only bounded club and preceding admission inputs, never a repository '
                     'checkout."""\n'
                     "    with tempfile.TemporaryDirectory(prefix='club-directory-admission-') as "
                     'temporary:\n'
                     '        root = Path(temporary)\n'
                     '        for relative in sorted(COMBINED_INPUTS):\n'},
           {'before': '    def '
                      'test_three_product_sources_restore_exact_published_baseline_and_reject_edits(self):\n'
                      '        self.assertEqual(len(admission.SOURCE_EDITS), 4)\n'
                      '        for relative, row in admission.SOURCE_EDITS.items():\n'
                      '            raw = (ROOT / relative).read_bytes()\n'
                      '            restored = admission.restore_product_source(relative, raw)\n'
                      "            self.assertEqual(digest(restored), row['before_sha256'])\n"
                      "            self.assertEqual(digest(raw), row['after_sha256'])\n",
            'after': '    def '
                     'test_three_product_sources_restore_exact_published_baseline_and_reject_edits(self):\n'
                     '        self.assertEqual(len(admission.SOURCE_EDITS), 4)\n'
                     '        for relative, row in admission.SOURCE_EDITS.items():\n'
                     '            raw = admission.permission_product_bytes(ROOT, relative)\n'
                     '            restored = admission.restore_product_source(relative, raw)\n'
                     "            self.assertEqual(digest(restored), row['before_sha256'])\n"
                     "            self.assertEqual(digest(raw), row['after_sha256'])\n"},
           {'before': '\n'
                      '    def '
                      'test_original_scanner_methods_assertions_and_historical_lines_are_preserved(self):\n'
                      "        path = 'tools/tests/test_gitleaks_configuration.py'\n"
                      '        raw = (ROOT / path).read_bytes()\n'
                      '        previous = admission.restore_product_source(path, raw)\n'
                      '        self.assertEqual(digest(previous), '
                      "'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n"
                      '        old_tree, new_tree = ast.parse(previous), ast.parse(raw)\n',
            'after': '\n'
                     '    def '
                     'test_original_scanner_methods_assertions_and_historical_lines_are_preserved(self):\n'
                     "        path = 'tools/tests/test_gitleaks_configuration.py'\n"
                     '        raw = admission.permission_product_bytes(ROOT, path)\n'
                     '        previous = admission.restore_product_source(path, raw)\n'
                     '        self.assertEqual(digest(previous), '
                     "'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n"
                     '        old_tree, new_tree = ast.parse(previous), ast.parse(raw)\n'},
           {'before': '                file.write_bytes(admission.restore_evolution_source(relative, '
                      'file.read_bytes()))\n'
                      '            for relative in admission.EVOLUTION_SUPPORT:\n'
                      '                (root / relative).unlink()\n'
                      '            self.assertEqual(admission.historical_scan_contract(root), baseline)\n'
                      '            (root / admission.CONTRACT_PATH).write_bytes((ROOT / '
                      'admission.CONTRACT_PATH).read_bytes())\n'
                      '            with self.assertRaises(ValueError):\n',
            'after': '                file.write_bytes(admission.restore_evolution_source(relative, '
                     'file.read_bytes()))\n'
                     '            for relative in admission.EVOLUTION_SUPPORT:\n'
                     '                (root / relative).unlink()\n'
                     '            (root / admission.CLUB_PREADMISSION_PATH).unlink()\n'
                     '            self.assertEqual(admission.historical_scan_contract(root), baseline)\n'
                     '            (root / admission.CONTRACT_PATH).write_bytes((ROOT / '
                     'admission.CONTRACT_PATH).read_bytes())\n'
                     '            with self.assertRaises(ValueError):\n'}]}
FROZEN16_SOURCE_ROWS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27',
                                              'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
                                              'hunks': [{'before': '        return '
                                                                   '(1...maximum).contains(id) ? id : nil\n'
                                                                   '    }\n'
                                                                   '}\n',
                                                         'after': '        return (1...maximum).contains(id) '
                                                                  '? id : nil\n'
                                                                  '    }\n'
                                                                  '}\n'
                                                                  '\n'
                                                                  '/// Mirrors CRM list/count/detail '
                                                                  'requireGovernable using current access/me '
                                                                  'evidence.\n'
                                                                  '/// Contact-list visibility and '
                                                                  'event-only grants cannot authorize this '
                                                                  'club-wide read.\n'
                                                                  'public extension '
                                                                  'ClubGovernancePermissions {\n'
                                                                  '    func allowsCustomerDirectory(scope: '
                                                                  'ClubGovernanceScope) -> Bool {\n'
                                                                  '        guard active, clubID == '
                                                                  'scope.clubID, (scope.clubID ?? 0) > 0 '
                                                                  'else { return false }\n'
                                                                  '        do { try scope.validate() } catch '
                                                                  '{ return false }\n'
                                                                  '        return '
                                                                  'roleCodes.contains("CLUB_OWNER") || '
                                                                  'roleCodes.contains("CLUB_LEGACY_ADMIN") '
                                                                  '||\n'
                                                                  '            '
                                                                  'permissions.contains("club:member:manage")\n'
                                                                  '    }\n'
                                                                  '}\n'}]},
 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264',
                                        'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
                                        'hunks': [{'before': '        if permission == "ROLES" { return '
                                                             'canManageRoles }\n',
                                                   'after': '        if permission == "ROLES" { return '
                                                            'canManageRoles }\n'
                                                            '        if permission == "CUSTOMER_DIRECTORY" { '
                                                            'return allowsCustomerDirectory(scope: scope) '
                                                            '}\n'},
                                                  {'before': '        case .customers, .customer, '
                                                             '.customerCount, .checkin, .topicCustomers, '
                                                             '.registrations: return "club:member:list:read"',
                                                   'after': '        case .customers, .customer, '
                                                            '.customerCount: return "CUSTOMER_DIRECTORY" // '
                                                            'Local preflight, never an API grant.\n'
                                                            '        case .checkin, .topicCustomers, '
                                                            '.registrations: return '
                                                            '"club:member:list:read"'}]},
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f',
                                                         'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
                                                         'hunks': [{'before': '                payload = '
                                                                              '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                              '? (chapterFlow ? '
                                                                              '"[\\"club:content:manage\\"]" '
                                                                              ': (banFlow ? '
                                                                              '"[\\"club:member:manage\\"]" '
                                                                              ': '
                                                                              '"[\\"club:member:list:read\\"]")) '
                                                                              ': '
                                                                              '"[]"),\\"canManageRoles\\":false}"\n',
                                                                    'after': '                payload = '
                                                                             '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                             '? (chapterFlow ? '
                                                                             '"[\\"club:content:manage\\"]" '
                                                                             ': (banFlow ? '
                                                                             '"[\\"club:member:manage\\"]" : '
                                                                             '"[\\"club:member:list:read\\",\\"club:member:manage\\"]")) '
                                                                             ': '
                                                                             '"[]"),\\"canManageRoles\\":false}"\n'}]},
 'tools/tests/test_gitleaks_configuration.py': {'before_sha256': 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c',
                                                'after_sha256': 'e6c0f1cb301fa8a762040ad4ed81c3ab8e5493ca1bfb99329bbbceb395b0c868',
                                                'hunks': [{'before': 'import unittest\n',
                                                           'after': 'import unittest\n'
                                                                    'from '
                                                                    'tools.club_customer_directory_admission '
                                                                    'import historical_scan_contract\n'},
                                                          {'before': '        raw = (ROOT / '
                                                                     'FILE_DIGEST_PATH).read_text()',
                                                           'after': '        raw = '
                                                                    'historical_scan_contract(ROOT)'}]},
 'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a',
                                   'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
                                   'hunks': [{'before': 'import SwiftUI\n'
                                                        '\n'
                                                        '/// Mount independently of legacy '
                                                        'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                        'struct ClubGovernanceEntryButton: View {\n',
                                              'after': 'import SwiftUI\n'
                                                       '\n'
                                                       '/// P044 keyword-only scheduling. The view still '
                                                       'owns authorization and response fences.\n'
                                                       '@MainActor final class ClubCustomerKeywordDebounce '
                                                       '{\n'
                                                       '    static let delayNanoseconds: UInt64 = '
                                                       '300_000_000\n'
                                                       '    private var pending: Task<Void, Never>?\n'
                                                       '    private var revision: UInt64 = 0\n'
                                                       '    private let sleep: @MainActor @Sendable () async '
                                                       'throws -> Void\n'
                                                       '    nonisolated init(sleep: @escaping @MainActor '
                                                       '@Sendable () async throws -> Void = {\n'
                                                       '        try await Task.sleep(nanoseconds: '
                                                       'ClubCustomerKeywordDebounce.delayNanoseconds)\n'
                                                       '    }) { self.sleep = sleep }\n'
                                                       '    func cancel() {\n'
                                                       '        revision &+= 1\n'
                                                       '        pending?.cancel()\n'
                                                       '        pending = nil\n'
                                                       '    }\n'
                                                       '    @discardableResult func schedule(_ action: '
                                                       '@escaping @MainActor () async -> Void) -> Task<Void, '
                                                       'Never> {\n'
                                                       '        cancel()\n'
                                                       '        let expected = revision\n'
                                                       '        let task = Task { @MainActor [weak self] in\n'
                                                       '            guard let self else { return }\n'
                                                       '            do { try await self.sleep() } catch { '
                                                       'return }\n'
                                                       '            guard !Task.isCancelled, self.revision '
                                                       '== expected else { return }\n'
                                                       '            // Release the handle before load() '
                                                       'cancels any still-pending timer.\n'
                                                       '            self.pending = nil\n'
                                                       '            await action()\n'
                                                       '        }\n'
                                                       '        pending = task\n'
                                                       '        return task\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// Mount independently of legacy '
                                                       'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                       'struct ClubGovernanceEntryButton: View {\n'},
                                             {'before': '    @State private var filter = "all"\n'
                                                        '    @State private var topicCustomerFilter: '
                                                        'ClubTopicCustomerFilter = .all\n'
                                                        '    @State private var keyword = ""\n'
                                                        '    @State private var sort = "composite"\n'
                                                        '    @State private var page = 1\n'
                                                        '    @State private var editor: '
                                                        'ClubGovernanceFormRoute?\n',
                                              'after': '    @State private var filter = "all"\n'
                                                       '    @State private var topicCustomerFilter: '
                                                       'ClubTopicCustomerFilter = .all\n'
                                                       '    @State private var keyword = ""\n'
                                                       '    @State private var customerKeywordDebounce = '
                                                       'ClubCustomerKeywordDebounce()\n'
                                                       '    @State private var sort = "composite"\n'
                                                       '    @State private var page = 1\n'
                                                       '    @State private var editor: '
                                                       'ClubGovernanceFormRoute?\n'},
                                             {'before': '                    Picker("club.gov.filter", '
                                                        'selection: $filter) {\n'
                                                        '                        ForEach(["all", "repeat", '
                                                        '"new", "remark"], id: \\.self) { '
                                                        'Text(LocalizedStringKey("club.gov.filter." + '
                                                        '$0)).tag($0) }\n'
                                                        '                    }\n'
                                                        '                    .onChange(of: filter) { _, _ in '
                                                        'Task { await load() } }\n'
                                                        '                    TextField("club.gov.keyword", '
                                                        'text: $keyword).submitLabel(.search).onSubmit { '
                                                        'Task { await load() } }\n'
                                                        '                    Button("club.gov.search") { '
                                                        'Task { await load() } }.disabled(loading)\n'
                                                        '                }\n'
                                                        '            }\n'
                                                        '            if operation == .topicCustomers {\n',
                                              'after': '                    Picker("club.gov.filter", '
                                                       'selection: $filter) {\n'
                                                       '                        ForEach(["all", "repeat", '
                                                       '"new", "remark"], id: \\.self) { '
                                                       'Text(LocalizedStringKey("club.gov.filter." + '
                                                       '$0)).tag($0) }\n'
                                                       '                    }\n'
                                                       '                    .onChange(of: filter) { _, _ in '
                                                       'loadCustomersNow() }\n'
                                                       '                    TextField("club.gov.keyword", '
                                                       'text: $keyword).submitLabel(.search)\n'
                                                       '                        .onChange(of: keyword) { _, '
                                                       '_ in scheduleCustomerKeywordRead() }\n'
                                                       '                        .onSubmit { '
                                                       'loadCustomersNow() }\n'
                                                       '                    Button("club.gov.search") { '
                                                       'loadCustomersNow() }.disabled(loading)\n'
                                                       '                }\n'
                                                       '            }\n'
                                                       '            if operation == .topicCustomers {\n'},
                                             {'before': '        .task(id: readContext) { snapshot = nil; '
                                                        'editor = nil; customerTopic = nil; feedClub = nil; '
                                                        'coordinator.cancelReview(); await load() }\n'
                                                        '        .onChange(of: readContext) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onChange(of: identity) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onDisappear { generation &+= 1 }\n'
                                                        '        .refreshable { await load() }\n'
                                                        '    }\n'
                                                        '    private func load() async {\n'
                                                        '        generation &+= 1; let revision = '
                                                        'generation; let expected = identity; let context = '
                                                        'readContext\n'
                                                        '        snapshot = nil; failure = nil; loading = '
                                                        'true\n'
                                                        '        snapshotContext = nil; customerTopic = nil; '
                                                        'feedClub = nil; feedMediaScope = UUID()\n',
                                              'after': '        .task(id: readContext) { snapshot = nil; '
                                                       'editor = nil; customerTopic = nil; feedClub = nil; '
                                                       'coordinator.cancelReview(); await load() }\n'
                                                       '        .onChange(of: readContext) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onChange(of: identity) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onDisappear {\n'
                                                       '            if operation == .customers {\n'
                                                       '                customerKeywordDebounce.cancel()\n'
                                                       '                generation &+= 1\n'
                                                       '            }\n'
                                                       '        }\n'
                                                       '        .onDisappear { generation &+= 1 }\n'
                                                       '        .refreshable { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func loadCustomersNow() {\n'
                                                       '        customerKeywordDebounce.cancel()\n'
                                                       '        Task { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func '
                                                       'scheduleCustomerKeywordRead() {\n'
                                                       '        guard operation == .customers else { return '
                                                       '}\n'
                                                       '        let context = readContext; let expected = '
                                                       'identity\n'
                                                       '        let expectedFilter = filter; let '
                                                       'expectedKeyword = keyword\n'
                                                       '        // Invalidate an older response immediately, '
                                                       'including the 300ms wait.\n'
                                                       '        generation &+= 1\n'
                                                       '        snapshot = nil; snapshotContext = nil; '
                                                       'failure = nil; loading = false\n'
                                                       '        let keywordRevision = generation\n'
                                                       '        customerKeywordDebounce.schedule {\n'
                                                       '            guard operation == .customers, context '
                                                       '== readContext, expected == identity,\n'
                                                       '                  access.identity == expected, '
                                                       'keywordRevision == generation,\n'
                                                       '                  filter == expectedFilter, keyword '
                                                       '== expectedKeyword,\n'
                                                       '                  !Task.isCancelled else { return }\n'
                                                       '            await load()\n'
                                                       '        }\n'
                                                       '    }\n'
                                                       '    @MainActor private func load() async {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; let revision = generation; '
                                                       'let expected = identity; let context = readContext\n'
                                                       '        snapshot = nil; failure = nil; loading = '
                                                       'true\n'
                                                       '        snapshotContext = nil; customerTopic = nil; '
                                                       'feedClub = nil; feedMediaScope = UUID()\n'},
                                             {'before': '        }\n'
                                                        '        if revision == generation { loading = false '
                                                        '}\n'
                                                        '    }\n'
                                                        '    private func invalidateRead() {\n'
                                                        '        generation &+= 1; snapshot = nil; '
                                                        'snapshotContext = nil; failure = nil; editor = nil; '
                                                        'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                        '= UUID(); coordinator.cancelReview()\n'
                                                        '    }\n'
                                                        '    private func current(_ target: '
                                                        'ClubFeedClubRoute) -> Bool {\n',
                                              'after': '        }\n'
                                                       '        if revision == generation { loading = false '
                                                       '}\n'
                                                       '    }\n'
                                                       '    @MainActor private func invalidateRead() {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; snapshot = nil; '
                                                       'snapshotContext = nil; failure = nil; editor = nil; '
                                                       'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                       '= UUID(); coordinator.cancelReview()\n'
                                                       '    }\n'
                                                       '    private func current(_ target: '
                                                       'ClubFeedClubRoute) -> Bool {\n'}]}}
FROZEN16_SUPPORT_ROWS = {'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590',
 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba',
 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5',
 'tools/club_customer_directory_admission.py': 'bf14068e7dd7c8193c88121064168935b88c608ef0def7730e9eb878bc264cea',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5',
 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e'}
FROZEN_SCANNER_BYTES = ('"""Offline configuration guards; the real full-history scanner runs in CI."""\n'
 'from pathlib import Path\n'
 'import re\n'
 'import json\n'
 'import hashlib\n'
 'import unittest\n'
 'from tools.club_customer_directory_admission import historical_scan_contract\n'
 '\n'
 '\n'
 'ROOT = Path(__file__).resolve().parents[2]\n'
 'MAIN_MERGE_COMMIT = "4e7349186d21448354d3bf4c6b4ab6adfc25fc1f"\n'
 'MAIN_MERGE_RECORDS = json.loads((ROOT / '
 '"tools/tests/fixtures/gitleaks-main-merge-audit-2026-10-05.json").read_text())["findings"]\n'
 'MAIN_MERGE_FINDINGS = {f"{r[\'commit\']}:{r[\'path\']}:{r[\'rule\']}:{r[\'line\']}" for r in '
 'MAIN_MERGE_RECORDS}\n'
 'IMPORT_COMMIT = "e39c367a35e1f15f9553701cbad56d0d10796c80"\n'
 'COVERAGE_PROSE_FINDING = '
 '"bcd754bd41dd41b3dad22a436211cd89ee47b657:docs/public-template/composition-read-grant.md:generic-api-key:75"\n'
 'CI132_PROSE_FINDING = '
 '"c95737b4c54881a7492ca72bd31f68749304d1d1:docs/square-post-local-media.md:generic-api-key:31"\n'
 'FILE_DIGEST_COMMIT = "65023b84211895bf6c3f6d8ec64804edbfc45e4d"\n'
 'FILE_DIGEST_PATH = "tools/run138_editor_readiness_contract.json"\n'
 'FILE_DIGEST_RECORDS = (\n'
 '    (174, "current_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (243, "previous_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (4028, "feature_batch_support_sha256", '
 '"Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4"),\n'
 ')\n'
 'FILE_DIGEST_FINDINGS = {\n'
 '    f"{FILE_DIGEST_COMMIT}:{FILE_DIGEST_PATH}:generic-api-key:{row[0]}"\n'
 '    for row in FILE_DIGEST_RECORDS\n'
 '}\n'
 '\n'
 'COUPON_FIXTURE_FINDINGS = {\n'
 '    f"abe535809517ceb327223679f85c14b5f5b8b6d7:App/CouponRuntimeFixture.swift:generic-api-key:{line}"\n'
 '    for line in (55, 81, 110)\n'
 '}\n'
 '\n'
 '\n'
 'class GitleaksConfigurationTests(unittest.TestCase):\n'
 '    def test_reviewed_ignores_are_commit_bound(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual(len(entries), 92)\n'
 '        self.assertEqual(len(set(entries)), 92)\n'
 '        self.assertEqual(entries.count(COVERAGE_PROSE_FINDING), 1)\n'
 '        self.assertEqual(entries.count(CI132_PROSE_FINDING), 1)\n'
 '        legacy = [entry for entry in entries if entry not in (COVERAGE_PROSE_FINDING, CI132_PROSE_FINDING) '
 'and entry not in COUPON_FIXTURE_FINDINGS and entry not in MAIN_MERGE_FINDINGS and entry not in '
 'FILE_DIGEST_FINDINGS]\n'
 '        self.assertEqual(len(legacy), 42)\n'
 '        for entry in legacy:\n'
 '            with self.subTest(entry=entry):\n'
 '                self.assertRegex(entry, rf"^{IMPORT_COMMIT}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '                commit, path, rule, line = entry.split(":")\n'
 '                self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '                self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '\n'
 '    def test_main_merge_exceptions_bind_exact_source_lines_and_do_not_cover_new_history(self):\n'
 '        entries = {line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")}\n'
 '        self.assertEqual(len(MAIN_MERGE_FINDINGS), 42)\n'
 '        self.assertTrue(MAIN_MERGE_FINDINGS.issubset(entries))\n'
 '        self.assertEqual({r["classification"] for r in MAIN_MERGE_RECORDS},\n'
 '                         {"external_source_sha256_provenance", "native_source_sha256", '
 '"forbidden_mutation_route_assertion_literal"})\n'
 '        for row in MAIN_MERGE_RECORDS:\n'
 '            with self.subTest(path=row["path"], line=row["line"]):\n'
 '                self.assertEqual(row["commit"], MAIN_MERGE_COMMIT)\n'
 '                self.assertEqual(row["rule"], "generic-api-key")\n'
 '                line = (ROOT / row["path"]).read_text().splitlines()[row["line"] - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), row["source_line_sha256"])\n'
 '                suffix = f"{row[\'path\']}:{row[\'rule\']}:{row[\'line\']}"\n'
 '                self.assertNotIn(suffix, entries)\n'
 '                self.assertNotIn("0" * 40 + ":" + suffix, entries)\n'
 '                unlisted_line = max(r["line"] for r in MAIN_MERGE_RECORDS if r["path"] == row["path"]) + '
 '1\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:{row[\'rule\']}:{unlisted_line}", '
 'entries)\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:other-rule:{row[\'line\']}", '
 'entries)\n'
 '        self.assertFalse(any(entry.startswith("6757dfac63086ac80bc849df587895bcaaa820df:") for entry in '
 'entries))\n'
 '\n'
 '    def test_file_digest_findings_recompute_from_exact_native_source_bytes(self):\n'
 '        raw = historical_scan_contract(ROOT)\n'
 '        contract = json.loads(raw)\n'
 '        for number, section, key, source, line_digest in FILE_DIGEST_RECORDS:\n'
 '            with self.subTest(line=number):\n'
 '                line = raw.splitlines()[number - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), line_digest)\n'
 '                expected = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()\n'
 '                self.assertEqual(contract[section][key], expected)\n'
 '                # Bind the actual finding line to the reviewed JSON field, not just a matching value '
 'elsewhere.\n'
 '                self.assertEqual(json.loads("{" + line.strip().rstrip(",") + "}"), {key: expected})\n'
 '\n'
 '    def test_file_digest_exceptions_cannot_ignore_new_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if FILE_DIGEST_PATH in entry}, FILE_DIGEST_FINDINGS)\n'
 '        self.assertEqual({entry for entry in entries if entry.startswith(FILE_DIGEST_COMMIT + ":")}, '
 'FILE_DIGEST_FINDINGS)\n'
 '        for finding in FILE_DIGEST_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            for other in (f"{path}:{rule}:{line}",\n'
 '                          f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                          f"{commit}:tools/other.json:{rule}:{line}",\n'
 '                          f"{commit}:{path}:other-rule:{line}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) - 1}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) + 1}"):\n'
 '                with self.subTest(other=other):\n'
 '                    self.assertNotIn(other, entries)\n'
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_new_prose_exception_is_exact_and_new_text_is_not_ignored(self):\n'
 '        commit, path, rule, line = COVERAGE_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "bcd754bd41dd41b3dad22a436211cd89ee47b657")\n'
 '        self.assertEqual(path, "docs/public-template/composition-read-grant.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "75"))\n'
 '        entries = (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '        self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '        self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        self.assertIn("viewers, absent grants", (ROOT / path).read_text())\n'
 '\n'
 '    def test_ci132_prose_exception_cannot_ignore_other_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        commit, path, rule, line = CI132_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "c95737b4c54881a7492ca72bd31f68749304d1d1")\n'
 '        self.assertEqual(path, "docs/square-post-local-media.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "31"))\n'
 '        self.assertEqual([entry for entry in entries if path in entry], [CI132_PROSE_FINDING])\n'
 '        for other in (f"{path}:{rule}:{line}",\n'
 '                      f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                      f"{commit}:docs/other.md:{rule}:{line}",\n'
 '                      f"{commit}:{path}:other-rule:{line}",\n'
 '                      f"{commit}:{path}:{rule}:30",\n'
 '                      f"{commit}:{path}:{rule}:32"):\n'
 '            with self.subTest(other=other):\n'
 '                self.assertNotIn(other, entries)\n'
 '        for entry in entries:\n'
 '            self.assertRegex(entry, r"^[0-9a-f]{40}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '        current_line = (ROOT / path).read_text().splitlines()[int(line) - 1]\n'
 '        self.assertIn("Backend ownership checks and moderation remain prerequisites.", current_line)\n'
 '        self.assertIn("Readback must remain authenticated.", current_line)\n'
 '        self.assertIn("Expired or revoked approvals and interrupted uploads require explicit recovery '
 'handling.", current_line)\n'
 '\n'
 '    def test_coupon_fixture_exceptions_are_exact_historical_findings_only(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if "CouponRuntimeFixture" in entry}, '
 'COUPON_FIXTURE_FINDINGS)\n'
 '        for finding in COUPON_FIXTURE_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            self.assertEqual(commit, "abe535809517ceb327223679f85c14b5f5b8b6d7")\n'
 '            self.assertEqual(path, "App/CouponRuntimeFixture.swift")\n'
 '            self.assertEqual(rule, "generic-api-key")\n'
 '            self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '            self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        fixture = (ROOT / "App/CouponRuntimeFixture.swift").read_text()\n'
 '        self.assertTrue(fixture.startswith("#if DEBUG"))\n'
 '        self.assertEqual(fixture.count(\'"test-7"\'), 3)\n'
 "        self.assertIn('https://coupon-runtime.example/native', fixture)\n"
 "        self.assertIn('makeTransport: { self }', fixture)\n"
 "        self.assertNotIn('URLSession', fixture)\n"
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_scan_stays_read_only_and_pinned(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        job = workflow.split("  secrets:\\n", 1)[1].split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("permissions:\\n  contents: read\\n", workflow)\n'
 '        self.assertIn("fetch-depth: 0", job)\n'
 '        self.assertIn("persist-credentials: false", job)\n'
 '        self.assertIn("gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e", job)\n'
 '        for key, value in [("GITLEAKS_VERSION", "8.24.3"),\n'
 '                           ("GITLEAKS_ENABLE_COMMENTS", "false"),\n'
 '                           ("GITLEAKS_ENABLE_UPLOAD_ARTIFACT", "false")]:\n'
 '            self.assertIn(f"{key}: \'{value}\'", job)\n'
 '        self.assertNotIn("continue-on-error", job)\n'
 '\n'
 '    def test_full_history_step_reuses_binary_and_fails_closed(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        step = workflow.split("      - name: Scan full checked-out branch history\\n", 1)[1]\n'
 '        step = step.split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("shell: bash", step)\n'
 '        self.assertIn("set -euo pipefail", step)\n'
 '        self.assertIn("command -v gitleaks >/dev/null", step)\n'
 '        self.assertIn("test \\"$(gitleaks version)\\" = \'8.24.3\'", step)\n'
 '        self.assertIn(\'gitleaks git --redact --exit-code=2 --log-opts="--full-history -m HEAD"\', step)\n'
 '        commands = "\\n".join(line for line in step.splitlines() if not line.lstrip().startswith("#"))\n'
 '        self.assertNotRegex(commands, r"--all|--first-parent|--no-merges|curl|wget|\\|\\|\\s*true")\n'
 '\n'
 '\n'
 'if __name__ == "__main__":\n'
 '    unittest.main()\n')

_FROZEN16_PERMISSION_READER = frozen_permission_contract
_FROZEN16_HISTORICAL_READER = historical_scan_contract
_FROZEN16_PRODUCT_READER = restore_product_source


def _encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def restore_creator_history_test(data):
    if digest(data) != CLUB_RAW_SHA256[CLUB_HISTORY_PATH]:
        raise ValueError('Unreviewed complete club creator-history input')
    first=b'\n# CLUB_HISTORY_INPUT_BEGIN\n';last=b'# CLUB_HISTORY_INPUT_END\n'
    if data.count(first)!=1 or data.count(last)!=1:
        raise ValueError('Missing or repeated club creator-history extension')
    start=data.index(first);end=data.index(last,start)+len(last)
    return _inverse_row(CLUB_HISTORY_PATH,data[:start]+data[end:],CLUB_HISTORY_INVERSE)


def _profile_module():
    import importlib.util
    path = Path(__file__).resolve().parents[1] / CLUB_PREADMISSION_PATH
    spec = importlib.util.spec_from_file_location('club_finite_profile_reader', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def current_predecessor_contract(contract, root):
    """Full club raw admission -> exact complete creator floor; never a scanner view."""
    root = Path(root)
    if digest((root / HELPER_PATH).read_bytes()) != '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297':
        raise ValueError('Current club reader changed')
    prefix = (root / HELPER_PATH).read_bytes().split(b'\n# Finite club layer on the exact creator/fixed45 floor. Frozen reader above retained.\n', 1)[0]
    if digest(prefix) != FROZEN16_HELPER_SHA256:
        raise ValueError('Frozen club reader was not retained exactly')
    permission_prefix = prefix.split(b'\n# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.\n', 1)[0]
    if digest(permission_prefix) != FROZEN_PERMISSION_HELPER_SHA256:
        raise ValueError('Frozen original club11 helper not retained exactly')
    restore_creator_history_test((root / CLUB_HISTORY_PATH).read_bytes())
    support = contract['feature_batch_support_sha256']
    if support.get(HELPER_PATH) != '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297':
        raise ValueError('Current club helper support changed')
    for name, expected in CLUB_RAW_SHA256.items():
        if digest((root / name).read_bytes()) != expected:
            raise ValueError('Changed or mixed club raw input: ' + name)
        if name in support and support[name] != expected:
            raise ValueError('Changed club support binding: ' + name)
    if digest((root / 'tools/tests/test_gitleaks_configuration.py').read_bytes()) != CURRENT_SCANNER_SHA256:
        raise ValueError('Current scanner changed')
    for name, expected in CLUB_SOURCE_ROWS.items():
        if contract['feature_batch_sources'].pop(name, None) != expected:
            raise ValueError('Unknown club source inverse: ' + name)
        _inverse_row(name, (root / name).read_bytes(), expected)
    pbx = 'Questify.xcodeproj/project.pbxproj'
    row = contract['feature_batch_sources'][pbx]
    extension = EVOLUTION_SOURCES[pbx]
    if row['after_sha256'] != extension['after_sha256'] or row['hunks'][-len(extension['hunks']):] != extension['hunks']:
        raise ValueError('Unknown club PBX extension')
    restore_evolution_source(pbx, (root / pbx).read_bytes())
    del row['hunks'][-len(extension['hunks']):]
    row['after_sha256'] = extension['before_sha256']
    if digest(_encoded(row)) != CLUB_PBX_PRE_ROW_SHA256:
        raise ValueError('Complete preceding PBX row not restored')
    for name in CLUB_SUPPORT_PATHS:
        if name not in support:
            raise ValueError('Missing club support row: ' + name)
        del support[name]
    support[CLUB_PREADMISSION_PATH] = CLUB_PREADMISSION_SHA256
    if digest(_encoded(contract)) != CLUB_PRECONTRACT_SHA256:
        raise ValueError('Complete creator predecessor not restored')
    return contract


def _current_baseline(root):
    from tools import run138_editor_readiness as current
    root = Path(root)
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    raw = (root / CONTRACT_PATH).read_bytes()
    current.contract(root)  # Current raw pin must succeed before historical projection.
    return _profile_module().historical_readiness_contract(raw, root)


def _validated_frozen16(root):
    baseline = _current_baseline(root)
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Full historical baseline changed')
    # Bind both changed club support files to their exact frozen predecessors.
    from Tests.ContractChecks.test_category_roam_registration import repair_predecessor_source
    current_test = repair_predecessor_source(FROZEN_TEST_PATH, (Path(root) / FROZEN_TEST_PATH).read_bytes())
    frozen_test = _inverse_row(FROZEN_TEST_PATH, current_test, FROZEN16_TEST_INVERSE)
    _inverse_row(FROZEN_TEST_PATH, frozen_test, TEST_EVOLUTION)
    restored = json.loads(baseline)
    restored['feature_batch_sources'].update(copy.deepcopy(FROZEN16_SOURCE_ROWS))
    pbx = restored['feature_batch_sources']['Questify.xcodeproj/project.pbxproj']
    extension = EVOLUTION_SOURCES['Questify.xcodeproj/project.pbxproj']
    if digest(_encoded(pbx)) != CLUB_PBX_PRE_ROW_SHA256:
        raise ValueError('Original baseline PBX row differs from creator floor')
    pbx['after_sha256'] = extension['after_sha256']
    pbx['hunks'].extend(copy.deepcopy(extension['hunks']))
    restored['feature_batch_support_sha256'].update(FROZEN16_SUPPORT_ROWS)
    raw = _encoded(restored)
    if digest(raw) != FROZEN16_CONTRACT_SHA256:
        raise ValueError('Complete frozen club16 contract not restored')
    return restored


def frozen_permission_contract(root):
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == FROZEN_PERMISSION_CONTRACT_SHA256:
        for name, row in SOURCE_EDITS.items():
            if digest((root / name).read_bytes()) != row['after_sha256']:
                raise ValueError('Hybrid frozen permission source: ' + name)
        frozen = _FROZEN16_PERMISSION_READER(root)
        if (root / CLUB_PREADMISSION_PATH).exists() or (root / CLUB_PREADMISSION_PATH).is_symlink():
            raise ValueError('Frozen domain contains current admission')
        return frozen
    contract = _validated_frozen16(root)
    app = 'App/ClubGovernanceViews.swift'; pbx = 'Questify.xcodeproj/project.pbxproj'
    for name in EVOLUTION_SOURCES:
        restore_evolution_source(name, (root / name).read_bytes())
    if contract['feature_batch_sources'].pop(app) != EVOLUTION_SOURCES[app]:
        raise ValueError('Frozen keyword inverse changed')
    row = contract['feature_batch_sources'][pbx]
    new_hunks = EVOLUTION_SOURCES[pbx]['hunks']
    if row['hunks'][-len(new_hunks):] != new_hunks:
        raise ValueError('Frozen PBX inverse changed')
    del row['hunks'][-len(new_hunks):]
    row['after_sha256'] = EVOLUTION_SOURCES[pbx]['before_sha256']
    for name in EVOLUTION_SUPPORT:
        del contract['feature_batch_support_sha256'][name]
    contract['feature_batch_support_sha256'][FROZEN_TEST_PATH] = TEST_EVOLUTION['before_sha256']
    contract['feature_batch_support_sha256'][HELPER_PATH] = FROZEN_PERMISSION_HELPER_SHA256
    raw = _encoded(contract)
    if digest(raw) != FROZEN_PERMISSION_CONTRACT_SHA256:
        raise ValueError('Complete frozen club11 contract not restored')
    return raw.decode()


def _original_scanner(raw):
    if digest(raw) != CURRENT_SCANNER_SHA256:
        raise ValueError('Unknown current scanner input')
    text = raw.decode()
    for before, after in reversed(_profile_module().SCANNER_READER_HUNKS):
        if text.count(after) != 1:
            raise ValueError('Missing or repeated original scanner inverse')
        text = text.replace(after, before, 1)
    original = text.encode()
    if digest(original) != SOURCE_EDITS['tools/tests/test_gitleaks_configuration.py']['before_sha256']:
        raise ValueError('Original complete scanner not restored')
    return original


def permission_product_bytes(root, relative):
    raw = (Path(root) / relative).read_bytes()
    if relative != 'tools/tests/test_gitleaks_configuration.py':
        return raw
    frozen_permission_contract(root)
    if digest(raw) != CURRENT_SCANNER_SHA256:
        raise ValueError('Unknown current scanner')
    frozen = FROZEN_SCANNER_BYTES.encode()
    # Both adapters restore the identical original scanner with every assertion.
    original = _original_scanner(raw)
    if original != _FROZEN16_PRODUCT_READER(relative, frozen):
        raise ValueError('Historical scanner adapter predecessors differ')
    return frozen


def restore_product_source(relative, raw):
    if relative == 'tools/tests/test_gitleaks_configuration.py' and digest(raw) == CURRENT_SCANNER_SHA256:
        return _original_scanner(raw)
    return _FROZEN16_PRODUCT_READER(relative, raw)


def historical_scan_contract(root):
    root = Path(root)
    if digest((root / CONTRACT_PATH).read_bytes()) == BASE_CONTRACT_SHA256:
        baseline = _FROZEN16_HISTORICAL_READER(root)
        if (root / CLUB_PREADMISSION_PATH).exists() or (root / CLUB_PREADMISSION_PATH).is_symlink():
            raise ValueError('Baseline domain contains current admission')
        return baseline
    frozen = json.loads(frozen_permission_contract(root))
    for name in SOURCE_EDITS:
        del frozen['feature_batch_sources'][name]
    for name in ADDED_SUPPORT:
        del frozen['feature_batch_support_sha256'][name]
    baseline = _encoded(frozen)
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete original club baseline not restored')
    return baseline.decode()


# Exact e2b retained-readiness and current-entry runtime. These old assertions
# describe their authenticated physical predecessor, never the new 742/164 UI.
import atexit as _club_atexit
import builtins as _club_builtins
from contextvars import ContextVar as _ClubContextVar
from functools import wraps as _club_wraps
import importlib.util as _club_import_util
import inspect as _club_inspect
import os as _club_os
import sys as _club_sys
import tempfile as _club_tempfile
from types import MappingProxyType as _ClubMappingProxy, ModuleType as _ClubModule, SimpleNamespace as _ClubNamespace

_CLUB_E2B_COMMIT = 'e2b21242757444ff8e9dc28477cd182ac9c27f8d'
_CLUB_E2B_TREE = '8e7ff1ad00fc375bd428a8735a7cfaa40197f821'
_CLUB_E2B_SHA256 = {'.github/workflows/native-ios.yml': '4ca695bdc86a7df5fa1a8ccb480288225a7ea0d1b64cabbf1891a1d753883fa2', 'App/AccessibilityFixtureOptions.swift': '49716b6d94f4534ec2b9065712dbd27663a292f5d472e957610fc049831b7aee', 'App/AccountComplianceViews.swift': '1a9b3a80aa3bd36a48025f3b130caa49ebacef9a81b0d12622593d6c82997df9', 'App/AccountView.swift': '906c2359586203dbc9d56958dbf6b3a9ed77f0ccc275f4d402da988655b371a0', 'App/ActivityAssociatedPlaysSection.swift': '6f3634b788bd115b6175ec4b3ee87736f08f1d0c68cbf793421752565ed983b3', 'App/ActivityDetailView.swift': '3553c0524eac4f2858801c6cefe2b65b932e8e50a075faba8a48e6f01ace9c35', 'App/AppCompositionRoot.swift': 'ed3ef356f8762a0690bcfdfad8fe5c053381df72ec0b60a108a7f9c7a7ffdde1', 'App/AppSession.swift': '56e188e6c1cf80050ea642a4ebe53a7fd03645d0dda9635ce189b7e9a4d033f0', 'App/ApprovedReleasePreparationView.swift': 'd12bf7cca63e0c44ab17a7dff9a20a1afbdaee5ee58f8dce8e9f80c7099fed3d', 'App/ClubAIDesignView.swift': '09cc292a4e2adfda4d8de322012ee0f96e0d90b5a67a056a8782d57c323fb751', 'App/ClubGovernanceViews.swift': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff', 'App/ClubOperationsViews.swift': '14608aee48b83797bbb5953ebaf1ef5caac30ba47de01e395d754d3c086292eb', 'App/CouponCodeView.swift': '8da25c9872f08b1fa47a9fb6356112595bc353b6a77386a243ab968d879f2292', 'App/DiscoveryReading.swift': 'baf78d181e36f5d7800fd0646e457a19b0a39ed8e5d2114626ef4f6d383191be', 'App/ExploreCompletionView.swift': '6e6307a9c39e8547adb941d7b303aac8ea1e4d27df57876297b93b4972a6c365', 'App/FreeExplorationViews.swift': 'f24359157c96791e6ff06d664dde591a49aa9958e51228980a05b1fee3ca7d67', 'App/GlobalSearchView.swift': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78', 'App/GrowthCenterView.swift': 'fd7cfec8b5b1fb08387c708e0b7cbf3ea9fcc83438a52fd8358988aab066c329', 'App/GrowthLeaderboardView.swift': '35ddcbf7f4b0691f2d595ff162006625ae389b9d3489ed00dae10f29316802e2', 'App/MerchantAftercareEvidenceFlow.swift': '55d5c3e7c8cb41b0a436786dd0c0eda441999c8b575e4c34a73dfa9c721ba7ce', 'App/MerchantBusinessEditor.swift': '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0', 'App/MerchantBusinessRecordViews.swift': '2f7d3460c1ffdc81f29ab1d4dd5c86ac941dafe204248f7c37940c46f4774bb5', 'App/MerchantBusinessViews.swift': 'ff06016dfbaf4c95c82fee87379905d8e6ea9261ab8e0fa74430a7f56eee91a7', 'App/MerchantCRMDateRangePicker.swift': 'f03036e3cfe9270dd2b9ae862d41660670c82ef9eb86d63533d3fd52d90b3f2c', 'App/MerchantCityQuotaSummary.swift': 'a99c730f4b866d7ad97148b7b394ca540936640adf49bb7e6ade83e9074a0af7', 'App/MerchantContentEditor.swift': '6cb6e94542efe2d4b25a163b5be5d504961c5c42694c4ce31722f502c865637b', 'App/MerchantContentViews.swift': '4aa343a5f78feb285c1539634aa65c921f47886fe9e565c34ec313e62496fc6f', 'App/MerchantCustomerContactSummary.swift': '1b2555f50dd092797f19f67a006b1151bb96d54b5a2fe266de0c4d4cfedca41d', 'App/MerchantCustomerEmptyRecoverySection.swift': '362047bb35a694e526117f9ce6569560cf3991a98b133d8a720a5ad3fc482c37', 'App/MerchantDecorTagEditor.swift': '5bd1051ea79f0dba4c45df949dfaa2e581685db749839fd1ea86f15fbcd08597', 'App/MerchantEngagementViews.swift': '7664daffbe1e9846bac66b8de675761fffd2cd0e93b2e792699ae04cae5c1128', 'App/MerchantFeaturedActivityPicker.swift': 'db1618666f1364c695ece321491d23f84ff9cdab071b10d107d2f64457c900eb', 'App/MerchantFeaturedClearControl.swift': '93ebae71c11bfce5d6c7d5384cb76f813ef13804ab941ac34d204b8d0e637fa1', 'App/MerchantHomeView.swift': '563f5316fb58ad94549236c06491447db87ad4cc0ea9b61d1b270a694dcbc4a2', 'App/MerchantInsightAttributionSummary.swift': '5160e20ba7dd96a3d290d0ca90685db21374a3b95b42f2c366fbe3894eccb842', 'App/MerchantInsightProfileSummary.swift': '437c4309eba8c50717c92985ff8e450803a05b2c8102490e3a8fff2df6b4fb06', 'App/MerchantInsightRecentVisitorsSection.swift': 'ee2fc3437c136621eba5ab1a1491bfd9918841da69b1275efd54da56e1dae9d3', 'App/MerchantInsightRecommendationRows.swift': '241e124d6585c3cbfe0ab8e0bdf2204593b2f07bb3e9ed04d1cef3a1bf743b16', 'App/MerchantMarketingView.swift': '351a593b4db72b991237193a80937f809f708b4b61e4ed6c2f545e478979cee4', 'App/MerchantNPCComposerRetention.swift': '734810037822e624588a8e98894e621f8321c36f97de52ad51e8140ce39e67b6', 'App/MerchantNPCConversationHistoryView.swift': 'fd02af774dc2dba652406b45e4c421c970bb06c8082e8631c79aca7029065485', 'App/MerchantNPCFixtureView.swift': '761bfa03dc3254eedca08fb6d01e71b9b22a9195c9859d68cb87bddc34e7c318', 'App/MerchantNPCGreetingPreview.swift': 'eae039d058a324882edd0bc62f3079071249de95e6f71aa9870bc07717be5751', 'App/MerchantNPCKnowledgeDismissal.swift': 'a4a4a7fd09a95f1f29064383e7dffec2c2d09935f3f8ac7cd63cedfc3cfd54d7', 'App/MerchantNPCKnowledgeDraftView.swift': 'f62a4bbbef2d4eab2c74752d666fb27a576ecb0b438e7c63ed58e5c1719a7b0f', 'App/MerchantNPCRecoveryPresentation.swift': '825881004dd9392b8eaad9767e6f42a53d57703f07936bb449e0a6a72db1ee93', 'App/MerchantNPCTranscriptScroll.swift': '84c70ddba97f7455f5de0b3bb5263651fc8d11b084f987d1286abb30344eb260', 'App/MerchantNPCViews.swift': 'a3ef38e33c2154a8c9951d0abbf3ca3cf234c69ac92330572efdf7a75d14ccd5', 'App/MerchantOnboardingHoursEditor.swift': '895961e8503144f7ad7f03efad98c85d9580b8b4bceb5d0d665060e569fdfcae', 'App/MerchantOnboardingView.swift': '7ca3caa1288c4a8bd3bf52cf103bb0208cd7964c724bf42462f52aee00779679', 'App/MerchantOperationsEditor.swift': '3656f645fdac72a57fc05caeafc71a61bdcb1728d7c5da0196ce7d0fa184fbbe', 'App/MerchantOperationsViews.swift': '62c9d5c038026c4dd8cc7a5c1389aff5caf4308bad0f2df33eeb23b084271833', 'App/MerchantOperatorInvitationReceiptView.swift': 'cab6567b0fd9969b1b38f3632d1e786cfcad84de419aab21c6ffb54004749829', 'App/MerchantProjectsView.swift': 'e3411a33a94faa115d05f86f6c5177f44f0e2c51d9173f4c46ad4a7f93296be0', 'App/MerchantReviewDraftReturn.swift': '98d664c871645851a7837b33931453fd3cabb0b3f698f53630601ca5f8089b56', 'App/MerchantReviewPhotoGallery.swift': 'd61f85d53fcf8696870dc9836330cedaaa15ecb4c3c2a56579d0bebe946220ed', 'App/MerchantStationLiveCodeView.swift': '992eeff1dbeab2726a3539f988216a67b1e8f23d57884e402403f6eb24873c19', 'App/MerchantStationServiceTimeFields.swift': 'cba6d695d61a9ad41b616672d6822bfdc9fdfdab9bc0fd4d42afd4a0a7e78f6e', 'App/MerchantStationSubmissionImportView.swift': '98ba8a66da73245dca92ef5fe86216f700a1b58ad87125be0302f653adff63ed', 'App/MerchantTemplateAssistSheet.swift': '2a2ce68ba108bc325955bb2a140150817725b23fbbe65a7e16f6f7134a5749a0', 'App/MerchantTemplateSuggestionEditSheet.swift': '5f61a0a2d39d2f80bbd1e1f439e2f890f558956b42ebe2eb01b3920cd9694623', 'App/MerchantTemplateSuggestionReviewPanel.swift': '7ffc9a0efdf5b4d7621d00a02ee09a3b6ed12696e40b99cd363e8d32d6426039', 'App/NPCChatDataView.swift': '61f8775a73d30fc8c231d3c2a5bc3c0621351da763da52f8c9bbe9f0656b9898', 'App/NPCQuickQuestionBar.swift': 'dd4372b5bd9dc60e994e38189698c601fbf4deb2391ebf647ad9bb7665391cb7', 'App/NativeEntryLandingView.swift': 'f28db9742c63fe0bb48a6b8000738af051a67c31668706d9421f18e37eb7baa2', 'App/ObjectBadgeViews.swift': '86614a91b92cb9d5c7ce560e01c7e195d69b64f3fe977186c102b72c1ad21c3f', 'App/OfficialEventsBrowserView.swift': '782cfba23a5f7e864efe2429e86cbe5def5b18d48480d61d5b5d30d995383906', 'App/OwnedOrderComposition.swift': '115c576d280fa5ae918cd8baa15cd6461bf3340b084255f70b14bfae20175825', 'App/OwnedOrderFixtureHost.swift': '97387b59008c7ec7bfc935b3379ebaf1ab9f61d5b28b61476fd926aeee9a40ec', 'App/OwnerDraftFixtureHost.swift': '3c1bd2ea7d2dd11b0b0b15a8e7fa475a7d2f28a5c792147e7714dc218c50c17a', 'App/PlayBranchHistoryFixtureSupport.swift': '60e6d26239482cf5f525b458f3b99108a46ed9d5dcc03a2e8f7d609c323b02c3', 'App/PlayBranchHistoryView.swift': '26e15f0ecb0281395d95cc987f8c5f3333a696fc0e0f7f1be5ce6954e5cfdb33', 'App/PlayExperienceView.swift': '8daceb0f5b2f47d31cfb4ab1f189a905d61c789abe34962aec193b3d86dae8cc', 'App/PlayTaskSummaryView.swift': '24577b93d3ed8c158a32f2dae0a020b7354676c4fd7fa7ed74ac52e18ae34c89', 'App/ProfileAvatarDraftSection.swift': '9a5332680d908c847e23d29a119cbf2662de22273cb90f422074ca9ed6a0613b', 'App/ProfileEditView.swift': '3aad961d139bb39d7a4a9fdda5eb44d4c7d67f547af5e14e61ba48962607d91d', 'App/ProfileOrdersView.swift': '06259529c65743396c6a888c3ec332a57f7012fb3696b843250c89075c84f080', 'App/ProjectAlbumImageAuthorField.swift': 'fbd96a41b489657b9cb2ebe8b7432c42ec651e664a873586a60eebd2dddbf140', 'App/ProjectAlbumPhotoRemovalButton.swift': '6e2e635c3c033b3dadc5e7561b97690760027e3097da004fe1d3d439b483a945', 'App/ProjectCategoryPicker.swift': 'fae1345af183c17a4da514fccc4c755e86c5c6a9b747ff7decb004178089818c', 'App/ProjectChapterAudioAuthorView.swift': '47656b69eb4330f00319f7dde5255f7348121f136673962e930f111920f7a1a2', 'App/ProjectChapterAudioField.swift': '28ce412947bb3ddd5fa6ed2adf6c4f5b391ebe68475f4bcf10f91ebd711b1e5d', 'App/ProjectChapterAudioPresentation.swift': 'a60bcef9cb3e483db5e6fb7d46be0c55800e90662975901f78ca8b627d7089c5', 'App/ProjectChapterRemovalPresentation.swift': '5e51412a3f0ce37b6f77186cb781ec285b85347accf10e9e6e6da878dd70acdd', 'App/ProjectCityStoryNodeRemovalController.swift': '8274b4bd07ac40f2ccb4c259a093a2fa73187a6170dd9f556c72126319442926', 'App/ProjectClubLeadFields.swift': 'd30db038f00f3253b9d52245d7794820c143ba6dcc859c16f70eb2286dd4ceb9', 'App/ProjectDraftNodeOverview.swift': 'a463536269bf494b621562903770ffb72fcff0d4b3a7ff5c2cb3d030f9664de1', 'App/ProjectDraftStoryPreviewView.swift': '7e24094f40784e937823f4cc250ea3a8b46e8f3edcdcafacaaa8d2ef628f68df', 'App/ProjectEditDatePicker.swift': '093f29da316764705f8017e2d647e82af09e7a5baeb6a4ff24179e45a1a6d970', 'App/ProjectEditDetailForms.swift': '136baf9d0aef8a3856e2840bdc9555aa675b8beee0b0e892b6573095f024f2f9', 'App/ProjectEditFixtureSupport.swift': 'ec91bb9851338ac6f69ec04f96728a557ffde2718f159c1e7942cf1dc54a7e6b', 'App/ProjectEditIssueNavigation.swift': '6d10281d7c74e6664404ed359902fd3673873bce0ddd519686dbb521cf29319d', 'App/ProjectEditNodeDescriptionField.swift': 'c03d2b762a9c339449f799214b356180ead19d9c6bc9065ff2c25e0cabc77053', 'App/ProjectEditPendingPresentation.swift': '191d28fa6c4a65bd1c15c20c88d657cd01e48fabbe8fb5d2cbaa8f965d9c4a5e', 'App/ProjectEditPreparedReview.swift': 'dd0487f8c74b1ed44b47064c7a08e5b98d43940c37dcef7fb6730170b4c4e410', 'App/ProjectEditRichStoryForms.swift': '5bbafc7e8ca29604dc62e6f13a064be3e1ffa3855026892a520b3185907eefe0', 'App/ProjectEditSecureStorage.swift': '9d4d4c864fb35ba0f85da84e3ee5d58078a240681d71f3455d0e3b2f431f2312', 'App/ProjectEditStarterPresentation.swift': '98ca1769b20ed757e44021b60edfde904a6f4a838eaee81f54cfe74d23b40726', 'App/ProjectEditView.swift': 'cd1e2c69457a187343cf5236bc5afef9a4587a2c9f1a2d7835859be9ea99a4fc', 'App/ProjectEditorAudioPreview.swift': 'f63f2f94b67c93a6ad5281cca28a2b46e31fd859df8d3bf02fc4199464ae20b6', 'App/ProjectEndingConditionPicker.swift': '16da43f7d88ae2aa153b622dfce15d91938d580a8ad0fdec61f51418d7827688', 'App/ProjectInitialAttributesEditor.swift': '9514d6ae8d54ce9627261aa2309a12cf460948fda2fe61da46bd0466cc940361', 'App/ProjectInitialStateEditor.swift': '3ecfb16af19c7c86e511ed99242f24ce0fd69a62abf10b0f04cbb5032d546569', 'App/ProjectNodeBusinessHoursField.swift': 'e00f7cdb16206ab6343f94f80256d78573004a6df35498505d428c45f5644277', 'App/ProjectNodeDurationField.swift': '9f7923e66183ad12f786a947592e7ac5f2a95dffb14ad18e930de930bc2ae5cd', 'App/ProjectNodeGameplayRemovalField.swift': '9d288a5e0909bc64a6fc0b527ef7a70c1be285475af44f72c2cf1670062e01a1', 'App/ProjectNodeImageAuthorView.swift': 'a7006d55e77a1a643797bcbf48617418ce9965cc86bf96dc83e19a638ad8e7de', 'App/ProjectNodeImageCompositionRoute.swift': '9c010ba99f45f37d0ad2b502123e1a871418cd09940682f4693dbf49b8b3045f', 'App/ProjectNodeImageCrop.swift': '47901a84bfc8ffa2f69dca618ab4de6eb7a151f7cc20fdebd4cb79425bcdb894', 'App/ProjectNodeImagePresentation.swift': '28013a0c087517efb256fbe159ea7b21128ba6b59ae7458c1cec8b998a11d2d5', 'App/ProjectNodePhotoRemovalField.swift': 'd4e30ac3692c577ba78c268d138921fa809bd86de82c883c27eff7b33734b01d', 'App/ProjectNodePlacePicker.swift': 'abd4946cc584aad843bf980623bf72e19323b4612c3ecba163603389a6f644dc', 'App/ProjectNodeRouteMappingEditor.swift': 'a653f9ae677af48213234ed45a04547bb946681d1926dbc8b78b16686f98d8c2', 'App/ProjectNodeTemplateCreationField.swift': '6aeceada5f7ecba8cf6e024c5bdfd8bf7f4a32353e8460ab4c32e188e5ef7d07', 'App/ProjectNodeTemplateSelectionField.swift': '28faf03bf66c81b3f91ca1082601273b498b1573ef1f02bbd5a9edcd8650a0c7', 'App/ProjectPendingNodePlacePicker.swift': '0ddb7384a476c01672dc5c3df23ab1dad95b49214551f6ad7a24c38f9337c75d', 'App/ProjectPendingNodeRemovalController.swift': 'b0d03998cb16faf613baaae2297eb9127d2282370b18b207f5a893fe3139f168', 'App/ProjectRemoteVersionRow.swift': '674f108bdb6a87184b584efe301fc94175edd211f6b2f5cd2fe8a633f0640cb7', 'App/ProjectRichStoryInsertionButton.swift': '35d807dfdbc5f975b2498ec236b613504f821e54f27547dd5fbc6008ad60b8bb', 'App/ProjectStoryAudioAuthorView.swift': '7ad49d5e049a79714e093cd34c98c8cf73b238ca062fe1da76ce0553dbca9e50', 'App/ProjectStoryImageAuthorView.swift': '89793a8b466fed8285ab64f1f6faa5b9294be54c2c5e62bbb0511eb93b93d8b0', 'App/ProjectStoryImagePresentation.swift': '8697e21ef23deec42721edc1f74dfb6901691d84dc61b13265e0f82713d6f5b5', 'App/ProjectStoryTemplatePresentation.swift': '4614443f481e2b9218dc6ecfa7eb81374dad454fe73c026110660fe001d22604', 'App/ProjectStoryTemplateView.swift': 'b6e5b4c8a57dc76a902de5f507acf065ff13ca18dc11c6772b5f0197ec8e445e', 'App/ProjectStoryTextField.swift': '611e24e47cbb7ca32c1fc22e7c5d7a427ebb7b91a629e4abf5cf84def59ca7ac', 'App/ProjectStoryTextInsertionButton.swift': '9844c587e8cee24c520ff0ae06d2f260fc2e1c38b04d184334912879eed3651a', 'App/ProjectStoryVariablePicker.swift': 'e299dceb71ee970628fd7cf94e1a2540d9c8183e1c6b74e4aae0633573e29062', 'App/ProjectSubmissionEvidenceViews.swift': '50553cf5fa45ddfaf30c5660bfb2fb5942ff6016798153303ece4115b88ab858', 'App/ProjectTeamConfigurationEditor.swift': 'e38953b6fbaad0081f2425b60049a9a37c255dbe7322b1675c3e221dc568f035', 'App/ProjectThoughtDefinitionsEditor.swift': 'e580e547bd55d7a0df2ef032fb39699aeb6187701cc604ab5d20be1129f91750', 'App/ProjectTopicMediaHost.swift': 'd7ff73d85afbcffe53216072a959e65fe751baddc2521eeb3163787eaeac79cc', 'App/ProjectTopicMediaInspector.swift': '7580239509c381b62deeac416696b9836cc0f749c7dc815ec4935429ae1ec9ba', 'App/ProjectTopicMediaPicker.swift': '4aaea382b7b74b7cbd5adfa1b09aa45e64acd095f029a197044450c772a9ab20', 'App/ProjectTopicMediaPresentation.swift': '43b4d175b0b4bc53d154efa6b2dbd84de4ea7c122ffb3f4a6ca8ce55a9a74488', 'App/PublicMerchantHomeView.swift': '8d48f81f849c581acfa39f1403a2622c3c99a3bb64a4f5b23e2ccfe7add49391', 'App/PublishingAIDraftSheet.swift': '7268ca91dd4600a956b32d10a820738110113aef6be493935038b7d85d02e076', 'App/PublishingAIQuotaSection.swift': '1415dd3127a03ecf549e373026adb5bd7ebf68e7c7f70389af3de96f55ac7d02', 'App/PublishingContextHandoffViews.swift': '87cf34be895fdda347d4b61aed35e7a6f25dc85e41cf3a4ecd5d2372c0edc7b4', 'App/QuestifyApp.swift': '12cb038406bd94963807345d0a4c557efeb011a4e6ffee8dc4b2fd9a2a344511', 'App/QuestifyDensityMap.swift': '0b69183ac6171af1a8764bafe643af5ef915a752d7f439eaf8b2c66b77e052cd', 'App/QuestifyImageEntityCard.swift': 'e96d35e272fabc2ad6af9c59d255d226ba06e3a464991d07e011f55506c97d74', 'App/QuestifyProgressiveBlurArtwork.swift': '4faf6578f90f0311de74283100d76a7edbe0419d2dbacbba49a548e520e3529c', 'App/ReferenceMapCardFixtureView.swift': '8d1de345b015df9f0b5c0fc2733ca395bbc6988c5379ab40754a728624c74c97', 'App/RetainedNativeImagePicker.swift': 'fff1d70ec5316b625714a34c4fa710f84442657e743eacc9167821dd375b61d1', 'App/RoamBrowserView.swift': 'f7e93b3ef55ac7d91de52e566951cb65366e1deecfb3f15fce0c222352c0f0ee', 'App/RoamExperienceComponents.swift': '02188caf2ccd48dae34f6775828d2e722ce4f8239f9925af8d972d9148e772fb', 'App/RoamExperienceHubView.swift': '3a5bef7227dc189e13771fefd3d6b591da64ef20d5ab1a5c5610e77535c15419', 'App/RoamHistoryViews.swift': '2a4d67bbb003df0646599c911ae8c2ac6e20b99e2af7ae81f89be384af608172', 'App/RoamItemDetailView.swift': '14d073fb21dcdf75f0bfdf27dcd0b6467fc148c84a055e9debb2ad62d167e4bc', 'App/SearchMapCanvas.swift': '9024071ed961468179fc033686736249beadbec4bbb275fdfb100ae57f1a4101', 'App/SearchMapExplorerView.swift': '8ff7a9df03d1c1cf821ad279b1ba3897af79548127857784942472fafa5c4558', 'App/SearchMapFilterSheet.swift': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54', 'App/SearchMapLayerSelection.swift': 'a6d2019d89a08af51699adcba7f9ff05438418c54d4678950e76614e0c5a0ec2', 'App/ShopNPCFixtureView.swift': 'e692acac3e81778303ed26be038d1bcea26ef564dfd7def9c4f6c0bd7c7c98b7', 'App/ShopNPCQuestionReuseButton.swift': '885b5f145bc123aaa1625765adc9d55e94964283621b3c376b49c3497e97a1bd', 'App/ShopNPCScriptedGuideView.swift': '165ec1150cfdef62a45b5f84201ceb02614a2d118409221d75f9e34c2799f18b', 'App/ShopNPCSessionHost.swift': 'c836b68cecdb7fa73898af62a88d1a7df27e46dddb7436891c96f43ec7e3beea', 'App/ShopNPCView.swift': '346401853fe0071f1bbee3f59a2e59471519503ade5a1920aee9685881b1c787', 'App/SocialGuideTemplateSection.swift': '0e14cc76c72416cf152f8edbd02383251b2671952f958a18af078e883f4ffc51', 'App/SocialGuideViews.swift': 'bd8c52bfabcf0f8d3d333449e46ce7e4c62d9348f638de2bcf748cd3e6ca36eb', 'App/SquareWorkspaceView.swift': '6421234ae743f06f655319d3a87f1a22384167263e83630ad2e2244a29fe03f9', 'App/TemplateAuthoringFixtureSupport.swift': '7360559489a6fc67139fe5afbffd474f89b579c2f87bc444a6bf0ab41b29af92', 'App/TemplateAuthoringMineView.swift': '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f', 'App/TemplateAuthoringView.swift': '111d31fbc102559098f61584736f22101a8893c09fa30e937519ce8e0c252d7f', 'App/TicketWalletDetailView.swift': '14ec2d52d271813a1ad64f8045918eb344fcd6f3b2ee6cb85ab32bc066766367', 'App/TicketWalletModel.swift': '77e233002e0de8562c4b3eb7aa3d41ee1bf6cfc10b0db298adb293279f6f1b76', 'App/TicketWalletTeamView.swift': '3213fc9e3661a87dd0803fa2dd40d8db16161c699e85fd5664cbb3db62a5a1f6', 'App/TicketWalletView.swift': '7780cc39c5fd347fdf89aa6a5e293abae2f3930e8395969d9b20cce64c8189a7', 'App/TopicBrowserView.swift': '380f40b180b0b3497f1622078b8fbf6b1a2e37f20e61785c7f9d354f81c3625f', 'App/WorkshopCreatorPendingFixtureSupport.swift': '4084ba4106fb94630ba3091ef7eb754e29864a21a85c38123b82ec58e4f7ebee', 'Config/AppUnitTests.xcconfig': 'ed3f7a0b80831d9b64803acea4d6e21a9c8c6429cca3de778a36dd7b154d982c', 'Config/Base.xcconfig': '5b93366b396a073537bba112571e8b6b05d3dc77ce854efb15beae7132fb56c2', 'Config/UnitedStates.xcconfig': 'b4a1a13f1d46927eeee464a8f8f07610c5d34ff27b2c01a5922b0f04c1d1b82e', 'Core/AccountComplianceCoordinator.swift': 'cf04c5d9d10dd4de5264d6bd8cc9584ab3821a612b3ede15d58c35cbf14824a8', 'Core/AccountComplianceService.swift': '128da5f30d731d8f1a38a289b2083f95420a1a4c5c7697a786d62082e1f865c2', 'Core/ActivityDetail.swift': '0861765d8508d6d4f0afc811b4215cff7254f864d76eda9512e3ffb75eb3c78b', 'Core/ActivityRequiredClubSelection.swift': '07ed19fc3890e9092a25f78664d2cd764729348939985d3c9b06159c37af261a', 'Core/ApprovedTopicReleasePublicationClient.swift': 'bfe80f68c377fa91b11fd19f1e74f91ce614ad1e0ffcd45983ecb8a2c97cae4f', 'Core/ClubAIDesignFlow.swift': '07fead332f66087557164c63ec42d0a9d184279de25316f922a060e3d5a8a4e1', 'Core/ClubCustomerHistoryTopicRoute.swift': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2', 'Core/ClubGovernanceContracts.swift': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32', 'Core/ExploreCompletionContracts.swift': '1487d14692ec13e4d56e889b06c8273657ae0f7755cdd240dbe212dc8a5f23d4', 'Core/ExploreCompletionRead.swift': 'e3115376b0f38e9969e5458d3279c7e2e54f8055f345de47de217f0252d5f7ba', 'Core/GlobalSearchRetainedResults.swift': 'abf28e1119cc8933f1ddb1ef67a38967f7a2e4725a881ec20c2ef4099db89445', 'Core/MapMarkerDensity.swift': 'a093668c2e0e3094adca93a535d029ea332ce8b8c0e4b1b4279d2a8ad519ac3f', 'Core/MerchantBusinessCoordinator.swift': 'b3977dd4e64edeaa9ecf8b168cf0a6de8ad53bb1a9f8d71ae1099f03dfda9899', 'Core/MerchantBusinessMutation.swift': '4695496ea387604f10c7749f270780472f8a9a39fc20fd712def1b12a7a37b0b', 'Core/MerchantCRMDateRange.swift': 'a06d517bf963c5da2edd1df9158f372a1af947cb72c0c11201d273f49a524a84', 'Core/MerchantCityClaimWithdrawal.swift': 'bdf6addef26bd0ace22a968867b84431dd859e908b15befd01c260f818366f38', 'Core/MerchantCityQuota.swift': 'd8f00d567993639bb33ad99c711c93793162e81bf536ab0a5a78ae9cbd184eb9', 'Core/MerchantContentCommands.swift': 'bd0b132835c2e2fdc19ed7dcacc87de08d435cff8e828599b40a11eb261940c5', 'Core/MerchantContentService.swift': '79e1c23ef89749048b723976ebf09b3ad5b655cd523cdc1529571a0700218d7f', 'Core/MerchantCustomerContactPresentation.swift': '45cba35c85f3fca9119d29592549511d17a5baecb98e21e4614074c9f127c294', 'Core/MerchantCustomerEmptyRecovery.swift': '6b048a173da7561f0b23a83e3585fa655831002610e969bffdb2e5307b1545da', 'Core/MerchantDecorTagDraft.swift': 'e6cfad52a32beb7cfa34e6fa5ff687438fb90f48bf05200578afc1737b4f8c40', 'Core/MerchantFeaturedActivityOptions.swift': 'a2dde9610cc8047582a22cacffac4a213f51c3448d3a8d35a7367ed09354e4ce', 'Core/MerchantInsightAttribution.swift': 'c0aa6514182af7e728059eb324a0acda8aa91c471a476cf3d27126252aa17552', 'Core/MerchantInsightRecentVisitors.swift': '4dcd9840fd853179d243dd1fe652ea8be4d750b4748bc0cf00f7d9473f0edc96', 'Core/MerchantInsightRecommendation.swift': '4beaa4ef266ebc8eb2bad07dfbb8727fc21a01255bc9fc377bca83d8dd146af6', 'Core/MerchantMarketingModels.swift': '6fedb63e7f32cdfcd88e2f6167102063ebac2d4e4a34b87dd651d41d4f0d9012', 'Core/MerchantNPCContracts.swift': 'ea64472a75d60b70a42b09fd86dcf4678936896c41d7596b59adc2234de8472e', 'Core/MerchantNPCConversationHistory.swift': '7ce329914208e963375f296e1ee1aa13826078a324ed4c53f9c8e2afcdbeacb8', 'Core/MerchantNPCCoordinators.swift': '758228a3feef82ad4a6000ba1811687f0665b583c469e5ce3fc1810d2ac6f252', 'Core/MerchantNPCHTTP.swift': 'a35e1e6898a4fb459f9a95035212b90c7380e3dd5e4a9ceb3006e81cbd0b9332', 'Core/MerchantNPCKnowledgeDraft.swift': '5911f24f48497544691319e7d321be22f11b4f9946315d2a27906635222ff61b', 'Core/MerchantNPCKnowledgeDraftCoordinator.swift': 'b73e0561b301161990ae20fefea05b3b30e62e2b7c36a67ec9784005a1c7fbd3', 'Core/MerchantNPCKnowledgeValidation.swift': '39913c4b062d59ed43a44d3bbd49328435353d6feb63a58777d802f60335da31', 'Core/MerchantOnboardingContracts.swift': 'f748f509e012a68bf4be8a75031a5a88839f1b539f9f13b68d9e621003555388', 'Core/MerchantOperationsContracts.swift': 'ae53eada2d41bb3868032618afda8b97bea2844d1e1f6aaf941026aeac603052', 'Core/MerchantOperationsReading.swift': '1443259beec87da46817343187529c52a988bdde1eec2d2642c8bedc2f167e75', 'Core/MerchantOperationsService.swift': '055d24c0a2ad78f1929b4b2a710c18b27678d0571933f5f5bfe594579c90667b', 'Core/MerchantOperatorInvitationPresentation.swift': '91de455344f7d34dda4880b507847a5dd1730d8f8224ea377bc2b7dee772bc1a', 'Core/MerchantRedemptionFilter.swift': 'd0a349ba6e3833d1ed72d914dd9a8605568940e9135153f63192637c0cfe0294', 'Core/MerchantStationContracts.swift': '54d04df6f2f28571617f084c3c6cd7fcf1b6601b0c0fa587af88314dcad48c61', 'Core/MerchantStationPauseChoice.swift': '73376881499ce75b73152c49e542b32e3134a1dcdef02dc96adebd6c928788d9', 'Core/MerchantStationServiceWindow.swift': '62e93707db9f0bbad6e1f28477e012524b299930edfc6e03493c1a1c1d57066b', 'Core/MerchantStationSubmissionCode.swift': '292f1305ccf40eb7a7fcf603adc829641660e5a12b183ef72e635151c7e3c95c', 'Core/MerchantTemplateAssistFlow.swift': 'f223b7630011eb35d98b21779f1a8339f8fa36aa769146bfe63b49d5d45cfe54', 'Core/MerchantTemplateSuggestionEdit.swift': '24c9b2dd4ef76e78c44ac5dd5c32b41cf4d800599e74b1f7f254724341fa7e26', 'Core/MerchantTemplateSuggestionReview.swift': '2978a928d62c481f931645021b2548e01f453ecaaa32328babefe367982b6cbf', 'Core/NPCChatData.swift': '8575dcffddc5d95b708c0c808e914e314e146bb2ab7a7df1fa83e23eda5f43bd', 'Core/NPCChatDataCoordinator.swift': 'b6c1faab670a95347e2e2c58dfdb2b2ce99448395664b8310b98041e79dcbf3e', 'Core/NPCQuickQuestion.swift': 'db9447cd7566f14183579086a1080a3e2ec224f61b848d2760f0ea30181f9b1e', 'Core/OfficialEventContracts.swift': 'c83e9a941d39d6db3529dc95ea1eb4347547132ff8ea8e78e9011e87b62ef273', 'Core/PlayBranchHistoryPresentation.swift': 'f2c8ec28dfd8cfc8a4a1d3701d930815d742d0e902f4032e789a70ef232cd585', 'Core/PlayBranchHistorySyntheticFixtures.swift': '08453dd81301193ed0f48a9b755cbdd6b56bc9ae898c652bd601bf3e99e06a23', 'Core/PlayExperienceCoordinator.swift': 'e7f72f3a9f214c3d3ab3a56aa9fdedca8728966550b2190d2afbe045f197b658', 'Core/PlayExperienceService.swift': '764c1b1dcf9292382b2cefdc7ce95e21625ad1dd218bad31978a2b2a8f83568a', 'Core/ProfileAvatarFlow.swift': '6558a0f7606edd6319fc4088d90483215058e177d0310606c5247761c9f7de19', 'Core/ProfileAvatarJournal.swift': '0e5f828ded3b4c2ace321afd7fb7f3d6b27bd087fdc046f0026b730747465638', 'Core/ProfileAvatarUpload.swift': '77c15238360c99d568019f7065188b85b6d0aac17c13c0f96228a400460ee9b9', 'Core/ProfileContracts.swift': 'd22d0536ab3e1248bc4bfe652aa49895c42be69ec46f9d3d04544e0f1f745920', 'Core/ProfileEditContracts.swift': '146acb5466940df9b0711eecca880307973b5deb3f4244bcd05f8a91f677de3d', 'Core/ProfileEditCoordinator.swift': 'bbd462eed41321ab249fda4e2f80e48aad51942cc6ce195bbd45b7e52b1e1b67', 'Core/ProfileEditService.swift': 'f890e57a35af52f2a9698abc9a0d95238e5819ab1bf6258085fb0a3fab4ab2a2', 'Core/ProgressiveBlurParameters.swift': 'b5a1de80a262eb583a90e20806c9647280e1c989c5354e0519ce594756a7e0dd', 'Core/ProjectAlbumPhotoOrder.swift': '0452569cd7e948cac2324e3945efbf808f36544ce366dd3ce723b30f8b63e3d2', 'Core/ProjectAlbumPhotoRemoval.swift': '768067919736d0d32384a0db455c46d0907c3f8ba06fc3d2cf887f156796ff72', 'Core/ProjectChapterAudio.swift': '53d79227bc210c1c31a34282f1aaa9d73cb53687e23d7b94f22531efde593a22', 'Core/ProjectChapterRecruitmentCarryOver.swift': '75ef2554e55ff7aaaa8ecacc739e98159e47ea82e4cd699a188237d7440357e0', 'Core/ProjectChapterRemoval.swift': 'c99b2902a9d481655059ec80a3e9eb390fc06298d8a6ccb70dcecda881100120', 'Core/ProjectCityStoryNodeRemoval.swift': '41df4d41560a74f2e9a85e60542e89a6343f5555158f432e4ecdc0bfaebb8050', 'Core/ProjectClubLead.swift': '8fe39f9acea7191c7e43c3fb17bd80e495d3677faaa700c6407844167bcb2be1', 'Core/ProjectDraftNodeProjection.swift': '29d6a754e0eede386b855a9762a8068070992b16486b993957860a55bc6a8695', 'Core/ProjectDraftStoryPreview.swift': '07b72b407f46ef2fe18be3474e4ace5305279bb350f0da69525e24a0784356c3', 'Core/ProjectEditContract.swift': '2b57d855b7cf3e8a38676a0fb235226ef3fc61b68bc41f09c5dec46cf26bfe28', 'Core/ProjectEditCoordinator.swift': '82919d94f1d7c2d9a75acd543f8ac218b999860dd2e84b0fd0b22e980ac30ca5', 'Core/ProjectEditDateSelection.swift': '7b0ba9dc4397db51128b9f27aa65a7e216b72b134119ad17a107b35ab5bd51b9', 'Core/ProjectEditDraft.swift': '2555f642f134756bf0c4154bb8030e37b8304d4ce7fab0265f0490a3ff0b9607', 'Core/ProjectEditHTTPService.swift': '1711678604660a766c18822e122118f8a40724b036e1d995c0eb7c22e25e6f12', 'Core/ProjectEditIssueLocation.swift': 'df1ac3295019359fbabb61f77e4f8f65837f1e5b0a69d1ab2920a54320a5178b', 'Core/ProjectEditLocalStore.swift': '369d7b50b015cfc81754fc932c4ac7bbd665cbb68b33386ed2ef096f2da2365c', 'Core/ProjectEditService.swift': 'c41f97402402c417b0ebb777168839d21ade9ee9869f2ab6f5ea968c81e0f410', 'Core/ProjectEditStoryContract.swift': '7082ffdfd1e1b9becffb0e07e676cab093de5e7294c3c1cbd4aca7b79847bb23', 'Core/ProjectEditSyntheticFixtures.swift': 'ddca0fb40fe0c11cff5fcf4de6046b03d8ca360e83f4edf53b752a72d2dc1a42', 'Core/ProjectEmptyStoryTextRemoval.swift': '802bf501a18454f53c331fec20c2c5924e3ee30f3bbebdb0bfc4327e886844e7', 'Core/ProjectEndingConditionChoices.swift': 'd7a50a2c7f541d9d938004d48f35ee2973aaee56ad82ec3beaa4c4f144ce8599', 'Core/ProjectInitialAttributes.swift': 'ed1fb845fb337ee51ad1893d0c293f3cb1afb5b2bc2c96fc3f313742fb2f9f95', 'Core/ProjectInitialState.swift': 'cc41b1ca76a1bda7036cb3c22543d40d00585313c81ca5fc09d3cc51f9fc5a6b', 'Core/ProjectNodeBusinessHours.swift': '0e3ab2ccc7edb06966f047a89fb35c263bf5b0be34ab6c61417199963c4a1533', 'Core/ProjectNodeDuration.swift': 'dae88278e7a0b599a7990cee3a77e00a6e24a6c3014ca46ca3550cf6ff8efafc', 'Core/ProjectNodeGameplayRemoval.swift': '0fd71e5fe0cb9f89e9da36050babe1feabe570ed78871fd8c5b87c7fb954b5fa', 'Core/ProjectNodeImageFlow.swift': '90c0c7fd65a1f745b184e4cde241d9ae873f5a0b7f76fe5382bcb22ad4964d57', 'Core/ProjectNodeImageJournal.swift': 'c482001d625f9c705aaf014d07914e2addb12841ecd69de357fe5c129511dc09', 'Core/ProjectNodeImageTarget.swift': 'a6a02de6cd6367e810f2a27bbfc9a9bf699821e733df0e6d1ecbc25eee206aaf', 'Core/ProjectNodeImageUpload.swift': '3d57a57361e3ecbe43e77cec82309962033fd0869b324d70de31f21dfc47bfa9', 'Core/ProjectNodePhotoRemoval.swift': '7cac2d7ebaae16f6a2cda5a89425b6c6b1751a847e67050be790e893a28e455f', 'Core/ProjectNodePlaceSelection.swift': 'c94718ea4116b1cd1f1ffadf31b29d134e879afadf1daa6abf36cea5fd5afb65', 'Core/ProjectNodeRouteMapping.swift': '6c766ecffd55bc68a351272fbc9a168c24a8ed90e1a4b88085e1ebe016d776bd', 'Core/ProjectNodeTemplateSelection.swift': '7df889f96feecb67c1b001ccb43f8f7e116abfd9017368214e799ae68fc50b10', 'Core/ProjectPendingNodeRemoval.swift': '452b1f2a466b3fec735d363cdf1b664a9a9d74d4d0c9a5037a4bd5916453ea6f', 'Core/ProjectRichStoryInsertion.swift': '85571fc10a5f0dcc76d18547e4d1ba9a9d20bec46eec1e4ff0f4247653989ae7', 'Core/ProjectStoryAudioFlow.swift': '5d9dfc7a39db7c6a5f7b7499ffd5868265b363c2c6821fd04f158a5799d41603', 'Core/ProjectStoryAudioJournal.swift': 'e544cd3f6b171241940a14787a5d90b9ab354a2ac6e9f828eca48621f6af2111', 'Core/ProjectStoryAudioTarget.swift': 'e10502778086d089519d4f13f7c87712fb136801b549eb48b60232d8b70ee2a2', 'Core/ProjectStoryConditionChoice.swift': '3289a0820da77b71432ef721f5bff9b3e43a69d484bb734c922503f25319be12', 'Core/ProjectStoryImageTarget.swift': '4ff2173e3de21ab66acca46e82d3d11b1196f08dfde9e6f4a4a4057541103523', 'Core/ProjectStoryTextInsertion.swift': '3bfa34a812e8911c9dc61e3762e6333dc70bd2ebff8b6a3320797ed20c65954b', 'Core/ProjectStoryVariableInsertion.swift': '96a1afb5b6a14856cfbaed3b6a95d6bf5821a4646158ea68f0cf7d04b8be697c', 'Core/ProjectTeamConfiguration.swift': 'c6ec04eaf1080fa16499994e3e2aceb5914c71aac06275050aed4d42575e2697', 'Core/ProjectThoughtDefinitions.swift': '54696e75472667c127ded892bb5f0250ee67ba3a587b4875cad9f72cf366565c', 'Core/ProjectTopicBudgetCarryOver.swift': '86a33035e9eb430a5d1ddf8f35fabe03ae7c994d0ef7a39c88a058f828203f1d', 'Core/ProjectTopicImageUpload.swift': '9cf42be7c71eb49c09309ad840d86e359216d65bccd09e568079042acc1aeea5', 'Core/PublicMerchantHome.swift': '491b3412153923c53465f249ce50e10d1816ca0274486896e3db49fdc317cdec', 'Core/PublishingAIDraftFlow.swift': 'f86ea32dcc2a55a7236fabbb3afed4a104e5a9228b79054920222cb356575158', 'Core/RoamContracts.swift': '0d5547566592a4591de1e80e5b67dfe03fd5465700270fd6d7731c74d28f0af9', 'Core/RoamEventDestination.swift': '683ff5f23a87c7492b59598afc21014f3491a788475efcf9a6a16aeab6b7c947', 'Core/RoamExperienceMath.swift': '65f5ef1e0f0161c5875f6e962790e2690ef9de210da7cb75b7a72c3cda3b8a6b', 'Core/RoamFeaturedActivitySelection.swift': '93288ed6215e295c29bfe23de71af6f2ec4172580fe17158efa2b8cc326a2331', 'Core/RoamMerchant.swift': '2ba014085c223352a85a05638ae46db176fd237892396e22b015e7c9e729af72', 'Core/RoamPlayerProfileSelection.swift': '176fda0f760b868f543fc5a63fed84fddbaceffb62c3a59fe8d72fd38684991e', 'Core/RoamRetainedRead.swift': '7864b357ca7c20ad9f60f767a788f7a72ac3cd80edcc4554a87ef15d7db0bbe0', 'Core/RoamRouteTopicDestination.swift': '0344a52a9a85a0e5286ef8e9fb6b69c18c44dad270778bb3f8c343bd40a20363', 'Core/RuntimeLocationProjection.swift': '7fc41176bf66eb5cf604f01e3e32772eb3e0ccabd446393b1265cd6bac71a2ee', 'Core/SearchMapLayerVisibility.swift': '2e95d0a1b587228fcf6f7b1b893d31c1ef67b3679702953810fb5e39feeec6b5', 'Core/SearchMapReading.swift': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad', 'Core/SearchMapService.swift': '449f21a53d8b75592aa82b06c404b3107752fb37176d366fc27c43b463835445', 'Core/SearchMapViewportSelection.swift': '8cb68c5decb74da1b172da29507953f5b3fae9ece71eac4cce947c0cc84bcfc7', 'Core/ShopNPCContracts.swift': '2a3a7fd25a711045e8a54d886747096013f4038d2e861963871abd2b76cb4fd3', 'Core/ShopNPCCoordinator.swift': 'c268f6085afcf6eef78d548bf77899eb34a1c36bd9dea6c0b1c05dd5a8eadb1e', 'Core/ShopNPCQuestionReuse.swift': 'b6855d89de757801dc6b40eb5abc0441f07b3b5247c2afcdb025ea873ae168c3', 'Core/ShopNPCScriptedGuide.swift': '7d50f00e7e0e26d107ca6b5a7ea8c4dfd2e4f236b7b1f789e2e73e6d7771a71f', 'Core/TemplateAuthoringCoordinator.swift': '4ff6c98901cd4d2fe752ca70650eeca4cd44dab04ed9ede0b8b445f03808be76', 'Core/TemplateAuthoringSavedDraft.swift': '63bf643910adb655769497d86aae5b0851196dba8b8cca5f5c6574ec2a93460c', 'Core/TemplateAuthoringService.swift': '097aeab1ebeb6762adcacaea980cbd6e24ea8352a9045495f80546a271934580', 'Core/TemplateAuthoringShelf.swift': 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a', 'Core/TemplateAuthoringStorage.swift': 'de4463353e10e133d9453a2642cedbb716a1de1be05d4400a529d3d91e73a470', 'Core/TicketWalletReading.swift': 'ff0b7f497b1945a24f105126e4a37372ea7d8e3ced6d9acf98f6ad804060bfb1', 'Questify.xcodeproj/project.pbxproj': '211fe2e6ded15704a582d9340bb45d198620afe118b2add40d60679820b64f65', 'Questify.xcodeproj/xcshareddata/xcschemes/Questify.xcscheme': '41d92b9e86e1c30d9ab44589467782b7db30097e28520c08baeb187d63c31680', 'README.md': 'ab9505990ae97647d4b0af6db2195cfe390a1a6e05ad8559f963d935ddab49b2', 'Resources/ActivityAssociatedPlaysLocalizations.fragment.json': '36676f1c6c3e4341516f9f7dea1763f50fe4183fbecfe77fa46c7efa58f40ade', 'Resources/ActivityRequiredClubLocalizations.fragment.json': '5c07facedf1a342993363bbd530e99604ce3d7b26f1456dec915424f54d37027', 'Resources/ExploreCompletionLocalizations.fragment.json': '7cf4a3c8ab176cf63a1386d20b5169c2ee2dfb0113005de9d0706850f588f99b', 'Resources/GlobalSearchDatePresetLocalizations.fragment.json': '5974b19bcfb2fc8188a7756fa6271e777cb0a71e903d7c0c68b767eeed22def2', 'Resources/GlobalSearchRetentionLocalizations.fragment.json': 'b5d343984158a1cbceba4864efdb8d8238de55018b2f24104af05307e7a32cd3', 'Resources/GrowthLeaderboardExploreLocalizations.fragment.json': 'dd73b50979b50b0986489b774e2c253667fbd6692fd8c12d0055621f2b3cf437', 'Resources/Localizable.xcstrings': '901ba5a72ab2748c171483dff7743c63a30552ab9ded21b2c3379ae410f2a898', 'Resources/MerchantAftercareDecisionLocalizations.fragment.json': '548179fce66f92f8153d83e7f79ad500699bfd8097509bfe743f2fbcb3c02c02', 'Resources/MerchantAftercareEvidenceLocalizations.fragment.json': '89de38840dff91ea076dca74de6deda1f557c7b148661a769d03e821023af0be', 'Resources/MerchantCRMDatePickerLocalizations.fragment.json': 'e5a2e26920f277cee8472eec8e5a34affdb31d06fc7408e5b6feb72f1e8d2ecf', 'Resources/MerchantCityClaimWithdrawalLocalizations.fragment.json': 'a19e4d670bc4be11489d8a45e4e5e1d4b68e2e074abacd86301f75a44fde800e', 'Resources/MerchantCityQuotaLocalizations.fragment.json': '8c0b7f0fa055ae9cfd55517319138c01d58ca7fd5c1368196eeb608237bca3be', 'Resources/MerchantCoopCapacityClearLocalizations.fragment.json': 'f1253baec39706c0c7b6599b5569ec89090e7d223b4771c78da7bdd30f27b588', 'Resources/MerchantCoopChargeChoiceLocalizations.fragment.json': 'a483a2b4ac3b037783fb96f0dab1d42717c62308bf662b847a93a8344af9d58b', 'Resources/MerchantCustomerContactLocalizations.fragment.json': '45fbb42eb318bd44ac1a0c728c1510941701d10aa5bb945fd135686147ca3cc6', 'Resources/MerchantCustomerEmptyRecoveryLocalizations.fragment.json': '776aee403e9a84d12acc48cdbd0139eb45eefe0a484a041228d82c646e6f3f27', 'Resources/MerchantDecorTagLocalizations.fragment.json': '907b5b529c979415102ad5fbfa0fc10542e8dd83848adc37682766d792af4c00', 'Resources/MerchantFeaturedActivityLocalizations.fragment.json': '38aa734b16791c093d380896eb25060cbf10bc82fbb9f8386c881e0f38459d2f', 'Resources/MerchantFeaturedClearLocalizations.fragment.json': '248511e4b63a4d1ba58c228e3a10cedb9a8500cd4c0b30f81e9559db12bdd35b', 'Resources/MerchantInsightAttributionLocalizations.fragment.json': 'ab566bead3c12d0ebde67f6906e59ee2d071a36efe0138e9b0ee807188001d6d', 'Resources/MerchantInsightInterpretationLocalizations.fragment.json': 'abd51014f87c00e23306cb8dc4fd1d1d614d74ee018ece6214917c55939f59fa', 'Resources/MerchantInsightNavigationLocalizations.fragment.json': '02ef095dca7f821f4611fd4df2eb36e45aa393ddfb8c0ba36a80092ecc0e528d', 'Resources/MerchantInsightProfileLocalizations.fragment.json': 'e5cceb7e2be76486303c0c67bd0d214db57b3b5eb0434708f4bdfb1fffacd0b1', 'Resources/MerchantInsightVisitorsLocalizations.fragment.json': 'bc7480b8e95340f7519401b53dbdfa702da329b10d37526c2798acc1c9563a91', 'Resources/MerchantNPCRecoveryLocalizations.fragment.json': 'b756c0b7c8150a3e54a23f7fb4163aa50c2691484aff7589f1d0bcd8e045939d', 'Resources/MerchantNoteCorrectionLocalizations.fragment.json': 'c42272d00463dc5f35ce035876beb28ab26a1086e2779c2b7de442449d9aa532', 'Resources/MerchantOnboardingHoursLocalizations.fragment.json': 'c4bc4815d6a2b12f49b57f69820c224f2c3332b6682d7d23eacbd396b1227cb1', 'Resources/MerchantOperatorInvitationReceiptLocalizations.fragment.json': 'de9071c1954f0eb60d64a647e02f24598981fd06056b68b4114af3626561f34a', 'Resources/MerchantProjectWorkspaceLocalizations.fragment.json': '866291d97ef6fa86c67c582fe6d309f5a64a0707c2ab5a7d5e50e68095063285', 'Resources/MerchantRedemptionFilterLocalizations.fragment.json': '64c9616cfd8aaff9b847c64ba9c3b724af39acca50c728a084f26d452e31a20d', 'Resources/MerchantReviewDraftReturnLocalizations.fragment.json': '74e44b290d23d6727e3901372baa5368d82a22c0d5f4fa9ff30f66a52ae3d7cc', 'Resources/MerchantReviewPhotoGalleryLocalizations.fragment.json': '921d1bc769eeed3d62dcbc349e44dc14f975cdd6dfc48bc88e69eefc1f39351b', 'Resources/MerchantStationLiveCodeLocalizations.fragment.json': '2d5cb5ad61253d760748d449e61c857f639f7ab31d9d22440981308c406688f6', 'Resources/MerchantStationPauseLocalizations.fragment.json': 'd18227fe7371079b6c397374298ce691558840ab16d950bb1558bb8f444bec40', 'Resources/MerchantStationServiceTimeLocalizations.fragment.json': 'e0ef46abe75ce95b1794e602000340b57caa380cfc9447035d889bf6664f0857', 'Resources/MerchantStationSubmissionImportLocalizations.fragment.json': 'b11454e0f1483f7daec41bcab3c7de78e6090a06be33c4e533c997aa1e6f40ef', 'Resources/ObjectBadgeWallLayoutLocalizations.fragment.json': '72d47a869672f1783244d8cff5e17627a1dc576b273a212d7e1a24a4f6f75217', 'Resources/ProfileAvatarLocalizations.fragment.json': 'cdf169196f1a916bcd7c62f0cfe766f521df88ded12744ba5467335161458659', 'Resources/ProfileOrderTicketEntryLocalizations.fragment.json': 'ac9bcb6e1428d62722c01dbddf57b3cc063efb81f08d24b7555b997ffc0b4a13', 'Resources/ProfileOrderTicketScheduleLocalizations.fragment.json': '1bde51d28a3c358629b70f08d04122d6e0455c4b553878522ee29d2c305f8c29', 'Resources/ProfileReloadDiscardLocalizations.fragment.json': '37f4c3dee27ef69fcb09a2ef393abae9ef82cf0343587d688ed167d7b7b194f9', 'Resources/ProjectAlbumImageAuthor.xcstrings': '904b6503a2caafe93f84c2aa8a7e80421ae5eabfd3a1e57efe5c15b73b0ed314', 'Resources/ProjectAlbumPhotoOrder.xcstrings': '729e82299ae8b134207632793b5bae3dea2e8fa97bf4b0b2ec08b3104ccdd664', 'Resources/ProjectAlbumPhotoRemoval.xcstrings': '21e73888e9bb4fc4143ab73f5d3888d64e7f712de95a23a4b858aa51ccd7a191', 'Resources/ProjectCategoryPicker.xcstrings': '9cb9d0f9bcec7484a90384e11580581a932ff514c44519e642d1eba31625db09', 'Resources/ProjectChapterAudio.xcstrings': 'ab82374dd0007d4b96b72b1f2950f066b80f58fd587962ee286cd634b073a158', 'Resources/ProjectCityStoryNodeRemoval.xcstrings': '137615d48be52d52763ebb365083fa91266889768a912a2f10b84764c278bcea', 'Resources/ProjectDraftNodeOverview.xcstrings': 'e3df1474b523e1a74a15477a5bcf9888dc326a0172ebfa1cfaba9eaa652382d6', 'Resources/ProjectDraftStoryPreview.xcstrings': '024de120552c930f2fde7f7e8b6e8a4b38ceb771eef05db1c8952c38f4eae712', 'Resources/ProjectEditDatePicker.xcstrings': 'f9aedcada82e926e8ce755436778d7f0984de11e19e8f4a9b0af19b6c204b55a', 'Resources/ProjectEditorAudioPreview.xcstrings': 'c19ff5d7e4bcf6dd20d728debaf84f198e6d520edfda0374f860554984b71cf9', 'Resources/ProjectEndingConditionPicker.xcstrings': 'b3cd425741f55b636247488ee20a8d8ec91aef4848c565918b6d4a032833aaf2', 'Resources/ProjectInitialAttributes.xcstrings': '5a7709ee9e023567037456b73d58cb044c00edbb10de1ba1536a557e2ed7f390', 'Resources/ProjectInitialState.xcstrings': 'f99b20c8d6fdf7fe722a8c169c864d74964ae6ec35796c0124b09da729f6b4f7', 'Resources/ProjectNodeBusinessHours.xcstrings': 'a7409b3a3e610049d20f2aee83ac3288ae5416e25bc91d081c895789d2094731', 'Resources/ProjectNodeDuration.xcstrings': '5fed9b4d6de00bcf20b4305d293b4c8a18c666ea68fb43ea159dc8fb46584441', 'Resources/ProjectNodeGameplayRemoval.xcstrings': '906f1f3653957432d8f255bc145b79be042c0b1195a021dac3347a1739561bc9', 'Resources/ProjectNodeImageAuthor.xcstrings': '555ed07009d49ba4634b01d480502373bc1039d1e30ae05273689e8b7072a4f9', 'Resources/ProjectNodePhotoRemoval.xcstrings': '881b9a95ee398cefbf0bd67beac41d6ab2d8b1e2d3b779104cfd9aed1e904b88', 'Resources/ProjectNodePlacePicker.xcstrings': '8273bde2e0faecf242506dbb38d1a571457ea5ab8dff9b72d971366a0b9819a4', 'Resources/ProjectNodeRouteMapping.xcstrings': 'e5d2e5b242401bbca3cf98dae5aeabd4dcbaee11c718918126b3e2213aad74d0', 'Resources/ProjectNodeTemplateCreation.xcstrings': '1db327c344937d7d9d4ff4e473407546053040102ecda478807e126ce49853b5', 'Resources/ProjectNodeTemplateSelection.xcstrings': '69d375219a0fd0b2b6729894d9f50efe9b886d6abf7c93b0380c8eceb7da3bc6', 'Resources/ProjectPendingNodeRemoval.xcstrings': '7c2423bee9c15b27cbb8ead4c7a98702c6a018175b5939ad011850c4041f17bf', 'Resources/ProjectPendingNodeRemovalLocalizations.fragment.json': '1ec458be9f8c4ce93e651ace8303b0d2487a0b8c0d03f62a3e4bd970efd5f05c', 'Resources/ProjectRichStoryInsertion.xcstrings': '18bf63ab7e3544cd9f0d4b8c35b50904c9619ac8e5410c43f8a62cd223512273', 'Resources/ProjectStoryTextField.xcstrings': '1a69646936d2f24cd4e4d6a85cd7fbbaae690a9210b455233f2810b5249c4d29', 'Resources/ProjectStoryTextInsertion.xcstrings': '1c3b0336502f8eef6b4b3e7474d3ca4407b59f47b99058495d5776341f86c33d', 'Resources/ProjectStoryVariableInsertion.xcstrings': '10c5da0b06edfc39d9497c9fc73df55a8c288eb26de306f8fe1356a099b835d9', 'Resources/ProjectTeamConfiguration.xcstrings': '6823a88f81885dcfa9e56347ff2b557ba0e766f4feceb2b4ad56be3a50bfd23e', 'Resources/ProjectThoughtDefinitions.xcstrings': '6df35257380cea8fbff89e0e0e82feb8eab51b45ffba740ef55243910684f5d9', 'Resources/PublicMerchantHomeBusinessStateLocalizations.fragment.json': 'd8c48d36728d76379dce0081d89d10a7f01c3998054694737adc0993f7091bb1', 'Resources/RoamEventDestinationLocalizations.fragment.json': 'd72a78d1d261fdaf60c95f279d11bf9c8ddf304cb809dc2317b58b17afecf653', 'Resources/RoamMerchantBusinessStateLocalizations.fragment.json': 'c29d22a62855432d1087dd64b38f71ba269576e67872e0c8963a33ffddbbc40a', 'Resources/RoamPlaceReadStatusLocalizations.fragment.json': '36b7190d31b92d3e4c9de123fbff3ef95f69cc93c96c79c9a65ba55ddf2d6835', 'Resources/RoamPlayerProfileLocalizations.fragment.json': 'ea000abba5ad7c52be3a98c43d287edbdfb793dc83b3513067fed30542e314da', 'Resources/RoamRetainedReadLocalizations.fragment.json': 'f73a4fdf4c5e8e7668342b46f96c895db01c2e2ea60f5e0c3586eb8cff915efe', 'Resources/SearchMapLayerVisibilityLocalizations.fragment.json': 'bcd45cdafdbc34351d07a0b984ddfe522d656cc2eb74e4a18973969c073ba79d', 'Resources/SearchMapViewportLocalizations.fragment.json': 'a73db7ef80c3cf7391420513224ed51ea59653a3afbcd7671e085e48a31c0175', 'Resources/SocialGuideTemplateLocalizations.fragment.json': 'fd8111db50d162d057e00eb2596c00b1cb3ba4c5f348669cbf287d5abe109b24', 'Resources/TicketWalletTeamLocalizations.fragment.json': '24044cb2fa66435c21a4542e39a33d5b81862297d4a6a8973622631e7c711e04', 'Tests/AppUITests/AccessibilityPresentationFlowTests.swift': '34b15121fb2f5eb93efcf0709c4f7d4c50b31db1b1e8765e424a4f24fbd201f0', 'Tests/AppUITests/AccountCollectionFlowTests.swift': 'a7e98b59a99954f21dd70d997b0deffbedaebc4335df52c4c25799e954f9e974', 'Tests/AppUITests/AccountSavedPostCollectionFlowTests.swift': 'da788dddda108d6f13970424e9d3b8b88a15dbce3ff911d713c25f38204abacf', 'Tests/AppUITests/ActivityFlowTests.swift': 'ec86e3283c73fb1e9589459231ff63a8999e76aba888f113fc1113773089ac80', 'Tests/AppUITests/ApprovedReleasePreparationChineseFlowTests.swift': '720f17dbc1a0d613c29d426e8d5405e24def9143b2669cc22cfba2c5ea15065c', 'Tests/AppUITests/ApprovedReleasePreparationFlowTests.swift': '310a2d069c69a0141e358d4e0a313a0db5886757989df8efafba27ff98b9a9ce', 'Tests/AppUITests/ApprovedReleasePublicationFlowTests.swift': 'c2e72f5a8476541c4298ad934685fc36cb7fe02916741e61391e605702ae354e', 'Tests/AppUITests/ApprovedReleaseReceiptRecoveryFlowTests.swift': '8e497b471cb9d2ef46c62c051d9711068a438f2999cbe3bbc8368df71d19f6a0', 'Tests/AppUITests/ApprovedReleaseRecoveryFlowTests.swift': 'a6f47484264a2b9c5ee72567665fae6ef1c7fd30dff12b6d0faf7ee140ccf06f', 'Tests/AppUITests/ApprovedTopicFrozenCoverPublicationFlowTests.swift': '7a746e2711cf2b6a0de6f90c0c96c6762113cc0212b16eaca4331786ba3b1d90', 'Tests/AppUITests/ApprovedTopicFrozenCoverReviewFlowTests.swift': '2366899354a57fc696522bac39bab8196897f5c18566ce8de9151673189c5968', 'Tests/AppUITests/ApprovedTopicReviewCurrentChineseFlowTests.swift': 'e1bf02652ddb0e9a61d771a1199ea9834927e97ae04407b16576f78850c81db5', 'Tests/AppUITests/ApprovedTopicReviewCurrentFlowTests.swift': '69bb9f6c9780bfa70d8d0fa9737a35b255a5f97bb530fad009653eba046d87e6', 'Tests/AppUITests/ApprovedTopicReviewPersistenceFlowTests.swift': '920404b722b8c1c4a646e636f5d2665a1364adbdf542038d624fa6fdc22a222b', 'Tests/AppUITests/ApprovedTopicReviewRequestFlowTests.swift': '1f1e787a1beb9d46675f2662fd61890b0f2d90926bf6bc3d228bf2af3efe8a6b', 'Tests/AppUITests/ApprovedTopicReviewUnknownFlowTests.swift': '12d3b39f6819ae294c37399f303cb08dfcc0ac49122460a6683c1df9cadda098', 'Tests/AppUITests/ApprovedTopicSelectedCoverChineseFlowTests.swift': 'f56a803a8581e9ba340fff97f76bce3929c63ba6c9baf74de8ed522ccd688d81', 'Tests/AppUITests/ApprovedTopicSelectedCoverFlowTests.swift': '292d83ab1e6f818622d3249d37e73c12cd1da6aac92c68bab81cc98bf4082d68', 'Tests/AppUITests/ClubActionFlowTests.swift': 'ec872341ba84f2e3844a980e99a7134b6c86939d9f426c425ffc746f50506e5a', 'Tests/AppUITests/ClubCommunityUITests.swift': 'bd56adbfe7555d5ddb841c325956ac4b68b32fa77f8286017b8c01e877b3691c', 'Tests/AppUITests/ClubEnrollmentFlowTests.swift': 'fb6bf952ef69e09eb0aef75153752a5515d62e9d27f32048726849b3f9a8ea24', 'Tests/AppUITests/ClubFeedReadFlowTests.swift': '11e6d9f2f0e886eb46d39cc32d0f4d2e55f30006d48f8d555bf76889e540172d', 'Tests/AppUITests/ClubGovernanceFlowTests.swift': '4d41464ed772a0c371669e5dd55c8a06700b5980e2cb6f17e6ece58a7d1ce7ee', 'Tests/AppUITests/ClubManagementFlowTests.swift': '22e581ab357d252769d40c71fc8222c87a8cea5a6d9b88573bfa36d0089c3a92', 'Tests/AppUITests/ClubOperationsFlowTests.swift': '1b1de2b71ed658e09a004b15102201b9ee9a66fb702d4797e93f4df68d70192a', 'Tests/AppUITests/ClubOwnerRefundFlowTests.swift': '83112f2ee22cbac73e561c0f6e11247ed4481a171a52aaa0b11501d0db03ab98', 'Tests/AppUITests/ClubProfileScopeFlowTests.swift': '8cae5d6cb5f38bc4c65ac213251a400056bf305614b9449530321809189bbd9a', 'Tests/AppUITests/ClubStoryFlowTests.swift': 'ed0766adf387f2813c91fad54b3716d901c1c4db256ec3597c952452d9f1b7a1', 'Tests/AppUITests/ClubStoryNavigationFlowTests.swift': '28af5b75320b585e93edeb80ba5ce6493c666b05632f3e61e6698a4cd4c086d3', 'Tests/AppUITests/CoopRelationDiscoveryFlowTests.swift': 'fe71447339f4d8006cf1b668ecc80df501722e0153edf37a77c8a5ba2c869c42', 'Tests/AppUITests/CooperationFlowTests.swift': 'fd7f8883ac1d32d2db9aa7f5b912b078301ba94443411ed092f6d1118f82f706', 'Tests/AppUITests/CooperationFlowUITests.swift': '914ac0900365b40e72de7a304b8c058cb6cd5a09b7bcfbb4b56f869337e068f2', 'Tests/AppUITests/CouponCommandRecoveryFlowTests.swift': '17ea016fd49b9bc97a3eb39bb4070618154faf4ff08b45b0dc1540ca1d01a2d6', 'Tests/AppUITests/CouponManagementFlowTests.swift': 'ceed7f5b854426dbf598786b26d1c974f3cad4b7c1d58cb9bcf8745204f66363', 'Tests/AppUITests/CouponRuntimeChineseFlowTests.swift': 'cd4248ccbbd4543e515582fd8b4b5afdbe55d1d8bb756fdedc494fda46458bf4', 'Tests/AppUITests/CouponRuntimeFlowTests.swift': '29d491e08624930b2943e4a59bdf605184de68c1bd6d99500637a28af1883225', 'Tests/AppUITests/CouponRuntimeJourney.swift': '83906936ce979ab1cbd070794bacdf24044c508a9aa7be58c9f159195c3aae87', 'Tests/AppUITests/CreatorContentFlowTests.swift': '41f2288cdbcff8e3474d89e7c834c615bec907792b7bc87bce5b1b280070dd01', 'Tests/AppUITests/DoorReferralUITests.swift': 'b21271c91fa6609e664233e394da06d7ec0277f9452affcdac6b02d7f806cb3e', 'Tests/AppUITests/EntryFlowTests.swift': '3b37248790bc7f8b1ea372e9f194050492ba331c843f08c754d82d2ca7d33a40', 'Tests/AppUITests/FailureScreenshot.swift': '705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49', 'Tests/AppUITests/FixtureEnvironmentAssertions.swift': '5c6980720d17cdbd6509d3819471f9b00183c1d909fa91e1d18dfd31f8453ef7', 'Tests/AppUITests/GroupPollUITests.swift': 'b5bafcac4f364f38178e8dd74dced246e7b1fb2390023952205ea78600683086', 'Tests/AppUITests/GrowthCenterFlowTests.swift': 'fc7d491130ce3388d188e48df31784e696bd41e33903c6ff99d545af07eeb025', 'Tests/AppUITests/HomeFeedFlowTests.swift': '1ac5148b32f4727965c7e2298db6cb21aa1a3ccea6e7b61a83ceff68c80c6792', 'Tests/AppUITests/IMExpandedUITests.swift': 'b2ed06bf0be180fb5cadf2a72c2a59d182b1d79b757c21af0359a8334a5a033b', 'Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift': '52242b06d592da9facdb20e2d7cf6c1331f558aaec1023923e6982e069d7ac69', 'Tests/AppUITests/IntegratedDeniedAcceptanceFlowTests.swift': '24c0b29e21178acf569d1d6ed92d685934fe1ea32f39370a98819cc627edd921', 'Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift': 'c9ba0d1df3d6dac1e331fb5770b3ea064a6fb97de381782d6b74f28cc7a616d3', 'Tests/AppUITests/JourneyContentFlowTests.swift': 'cd56d905e1d42c413d921f48106872ea27e334e9213d68fc384a786acaa9cebc', 'Tests/AppUITests/JourneyRoleViewFlowTests.swift': 'ac8cc4dc31662355fdf50cab238c815de5e31ab3e83d0eb07cb349c7d132c704', 'Tests/AppUITests/MerchantBusinessFlowTests.swift': '6f7abf0f8348ef9c53137270d0fdb3150a5e1cefb625710a218aa4b5c4aa305c', 'Tests/AppUITests/MerchantClubDiscoveryFlowTests.swift': '4ef4f6534ab84a98978711196f98ad0b41d822411fb08e342f494c422ef9f5eb', 'Tests/AppUITests/MerchantContentFlowTests.swift': 'f3eae34c014c2fa58a3b3c6fae5d6c143d3a4f88ffc2bdf3ab2bbd4c08439d04', 'Tests/AppUITests/MerchantEngagementFlowTests.swift': '10d93de727d27a9b6567cb13e2a0c9462c96946e1c580dea9c7dc911c000fbd0', 'Tests/AppUITests/MerchantMarketingUITests.swift': 'bb864fc5a5a61e2c8b5a88eebb01ac2775f2de3c5cc2569c421e1e4a3aec757d', 'Tests/AppUITests/MerchantNPCFlowTests.swift': 'd64a77db83ad9228988fc6fd7b855e7d4f435d802fb8549ab00fabee674a87d2', 'Tests/AppUITests/MerchantOnboardingFlowTests.swift': 'efe66ffdf924eeaed5833c5bf482f84af643882afbc3d156646f6113e5234cac', 'Tests/AppUITests/MerchantOperationsFlowTests.swift': 'c67960f25bde6fb02b1b9c8f3cbf3c854c96abfa91b0a55a6769470923b6fa0b', 'Tests/AppUITests/MerchantTemplateAssistFlowTests.swift': '0f3f046377c674ee281923ec2153ff08acce31248e8300c3b2784996a2793498', 'Tests/AppUITests/ModuleFlowTests.swift': 'bb8a6103f9b878d4f86355dc88acef53ff0f51ce830707aa17787abc51cdb37f', 'Tests/AppUITests/NativeEnrollmentFlowTests.swift': '73fff42b9d3eb694dc936f578d43e9f4d37a3110e60206a0ee94d24ce5605175', 'Tests/AppUITests/NativeNavigationCompletionUITests.swift': 'f8753a247d2412fbfb8647065a98e49e01b98ebb8d00aae8aae4536bc3f833bc', 'Tests/AppUITests/NativePlatformFlowTests.swift': 'b9e8711950fa3f3e13c2f7802aeb3365879a00c26ae2697689002521f3dbfaa4', 'Tests/AppUITests/NativePresentationPatternFlowTests.swift': '8d6928510236f31608f35335e3a7e5f04eb6339e16220daf4a768c44b08109f8', 'Tests/AppUITests/NativeSettingsReuseFlowTests.swift': '08f355f90f680f33af778ae60da46d7f635d801fccbc64f83deb4b456d757fae', 'Tests/AppUITests/NativeVerificationFlowTests.swift': '33812ae6464baffd58bfcc5aed48b3713a4f62ca2bc8befaff03ae76347051cf', 'Tests/AppUITests/NearbyTeamUITests.swift': '7c408b308478448e6a8176c89433cd431f480e112f7d2e120f227baa5714d3b9', 'Tests/AppUITests/NonCashRewardFlowTests.swift': 'c42f8eb9afa9dfde589995c894b3ff256dd83b9cbd3bec76dd54bc40295c22fa', 'Tests/AppUITests/ObjectCardFlowTests.swift': '2a4223607dcdb62ea07c6909dba70a250358182f592f31fe8fcd493d1a75845c', 'Tests/AppUITests/OfficialActionUITests.swift': '31f8642fedd6dd93907157e8a450866706fe0087a14182bb3b27756d1d74d98a', 'Tests/AppUITests/OfficialEventFlowTests.swift': '1385657529c64512d7e3c8456336c9492ed8ee6967562431e2120ff44f359dea', 'Tests/AppUITests/OrderLifecycleUITests.swift': '47277c352682645056bb751c67be3b0c9bce32a2298f191b87835c13870d19c0', 'Tests/AppUITests/OwnedCouponCodeJourneyUITests.swift': 'e90cdc1ecbac62b8d258767a54e82848d0118fc562e3a4bbe79cbde395926414', 'Tests/AppUITests/OwnedOrderFlowTests.swift': '6ceb1cf1aed9b14859f4bfec5866cdc6d4adf5118c3926aa4b11ffdd181f3aa6', 'Tests/AppUITests/OwnedTopicCoverRecoveryFlowTests.swift': '98aae087e9048ce0eab91987fe5b14d66b7bb8505565ccee4e87b636b6802503', 'Tests/AppUITests/OwnedTopicCoverSelectionFlowTests.swift': 'eccef38b0bca7d50aa67b299b0252089c292bc6d96f539a3477e3997d237f30b', 'Tests/AppUITests/OwnerDraftBrowserFlowTests.swift': 'f7229b195dd3e47ee90ec6038ebd893ac9dd444182192c4a2de76bf861f90aa8', 'Tests/AppUITests/OwnerDraftHistoryFlowTests.swift': '17384dc614940b687f31d1b5cc1f85c71ff1b50cd4ec496e4e08c52ee27c510c', 'Tests/AppUITests/OwnerDraftReceiptFlowTests.swift': 'f02e2cff62a7fdc0840e87815023c63bad054c6e150a39f0968a11118b194cf1', 'Tests/AppUITests/PlayBranchHistoryFlowTests.swift': '66d9552a55f04d286ff267803786d434c08da35977338042c31c229cdc88729c', 'Tests/AppUITests/PlayBranchHistoryLifetimeFlowTests.swift': 'd2baa99029f6706f2e24f4b8389aa0d10c4dc071cd0ca61b1a489c0f9b2fa05d', 'Tests/AppUITests/PlayCompareFlowTests.swift': '77ab14431d332b6f30ede7c5425f8d97b9ebdce7f3aac413cd1659b67a5c8aa5', 'Tests/AppUITests/PlayDirectorPrefabFlowTests.swift': '710afa5c51c3be25b3ea45abeedfa975c9703757aba24c00920bcf7a1fe094d6', 'Tests/AppUITests/PlayExperienceFlowTests.swift': '9dc9ecdc777622bbf4f906c17749a83d9719ea0f46084cbdb4a5bad00248e8e9', 'Tests/AppUITests/PlayPreferenceFlowTests.swift': '87b702b0966a3758454d115a658fa1cccc14a415ccbe8c28e65102fcd68f2a17', 'Tests/AppUITests/PlayRouteMapCameraFallbackFlowTests.swift': '4f9bfb0535abbb3b61b40847d040b07ca476cef323016ab29925dac2ad2c156c', 'Tests/AppUITests/PlayRouteMapCameraFlowTests.swift': 'd329e8f87741c7a7bb78404e0bc4fea123051fe0355182c582bbf28a5034c872', 'Tests/AppUITests/PlayRouteMapContinuationFlowTests.swift': 'a6024af16bb73e474e20cb6ee0821a6a39cf9557df25dca12396eba10273ba26', 'Tests/AppUITests/PlayRouteMapFlowTests.swift': 'bfdd211e9113d87788f6555d4a4736c6e77e04175d84807981df0fb34d6ed4ca', 'Tests/AppUITests/PrivateHomeFlowTests.swift': 'db437c5ac4d4c5f48e3f15f1e5bd65f1bfac66aa62cd363b7c0e4b15f97625ab', 'Tests/AppUITests/PrivateHomeMapPickerFlowTests.swift': 'd40b439eb9720ee8442939c6aeb74a49e79cc4bc276a2ab4552d19f7a9a03a2d', 'Tests/AppUITests/ProfileEditFlowTests.swift': 'b868fef77b7dd8235fe6fcc65518027d79db7e805c60636998bf47b408c168be', 'Tests/AppUITests/ProjectEditFlowTests.swift': 'f900b7c8d78924d765a37d391e49503467a4a371d172288518c937d321ed6b5b', 'Tests/AppUITests/ProjectEditPendingFlowTests.swift': 'abea0305a979a0fddf8acc5cabb81c6c230afd9c33241e31dc15a4f2ec2d19ab', 'Tests/AppUITests/ProjectEditPendingRestoreFlowTests.swift': '36e3ab9017004357c892f91620c0a133892b0750602323a18ad4a765fb9c654f', 'Tests/AppUITests/ProjectEditPreparedNodesFlowTests.swift': '0840b45f13e092a1904f1e8ed3e407264d76ae4ba322c3c7d1551aadf8706e66', 'Tests/AppUITests/ProjectEditPreparedStoryOrderFlowTests.swift': 'e28b96f2bff03ba04ce8838eac35747febd293d6788df281481b126ceaaa95bb', 'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift': 'f0faaac7f2c9483ea61c38a66a22ddd381502c3435b28ffb478ef637238a5396', 'Tests/AppUITests/ProjectEditRichStoryFlowTests.swift': '52742845580a9d0412570f156376193e0e517f97269013ac47ef58203650ee1e', 'Tests/AppUITests/ProjectEditStarterFlowTests.swift': 'cc1f2d6d1c9b457af206881bd3392d054ba4f705d9159bccc5f56edcddfd3483', 'Tests/AppUITests/ProjectOwnedEditorFlowTests.swift': 'e06f4f77108ca084088c5a0a412fe754938530611fd4e2ff12199e4d1ae278c6', 'Tests/AppUITests/ProjectOwnedModeCopyFlowTests.swift': '4f45e3e382bf3d9988b82d4667580f2d61d8264fa072918f0c6e5840a991cec7', 'Tests/AppUITests/ProjectPendingNewChapterFlowTests.swift': 'bb7d8be16e5d5e4fa8ec7f67ef6ea8ff37da3821d3a09f2de83fe111b50bc516', 'Tests/AppUITests/ProjectPendingStoryAudioFlowTests.swift': '48a4937a51d290aa3d5851eca59a259a17e570dd0ca5c24764f7c3a6286102c5', 'Tests/AppUITests/ProjectPendingStoryImageFlowTests.swift': '55e7cced493afbbb70e9a5a632f0deb938df583b54cd70459d76e267fc19f59e', 'Tests/AppUITests/ProjectStoryAudioEndGapFlowTests.swift': 'f6e5c82ea86678312349f66d526c924ec43cdc654821f89925598aebde09583a', 'Tests/AppUITests/ProjectStoryAudioFirstGapFlowTests.swift': 'fc27e0d0fd10dc26c00d846c73b70fb93f0b0941d4760ab21f68f83b210e11a2', 'Tests/AppUITests/ProjectStoryAudioFlowTests.swift': '09ed44f1047ce78327e94d78d7a96039a40ed1ad375a68f5858ef9e3eddd72c6', 'Tests/AppUITests/ProjectStoryAudioMiddleGapFlowTests.swift': '65f6a0e23b24f20370e046b33fd827a0e580ab671adecae66de4293f22e29b46', 'Tests/AppUITests/ProjectStoryAudioRecoveryFlowTests.swift': '75b012d6cb4c2d056fdff63589da5fa4d91da65d2b9602346c7c9da6f426868c', 'Tests/AppUITests/ProjectStoryImageCancellationFlowTests.swift': 'e8b6c7b7471fdd762355dd73884c66c8fd015db9a49d94b4568857027e73fd99', 'Tests/AppUITests/ProjectStoryImageEndGapFlowTests.swift': '8a6b4aaec660277779498763b6949d1d1245bfc75936bf28c4e448fd5b44160e', 'Tests/AppUITests/ProjectStoryImageFirstGapFlowTests.swift': '8e1a7dba152edf2108aef8d277208a0b1e27ba9d11089a0cfa998d2e6fa5754c', 'Tests/AppUITests/ProjectStoryImageFlowTests.swift': 'dbe83155026481a333a2be69ea2ba5a00a2ae133b070338bf461d727f0f080d6', 'Tests/AppUITests/ProjectStoryImageMiddleGapFlowTests.swift': '14ccbf3f0c0f1dbb2caacdfc44c3867069033931ad3a1d136809262dea2dece5', 'Tests/AppUITests/ProjectStoryMediaGapFlowSupport.swift': '2700c2aa085765facb8c443e7981baec5a4484d35dbf07e08b970eeafae09014', 'Tests/AppUITests/ProjectStoryTemplateAlbumEndFlowTests.swift': '6377916c6dc133ae9ed6c617001d6af03ae40e84063d8d7c3a62903d4e0adf45', 'Tests/AppUITests/ProjectStoryTemplateAlbumFirstFlowTests.swift': 'fa8008549f9c942efa8206c2346fdefdeba8ffe69e988bdabc3d000b9d9d6d8d', 'Tests/AppUITests/ProjectStoryTemplateAlbumMiddleFlowTests.swift': 'd49e49faa131146f8b92d6595b94812e5b51e7ca9b6e077933a1ff1b93e1c207', 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift': 'b681a4dfab49f19c0ef17cccf76a0fbd18bd64ea7a0cd4bea7ee5e23c168db9e', 'Tests/AppUITests/ProjectStoryTemplateGameEndFlowTests.swift': '5c609f541e23260d28d92af58aff62cc75217b19f197b4c83a357ecf51b1c188', 'Tests/AppUITests/ProjectStoryTemplateGameFirstFlowTests.swift': '0af0a11c92b255213a3a268bb0a3910413883ad81b61f0286cfb948d4768b8ed', 'Tests/AppUITests/ProjectStoryTemplateGameMiddleFlowTests.swift': 'b4f91805d7ccf4ca6504ce88cc441997c2762d85b68b0038e01d02444e0d79f2', 'Tests/AppUITests/ProjectSubmissionAcknowledgmentChineseFlowTests.swift': '71adad3b7f246a732a01aa579c07fba4b7bb7e57986d2c1b53c16f53cd08a617', 'Tests/AppUITests/ProjectSubmissionAcknowledgmentFlowTests.swift': 'cc4d7d4e495e5bd9352b48bbeedb6cdde531cad94d64374c8698c5703e1343ab', 'Tests/AppUITests/ProjectSubmissionEvidenceUITestSupport.swift': '49a420e87068cbc4b28e8b570ec7faceec09d3b9b7521cd2c3e75f53803db3c6', 'Tests/AppUITests/PublicMerchantHomeFlowTests.swift': '7ada18a8f87bd815359f10bb4ae7b3b3a20ced50158a7b49af8db60c12a75e08', 'Tests/AppUITests/PublicMerchantReviewFilterFlowTests.swift': '981ae8379b43d7ac65ee79c9976d5e383ad85005ecab276955eed016b3382f02', 'Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift': 'd2e29a26850319048b7a246ab7a9b69c1e256bf43a1b9548a415202dfab2d402', 'Tests/AppUITests/PublicTemplateDetailFlowTests.swift': '97456797aabff5343ffac2d59567cf45366e6af3238dd99ee10a710de613422d', 'Tests/AppUITests/PublisherLifecycleUITests.swift': '85d6d3c53b726ec4eded7a4581c77b3fe2dfbd20846da92bba0187813909a4c4', 'Tests/AppUITests/PublishingModesFlowTests.swift': 'e23f25375776a35553204977cb9ead02875c2cc38695f0ac20a13dfd99a5b642', 'Tests/AppUITests/ReferenceChatTaskFlowTests.swift': 'd96e7e68af7b0b36a4f33299b0fbd84d5abcf98b2abed7e7c202839a37fca602', 'Tests/AppUITests/ReferenceMapCardFlowTests.swift': 'd5891be32187229dc059e54c45770165550731b60a2dab62f969c7c2fba19e15', 'Tests/AppUITests/RegionalEntryFlowTests.swift': 'a5993099e207811a32c6ebf139d76d3ce97d9ee309ad7b82c5c2d4a6cb362642', 'Tests/AppUITests/RegistrationWaitlistOrderUITests.swift': '41b1adbf4ea544490337879865000eb08d8b37ec14d0a1bbe26430eb4b8dc648', 'Tests/AppUITests/RegistrationWaitlistUITests.swift': '6b798a02b14c8eca196441ece7fef851063788fa1e757ccb8d717e2dc5d4419a', 'Tests/AppUITests/RetainedImageUITests.swift': '5639a62d4ce407907c0f3d40376bb7c336ace03bdd4c919246674b0d83c6d1e5', 'Tests/AppUITests/RoamExperienceFlowTests.swift': '5c38eb0ba990fdb5dea75121444e882b6add575a34c4afb37a49dfbd74a0ff51', 'Tests/AppUITests/SearchMapAlternativeListFlowTests.swift': '57f1c4b1e01ec0bed5313181ceaf8583c2cdbdf57f30d1c74973550d9ddaa9da', 'Tests/AppUITests/SearchMapFlowTests.swift': '23ff72dd010bded72404168d4f3ecc9da2c3fb553a135585a9009f68486a4c74', 'Tests/AppUITests/SettingsNativeFlowTests.swift': '8ee242078d4cc1e496309a2f1057aaec06b4c544c89ffcb4f1b30e004a5a5d44', 'Tests/AppUITests/ShopNPCFlowTests.swift': '609f1e4bca562679d582789df265f7b6e340f02341b481609573eee3b97fa8d2', 'Tests/AppUITests/SignedInContentDetailFlowTests.swift': '172f0db6c6a73badeab368f510e1793f54abb63cafbf31e01237e21c431889ff', 'Tests/AppUITests/SocialAccountFlowTests.swift': '4be80eb36a96fb19420fde772a46661f56217afd20319333c84b0e6f79ba6e36', 'Tests/AppUITests/SquareFlowTests.swift': 'ad1287b0eb9a6a47f18145ec844e13679c0036fbcfe2af33b94b82077639b07f', 'Tests/AppUITests/SquareGovernanceFlowTests.swift': '3b6f3e2ec02a3939e90047635824bfe681de43f5b9ba45d82d9022780914b2b8', 'Tests/AppUITests/SquareReportFlowTests.swift': '7152af267e98cb8d9cf5a67c6e2686403c2e6353504aad6a4f1fc26ad40f65e9', 'Tests/AppUITests/SquareWorkspaceFlowTests.swift': 'b7e7f7e894b1789c75ef3005284e7597319ad6e6f6df8a45cb7072f5ee70bf2c', 'Tests/AppUITests/TeamFlowTests.swift': '94469129c7b605b748d1556fbf44458ba1662c312c7a5ed8f0c5f2768113cae3', 'Tests/AppUITests/TemplateAuthoringFlowTests.swift': 'dafe1f98f1ab54d3d2564a224ad27860e877fabb7a474c1a206192063153b948', 'Tests/AppUITests/TemplateCompositionFlowTests.swift': '2786ec402ff09027d1bd96b1981fb92d287cffcb94c3c4add30de3b5d6530393', 'Tests/AppUITests/TemplateEditorControlsFlowTests.swift': 'e11dfa363adeb722fc64b93ca7572d74fde3c478a166686560722db242ad38b2', 'Tests/AppUITests/TemplateHistoricalHintFlowTests.swift': 'c6240505b4ab86c338ed8f34149992338ad37dc6c436a559c162b71ade624f19', 'Tests/AppUITests/TemplateMediaReviewFlowTests.swift': '8e052ab35f47a07eaed5ee7332489254d1791e1faabb4b3c232650f1738de438', 'Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift': 'a56a732d72fa7d656ec32ebdd96d3523515f43efd3a05c659a2f870dba746102', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift': '3ead06d83d63800015dd8255d73aae100ab8ae85fc0553787edc12d6951419ce', 'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift': '92a68fe87676f1a874445f679114fe072c441891d49356db003f0bf1d352b270', 'Tests/AppUITests/TemplateSensorDraftFlowTests.swift': 'c6953c1caa1123229985fa2d5fae7381166d3d3232cad8e6dd1e47f59dc44f9d', 'Tests/AppUITests/TicketWalletFlowTests.swift': '59e425ea9cfb0a621640c9673f40db86f2ce94aa8a2fe65c5d3f20eb450eddc6', 'Tests/AppUITests/TopicFlowTests.swift': '7f10c301530c999528b055414dc9e2a8f3cab099b556b5f950ee9a9e97271313', 'Tests/AppUITests/TopicTemplateNameSearchFlowTests.swift': 'c4e6bb1724ebac6bcefec3389f639b9a532dcc76f8d698f90ae5b1826433ce04', 'Tests/AppUITests/WalkingNavigationFlowTests.swift': '06b8f3a8e2cbc92d47ef44058a5e4ad50b0d2025ab22526f264d435478355502', 'Tests/AppUITests/WalletCommerceFlowTests.swift': 'b10534587a9b4404222f0d3b87b0fd271f2905531ceb02ba780aeea76131d31a', 'Tests/AppUITests/WeChatAppAuthFlowTests.swift': 'd5c4b559ba35a52da62527695761a638bb8dfe512f45f73d0010cfa63a1b7942', 'Tests/AppUITests/WorkshopCreatorPendingEntryFlowTests.swift': 'f83f768726e0b11f63b7ebf013db5da842c12fb06196b19e77f37ba64f0eb9e1', 'Tests/AppUITests/WorkshopCreatorPendingRecoveryFlowTests.swift': 'a347e744e54c6e8b6673e9e6db0e3a99f954d037e1dabac98793caa8bfe52150', 'Tests/AppUITests/WorkshopCreatorPendingReviewFlowTests.swift': 'ae5e2dfa18f2225abc36507c7fea871dde1ae327567b56ff796aebac14bbe53c', 'Tests/AppUnitTests/ActivityAssociatedPlaysViewTests.swift': '9a0162f00d6527cdc47bd76803260cfdb7dee022c5e2d3422fa4222cdcee66f9', 'Tests/AppUnitTests/ActivityRequiredClubSelectionViewTests.swift': '70c01efa2702c95f550da9e4cbc9e62b7983c292c70dba1c82900d972c1de923', 'Tests/AppUnitTests/ClubAIDesignCandidateRetentionTests.swift': 'd83fea483419c2c1f649a556e0e3e75a1223d56f0d650374b1a7e6a66fc5d0ce', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5', 'Tests/AppUnitTests/GrowthBadgeExploreViewTests.swift': 'f18c695af2331a9e1be586ab8cd6996b089e598bfda97d7e77827f8348344afb', 'Tests/AppUnitTests/GrowthLeaderboardExploreViewTests.swift': 'd5259dd8a6d7d9be8802e28a2c71d9898dedfdac78190e10b9b6ce922dc4c50c', 'Tests/AppUnitTests/MerchantAftercareDecisionChangeTests.swift': 'b183a027773e34128e16d672c7fe08752d914d8544605eea42509aab824f791d', 'Tests/AppUnitTests/MerchantAftercareEvidenceFlowTests.swift': 'e14dec19f8f302d43f30db52a22f422d09d35267ca03b14b72482156c4fcec80', 'Tests/AppUnitTests/MerchantCustomerContactSummaryTests.swift': 'aef88aa3401e8e3d136e12e207d038de1cbb627108daa3cbead62919fe031e87', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift': '8f6e488cbdb80d6c62ebd1aa62c280aadbd9c2b9e69b0f62dd17c1ad435a703e', 'Tests/AppUnitTests/MerchantFeaturedActivityPickerTests.swift': '365d642bce203b55306b25a19e036d93415620359106fb7b5ca602bcd92ec40d', 'Tests/AppUnitTests/MerchantFeaturedClearControlTests.swift': '143ec2c52bfc4ea4b6e039a97cd2a4e98abcf51714e3506474d4b3572374edcf', 'Tests/AppUnitTests/MerchantInsightProfileSummaryTests.swift': '11e4bb02bacb2e1db037a5af8bb1a157c3377887d031b643fc677f5d369512c4', 'Tests/AppUnitTests/MerchantNPCComposerRetentionTests.swift': 'b9f9de35e0a1f64475f844fddc4ee46b452f450c52e86a9bb160606429cd33f3', 'Tests/AppUnitTests/MerchantNPCConversationHistoryTests.swift': '0b0e4181c069f4cc02ebac5bac0da6c6845d70cfedd40c378326268294ee2a16', 'Tests/AppUnitTests/MerchantNPCGreetingPreviewTests.swift': '102760ba1ec601c57ecaf4f65909815dce5b77aec1caf8c510b314c1296963c2', 'Tests/AppUnitTests/MerchantNPCKnowledgeDismissalTests.swift': '102a412f9cf5bb026ef75ca094992ccce151b38ed8b2fa7f79d7ce45cd9dca0f', 'Tests/AppUnitTests/MerchantNPCKnowledgeDraftViewTests.swift': '1b7f9b3565b650e7be42e3966a52f0df704410b50f45bae779763f90d6355af7', 'Tests/AppUnitTests/MerchantNPCRecoveryPresentationTests.swift': '47925b6f95a31532c151459e8dba4ee1cd85254328c10c8adacb3c5d52f104c4', 'Tests/AppUnitTests/MerchantNPCResponseIdentityTests.swift': 'd57d980f79bf61bfce777d7a21059cb9f16ed097f04b9b683181cc8c8849a042', 'Tests/AppUnitTests/MerchantNPCTranscriptScrollTests.swift': '223dbd5c28c241ecdfaa08b39bda6c48f271d876bdcc24103cbbaab28a2dcca2', 'Tests/AppUnitTests/MerchantOnboardingHoursSessionTests.swift': '100d074053ca07f0f0bf93175c6d804cefdf53f14f4c526020d8545ca0ea3461', 'Tests/AppUnitTests/MerchantOperatorInvitationReceiptTests.swift': 'a503030463d77fb29b19a77614e19dfe2cc76a7605beba7c1926b1f4394b51f3', 'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift': 'e6ec7120e171c0dc72708922add8e0a65e3049f486084fd8671db3173d8b5506', 'Tests/AppUnitTests/MerchantReviewDraftReturnTests.swift': '0407f306896272c7d8cedc7aa28a1b82a52730920372bf3102b64e6dc046307d', 'Tests/AppUnitTests/MerchantReviewPhotoGalleryTests.swift': '5d561f205a30c9f55f3e114b2bab197da458a00e9e324d4d720e55df2f25c6a3', 'Tests/AppUnitTests/MerchantStationLiveCodeTests.swift': '231a7127eb9d71a1354725f4308df087bf1f34215268ee511321d2f59f40c191', 'Tests/AppUnitTests/MerchantStationSubmissionImportTests.swift': '900d9311a5b251cf7b00c846fc41053a935cfc2074cc2ed0bbfafee67c86d8c7', 'Tests/AppUnitTests/MerchantTemplateSuggestionEditTests.swift': 'f02031b71eea67d3939308fb7aad0acd4d90dca7d631769208322efda13876f7', 'Tests/AppUnitTests/NPCChatDataViewTests.swift': '721f9e3b93e197545b8e77e86b16e49d1b1d5d7e01608e39e75489cbb94ecd19', 'Tests/AppUnitTests/NPCQuickQuestionBarTests.swift': 'f555508a066b35c8c2c8c71ba419b4736d8ede33209888e1b32f91f0dcd16dbf', 'Tests/AppUnitTests/ObjectBadgeWallLayoutTests.swift': '696382f197e51ec02e329f82cb9f32d048ff6ba9497b7d172fa93e73a3b62508', 'Tests/AppUnitTests/OfficialEventBrowseStateViewTests.swift': '2fd2cc3730bded23b8b226df52aa28082e29b57e02d549ed6b0fc9d811076548', 'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift': '1694604fb92867941ff39c66c235522bf77145e25fa61c4a15ac99c62e1ec3b9', 'Tests/AppUnitTests/ProfileAvatarPresentationTests.swift': '48f3f73ce774329b8f1da1c09bb3192f3cccf4ee38d329535d4c98f48e53071b', 'Tests/AppUnitTests/ProfileOrderTicketNavigationTests.swift': 'f5fa83da9427fc0735102ec0af399942737cff27767f3f05a8383479aed28e42', 'Tests/AppUnitTests/ProfileOrderTicketScheduleViewTests.swift': 'e983089dfa04e2bf1794f8533f291b8a2ce2fa67ee920a8dd9dced0f19c4ddc0', 'Tests/AppUnitTests/ProfileReloadDiscardTests.swift': '0bb35445dd7316dc231449bbdeabe2bba22efe004eb3988bb0c4303ff0ae51f1', 'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift': '5c74526f40c44327ec68254de76bd4c316e976b5aa1f6a409502774402699054', 'Tests/AppUnitTests/ProjectAlbumPhotoOrderPresentationTests.swift': 'e2c47321b63fb0dba2b00710615de7d6435511a22cfd351fcd1034337f68fd6a', 'Tests/AppUnitTests/ProjectAlbumPhotoRemovalPresentationTests.swift': 'a6da477a522d62fffb8b4c6840dbfedaeda9094cd1351a38be5dcbda4cb2bb78', 'Tests/AppUnitTests/ProjectCategoryPickerTests.swift': '4346a80460b654d68069c34219d24625c380175147dc3b8aa4e885d1069312c6', 'Tests/AppUnitTests/ProjectChapterAudioFieldTests.swift': '8f79d91d88e80bb83b65b3efb1965547517d275ce6a4b5525c01aca35bde2d0d', 'Tests/AppUnitTests/ProjectChapterAudioPresentationTests.swift': '3564e568ac1c571b45657e02ad10bae52333860821cc1a0663fae2dc4614f8c3', 'Tests/AppUnitTests/ProjectCityStoryNodeRemovalPresentationTests.swift': '986074d480743bc30cd2fcaccea0fc67c64318a1f7a98d7911e3da82c780e234', 'Tests/AppUnitTests/ProjectDraftNodeOverviewTests.swift': 'c6a91c3dab968dfd083c177b3bae8bfec09cfe762fba2806283c5c3d3b480594', 'Tests/AppUnitTests/ProjectDraftStoryPreviewPresentationTests.swift': 'fd1781c867629afced7c682ea8519bc2f35c98d5180c29f58b5942df939e1e1b', 'Tests/AppUnitTests/ProjectEditDatePickerTests.swift': 'a8080c65afaf90ef709a656e2421e016f90a824a6db84ff7e67b263b09a1edb2', 'Tests/AppUnitTests/ProjectEditExactAutosaveTests.swift': '224df80fc57ea30e2c1841971a14f42f7cf1e303ae63c623872529781f5df8ba', 'Tests/AppUnitTests/ProjectEditIssueNavigationTests.swift': '6c48c2a6fd780abb34c172e690c57da15c0af90a1c13291386890263d4ef1a93', 'Tests/AppUnitTests/ProjectEditNodeDescriptionFieldTests.swift': '6084aa2fd2fd9d29a6736944e572eb7c3f805b03005e89d9e613498d13d62294', 'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift': '7c9f7437d0364456d22af254e499caea2686a1e6eaee127fd2e0f89b8a141f8e', 'Tests/AppUnitTests/ProjectEditorAudioPreviewTests.swift': '73a67c4e496e513821291c3096472b0b3e1ec985f1036ce46b256750b76a60df', 'Tests/AppUnitTests/ProjectEndingConditionPickerTests.swift': '0fea68ee948203450c3055939b335ba15b63c1e2bb1c6f8106c56cc354e1f5d2', 'Tests/AppUnitTests/ProjectInitialAttributesPresentationTests.swift': '3eb8efbe7604ab971be92986d3fa84b0d24c2041cbbfc0f1d9cdb68b3cffeb64', 'Tests/AppUnitTests/ProjectInitialStateEditorTests.swift': '4aa19040c19441d513d860910446d92b4989f5ae23590f41e1319c55734c20dc', 'Tests/AppUnitTests/ProjectNodeBusinessHoursViewTests.swift': 'e91a92d3104300f449b420ec7efe33326a57c03fb4d89066a399cfc67d5fbacf', 'Tests/AppUnitTests/ProjectNodeDurationPresentationTests.swift': '0b5ca7f43dd8b86f5dbe5bd8e3760c9c53b492b0dfbea7e5b58ad0c26c32e850', 'Tests/AppUnitTests/ProjectNodeGameplayRemovalFieldTests.swift': '19412514787234d62a5c264cd91458ea979ac45f6edcf7fe10c215215a0aa306', 'Tests/AppUnitTests/ProjectNodeImageAuthorTests.swift': '10a34d1fec0ab3c2eea73389d1990fef249b2cd6c8a0548966e7041127a9ec25', 'Tests/AppUnitTests/ProjectNodePhotoRemovalViewTests.swift': '813d39dd94d076547ea2e52e97b5f5c1bf78c9e7cc550c41c37b4d00bfbc8fce', 'Tests/AppUnitTests/ProjectNodePlacePickerTests.swift': '7a24ac97b874c58bfb490d74fb77504f3c8258002805f8efa72c0e9200f5d0b9', 'Tests/AppUnitTests/ProjectNodeRouteMappingEditorTests.swift': '164a4b910b8a669d2bc1aa244a163c5ebc037f5d550eada827e528837e8a8f28', 'Tests/AppUnitTests/ProjectNodeTemplateCreationTests.swift': '0c7393d9d0a1eafdb6043e76560b12ac170aa42eb8e9db7aec47a5d15d20db0c', 'Tests/AppUnitTests/ProjectNodeTemplateSelectionPresentationTests.swift': '51df87806ccf4ca38f79be19775d3f3a13d7bb78cf17f965dec6508bf161b2e7', 'Tests/AppUnitTests/ProjectPendingNodePlacePickerTests.swift': 'ca7be5785e98ee3cd2354ad687c6a58da488ea141e3d21ff2e66919f4007035c', 'Tests/AppUnitTests/ProjectPendingNodeRemovalControllerTests.swift': 'c925cae160fc4e54ba871a20d36e1e0596692ceca5af89cd432b54c3cc4ef837', 'Tests/AppUnitTests/ProjectRichStoryInsertionPresentationTests.swift': '9259a4258a53d43ca0438c4cab5a9117769530104f6980340bc23f7fb1d7d78f', 'Tests/AppUnitTests/ProjectStoryConditionPickerTests.swift': '3e9d693fb3f3e0b4507086786b1809a5e7ec5c3280002c102dd4a73367ed621f', 'Tests/AppUnitTests/ProjectStoryTextFieldTests.swift': '5c4cbd03b6f903ba6da5c270fafda1f6973714561cd2d58cd45f8a74fd2f8d4c', 'Tests/AppUnitTests/ProjectStoryTextInsertionButtonTests.swift': 'f19ce129144b461dd634f162b21f933293fd97fb3a049f5f609e74cef86fb01a', 'Tests/AppUnitTests/ProjectStoryVariablePickerTests.swift': 'b0023202ee775ac025980180c3d111a3e5eb3364350d3c865c96c770bdc9682a', 'Tests/AppUnitTests/ProjectTeamConfigurationPresentationTests.swift': '2e3a41988e8594d3e3aa5c5fd5c23afcf163fe76e253a587cd7e8f229c9aa6cb', 'Tests/AppUnitTests/ProjectThoughtDefinitionsEditorTests.swift': '2e97071c046235357d147c12a679e23db76c56451c2d8536c468bd1c7fe05ec1', 'Tests/AppUnitTests/ProjectTopicMediaPresentationTests.swift': '1d2ceb949c006054330f56e6342e039461fd2873cdab2996ba818fbfd701c938', 'Tests/AppUnitTests/PublicMerchantHomeBusinessStateViewTests.swift': '598196265c8667bab31c30c44a44165909bb309baecaf0394993e0ee88636fcb', 'Tests/AppUnitTests/PublishingAIDraftCandidateRetentionTests.swift': '2cb5ab655d7f09bdf001ee19ff3caa75c6d69fcf8637ad64c504d0b178516e5e', 'Tests/AppUnitTests/PublishingAIQuotaSectionTests.swift': 'ccd7cb5008d92ed39950983bb36bf301214066e4f262cf3bfac9409b16670ae8', 'Tests/AppUnitTests/QuestifyProgressiveBlurArtworkTests.swift': '6c1d2142ea543a4a1ce29a06425af90202dab421e2fb2847d17137f869cfa931', 'Tests/AppUnitTests/RoamEventDestinationViewTests.swift': 'ac2146be56ad0710bc530e984f69ba4b08030928368eda520ac79ef4ed9b9536', 'Tests/AppUnitTests/RoamFeaturedActivitySelectionViewTests.swift': '2bd6cbfa8e80255fd918cd5a9a1ff320f38f1573de4776f88701de6b1c5303eb', 'Tests/AppUnitTests/RoamHistoryLiveEntryTests.swift': '648a0ef063fccc787e64170f78f63898bdcb4b5f9df511aaf63530be475ddaee', 'Tests/AppUnitTests/RoamMerchantBusinessStateViewTests.swift': 'ba870351974b38c31209ddf4af84c1c29093a4872734651abee7c9198a3a336c', 'Tests/AppUnitTests/RoamPlaceReadStatusViewTests.swift': 'fdea2b35b4868b6867fd9a26aa3d82c1246a2b7bcee7bda020032d054b4228e6', 'Tests/AppUnitTests/RoamPlayerProfileSelectionViewTests.swift': '5f912492d637233e19434761a36e8a58117396cf6738753465362471e85ee204', 'Tests/AppUnitTests/RoamRetainedReadViewTests.swift': '20e588f502db536d055eeb0dc04c7681eefccb619229f92588757f760edfed30', 'Tests/AppUnitTests/RoamRouteTopicDestinationViewTests.swift': '0159bf3f470940d9e1af80184a11ba2db6da48eb052096f759e28486820180ff', 'Tests/AppUnitTests/SearchMapDatePresetDraftTests.swift': 'ec3601732b267ef28117c3f528ab6b4ead894be9cc8d9a3fc0abf908af921a64', 'Tests/AppUnitTests/SearchMapLayerVisibilityViewTests.swift': '543fdcee7dc5a8775a263595f8f618153acf022bc4bba245ffa9b601ea2f95f8', 'Tests/AppUnitTests/SearchMapViewportSelectionViewTests.swift': '786ce7423b652d0e8854b2891e99bdacc2b42221e711f240c9641f99672e86bc', 'Tests/AppUnitTests/ShopNPCModernOutcomeTests.swift': '12152605de980623ca08edac4db32444da6bd580d0b5b59600c266134ff6a539', 'Tests/AppUnitTests/ShopNPCQuestionReuseTests.swift': 'ed9f7d2fab7f212a5073c5fcd109ad369affbb1553ef1c5db3e62dd34fee8dac', 'Tests/AppUnitTests/ShopNPCScriptedGuideTests.swift': '24ad7c83c0ccb2aae9997f85b345d5ca229e1c4b8736fe3387549f9de39f85e3', 'Tests/AppUnitTests/SocialGuideTemplateTests.swift': '1dcbc0105f556038d4935fddb0bd7a2e846bb26dd9e8ea4a5d8c0c0fa1f34468', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673', 'Tests/AppUnitTests/TicketWalletPlayEntryTests.swift': 'a6f7432a2960ba9458cc7eb776b62f28ecf0cad6f66005981d0d5937c7ad6712', 'Tests/AppUnitTests/TicketWalletTeamTests.swift': '55e7b52c18393d4d855a44559e97a8d71c399a0e1d86a9238a5d96772ba16f89', 'Tests/ContractChecks/check_shop_npc.py': '23096db75522dba320512a16736bdeb5d124fae30f4350a6cbd21faa49356749', 'Tests/ContractChecks/fixtures/project_editor_readiness.json': 'e6a48f0e2ca5f9e4c64524097c3ff61279d68c15e70d287bc3ea4e9752f8a438', 'Tests/ContractChecks/fixtures/run130_submission_evidence.json': '8637dc1f4fe1f1574424e173c28a71d9d6da600cb1195775071fb96416d494ee', 'Tests/ContractChecks/fixtures/run138_ui52_driver.json': 'a0cbac7ca82b97e94745b46fbb1e5fe1157d6a0b85c2eee5f046b7d243270cb8', 'Tests/ContractChecks/merchant_customer_empty_inverse.py': '57f050da9ab76645c8128149a686c95b8059ec56e00662156c5bfb7a794d3fcd', 'Tests/ContractChecks/test_branch_history_fixture_handshake.py': '5a8859283540a6852711e2b6a5513927af71bbf137aba7a5b3fa78cbe8e838fe', 'Tests/ContractChecks/test_branch_history_fixture_lifetime.py': '81535d2fee61c03c83bc412571ef833bd644095aadfb0d9ce283259eb0a93ab9', 'Tests/ContractChecks/test_category_roam_registration.py': 'dee696f738a6e58095168e15faf4f174cb4f41f6f52e8acf1045b488fcc2d461', 'Tests/ContractChecks/test_ci138_map_readonly_enabled.py': '153f2b3ce3dcc105e174d59be4f376f89f668dae9f870e16ec09ddd412c4b6ee', 'Tests/ContractChecks/test_ci138_version_row_source.py': '2b894bde3179e190df18b70abb5ad8cff215197abd754a863c37e93495eb8b38', 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': '09b5c57129442da635c71ff664b9a8c22ff0d694184592b86058312eb073e11e', 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c', 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba', 'Tests/ContractChecks/test_explore_completion_read.py': 'ba7555dc9e393256440f51a63c46ea28d24862efdc0925e3b06d806b7bb3915b', 'Tests/ContractChecks/test_global_search_category_recovery.py': '997a6c2b4de05fa45fa022a72efb781cf634c79e1531c5c0fcae460a3cc2e91c', 'Tests/ContractChecks/test_merchant_aftercare_decision_change.py': '25f2188158b865add1dc12922dc6a1c2a517876d255bc8b5d1fc064f41d48e94', 'Tests/ContractChecks/test_merchant_aftercare_evidence_flow.py': 'c579d080e28a2be900be9114d78449d7f15acbb1d3c0a6c952b328b01334cf61', 'Tests/ContractChecks/test_merchant_business_access_lifetime.py': '8dc268db59480c9718286193dcdf2b5674121dc91e3104fbf46217515d14e2b0', 'Tests/ContractChecks/test_merchant_city_claim_withdrawal.py': '8458784d80babda420771f52634f30050cc68f5f9dc8526be59a1d3dfa482da6', 'Tests/ContractChecks/test_merchant_city_quota.py': '8341066e052a90c2f339cec89bd4633d3d08ee603822efc02c8018ddf08439dd', 'Tests/ContractChecks/test_merchant_coop_capacity_clear.py': '5d6843f2879be004b7a6fdeb58354d567309b2183cfddc9617adc122f57fec95', 'Tests/ContractChecks/test_merchant_coop_charge_choice.py': '390e23ebba74d748ffddd3816802d3c4bd5c03771e4fe366931d8129209183f1', 'Tests/ContractChecks/test_merchant_crm_date_picker.py': '184ad40985bcfdb291515c0546f08f1951f4a78a6037c11f9c5b8806a5da408c', 'Tests/ContractChecks/test_merchant_customer_contact.py': 'ef962c0a2ffbb625ddff8b4ae7ad1672e7c8820f3ea483d466d4a118df0098d9', 'Tests/ContractChecks/test_merchant_customer_empty_recovery.py': '7383b71d63ad21e2a6050cdf9f277c5f23d0d4b6f43b720904fc394bfc327f1f', 'Tests/ContractChecks/test_merchant_decor_tag_picker.py': 'ce4a480162243e0e8b497fcc13fe6e08c8d28f00c3574e956f4ae4c6260ff1b5', 'Tests/ContractChecks/test_merchant_featured_activity_picker.py': '3849b7a5fb2bf009a5ad851bac6decf0953296242d037962eb39ec5ca5677335', 'Tests/ContractChecks/test_merchant_featured_clear.py': '07bc2218ecb371c7bd6fa4092d17d91457022b6b462feeb4e6452b35e3aa2da0', 'Tests/ContractChecks/test_merchant_insight_attribution.py': 'e27871bfb3c35b394b323846e997271f84f59afb706a55b5fce27b2bdf0a2009', 'Tests/ContractChecks/test_merchant_insight_interpretation.py': 'c8fcc9140d495b523162e0c4f5ed4e5ed12f42775aba88d60cd57935c8f4016e', 'Tests/ContractChecks/test_merchant_insight_navigation.py': '4b86e251295959d0b971cac12ba8819f5208c50adbb28eb75c27c6557f296e24', 'Tests/ContractChecks/test_merchant_insight_profile_entry.py': '8983d6adfe5f5215fc0f4b8b48063fb623ec0c6bdd2a489880421750b5f6ab5b', 'Tests/ContractChecks/test_merchant_insight_recent_visitors.py': '5f73e93330a80621963fd246f73b12d1d1807470339ce7b9bbcf16816743e141', 'Tests/ContractChecks/test_merchant_note_correction_presentation.py': 'c64c4d3f14a7bf125a65bb530f235ceeda7e2e5aa9ed7ba88c921d40e2c1ca35', 'Tests/ContractChecks/test_merchant_npc_recovery.py': '101af11d1e635f7844ca939c184399cef1deec77bc5f3bb7b49fc77dd3b9624c', 'Tests/ContractChecks/test_merchant_onboarding_hours_editor.py': '3d9b7982fa7917db4cb0d544a9e67f48b5c4a803717590b91c89f1e562bd9842', 'Tests/ContractChecks/test_merchant_operator_invitation_receipt.py': '4d9108cfaf84fda406ce9d7a4853c7b44620bc2953ee9cde68a4b67731eee2c3', 'Tests/ContractChecks/test_merchant_project_workspace_entry.py': 'c55acff39bd788e3531a63621a1d3645e8cc7667f54ae08c85fd1335bc2943b9', 'Tests/ContractChecks/test_merchant_redemption_filter.py': 'eb3f37d655fbc1788b90635ebbd7823a26fc1b8ff7a92f18d2ae71a9319d6040', 'Tests/ContractChecks/test_merchant_review_draft_return.py': 'e5b7c6ce7d66037ed49dba6b32b59fcf213c57e24b6f8694285e7d612575d777', 'Tests/ContractChecks/test_merchant_review_photo_gallery.py': '17c98568ee910b6a068a38795b6cb15d30dbe63916792e92fdf0c9473323f7af', 'Tests/ContractChecks/test_merchant_station_live_code.py': '570643cca0a06fc5ae838d51a4924042e5cc70d618fe1a46d823df5cc9c257ab', 'Tests/ContractChecks/test_merchant_station_optional_fallback.py': '1eca92004d8f0365bc8b230823da2cbad61ec47017b7027231b1568c0eeb4481', 'Tests/ContractChecks/test_merchant_station_service_time.py': '7a6e49c86e359a285f8061abf13308967dc79e4b882f4cb9ccf783aadc0278b4', 'Tests/ContractChecks/test_merchant_station_submission_import.py': '02eb6566b54093e1d211d578d53fe97a6a2857be6ce37354409e01f93276f9ed', 'Tests/ContractChecks/test_object_badge_wall_layout.py': 'd990f9c2a722d7e3bee3700c022a69cb9cec523cb28a0eef7849ae9464124e30', 'Tests/ContractChecks/test_official_event_contracts.py': 'a9ccf3eaa49a9b58235b1298113a9d9d2c211a4487a875adb785c234f1e6e893', 'Tests/ContractChecks/test_official_preference_ui_regressions.py': 'c8d6049d8e1ac1699ed5c656035149540c9404a9c92b46b02cc8e33863e55680', 'Tests/ContractChecks/test_owned_order_composition.py': '4734178b8394af4d8981189fbbbccb13fba4f3fdb9ec46dde37a60c69980d491', 'Tests/ContractChecks/test_profile_avatar.py': '031747f2374ef01e935753b51be7859c75f3f5861a83037cd935089ed006a1db', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': 'd3db1c20d6e14093b561efb17d082e263497a66108002981103f8198b0a52db5', 'Tests/ContractChecks/test_profile_reload_discard.py': '044ef04942dd76592917397f686cbe6c7d50bd199ceb0776806af965da78fada', 'Tests/ContractChecks/test_project_album_photo_order.py': 'be00f6c1b3d4550bff6bd387e7b4e879727b5bba2a890270573b59459dead61f', 'Tests/ContractChecks/test_project_album_photo_removal.py': '528e2a063b0ba39b17f3df994c80f9018240f453e83106358d2307a4b3e7d21c', 'Tests/ContractChecks/test_project_city_story_node_removal.py': 'cfedb0582099f570184bd67c787ec5cadfe27db1fac686996ed2b1b3277901a0', 'Tests/ContractChecks/test_project_draft_story_preview.py': '6ac4bd721ff728d220ea5f5cd90173ff19e629a159b46f56e406fdf9e078adac', 'Tests/ContractChecks/test_project_edit_contracts.py': '899020dc67819b822f9836bd514cff53651343cf74d7e7a457dac6ea068bed7d', 'Tests/ContractChecks/test_project_edit_prepared_nodes.py': '8d18d27c70008cc1163ca988c68d5c1fe47f4727ba4c0c5018583bcd7cca98eb', 'Tests/ContractChecks/test_project_edit_review_availability.py': '7156ed04fc1aa3bdf1e5c881abc922b1a4f4f5d7caa5bbf577f7b11a92240c70', 'Tests/ContractChecks/test_project_editor_readiness.py': 'dad4ff5b74bd7444e93e4ce6f7625b0603134104f6846c8ec7e03364176b64f1', 'Tests/ContractChecks/test_project_initial_attributes.py': 'dc7db40dd5c79ae77ade28a5a7983af1646bc2a658b5873968f541fc67f9337a', 'Tests/ContractChecks/test_project_node_business_hours_clear.py': '2c969e208e2f992884060707220f5da04cdfead6af4f769de502e0ade45d67aa', 'Tests/ContractChecks/test_project_node_duration.py': '63d9f25d4c215fe91d4a0e7943e5abfb49054822e781c2a3fc5bffdc26dce99c', 'Tests/ContractChecks/test_project_node_place_picker.py': 'e110dff2ce225570953658638a4ea65247d587edb695e2ca9178745879a81cc9', 'Tests/ContractChecks/test_project_pending_node_place_picker.py': 'e69814640109712e684af5af2637f8ced05c4acece8ad935bdad77138bdcb361', 'Tests/ContractChecks/test_project_rich_story_insertion.py': '11c8a57e48f113f51490f91ebe255dd41db957ebc5a144dbed893bfbdafdf38f', 'Tests/ContractChecks/test_project_team_configuration.py': '0cf93dc5e5fcf52009f18434ff53e32b8384def9275d97db62d22b5484090b39', 'Tests/ContractChecks/test_project_topic_budget_carryover.py': '8df5462f4556866f73a478c04a88b3bb54dfe7f005e4509071380e2dad90846b', 'Tests/ContractChecks/test_project_topic_media_app.py': '2c951bee993e25ea0e60de7244ca75625d33d5956c7014c8deeb0e230af6fa2e', 'Tests/ContractChecks/test_roam_history_live_entry.py': '90846ead477f4b7dbe775f05b21b86fabe450d45ed0e67fffbfff516ac075054', 'Tests/ContractChecks/test_roam_route_replay.py': '83d0cb05ce9ec6289354c960494e6923b78a2825f6c244ec08b6693dfbe8c5c3', 'Tests/ContractChecks/test_run129_map_button_role.py': 'c29592f04a5c068688e1eeb5ce2e840e58289068efebd54b2e6b5c8ad0a7e635', 'Tests/ContractChecks/test_run129_navigation_diagnostics.py': '7a7c8e175f4c53c4e45fd2a68a54375b799a061269be77987aec46bae43982a7', 'Tests/ContractChecks/test_run130_submission_evidence.py': 'ce361b8e0f0fe955ee3189f80e4cc108280a70a320cd7162f3575897fe3680da', 'Tests/ContractChecks/test_run130_topic_media_source_adapter.py': '8646d202950f7535a3a04995a5b107ebf5be13144e427a886d8f7b0fda96da3d', 'Tests/ContractChecks/test_search_map_date_presets.py': '4193bc9f340a4e9d9a91de0d016f74fa6b33a1d67f32e08d61ee5400908eb3a9', 'Tests/ContractChecks/test_shop_npc_interruption.py': '5badac23fa4f9bb3e013a678529cccec474ebc2d4ae14dabc4ce914d0d36f6dd', 'Tests/ContractChecks/test_social_guide_templates.py': '88e1ec0ee63e83d07f17bc05ebad3b68a888ee30ce7087b5a5caa121e3ce7af8', 'Tests/ContractChecks/test_template_shelf_read_bridge.py': 'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8', 'Tests/ContractChecks/test_template_shelf_state_projection.py': 'f229a3c1447956510c42368847e70a3c94d0935b838828bb959e124507b51595', 'Tests/ContractChecks/test_ticket_wallet_play_entry.py': 'd1840576971f00d11b17beb57163bf6226d454c854b460f9cf302d84b3dc93b7', 'Tests/ContractChecks/test_ticket_wallet_read_lifetime.py': '1d31e0385565f0e248e1e57b230fd60a8c45eee54beca1b3575f54f507a286c6', 'Tests/ContractChecks/test_ticket_wallet_team.py': '0c13f00f80cc3709871461e2efaa2aaa84578c829705fecd38a190344b3194c9', 'Tests/CoreTests/ActivityAssociatedPlaysTests.swift': '4be905b805f61c389ecce5ff5c74814e0714cc77b09935d831ee055ac692e898', 'Tests/CoreTests/ActivityRequiredClubSelectionTests.swift': '733ba03df9d5c7c4ca2356aab822d786347a36ad32fe4e41181a24c91408334e', 'Tests/CoreTests/ClubAIDesignCandidateRetentionTests.swift': '40aacadd3a1ed471c7d0310e27ec93d7cb70ece3113465dfef7ea1c90ddeac6c', 'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590', 'Tests/CoreTests/ClubGovernanceProductionTests.swift': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a', 'Tests/CoreTests/ExploreCompletionReadTests.swift': 'd3201e4a5c98049e23af98485f2a6f4dabde05131a3266deaea4afc84bdc17ca', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift': '4a78eca6ec1df117f1fd24675e775e7ffe4c6f1dc85f2e4988d223705092108e', 'Tests/CoreTests/GlobalSearchRetainedResultsTests.swift': '6c040968eb49b402e70df2aa98769b9329fd6bf5de901169fdd56f504b50aa64', 'Tests/CoreTests/MerchantCRMDateRangeTests.swift': '99a5f1b1229dbea4aeab90275b5cd6b1180e739b16a3c383a31c40cb2c2da06a', 'Tests/CoreTests/MerchantCityClaimWithdrawalTests.swift': 'bebcf58e1b3272af9ee54a9101ab57440d0b47aec8f1477d041e3fd0ba10b365', 'Tests/CoreTests/MerchantCityQuotaTests.swift': '757ecd7998bcef9267310f8bc2156b4ae7c5462c0905481058fa3234365f997b', 'Tests/CoreTests/MerchantContentContractTests.swift': '9bca6b1e9cb49be328d1eace7728dcf0e81de2d3412fa2cec1f89bd02dcb4b1e', 'Tests/CoreTests/MerchantCoopCapacityClearTests.swift': 'c71f3adadab63c117ebbe1fb0b56d3e1461c5b9ada6ffb1a572e1022b493e24f', 'Tests/CoreTests/MerchantCoopChargeChoiceTests.swift': '4d4790da01c5fe978f1df11d6bd4bc07e40aadfd6a428a6c82412642ae15ec8d', 'Tests/CoreTests/MerchantCustomerContactPresentationTests.swift': '1812ad74584d8b1b71a29afbe267bdad572f584d9010bd283e30687e677633b8', 'Tests/CoreTests/MerchantCustomerEmptyRecoveryTests.swift': '2ac2623884812d139f0cdb567eda7b1cf14e730ef7882e7e88da3be872c6f9ff', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift': '407e2da4496c3d3a81a1017a84220a41636631c3dfa6867805d510412e0cc3af', 'Tests/CoreTests/MerchantFeaturedActivityOptionsTests.swift': '826f05b68ca7717dda30618208557be155cd64e371e858e797b75061920430e3', 'Tests/CoreTests/MerchantFeaturedClearContractTests.swift': '9a23003881b0108365340703c0c431b54d02d0152020a842b5c61f08e2cb237e', 'Tests/CoreTests/MerchantInsightAttributionTests.swift': 'a32977dad926120a05f6af8a1f9cffd6349d7e86c3ffdc244930f3a14ddbbacc', 'Tests/CoreTests/MerchantInsightInterpretationTests.swift': '6d67bd82cd438cc55d219c56cc921a036387883529507042ab759c335bf7ae82', 'Tests/CoreTests/MerchantInsightRecentVisitorsTests.swift': '528df7f41e75decc9a038a3ea56b4314fceb4d10bc531e220086c96691e7647e', 'Tests/CoreTests/MerchantInsightRecommendationTests.swift': '1e0d6b9c3bbbf067eebcf61a3aac5211d09857c4db168fd6d81a0a2db43f44ff', 'Tests/CoreTests/MerchantNPCConversationHistoryTests.swift': 'd9af31ad0d6b892faac20769af1643915030e2161248c22695ada41405aea0c3', 'Tests/CoreTests/MerchantNPCKnowledgeDraftTests.swift': 'eee77d3dcdf8bc86322775b1f1fbff696cece9a7ec8f73be32777a2a51cbd089', 'Tests/CoreTests/MerchantNPCMessageDraftTests.swift': 'd091f97701b3e20e6e6014a318541eab8ffdf053dc46401733b269f5872702cb', 'Tests/CoreTests/MerchantNPCResponseIdentityTests.swift': 'a9ca4f71336eca2c69d57416abdfed3f51758e5927b57f3b3d77c47ad407744a', 'Tests/CoreTests/MerchantNPCTests.swift': 'e1da2c49fa5a0d892bdc7a0cf14774ddc7fa4185549ef236422243ce8d14a05a', 'Tests/CoreTests/MerchantNoteCorrectionPresentationTests.swift': 'bba439b6e0495b46ee6829e22db36b7a3d3987d077e0be5dc45096c7b0a67fb1', 'Tests/CoreTests/MerchantOnboardingContractTests.swift': '5e494f6fa6d4d19e8ee9b45ac7a2e45fa2a084825c61c9820299c1a6feb2fe95', 'Tests/CoreTests/MerchantOnboardingHoursTests.swift': 'de9eaf0499b6d86e3bd4db95cb52a7dd6e58114d310a779296d6a4a5917e0d66', 'Tests/CoreTests/MerchantOperationsTests.swift': '6c4d6a6da06c63d9c804b24a96d4c72da53e21081adbcf3ba13bd2bf72340f94', 'Tests/CoreTests/MerchantOperatorInvitationPresentationTests.swift': '6309dece3a896fc4ff8b9e202b54d90ddc2161e055689ff88914cacd71ad8486', 'Tests/CoreTests/MerchantProjectWorkspaceScopeTests.swift': '48bcbc83acb56611eb9e03d18332d9dee1863a88c2c4929085586532fe8a34a3', 'Tests/CoreTests/MerchantRedemptionFilterTests.swift': '110a4e60f76e00b7d25e8802e40a20c90deb0ee67ebc26d14184d809677c4110', 'Tests/CoreTests/MerchantStationLiveCodeTimeTests.swift': '33bb969e399f73e586155fc46ef04eed363b68df76057f3d74d92c487f851bbf', 'Tests/CoreTests/MerchantStationPauseChoiceTests.swift': 'c917a7e70f9d3b9f52b4938a5bb655d07dea920e8da6e2aeb98564ce01e95822', 'Tests/CoreTests/MerchantStationServiceWindowTests.swift': '3ba63416661e9e6d1698a1ddc96a57cf250730b5fd93a4a9e4a57601c579b9cb', 'Tests/CoreTests/MerchantStationSubmissionCodeTests.swift': '94d873644a8bd56b0cd2a542f5eaea1439dcd0bf8ed8655ce4e593c6285dec74', 'Tests/CoreTests/MerchantTemplateSuggestionEditTests.swift': 'd628611be054f3349507fb087e650ca28de05657c168c33d567d1c09c65eee5a', 'Tests/CoreTests/NPCChatDataTests.swift': 'a683b84508fcade83db9a259d3205e03e1bc8de224e1353f25001c820b18934a', 'Tests/CoreTests/NPCQuickQuestionTests.swift': '02911e95df030ad9a5e4bb8849862eed04011cea36cc00ec2ff59d8d1d451cda', 'Tests/CoreTests/OfficialEventTests.swift': '8f9f8b43bc4c735ffc7446eaf1630500c83237c6f75260e647ffd0bf1e1c14ce', 'Tests/CoreTests/ProfileAvatarTests.swift': '343516e9937a123b8907d89981e64f92650f1135e7883633a707624afc30db2e', 'Tests/CoreTests/ProfileEditTests.swift': '6319234ba77c43afec858692bc9ff00308be774b58ea585069a7b3dc90ce654c', 'Tests/CoreTests/ProfileOrderTicketScheduleTests.swift': '14491920341bc2a22a95b078d4da9157c275f2aa5bec040f638e6b000d9189b7', 'Tests/CoreTests/ProgressiveBlurParametersTests.swift': '514473bca8550fa376409cf56a6a49f735eb1e08a43cdd889054bf11cc4ae74c', 'Tests/CoreTests/ProjectAlbumPhotoOrderTests.swift': 'fe517690e5557a71d36156a0bd8a629a34b9f8fdaa66e67e878b3c756cd8d659', 'Tests/CoreTests/ProjectAlbumPhotoRemovalTests.swift': 'd78745d1b16e62cf83e70cc78bae278cdfb28d2fe30d7af76d14257a11f0a305', 'Tests/CoreTests/ProjectChapterAudioTests.swift': '6c824b5e8105169fecd3a5e7f064e238ff1a7bc7f1e847ccc19dc09f91f297cb', 'Tests/CoreTests/ProjectChapterAudioUploadTests.swift': '8077727e94e9a6f1732e4089394192cb56429e9adf6360fd4d39a2b047e4fbb6', 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift': 'bad6293bda4a08e10687686625969954a6b906f9b8c618c8462579840d343a3c', 'Tests/CoreTests/ProjectDraftNodeProjectionTests.swift': 'dbce6ca6dfb3b78860aaabfdbfcb7c20d514751098fb1e7107bff8c8ca85e3ba', 'Tests/CoreTests/ProjectDraftStoryPreviewTests.swift': 'e9be8c1223a19dd764f44bea2df4523572dfed9293431613ddfc2bdb0c052f2b', 'Tests/CoreTests/ProjectEditDateSelectionTests.swift': '881110446cc820f3bb1fdafd9ad45344777c17a1abd0305bd6d5f416f1c74203', 'Tests/CoreTests/ProjectEditIssueLocationTests.swift': 'c89c4d6d02413ba341ec8c545da28223002f88d052817df19b918505bda3a890', 'Tests/CoreTests/ProjectEditTests.swift': 'b3e93fc53983f754935890988522c8ed4d1415580efbc84698bf465a8350c252', 'Tests/CoreTests/ProjectEmptyStoryTextRemovalTests.swift': '45fd7bb2f0b9a90709b77691091fe4f5b41f60efd2fe8d0315475f0d3d1be03c', 'Tests/CoreTests/ProjectEndingConditionChoicesTests.swift': '31cb4b00d00d6565d332401b4c9693b121ddbf1101d7c0e44efe7d51245b4c25', 'Tests/CoreTests/ProjectInitialAttributesTests.swift': '40e506e72ef85e311f9c26a978bdd5b2f71ba25350f16c8a01c8bf1ffebed913', 'Tests/CoreTests/ProjectInitialStateTests.swift': '63e0ef18f2f27550d22c8bdcd46b7e4cf99e64ff56121fd47d236598f7e72e4b', 'Tests/CoreTests/ProjectNodeBusinessHoursTests.swift': '347a0a2ec8c7aaf8316f3b3cd58841beff8499cb572457ac6ceacc1d5ded76d8', 'Tests/CoreTests/ProjectNodeDurationTests.swift': '7998f4cf43e34e7801ea83117129314e373769b16ce019771100e7642b63369b', 'Tests/CoreTests/ProjectNodeGameplayRemovalTests.swift': '1d579d78f8632b3b543cfa03b34fcbef419373118e7c60b428927d575ca55891', 'Tests/CoreTests/ProjectNodeImageTests.swift': 'e3e88537f9d8d0668168c18da545766f606c0ab0f7dfeff62cac4d9ab75d50b6', 'Tests/CoreTests/ProjectNodePhotoRemovalTests.swift': 'c5a1eb59659f7811194d9dafb4cc0037acf922575d8725267bafb7d3abe12de0', 'Tests/CoreTests/ProjectNodePlaceSelectionTests.swift': 'b864c152cf35a1b55c055d634c3394d591c7eb4f27986af725edbb27dd8e3fc1', 'Tests/CoreTests/ProjectNodeRouteMappingTests.swift': '1fad22f7215540d12c57c543d44d9a1c51e59ed88725959835368e2aededbbc2', 'Tests/CoreTests/ProjectNodeTemplateSelectionTests.swift': '27b30939935a28ab673f972b772f6cc1b8e6f5eafa30a699e8f737430efac787', 'Tests/CoreTests/ProjectPendingNodeRemovalTests.swift': '31c51ad363c2b907c309e9a01a8473efb12b8b5e7ab868260f647d36962f78df', 'Tests/CoreTests/ProjectRichStoryInsertionTests.swift': 'fbc94e881b48b907a958baaac39c0e95d29c3351b4f07af51cfbc517bd1107a3', 'Tests/CoreTests/ProjectStoryConditionChoiceTests.swift': '0e081d496ebed24db9fdca0e3e0d717ae18311fa1f2cb3996804e2c8688e8ff8', 'Tests/CoreTests/ProjectStoryImageTests.swift': 'f46146ad3d5753e048e5cebe804bf5a43e6412831ba3be3768d2a3806ff52d70', 'Tests/CoreTests/ProjectStoryTextInsertionTests.swift': '7e48ce88da282d8d7947141a8e5827eac2d75d547f1c5a6038b04ca3779af7bb', 'Tests/CoreTests/ProjectStoryVariableInsertionTests.swift': '57cd36382a3222619ff70169f89b6412db37a510121b90a5d42b7a1e45653026', 'Tests/CoreTests/ProjectTeamConfigurationTests.swift': '76da9df6c0b43e03b7cf04a0574dd12e982d39431ea27141a04208ef6236cfd3', 'Tests/CoreTests/ProjectThoughtDefinitionsTests.swift': 'a24f5b2ddf72b3960126ad74083ee43d41906e37631a0730a8492002a76515cd', 'Tests/CoreTests/ProjectTopicBudgetCarryOverTests.swift': '04dd929044737f46dc59a89f0ad0795c690079aeb917878ba04b2f59204b7cf7', 'Tests/CoreTests/ProjectTopicImageUploadTests.swift': '1ed73ccf38b2db8d181ddffdfca2fc720d423655630e6012554fa8286ac29f44', 'Tests/CoreTests/PublicMerchantHomeBusinessStateTests.swift': 'bf08b8657541b70b31de4db1a95c15f8616abb2f7153505b71b594e5763a3692', 'Tests/CoreTests/PublishingAIDraftCandidateRetentionTests.swift': 'e68e9451157a1da6cd9cacbd40a83e359789355d18fa43354f6016b221fbac6d', 'Tests/CoreTests/PublishingAIQuotaReadTests.swift': '3192220a9ddeb1c8989e8cdcc4ba67950c92475c9a4fe72655e5c9fc2afba904', 'Tests/CoreTests/RoamEventDestinationTests.swift': 'd03279407eae487a68071116f735f968b49d8dea325f3d9493a3a75301cd2073', 'Tests/CoreTests/RoamFeaturedActivitySelectionTests.swift': '4c3a2d49b9a2d96557f5f0adb3f99d84c0805abc21ff9ab83c8c005be2f5247c', 'Tests/CoreTests/RoamMerchantBusinessStateTests.swift': 'd53426399c2a4fecf98899d1eb6f15763a2776f9f97be8fa8ca40d19347e701b', 'Tests/CoreTests/RoamPlaceReadStatusTests.swift': 'f01c0ccf4fad9514753a99aca3fce256594953cc9ac6791e43ad570742af0981', 'Tests/CoreTests/RoamPlayerProfileSelectionTests.swift': 'ba2580b5e81012f2ef52ae169a32019290b69dd41c0484f8e2eb81516d342568', 'Tests/CoreTests/RoamRetainedReadTests.swift': 'ef279473dc19ae17fbb1789a1bdacafba8a03d48f6084987c6042e4b58f4dde1', 'Tests/CoreTests/RoamRouteReplayTests.swift': 'bee4110b199342c675def44f367f9da180da699124b9cf5f9222e7ad06441e0a', 'Tests/CoreTests/RoamRouteTopicDestinationTests.swift': 'a45df380e2f434533f1b6fe27ec99522c1d8ad7595222754e243a3d5143075de', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift': '4f7ed5b79dd4929b5eb828c53e1a07826e1a8b6ff78a09c0f55148faa24a4dad', 'Tests/CoreTests/SearchMapCityNodeReadTests.swift': '0574a6a4f69386b0e48264824dd606e2b0c708a8495ffe9fc821e72e0c755463', 'Tests/CoreTests/SearchMapLayerVisibilityTests.swift': '47aa3df432030ccd1e43a9e74011c397bc09b5f9df4e358744ce2882b0792df7', 'Tests/CoreTests/SearchMapViewportSelectionTests.swift': '9eade4d1260aac559c3960415de7912ff431e24eed9896d7eb3f1a04c4b6744e', 'Tests/CoreTests/ShopNPCInterruptionTests.swift': '1cc439e49a1634a416c8b140c7b05a34e0515990d7823c0d1b5849336e084d55', 'Tests/CoreTests/ShopNPCModernOutcomeTests.swift': 'cfb688444fbbf6f895a82a3665900e3878f2035de8060d51dc35dc155d82e8e4', 'Tests/CoreTests/ShopNPCQuestionReuseTests.swift': '7ae0b85a619a3540f5caf9366b3f95f4076e9c3be8abe4f09ac2dab669f11386', 'Tests/CoreTests/ShopNPCScriptedGuideTests.swift': 'f93cce07ca7843b4e1ccbe2c156b97532fc251b754768253f716af43856757c7', 'Tests/CoreTests/ShopNPCTests.swift': 'c9875b3cedd6802351fe41211a3c3c2c4772da7678ab6ede30cfb4cab6aa1e3c', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6', 'Tests/CoreTests/TemplateAuthoringSavedDraftTests.swift': 'f1595a4c5cefcb5a93ff125fbdf73f065f4526f59a5b63f8a631e6c5a535cab6', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': 'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87', 'Tests/CoreTests/TicketWalletTests.swift': '900fb953876fa45e25ddfabd3ad70d2df9c8e36fd39d9504ac4413cbf8314d20', 'docs/branch-history-fixture-lifetime.md': '8212b542b5827ba06927be95529737fdf361fd570b10daa5a866748e4099d545', 'docs/branch-history-handshake/protected-baseline.json': '022a9e26d265be4908be3f2291411d5db3cd6ea551fb78b312af07ad858ee38c', 'docs/ci-run77-ui-observations.json': '82f3a1e666a527ed37430c66024ebe4cd4c4d27035b414a19337ca95bf180b45', 'docs/ci-ui-topology-trial.md': '266851a13ec77cb0651c82caa496788e7e75f01eb4768b697a2de2fb767978fd', 'docs/ci138-coupon-square-publication-driver-contract.json': '8ccc5a48dbf17ba5ddbfbf4bf96ff3f92e5c51c725c38dd408511e2d428c0f14', 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e', 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10', 'docs/global-search-category-recovery.md': '886a26d9fa6bbe316551c53fb83d7cdfae754351693d9a671040f6a72c878dca', 'docs/merchant-aftercare-decision/implementation.md': '991980c33deeace772c958832a2ee9babc47fffe386b97d21202aebf7d2f1a67', 'docs/merchant-aftercare-evidence/implementation.md': 'a5b035c54346f420bce38d09692422a4a17a15b0832a60a69ab606ad061bd545', 'docs/merchant-city-claim-withdrawal/implementation.md': '24f0a5da1040ad9cb5680b441367bba1f74604309ad8881bee9e7faaa62592d6', 'docs/merchant-city-quota/implementation.md': 'f82419272e1132cfdf5df6f136c8973a79e58a5524cf04f43737d0e740762ae0', 'docs/merchant-coop-capacity-clear/implementation.md': '04aecdc06e5d7e5da9f02868cb8ffdf69723241494fccce5d87c5c85cb5c2fd5', 'docs/merchant-coop-charge-choice/implementation.md': '0b52720ff292e5a729e88a3cfa1a9827ce0594042a86073b7c8444070b5fa5ba', 'docs/merchant-crm-date-picker/implementation.md': '595b3ddeb0bbec25061f4702f7339aeb82dc8e1aea15ffa566e2c3b32d7562a2', 'docs/merchant-customer-contact/implementation.md': '819099751aadebd164efe83aaf10c0dcee3fc195ba22e8e3c8cbc5fea6c85b9a', 'docs/merchant-customer-empty-recovery/implementation.md': 'ad5e95c0db5e90001601a74915bb3c843da7db5e1c62b0f72fd0305611b70fa2', 'docs/merchant-decor-tag-picker/implementation.md': '1d320a30163c369a222815a565bb1bc8ab4675b7905de465a205e50a95297539', 'docs/merchant-featured-activity-picker/implementation.md': '47e84b63997ce000d3222f6744eb0a0786c9c82f45980874797534e469f0d6d1', 'docs/merchant-featured-clear/implementation.md': '9582146ce7e0b2fbb31d7cae7b5cdd3055e7483eea843b210a2dd7564a02aa17', 'docs/merchant-insight-attribution/implementation.md': 'ec32b44680653f3fec91c0f159a26647fb63710c8c6c7544917aeeb64d9b06b9', 'docs/merchant-insight-interpretation/implementation.md': 'c42641cf199424a7a77b430df9980f7355636f76794517515abc2fa1716be7c5', 'docs/merchant-insight-navigation/implementation.md': '7d836771a72680c9a804f2f9b61730e58f82186300849837d94715eb735617c7', 'docs/merchant-insight-profile-entry/implementation.md': '01ed3737b0da431591e0ee144c310eb1105e020d47da47ccd405f9c308b512f3', 'docs/merchant-insight-recent-visitors/implementation.md': 'da2aea85abf2686bdec22f569a1341313c2a15367711c69b384f535254260b3c', 'docs/merchant-note-correction/implementation.md': '1a15cfe63266636da540142ec545fa509db7bcadbbc3efc8c3c3432fccac25e4', 'docs/merchant-onboarding-hours/implementation.md': '03cf5f4c005a884b34fe73000e473ca737bcd7a4771254ad1169c459571b3f1f', 'docs/merchant-redemption-filter/implementation.md': '802cea7a6ed87d963a57c21f65f922429090a461fe0c3db851d5a58758dc98bf', 'docs/merchant-station-live-code/implementation.md': '5f157f4474fdfbfdc38c07d6b9fe9f3b9bf583c38ec1447c4c0ed483f35b2972', 'docs/merchant-station-pause/optional-fallback.md': 'eba6aad738bcd7ab724e994eefaa4b6e98e161c60c2d756b636ed3070831a5c4', 'docs/merchant-station-service-time/implementation.md': '7f58decc5dc5391b07b24149418be87a1f566e7b47d85cfbca90db5200ebd646', 'docs/player-map-history-integration-budget.json': '8b38c4974f4bb1a565df0434062774e7512183d6953aa24f7af6b98808b14d3f', 'docs/profile-read-failure-recovery.md': 'b9ec88b1988042cd4d28a39e4640e6980fc1d02d2a7f248ab564a05e25b372fa', 'docs/project-edit-localizations.json': 'bebb705d09614e85200c0277e7b4b2ef527b8d33053715dfafc6daed0ab21b69', 'docs/project-edit-rich-localizations.json': '9e34c56f663e7df57afcb1b6d47513af478e2d3019be531edfc667226f78dc3c', 'docs/project-story-template-ui-budget.json': '7372cea8a75072590491762af7f5147831737cf369ac87f892fff8887a1c29f9', 'docs/project-topic-media-app.md': 'd8fa0b6e53e99f87fff1a1e223335f4ade7dd1efa09ddf4cac9339209596f102', 'docs/roam-route-replay.md': '5c409db1da0daffd0a5143873e96310094c417941b7497e1b5536e02b57a4395', 'docs/run129-late-readiness-budget.json': '20a638d4c50fa28161743a70d69847ae5f9ffd84f1a591ebc5b8a89fab280cd6', 'docs/run129-repair-integration-budget.json': '1bda107b5b1094486f680fd775ae67664437ad68ea9d736c7a12fb554a15f22d', 'docs/run130-prepared-readiness-budget.json': 'd50034db068610784ada5a52c4cdbf60df82cf1f58bdcc57e0d2fa7467ab4db3', 'docs/ui-shard-inventory.json': '987a87d769dbed8cd579e00d36b351dfad45fe7cdf016d1763b77dda85b0b0a2', 'tools/branch_history_fixture_lifetime_projection.py': 'c2d62e292abf65bc7189b52d3937c4b67fa11710edecd852b4b302d92d636ed9', 'tools/branch_history_fixture_lifetime_projection_contract.json': 'abb3b29dc745424c61e9d268dd5fa7e904631656a720f8abaeeb6a5c29dc7936', 'tools/branch_history_handshake_planning.py': '36b34a103b70496eeabf9524381b3d7969237c447cb4fac7d7e960141ea8dc79', 'tools/branch_history_handshake_planning_contract.json': '5f3e5d8bcddb6c84ec64dd7d4b3e8d1ed2fa1946c60906eb7c5e74aed355b586', 'tools/check_profile_read_failure_contract.py': 'e492facdded0e76615721d90081b912738ba490e503aab61a7ed549a6b2a4b8a', 'tools/check_scaffold.py': '04ff9963c1bf24878dc7ca76286e6d3e011dd07845013ff6b4d5ce688abc7fa2', 'tools/ci138_coupon_square_publication_driver.py': 'ed2b775f585b63645787365e7b6b4fa5d0fd67beaeb15b84f84c801c7c67a690', 'tools/ci138_followon_handshake_contract.json': 'ef9ebd949381cd2814c1c7e0368f5f9404625eeab8793eff7bc8a516b23815a8', 'tools/ci138_followon_projection.py': '6492bc876109ad704015f23d518b23b5329ac2cea4e9a7f50c1dfdd89fdc8425', 'tools/ci_gates.py': '1bb9bae7686b3e8cda4fdb86060351fa31b4da4145f89065643efeae5ea7625c', 'tools/club_customer_directory_admission.py': '7187f18779f4f44286b50bff6da7bea0ac27cc982eb04dc9ed330df25b959def', 'tools/club_parity_planning_contract.json': 'fc3334bb2f98ae1668cb7cd2a0e6dbb5a74bfa189f9c9d887cc509f8859617a7', 'tools/generate_project.py': 'ce41dcca87e292a31fcafb2a0655b419f5ef87a97a0b3a5d05eb61e87a2a4d4b', 'tools/map_readonly_contract.json': '54494b9e2b49b93a89d72bf02d8c1c75c7f31b2da31fc0cea59b8e293a472cab', 'tools/map_readonly_inverse.py': '19bfd5712b67ec6daaadd9f351a8e842661baf2fc2551f813cd40f55cd378be9', 'tools/player_map_history_planning_contract.json': '233f2dad8e06d49e10fcb9af868221979c3ead3b7a2bf987d9a567bdfe7faa67', 'tools/remaining_editor_drivers_contract.json': '36ebb3104a1f4fb0f5bb513163e2714e1b59c9933e604da75019a4a213f98733', 'tools/remaining_editor_drivers_inverse.py': '057f4ccce7213d597630a2e8264cf1be76b5d1432127579594c8ba53b5420f98', 'tools/review_availability_contract.json': '33d7db9ad0af3fc610cfabcdcfa4a3949491b9ecdc24f6f75d522e5494bbc151', 'tools/review_availability_inverse.py': 'b5cbcd231815c374fc729f237a1296437b691f2af69298adacbbdbec2705efb7', 'tools/run129_late_readiness.py': '7aa9f0a3aefd989840f0e4bca3b4ed4cfb632678c95ffe6f3cedbbc027e66acf', 'tools/run129_late_readiness_contract.json': '4028598b554aa20d4a57a60320533eb53497edabf27e7df789ed1dd368363bd8', 'tools/run129_repair_planning.py': 'f78bff41d3eb434ae4bfcb3b0e4d5dbaa363e4af526eafa76020b4224e8d4c8a', 'tools/run129_repair_planning_contract.json': 'e25a074752564213dc99b553ad26029a126c62466ba857fd22b87851fb08834a', 'tools/run130_prepared_readiness.py': '1ff11c0b08c5db8cb6c6f052e6bf45238de0fcdca777d13c45c6240c5c2d20f6', 'tools/run130_prepared_readiness_contract.json': 'b1186140ed33d50e9240278518c60534c9988c6dfc9ae648b550f53edd32a6b9', 'tools/run130_receipt_planning.py': 'ddf7dd3b4f957d71a39af89e9a7e343c3d792a2cdc1045e7d19fff7415353a8e', 'tools/run130_receipt_planning_contract.json': 'de0cd006285c64088ad5ad82124f8667072feccc1769fb03df12ca8d9d26d171', 'tools/run130_submission_evidence.py': '0a58e208d2d54e0db868757aac5a2537484084b8f25d3d4ea6db2a6374ad0e75', 'tools/run138_ci_entry_contract.json': 'f9a2475bbd7230951b7b2d9efa87130f502b935ddb1bf44f68b5fd9ead0a3cd2', 'tools/run138_current_source_projection.py': '3980907d0a3d33e40f229c6f856ac78024b18498ea7c3f4dcd28d34862f8b280', 'tools/run138_editor_readiness.py': '22a45d0a92e4253ee35ad4165bb9226bdd6fb8333495cb0bbcd635ad74ae6404', 'tools/run138_editor_readiness_contract.json': '5f319703db67d07817cacf26e7fbb51494fd821b1a4b91b1447250303d0a093c', 'tools/run138_ui52_driver_inverse.py': '1b9f144ccc14ade609abe5cb18601265e864edd8bf3566a44e899603ee970bad', 'tools/run_static_checks.py': 'a681d224bfbef5372678a11625fa6330da097b470592e0572c1afd88f77a0210', 'tools/run_ui_shard.py': 'bc7ec919ffa4b20cb4a317ead1676622d353b4d35fd1d5c832179590f8771a7e', 'tools/story_reveal_arrival_contract.json': '468a348b5ec509d12180fc74b4c8387da98680a94a92e8f8b0ac2494d5b1a211', 'tools/story_reveal_arrival_inverse.py': '04568264e596420f8018aa5642b21201ae1e2352a399b3372c47d24687a832ba', 'tools/story_template_planning_contract.json': '2c41a3053421739836bf545888444741146f4f2f91e589b6a8469e6d46311d74', 'tools/test_products.py': '79db40a1c65344c1ade731f13a3508e163e438043e1d6aefed15541f5fbca4ca', 'tools/tests/club_parity_budget_history.py': '18c294f968497989e26620144c8cf99e2810c793f76fda059c6d686f0232ab64', 'tools/tests/combined_native_budget_history.py': '2798ca51028c8302099049a4fe6f4647b5aefa826e8537ae4f3ce1893cc7bb73', 'tools/tests/creator_pending_budget_history.py': '6996c67008702efeabdb81ed07241ae9e52db68cd4090377abf30b37c64a9f71', 'tools/tests/creator_shelf_refresh_history.py': '55632e1d0235628b55478a6b50a5e5d369bf2c54d73f4d09ec33becf84b6d7e5', 'tools/tests/creator_shelf_state_history.py': 'db500fc7605d2fd12e98b4b042fd11ef284645156d0e4698f688ea3c92890b0e', 'tools/tests/fixtures/branch_history_fixture_lifetime/App__PlayBranchHistoryFixtureSupport.swift.txt': '56b35ee882ee9095d6c1364356d991c5ddbad552110fbfc3990187da068be0d5', 'tools/tests/fixtures/branch_history_fixture_lifetime/Tests__AppUnitTests__PlayBranchHistoryFixtureHandshakeTests.swift.txt': 'e377ce367af0afef0a960fc2437ccc1ea14f3a81e5611d7885339192a55512a8', 'tools/tests/fixtures/creator_pending/source-index.json': '2ff025a7fdea1cde71f91f6323baff5477f172e768ddd86282866fd37a5831bb', 'tools/tests/fixtures/player_map_history/authored-PlayBranchHistoryFlowTests.swift.txt': '19a6dccc6226808b8d1ca5f51b7495249f4ff4286202cd94d0d4b16957bd17cf', 'tools/tests/fixtures/player_map_history/authored-PlayRouteMapCameraFlowTests.swift.txt': '94dec5ea964025d5327fb9921538a9cc045d4d8d3b6150704fa48952960bbc13', 'tools/tests/fixtures/player_map_history/authored-PlayRouteMapFlowTests.swift.txt': '3082fe0f151ba7a51942c3ef551ac029d8378b73fbba5f1a0a64d380eac64940', 'tools/tests/fixtures/player_map_history/ci_gates.py.txt': '71611199427a4503d3c7edde4e37949e16e6c900694ae458eb5a37245af4e2eb', 'tools/tests/fixtures/player_map_history/native-ios.yml.txt': '042f0dade5b5051ad8a366fb31364906762f3dd69f00fe0d921b47413352e8e7', 'tools/tests/fixtures/player_map_history/project-story-template-ui-budget.json.txt': '7372cea8a75072590491762af7f5147831737cf369ac87f892fff8887a1c29f9', 'tools/tests/fixtures/player_map_history/run_ui_shard.py.txt': 'ea3a5e95d4f320a28faa4f56cb93fd690f4957880931098ea19f168ed88f7450', 'tools/tests/fixtures/player_map_history/source-index.json': '0246c8abcac1d1e45436f504b6a21221196b920bf29d60fb26a7015191184640', 'tools/tests/fixtures/player_map_history/ui-shard-inventory.json.txt': '14eefa49b475cf1e96947f9db7bb73b79cf5a1b0509ea334c15298927c06788b', 'tools/tests/fixtures/player_map_history/ui_duration_weights.json.txt': 'c8a3818c1be1e2c98c998b97110cd7ca72ef15bc9e7c1657b0f48093285a15e4', 'tools/tests/fixtures/player_map_history/whole-method-migration.json': 'ad834dfadb15f9c2fcd61439f6ed3711f37e4c152df5b71845c6b2a75ba2f885', 'tools/tests/fixtures/run129_late_readiness/ApprovedTopicReviewCurrentFlowTests.swift': '94e515f76214e83e0eec852a87effcedb7763646efdd0d319fd9559468ffa61f', 'tools/tests/fixtures/run129_late_readiness/ApprovedTopicReviewRequestFlowTests.swift': 'ed28b78f1345ba0763c4bca801f272a62c19e907e9e0871bacdf29dbedc8b617', 'tools/tests/fixtures/run129_late_readiness/ProjectStoryImageCancellationFlowTests.swift': '12c1a1cddc3e7085414bfef5a1da32f8f77cbba31dd1212bc777ec41dc26db97', 'tools/tests/fixtures/run129_late_readiness/ui-shard-inventory.json': 'e390403b317848b48b2f10338057d0af1ead97410485b2241493fa470cb28224', 'tools/tests/fixtures/run129_repairs/.github__workflows__native-ios.yml.txt': '89deea8b11d895ed5eccd156630b898c43500e4937943985de814ea44a240609', 'tools/tests/fixtures/run129_repairs/docs__ui-shard-inventory.json.txt': 'c746e110b726fcded8aa877ac63c119526f9b23d1bfc062b9380a39803dad692', 'tools/tests/fixtures/run129_repairs/source-index.json': '1dbb5d5f38189ca6d05caa726e9f543b6991a72e39b6b023641fa5a0ee25cce5', 'tools/tests/fixtures/run129_repairs/tools__ci_gates.py.txt': 'a4028fa9aaa7c517a272329a44964c30a9abc1ec1a3205f71b19404e18836b58', 'tools/tests/fixtures/run129_repairs/tools__run_ui_shard.py.txt': 'e91acdfcec088569bdb1fcf59bba9b62746136ce6a197eea765015d6b1b42e0e', 'tools/tests/fixtures/run129_repairs/tools__ui_duration_weights.json.txt': '9923254ecbe7dc7f640128c17d8de7909b90f3bd7ec6c80eba7f2d48a82a0c0c', 'tools/tests/fixtures/run129_repairs/ui-ApprovedReleasePreparationFlowTests.swift.txt': '3dc0672fe08b6096db1c867bbe886f705904aaa471c94e12e59faa8fe5c58420', 'tools/tests/fixtures/run129_repairs/ui-ApprovedReleasePublicationFlowTests.swift.txt': 'bbdb912dfa89b70d43c8d309efdd045beed12856adad275e5aaef3189acfa096', 'tools/tests/fixtures/run129_repairs/ui-ApprovedReleaseReceiptRecoveryFlowTests.swift.txt': 'f08ed9be3856378fc8fb791ad6ff6c6ef00408e57da430c1dec5c85c245f2eee', 'tools/tests/fixtures/run129_repairs/ui-ApprovedTopicFrozenCoverPublicationFlowTests.swift.txt': '3b6b7ba72b77ceeb2ac8b9c40d972811bf9d905b59aec9ed8ba9dc4995fb52f8', 'tools/tests/fixtures/run129_repairs/ui-ApprovedTopicFrozenCoverReviewFlowTests.swift.txt': '54ae7fd8e15feb46e4f3232a54a4fff785f8c8ac72b43f0792b239d90e29e3dc', 'tools/tests/fixtures/run129_repairs/ui-ApprovedTopicSelectedCoverFlowTests.swift.txt': 'ad96f2e205e76bf4e0284f67dcc5c1d126c0b0379eff68e84206e546c4894947', 'tools/tests/fixtures/run129_repairs/ui-ClubOperationsFlowTests.swift.txt': '7e9d6242fbe0cefa92ee1a89de8d978e6c9d8c4dd9687f4d24eed47c563ce7c1', 'tools/tests/fixtures/run129_repairs/ui-ModuleFlowTests.swift.txt': '611787cefedf99600a313281dbf8a5910b5b605a84eb3a6fc5b06a804d8260f4', 'tools/tests/fixtures/run129_repairs/ui-OwnedCouponCodeJourneyUITests.swift.txt': '6a53cffeb265ff17d3564d6ec6c51b48f2ed0208a0cae7e0486cec9b9de69c97', 'tools/tests/fixtures/run129_repairs/ui-OwnedTopicCoverSelectionFlowTests.swift.txt': '0854fe725a3a6a8e241d886a4e46cfecc381f83ca51ac7e6507a0ce1ca7bac97', 'tools/tests/fixtures/run129_repairs/ui-ProjectEditPreparedNodesFlowTests.swift.txt': 'cd7d1b4770bb3e6cd904d180b5c96be428bc67debaa478346409c7a87b0c48fa', 'tools/tests/fixtures/run129_repairs/ui-ProjectOwnedEditorFlowTests.swift.txt': 'a9091c6bfc7de716f5cbfe36b3154bfe397ee55f1fcd642a988850ad50c5534e', 'tools/tests/fixtures/run129_repairs/ui-ProjectPendingNewChapterFlowTests.swift.txt': '3b4f15e2979da607199117b73430f25cb6ec31fee1ada8a1e30666e7bdb11c24', 'tools/tests/fixtures/run129_repairs/ui-ProjectStoryImageFlowTests.swift.txt': '2a5e1dc1bb7162ea9c38129b12137459529623ff3d4eb22530d4239eeb12ba39', 'tools/tests/fixtures/run129_repairs/ui-ProjectStoryTemplateFlowSupport.swift.txt': '804ef2c2f7d5e6d9620d93a321dc45df4c72f4fa435b3c4b3803b8a6055ca857', 'tools/tests/fixtures/run129_repairs/ui-ProjectSubmissionAcknowledgmentFlowTests.swift.txt': 'ded7d4708cf5b6a3f4b9a84110b789f59a8ad3af5bbbd34859829dab89294f8c', 'tools/tests/fixtures/run129_repairs/whole-method-migration.json': '96110fbe83c8dae5860668bfe26c312a1b1e4bb02833475f9c82d8148fb2e6cc', 'tools/tests/fixtures/run130_prepared_readiness/AppUITests/ProjectEditPreparedNodesFlowTests.swift': '109a670557bf128946deddcae121e060188e2dfb024b51772b555e968195f104', 'tools/tests/fixtures/run130_prepared_readiness/previous-late-contract.json': '4028598b554aa20d4a57a60320533eb53497edabf27e7df789ed1dd368363bd8', 'tools/tests/fixtures/run130_prepared_readiness/ui-shard-inventory.json': '4528127d5f5ceab750d6ce55cf7c6a6c49e11c1be39e5398ad58b8226054ae90', 'tools/tests/fixtures/run130_receipt_semantics/.github/workflows/native-ios.yml': 'b1d0d24df1158b225efa4ca952333fb25d71ba1f929fbde246bc9c479a1654b6', 'tools/tests/fixtures/run130_receipt_semantics/docs/run130-prepared-readiness-budget.json': 'd50034db068610784ada5a52c4cdbf60df82cf1f58bdcc57e0d2fa7467ab4db3', 'tools/tests/fixtures/run130_receipt_semantics/docs/ui-shard-inventory.json': 'ca0f1612701e63c52367c8219dc22e2cd7e85a587e0a668b3923c336fee7fba3', 'tools/tests/fixtures/run130_receipt_semantics/tools/tests/fixtures/run129_repairs/source-index.json': '1dbb5d5f38189ca6d05caa726e9f543b6991a72e39b6b023641fa5a0ee25cce5', 'tools/tests/fixtures/run130_receipt_semantics/tools/ui_duration_weights.json': '9241c737e6bf479abc94905ff0bd3c19ddfefb0c1093cacb42edb792290ff885', 'tools/tests/player_map_history_budget_history.py': 'e673b0e5af6ed2921dc6969aa38a01777f176116bdd01646092c7be275eea79f', 'tools/tests/reviewed_feature_budget_history.py': '71a81f0bde80aa83129b1771199242439e3a4657197ef4eb5a1c583b022d9f2c', 'tools/tests/reviewed_map_budget_history.py': 'abe3130360f2e1a0e0136f62279607d9cd2f53f7eb81ffe91d09bf59ba354ca6', 'tools/tests/story_media_budget_history.py': '60a3dd1cb1ee6991108d127fea5ab0e4e785e3a64d4da1a1f54d82c75051358f', 'tools/tests/story_template_budget_history.py': '917307334a359b9a181a038b2ef04c5f12fb87e0ad36a25bd2eada6487f8438e', 'tools/tests/test_branch_history_fixture_lifetime_projection.py': 'f004c9a2c6b2d0ba47fb512925949466bb2464659d363987e13e7f98b3bf6d29', 'tools/tests/test_branch_history_handshake_budget.py': '8939157e99cd81e48ec3536bb7485a381f8d3f20a2ee9c983f455024d4692986', 'tools/tests/test_ci138_coupon_square_publication_driver.py': '724b4953d9f34a555a27926eb259d086eafac78e1965c3c54d250663c0af7c3e', 'tools/tests/test_ci138_followon_integration.py': '9c35e10de42b097dded356474751a5e94f3ee2c5caa10bc52d9da57aba7a86ce', 'tools/tests/test_ci_gates.py': 'fdb174626ffbb7b01e8943203baf42b312818210cce76b156189afd9d8f86c08', 'tools/tests/test_creator_history_fixture_rejection.py': '06c3f4dcd456d98f058f17fa2e915a63a46188f74ff9b770c511f5927f023a46', 'tools/tests/test_creator_pending_synthetic_storage_history.py': '8d4b8e0bf04a7ce28622b416956af3628348bf3f86d5af5630fe04bb07e7e739', 'tools/tests/test_creator_shelf_refresh_history.py': '26b98d87f9c465dd2e6cefbc31734e5925c13a86003a9e695a09f4b83ad36061', 'tools/tests/test_creator_shelf_state_history.py': '2806301717bd6b0d1ff66462cb006e801853daa9a87ffdd9aa679c8deb6994bf', 'tools/tests/test_fixture_environment_contract.py': 'e51a7d1db613f67f4a2d77b9516c7feb6a750433deb1c8f93a68fac82454395a', 'tools/tests/test_gitleaks_configuration.py': 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30', 'tools/tests/test_native_static_checks.py': 'b471892d1834b973424f1d74d4e00fb12fe37a8df8689f063441813d265eee3a', 'tools/tests/test_readiness_contract_parse_cache.py': '6811fbd7519acb5ed2a41261cc26a44266a433d919247c183a32fa6aa705723a', 'tools/tests/test_remaining_editor_drivers.py': 'c57781a7ebfed313be80db9621e88a23cb1d8d953bac0cc6448855ac4ef969b4', 'tools/tests/test_review_availability_inverse.py': '052f928979576e202d55d8ca0d9b132d05d49d8ec8abd1a3080c3189e2379072', 'tools/tests/test_run138_current_ci_entry.py': '2ee4f0dac630e697d10d06595a1ac257d50d49f9ef421ef9f0c1549e5f516f08', 'tools/tests/test_run138_editor_readiness.py': '1ac817d707a88fdd171982ff28636d8677cdb5184aaca0031f1d053b5a1a43d5', 'tools/tests/test_story_reveal_arrival.py': '1fdb2226fa1525c6bde8b34c7dd366207709a0a55619781c736073430db7af50', 'tools/tests/test_test_bundle_preflight.py': '50a580c7e30a8b8f929901d4d7d2cc9c2722d9b576d8520d19fc1063f5ab1c5c', 'tools/ui_duration_weights.json': '29702b1924f79fd62fed74b71de626e7e68545747990b0e55be21415accaced7', 'tools/ui_failure_evidence.py': '2e7a52f257cf051e81789fb37845d56388403efc5d7bf33a26e87b604131a9e8'}
_CLUB_LOCAL_TOOL_NAMES = ('add_social_localizations', 'apply_nearby_write_host_patch', 'branch_history_fixture_lifetime_projection', 'branch_history_handshake_planning', 'build_club_governance_catalog', 'build_compliance_catalog', 'build_coupon_management_localizations', 'build_media_destinations_catalog', 'build_merchant_business_localizations', 'build_merchant_content_localizations', 'build_merchant_crop_catalog', 'build_merchant_engagement_localizations', 'build_merchant_marketing_localizations', 'build_merchant_template_assist_localizations', 'build_object_cards_catalog', 'build_publish_modes_catalog', 'build_simulator_keychain_host', 'check_account_compliance', 'check_built_profile', 'check_chapter_thought_sync', 'check_club_community', 'check_club_coop_contextual', 'check_club_governance', 'check_content_draft_api_boundary', 'check_contextual_flows', 'check_cooperation_flows', 'check_cooperation_protected_dispatch', 'check_coupon_management', 'check_door_referral', 'check_gltf_linked', 'check_gltf_source', 'check_im_expanded', 'check_image_upload_recovery', 'check_journey_content', 'check_map_alternative_list', 'check_media_destinations', 'check_merchant_business', 'check_merchant_content', 'check_merchant_engagement', 'check_merchant_marketing', 'check_merchant_template_assist', 'check_merchant_voice_samples', 'check_native_enrollment', 'check_native_motion_reminders', 'check_native_navigation_completion', 'check_native_verification', 'check_nearby_team_module', 'check_nearby_withdrawal_races', 'check_nearby_write_repair', 'check_object_cards', 'check_official_actions', 'check_platform_consumers', 'check_play_recovery_api_boundary', 'check_play_reward_badges', 'check_play_runtime_hosts', 'check_player_journey_screens', 'check_private_home', 'check_profile_read_failure_contract', 'check_publish_modes', 'check_publisher_authority', 'check_publisher_lifecycle', 'check_retained_image_hosts', 'check_retained_images', 'check_scaffold', 'check_search_map', 'check_search_map_date_picker', 'check_settings_native', 'check_shop_npc_host', 'check_square_governance', 'check_swift_syntax', 'check_team_native', 'check_ticket_pending_order_navigation', 'check_wallet_commerce', 'ci138_coupon_square_publication_driver', 'ci138_followon_projection', 'ci_gates', 'club_customer_directory_admission', 'collect_app_unit_launch_diagnostics', 'export_ui_evidence', 'extract_settings_legal', 'generate_project', 'import_arb_catalog', 'map_readonly_inverse', 'prepare_simulator_keychain_host', 'remaining_editor_drivers_inverse', 'report_protected_storage_coverage', 'review_availability_inverse', 'run129_late_readiness', 'run129_repair_planning', 'run130_prepared_readiness', 'run130_receipt_planning', 'run130_submission_evidence', 'run138_current_source_projection', 'run138_editor_readiness', 'run138_ui52_driver_inverse', 'run_static_checks', 'run_targeted_native', 'run_ui_shard', 'story_reveal_arrival_inverse', 'test_products', 'ui_failure_evidence')
_CLUB_E2B_CONTRACT_SHA256 = '5f319703db67d07817cacf26e7fbb51494fd821b1a4b91b1447250303d0a093c'
_CLUB_CURRENT_ROOT = Path(__file__).resolve().parents[1]
_CLUB_LOADED_HELPER_SHA256 = digest(Path(__file__).read_bytes())
_club_context_cache = None
_club_context_lives = []


def _club_exact_current_root(root):
    root = Path(root).absolute()
    if root.is_symlink() or root != root.resolve() or root != _CLUB_CURRENT_ROOT:
        raise ValueError('Unbound or symlinked club current source root')
    return root


def _club_registration():
    # This import belongs to the actual current helper, outside the historical
    # importer. Its own checked_current binds its loaded implementation bytes.
    from Tests.ContractChecks import test_category_roam_registration as registration
    return registration


def _club_e2b_bytes(relative, raw, registration):
    if relative == CONTRACT_PATH:
        restored = registration.club_predecessor_contract(json.loads(raw))
        if isinstance(restored, dict):
            restored = (json.dumps(restored, indent=2, ensure_ascii=False) + '\n').encode()
        elif isinstance(restored, str):
            restored = restored.encode()
    else:
        restored = registration.club_predecessor_source(relative, raw)
    if not isinstance(restored, bytes) or digest(restored) != _CLUB_E2B_SHA256[relative]:
        raise ValueError('Exact e2b reader dependency not restored: ' + relative)
    return restored


def _club_authenticate_full(root=_CLUB_CURRENT_ROOT, *, collect=False):
    root = _club_exact_current_root(root)
    try:
        if digest((root / HELPER_PATH).read_bytes()) != _CLUB_LOADED_HELPER_SHA256:
            raise ValueError('Loaded club historical bridge differs from current bytes')
        registration = _club_registration()
        raw_contract = (root / CONTRACT_PATH).read_bytes()
        # Full actual-current admission must happen before projection/cache reads.
        registration.checked_current(raw_contract, root)
        restored = {} if collect else None
        for relative in _CLUB_E2B_SHA256:
            path = root / relative
            if path.is_symlink() or path.resolve() != path:
                raise ValueError('Symlinked finite current club input: ' + relative)
            raw = path.read_bytes()
            old = _club_e2b_bytes(relative, raw, registration)
            if collect:
                restored[relative] = old
        # Detect a current change made while the finite inputs were being read.
        registration.checked_current((root / CONTRACT_PATH).read_bytes(), root)
        return restored
    except (OSError, AssertionError) as error:
        raise ValueError('Current club inputs were not authenticated: ' + str(error)) from error



# A transaction is explicit and bounded to one synchronous caller/task. It is
# not a cross-call admission cache. Every inner reader still hashes all actual
# current inputs; before/after complete admission brackets each outer scope.
from contextlib import contextmanager as _club_contextmanager
import asyncio as _club_asyncio
import threading as _club_threading
_club_active_transaction = _ClubContextVar('club_authenticated_reader_transaction', default=None)

def _club_transaction_owner():
    try: task = _club_asyncio.current_task()
    except RuntimeError: task = None
    return (_club_os.getpid(), _club_threading.get_ident(), task)

def _club_transaction_hashes(root, paths):
    values = {}
    for relative in paths:
        path = root / relative
        if path.is_symlink() or path.resolve() != path:
            raise ValueError('Aliased current transaction input: ' + relative)
        values[relative] = digest(path.read_bytes())
    return values

def _club_check_transaction(state):
    if not state['active'] or state['owner'] != _club_transaction_owner():
        raise ValueError('Expired or foreign club reader transaction')
    root = _club_exact_current_root(state['root'])
    if _club_transaction_hashes(root, state['paths']) != state['raw_sha256']:
        raise ValueError('Actual current raw input changed during club reader transaction')

def _club_authenticate_raw(root=_CLUB_CURRENT_ROOT, *, collect=False):
    root = _club_exact_current_root(root)
    state = _club_active_transaction.get()
    if state is None:
        return _club_authenticate_full(root, collect=collect)
    if state['root'] != root:
        raise ValueError('Foreign root cannot use an authenticated club transaction')
    _club_check_transaction(state)
    return dict(state['predecessors']) if collect else None

@_club_contextmanager
def club_authenticated_transaction(root=_CLUB_CURRENT_ROOT):
    root = _club_exact_current_root(root)
    previous = _club_active_transaction.get()
    if previous is not None:
        if previous['root'] != root:
            raise ValueError('Nested foreign club reader transaction')
        _club_check_transaction(previous)
        try:
            yield
        finally:
            _club_check_transaction(previous)
        return
    predecessors = _club_authenticate_full(root, collect=True)
    registration = _club_registration()
    paths = tuple(sorted(set(_CLUB_E2B_SHA256) | set(registration.CLUB_CURRENT_INPUTS)))
    raw_sha256 = _ClubMappingProxy(_club_transaction_hashes(root, paths))
    _club_authenticate_full(root)
    state = {'active': True, 'root': root, 'owner': _club_transaction_owner(),
             'paths': paths, 'raw_sha256': raw_sha256,
             'predecessors': _ClubMappingProxy(predecessors)}
    token = _club_active_transaction.set(state)
    try:
        yield
    finally:
        try:
            _club_check_transaction(state)
            _club_authenticate_full(root)
        finally:
            state['active'] = False
            _club_active_transaction.reset(token)

def _club_tree_sha256(root):
    root = Path(root)
    if root.is_symlink() or root.resolve() != root:
        raise ValueError('Symlinked finite club historical context')
    result = {}
    # Match run138_current_source_projection.context_generated_path exactly:
    # only root-generated paths and Python caches, never nested source names.
    def generated(relative):
        parts = relative.parts
        text = relative.as_posix()
        return ('__pycache__' in parts or (parts and parts[0] in {'.git', '.build', 'DerivedData'})
                or text == '.DS_Store' or any(text == prefix or text.startswith(prefix + '/')
                    for prefix in ('Questify.xcodeproj/xcuserdata',
                                   'Questify.xcodeproj/project.xcworkspace/xcuserdata')))
    def failed(error):
        raise ValueError('Unreadable finite club historical context') from error
    for directory, subdirectories, files in _club_os.walk(root, onerror=failed):
        ignored = {name for name in subdirectories + files
                   if generated((Path(directory) / name).relative_to(root))}
        for name in subdirectories + files:
            if name not in ignored and (Path(directory) / name).is_symlink():
                raise ValueError('Symlink in finite club historical context')
        subdirectories[:] = [name for name in subdirectories if name not in ignored]
        for name in files:
            if name not in ignored:
                path = Path(directory) / name
                result[path.relative_to(root).as_posix()] = digest(path.read_bytes())
    return result



# Only the finite complete-source/AST-pinned pure declarations below bypass
# reader reauthentication. Their implementation uses captured pure primitives,
# never mutable historical module globals or arbitrary caller objects.
import ast as _club_ast
import hashlib as _club_hashlib
_CLUB_PURE_ROWS = {('Tests/ContractChecks/test_branch_history_fixture_handshake.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'data', 'source_sha256': '50b76bfffc27cbd7a792c95d031f6fd8e49777b6241b96ed8c4c4773edc356cb', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_category_roam_registration.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_category_roam_registration.py', 'encode'): {'kind': 'json_pretty_bytes', 'parameter': 'value', 'source_sha256': '15f3320e65d5c4bba44d67c074c3972550aea7b91090b60d3d90f1ed00d72a59', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=BinOp(left=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='ensure_ascii', value=Constant(value=False)), keyword(arg='indent', value=Constant(value=2))]), op=Add(), right=Constant(value='\\n')), attr='encode', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_ci138_map_readonly_enabled.py', 'digest'): {'kind': 'utf8_sha256', 'parameter': 'value', 'source_sha256': 'cc5bb1779d88066e25dff8c55223fca6cf834b65304663c6c628ac6679b14d36', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[Constant(value='utf-8')], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_ci138_version_row_source.py', 'digest'): {'kind': 'text_sha256', 'parameter': 'value', 'source_sha256': '8d8ff89613c063f6d1ca604e3e10eb0dc20c3d9a72305bf3b017bd742900e431', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_club_customer_directory_remote_admission.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_club_customer_keyword_debounce.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '502dba8f6f5eb96a4f95e6c251e4aef33e0dda40145021f0beefcc2d638aa19b', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_merchant_business_access_lifetime.py', 'digest'): {'kind': 'text_sha256', 'parameter': 'source', 'source_sha256': '12db6294459517a1b59d4ab71a696d4adc05156daf81378ccd3eb9b2319cfd23', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_merchant_station_live_code.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'b', 'source_sha256': '56b0e361ae61835f703c478901906e92c42022021e9f42feb0ce0ca8cdbba673', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_profile_read_failure_remote_admission.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'value', 'source_sha256': '8f10eb0e431bb653f8fd55a4a30f863abce726ca528f0615ddb71b1c587b1e4a', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_project_editor_readiness.py', 'digest'): {'kind': 'text_sha256', 'parameter': 'text', 'source_sha256': 'e5f5cb90a547b9ece882e8ee899a52a42f71f18ff1491da053acd5c0573c0e6b', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('Tests/ContractChecks/test_template_shelf_state_projection.py', 'digest'): {'kind': 'text_sha256', 'parameter': 'text', 'source_sha256': 'c7f9b07818012d808ea23a5a4dd21d45f105050031a7edf6c34f7811f11c228b', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/branch_history_fixture_lifetime_projection.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/branch_history_handshake_planning.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/branch_history_handshake_planning.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'value', 'source_sha256': '62296263865539c36916d85dbccec250e91f7bbadc8436800c11824cf3f7ef4e', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/ci138_coupon_square_publication_driver.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/ci_gates.py', 'encode'): {'kind': 'json_compact', 'parameter': 'value', 'source_sha256': '4f5b9842569e07472cffab4244e6d30983b407fe9fff30014d5b50dae4354766', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]))], decorator_list=[], type_params=[])"}, ('tools/club_customer_directory_admission.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/map_readonly_inverse.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/remaining_editor_drivers_inverse.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/review_availability_inverse.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run129_late_readiness.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run129_late_readiness.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'value', 'source_sha256': '62296263865539c36916d85dbccec250e91f7bbadc8436800c11824cf3f7ef4e', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run129_repair_planning.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'data', 'source_sha256': '50b76bfffc27cbd7a792c95d031f6fd8e49777b6241b96ed8c4c4773edc356cb', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run129_repair_planning.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'value', 'source_sha256': '62296263865539c36916d85dbccec250e91f7bbadc8436800c11824cf3f7ef4e', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run130_prepared_readiness.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '1117912448951bf90f44730f3937d91bd7fdae06b90791bbb0a617dfbd423fc6', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run130_prepared_readiness.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'o', 'source_sha256': 'ea17a90f03754e5b1ffd66f30494f79203c2ad03093c4703bfaecc80ee16d8c5', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run130_receipt_planning.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'b', 'source_sha256': '4c564deac14c3dfc8a6146358488ceac0c3428188e247f152e61f337c0f92517', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run130_receipt_planning.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'v', 'source_sha256': 'eb7544c6365ed7363a63ab8b6365430e82047743d5bf82472c31ed520fbe7e58', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run138_editor_readiness.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run138_editor_readiness.py', 'canonical'): {'kind': 'canonical_sha256', 'parameter': 'value', 'source_sha256': '62296263865539c36916d85dbccec250e91f7bbadc8436800c11824cf3f7ef4e', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run138_ui52_driver_inverse.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/run_static_checks.py', 'encode'): {'kind': 'json_compact_ascii', 'parameter': 'value', 'source_sha256': '4e66e20b1c6de1ca31fa9c9dc22ccc9c9a1d4e288117d9bab6d0d46efd68bb3d', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load())), keyword(arg='ensure_ascii', value=Constant(value=True))]))], decorator_list=[], type_params=[])"}, ('tools/run_static_checks.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/story_reveal_arrival_inverse.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/club_parity_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/combined_native_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': '3401a5c8db4c13b0489b228e47076661ae076bd36f0bd9e3b4aa73de50ab993a', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/creator_pending_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/creator_shelf_state_history.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/player_map_history_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/reviewed_feature_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/reviewed_map_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/story_media_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'x', 'source_sha256': '0ede61482b8ec6a6ea949b518896bf407288ccb40786c6d4098281fdba2ba31a', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/story_template_budget_history.py', 'canonical'): {'kind': 'canonical_inline_sha256', 'parameter': 'value', 'source_sha256': 'ef0adde1884c48bd50354f029e58ae08faf3f5298b358aa5e37d187c062b9be4', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/test_branch_history_fixture_lifetime_projection.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/test_creator_pending_synthetic_storage_history.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'data', 'source_sha256': '50b76bfffc27cbd7a792c95d031f6fd8e49777b6241b96ed8c4c4773edc356cb', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/test_creator_shelf_refresh_history.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}, ('tools/tests/test_creator_shelf_state_history.py', 'digest'): {'kind': 'bytes_sha256', 'parameter': 'raw', 'source_sha256': '884bb01e185f2d9d9430301d9fae0ad420aa9c9ab5ec6be9c82587a6bf0ed525', 'shape': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}}
_CLUB_PURE_SHAPES = {'bytes_sha256': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])", 'text_sha256': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])", 'utf8_sha256': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Name(id='_value', ctx=Load()), attr='encode', ctx=Load()), args=[Constant(value='utf-8')], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])", 'canonical_sha256': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Name(id='digest', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]))], decorator_list=[], type_params=[])", 'canonical_inline_sha256': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Call(func=Attribute(value=Name(id='hashlib', ctx=Load()), attr='sha256', ctx=Load()), args=[Call(func=Attribute(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]), attr='encode', ctx=Load()), args=[], keywords=[])], keywords=[]), attr='hexdigest', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])", 'json_compact': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load()))]))], decorator_list=[], type_params=[])", 'json_compact_ascii': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='sort_keys', value=Constant(value=True)), keyword(arg='separators', value=Tuple(elts=[Constant(value=','), Constant(value=':')], ctx=Load())), keyword(arg='ensure_ascii', value=Constant(value=True))]))], decorator_list=[], type_params=[])", 'json_pretty_bytes': "FunctionDef(name='_pure', args=arguments(posonlyargs=[], args=[arg(arg='_value')], kwonlyargs=[], kw_defaults=[], defaults=[]), body=[Return(value=Call(func=Attribute(value=BinOp(left=Call(func=Attribute(value=Name(id='json', ctx=Load()), attr='dumps', ctx=Load()), args=[Name(id='_value', ctx=Load())], keywords=[keyword(arg='ensure_ascii', value=Constant(value=False)), keyword(arg='indent', value=Constant(value=2))]), op=Add(), right=Constant(value='\\n')), attr='encode', ctx=Load()), args=[], keywords=[]))], decorator_list=[], type_params=[])"}

def _club_copy_json(value, stack=None):
    kind=type(value)
    if kind in (str,int,float,bool,type(None)):return value
    if kind not in (list,tuple,dict):raise TypeError('Pure calculation accepts exact JSON builtins only')
    stack=set() if stack is None else stack
    if id(value) in stack:raise ValueError('Circular JSON input')
    stack.add(id(value))
    try:
        if kind is dict:
            if any(type(key) not in (str,int,float,bool,type(None)) for key in value):raise TypeError('Non-JSON pure mapping key')
            return {key:_club_copy_json(item,stack) for key,item in value.items()}
        result=[_club_copy_json(item,stack) for item in value]
        return tuple(result) if kind is tuple else result
    finally:stack.remove(id(value))

def _club_make_pure(function, row, raw, *, _hash=_club_hashlib.sha256, _dumps=json.dumps):
    tree=_club_ast.parse(raw);nodes=[n for n in tree.body if isinstance(n,_club_ast.FunctionDef) and n.name==function.__name__]
    if len(nodes)!=1:raise ValueError('Ambiguous finite pure declaration')
    node=nodes[0];lines=raw.decode().splitlines(True);source=''.join(lines[node.lineno-1:node.end_lineno]).encode()
    if _hash(source).hexdigest()!=row['source_sha256']:raise ValueError('Changed complete pure declaration')
    # Compare AST after only the declared parameter/function-name normalization.
    if node.decorator_list or len(node.args.args)!=1 or node.args.posonlyargs or node.args.kwonlyargs or node.args.vararg or node.args.kwarg or node.args.defaults or node.returns or node.args.args[0].annotation:raise ValueError('Impure declaration signature')
    parameter=node.args.args[0].arg
    class Normalize(_club_ast.NodeTransformer):
        def visit_Name(self,n):
            if n.id==parameter:n.id='_value'
            return n
    node=Normalize().visit(node);node.name='_pure';node.args.args[0].arg='_value'
    shape=_club_ast.dump(node,include_attributes=False)
    if shape!=row['shape'] or shape!=_CLUB_PURE_SHAPES.get(row['kind']):raise ValueError('Impure same-name function refused')
    code=function.__code__;kind=row['kind']
    @_club_wraps(function)
    def pure(*args,**kwargs):
        if function.__code__ is not code or function.__defaults__ is not None or function.__kwdefaults__ is not None:raise ValueError('Changed loaded pure function')
        if len(args)==1 and not kwargs:value=args[0]
        elif not args and set(kwargs)=={parameter}:value=kwargs[parameter]
        else:raise TypeError('Invalid pure calculation signature')
        if kind=='bytes_sha256':
            if type(value) not in (bytes,bytearray):raise TypeError('Exact byte input required')
            return _hash(bytes(value)).hexdigest()
        if kind in ('text_sha256','utf8_sha256'):
            if type(value) is not str:raise TypeError('Exact text input required')
            return _hash(value.encode('utf-8')).hexdigest()
        value=_club_copy_json(value)
        if kind=='json_pretty_bytes':return (_dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
        encoded=_dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True)
        if kind in ('canonical_sha256','canonical_inline_sha256'):return _hash(encoded.encode()).hexdigest()
        if kind in ('json_compact','json_compact_ascii'):return encoded
        raise ValueError('Unknown finite pure kind')
    return pure

def _club_guard_context(context):
    """Isolate imports and functions in this context's exact physical namespace.

    No process-global tools/Tests module, __import__, sys.path, Path, or filesystem
    operation is rebound. Each historical module has its own import builtins.
    """
    if getattr(context, '_club_e2b_guarded', False):
        context.verify()
        return context
    context.root = Path(context.root).absolute()
    expected = dict(context.file_sha256)
    if _club_tree_sha256(context.root) != expected:
        raise ValueError('Finite historical reader membership is incomplete')
    context.file_sha256 = _ClubMappingProxy(expected)
    namespace = '_club_e2b_' + digest(str(context.root).encode())[:24]
    modules = {}
    guarded_functions = {}
    guarded_managers = {}
    call_frame = _ClubContextVar('club_42f_reader_' + namespace, default=None)
    packages = {''}
    for relative in expected:
        if relative.endswith('.py'):
            parts = relative[:-3].split('/')
            for end in range(1, len(parts)):
                packages.add('.'.join(parts[:end]))
    native_import = _club_builtins.__import__

    def verify():
        _club_authenticate_raw()
        if _club_tree_sha256(context.root) != expected:
            raise ValueError('Finite club historical context changed')

    def guard_result(value):
        # pathlib paths retain their complete original value protocol.
        if isinstance(value, Path):
            return value
        if hasattr(value, 'root') and callable(getattr(value, 'load', None)):
            return _club_guard_context(value)
        # ContextDecorator instances are callable but must retain their context
        # manager protocol. Each enter/exit/decorator invocation remains an
        # authenticated reader boundary, including exceptional exits.
        if callable(getattr(value, '__enter__', None)) and callable(getattr(value, '__exit__', None)):
            saved = guarded_managers.get(id(value))
            if saved is not None and saved[0] is value:
                return saved[1]
            enter = guard_function(value.__enter__)
            leave = guard_function(value.__exit__)
            decorate = guard_function(value) if callable(value) else None
            class ContextBoundary:
                __slots__ = ()
                def __enter__(self):
                    return enter()
                def __exit__(self, kind, error, traceback):
                    return leave(kind, error, traceback)
                def __call__(self, *args, **kwargs):
                    if decorate is None:
                        raise TypeError('Historical context manager is not a decorator')
                    return decorate(*args, **kwargs)
            proxy = ContextBoundary()
            guarded_managers[id(value)] = (value, proxy)
            guarded_managers[id(proxy)] = (proxy, proxy)
            return proxy
        # Returned closures, bound methods and callable objects may be invoked
        # after their creating reader has exited. Preserve the raw boundary.
        if callable(value) and not _club_inspect.isclass(value):
            return guard_function(value)
        return value

    def guard_function(function):
        saved = guarded_functions.get(id(function))
        if saved is not None and saved[0] is function:
            return saved[1]
        @_club_wraps(function)
        def checked(*args, **kwargs):
            frame = call_frame.get()
            outermost = frame is None
            if outermost:
                verify()
                frame = {'active': True, 'owner': _club_transaction_owner()}
                token = call_frame.set(frame)
            elif not frame['active'] or frame['owner'] != _club_transaction_owner():
                raise ValueError('Expired or foreign historical reader call frame')
            try:
                result = function(*args, **kwargs)
            finally:
                if outermost:
                    frame['active'] = False
                    call_frame.reset(token)
                    verify()
            return guard_result(result)
        # Keep one wrapper per callable identity, including already-bound
        # readers; do not trust caller-mutable function marker attributes.
        guarded_functions[id(function)] = (function, checked)
        guarded_functions[id(checked)] = (checked, checked)
        return checked

    def load_name(local):
        if local in modules:
            return modules[local]
        relative = local.replace('.', '/') + '.py'
        is_package = local in packages
        init = (local.replace('.', '/') + '/' if local else '') + '__init__.py'
        if is_package:
            relative = init if init in expected else None
        elif relative not in expected:
            raise ModuleNotFoundError('Module outside finite e2b namespace: ' + local)
        qualified = namespace + ('.' + local if local else '')
        module = _ClubModule(qualified)
        module.__package__ = qualified if is_package else qualified.rpartition('.')[0]
        if is_package:
            module.__path__ = [str(context.root / local.replace('.', '/'))]
        modules[local] = module
        _club_sys.modules[qualified] = module
        if local:
            parent, _, child = local.rpartition('.')
            setattr(load_name(parent), child, module)
        if relative is not None:
            module.__file__ = str(context.root / relative)
            module.__builtins__ = context.builtins
            raw = (context.root / relative).read_bytes()
            if digest(raw) != expected[relative]:
                raise ValueError('Changed exact physical historical module: ' + relative)
            exec(compile(raw, module.__file__, 'exec'), module.__dict__)
            for attribute, value in tuple(vars(module).items()):
                if _club_inspect.isfunction(value) and value.__module__ == qualified:
                    row = _CLUB_PURE_ROWS.get((relative, attribute))
                    wrapped = _club_make_pure(value, row, raw) if row is not None else guard_function(value)
                    setattr(module, attribute, wrapped)
                    if row is not None:
                        guarded_functions[id(wrapped)] = (wrapped, wrapped)
        return module

    def local_name(name):
        if name == namespace:
            return ''
        if name.startswith(namespace + '.'):
            return name[len(namespace) + 1:]
        if name == 'tools' or name.startswith('tools.') or name == 'Tests' or name.startswith('Tests.'):
            return name
        candidate = 'tools/' + name.replace('.', '/') + '.py'
        if candidate in expected:
            return 'tools.' + name
        candidate = 'tools.' + name
        if candidate in packages:
            return candidate
        if name.split('.')[0] in _CLUB_LOCAL_TOOL_NAMES:
            raise ModuleNotFoundError('Historical tool missing from finite e2b inputs: ' + name)
        return None

    def isolated_import(name, globals=None, locals=None, fromlist=(), level=0):
        absolute = (_club_import_util.resolve_name('.' * level + name,
                    (globals or {}).get('__package__', '')) if level else name)
        local = local_name(absolute)
        if local is None:
            result = native_import(name, globals, locals, fromlist, level)
            source = getattr(result, '__file__', None)
            if source and Path(source).resolve().is_relative_to(_CLUB_CURRENT_ROOT):
                raise ImportError('Process-global current module is not a historical dependency: ' + name)
            return result
        module = load_name(local)
        if fromlist:
            for member in fromlist:
                child = local + '.' + member if local else member
                if member != '*' and (child in packages or child.replace('.', '/') + '.py' in expected):
                    load_name(child)
            return module
        # Match Python's __import__ return convention for "import tools.x";
        # bare historical tools imports return their actual local module.
        if level or absolute.startswith(namespace + '.'):
            return module
        if absolute.startswith(('tools.', 'Tests.')):
            return load_name(absolute.split('.')[0])
        return module

    context.builtins = dict(vars(_club_builtins), __import__=isolated_import)
    context.verify = verify
    def load(relative, name=None):
        verify()
        if relative not in expected or not relative.endswith('.py'):
            raise ValueError('Historical module outside finite approved club inputs')
        result = load_name(relative[:-3].replace('/', '.'))
        verify()
        return result
    context.load = load
    context._club_e2b_guarded = True
    load_name('')
    return context


def club_original_current_context(root=_CLUB_CURRENT_ROOT):
    """Build/cache the finite physical e2b input only after actual-current checks."""
    global _club_context_cache
    root = _club_exact_current_root(root)
    if _club_context_cache is not None:
        _club_context_cache.verify()
        return _club_context_cache
    rows = _club_authenticate_raw(root, collect=True)
    # Callers may set TMPDIR to an authorized RAM-backed location. No repository
    # hardlinks, current fallback bytes, or broad repository copy are permitted.
    life = _club_tempfile.TemporaryDirectory(prefix='club-e2b-reader-')
    target = Path(life.name) / 'source'
    try:
        target.mkdir()
        for relative, raw in rows.items():
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw)
        if _club_tree_sha256(target) != _CLUB_E2B_SHA256:
            raise ValueError('Exact finite e2b physical input differs')
        context = _ClubNamespace(root=target, lifetime=life,
                                 file_sha256=dict(_CLUB_E2B_SHA256))
        context = _club_guard_context(context)
        context.verify()
    except BaseException:
        life.cleanup()
        raise
    _club_context_lives.append(life)
    _club_context_cache = context
    return context


def club_authenticated_test_case(case):
    """Keep original test bodies intact with actual-current pre/post boundaries."""
    for name, function in tuple(vars(case).items()):
        if name.startswith('test_') and _club_inspect.isfunction(function):
            def wrap(original):
                @_club_wraps(original)
                def checked(*args, **kwargs):
                    with club_authenticated_transaction():
                        _club_authenticate_raw()
                        try:
                            return original(*args, **kwargs)
                        finally:
                            _club_authenticate_raw()
                return checked
            setattr(case, name, wrap(function))
    return case


_club_atexit.register(lambda: [life.cleanup() for life in _club_context_lives])


def club_bind_creator_rejection_structure(case):
    """Bind only the original rejection-layer structure assertion to exact e2b.

    The other thirteen methods remain on the actual current module and sources.
    Actual-current authentication still precedes every historical reader call.
    """
    name = 'test_original_successful_function_body_and_all_old_tests_are_preserved'
    original = vars(case).get(name)
    if case.__name__ != 'CreatorFixtureRejectionTests' or not _club_inspect.isfunction(original):
        raise ValueError('Unknown exact creator structure assertion binding')
    @_club_wraps(original)
    def checked(*args, **kwargs):
        with club_authenticated_transaction():
            context = club_original_current_context()
            context.verify()
            historical = context.load('tools/tests/test_creator_history_fixture_rejection.py')
            function = getattr(historical.CreatorFixtureRejectionTests, name)
            try:
                return function(*args, **kwargs)
            finally:
                context.verify()
    setattr(case, name, checked)
    return case

# Explicit P044 historical source context, after authenticating the actual P045 files.
_club_keyword_cache = None
_club_keyword_lives = []
_CLUB_KEYWORD_INPUTS = {'App/ClubGovernanceViews.swift': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5'}


def club_keyword_context(root=_CLUB_CURRENT_ROOT):
    global _club_keyword_cache
    root = _club_exact_current_root(root)
    _club_authenticate_raw(root)
    expected = _CLUB_KEYWORD_INPUTS
    if _club_keyword_cache is not None:
        target = _club_keyword_cache
        if _club_tree_sha256(target) != expected:
            raise ValueError('Finite historical keyword context changed')
        return target
    registration = _club_registration()
    life = _club_tempfile.TemporaryDirectory(prefix='club-keyword-42f-')
    target = Path(life.name)
    try:
        for relative, pinned in expected.items():
            current = (root / relative).read_bytes()
            raw = registration.club_predecessor_source(relative, current)
            if not isinstance(raw, bytes) or digest(raw) != pinned:
                raise ValueError('Complete keyword predecessor differs: ' + relative)
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw)
        if _club_tree_sha256(target) != expected:
            raise ValueError('Finite historical keyword context differs')
        _club_authenticate_raw(root)
    except BaseException:
        life.cleanup()
        raise
    _club_keyword_lives.append(life)
    _club_keyword_cache = target
    return target


def club_authenticated_keyword_test_case(case):
    for name, function in tuple(vars(case).items()):
        if name.startswith('test_') and _club_inspect.isfunction(function):
            def wrap(original):
                @_club_wraps(original)
                def checked(*args, **kwargs):
                    club_keyword_context()
                    try:
                        return original(*args, **kwargs)
                    finally:
                        club_keyword_context()
                return checked
            setattr(case, name, wrap(function))
    return case


_club_atexit.register(lambda: [life.cleanup() for life in _club_keyword_lives])
