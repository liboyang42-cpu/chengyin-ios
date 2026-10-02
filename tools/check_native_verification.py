#!/usr/bin/env python3
"""Static native verification contracts, never runtime/Apple acceptance."""
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
def read(path):return (r/path).read_text()
core=read('Core/NativeVerificationWorkflow.swift')
assert 'reader.canExecuteSyntheticMutation && redemption != nil' in core
assert 'value.scope == reader.scope' in core and 'now() < value.expiresAt' in core
assert 'redemption.begin(value.context, expectedMerchantID: value.merchantID)' in core
assert 'private let journal: any MerchantBusinessIntentStore' in core
assert '$0.target == "redemption"' in core
assert 'journal.complete' not in core
assert 'guard phase == .reviewing else' in core
redemption=read('Core/MerchantRedemptionContext.swift')
assert 'code.hasPrefix("cq1.")' in redemption
assert 'self.generation == generation' in redemption
assert 'expectedMerchantID == access.merchantID' in redemption
assert 'registrationMerchantId' in redemption and 'station.id' not in redemption
ui=read('App/NativeVerificationView.swift')
for text in ['NativeQRScanner', '.sheet(item:', 'flow.prepareChoice(choice.target)', 'flow.deactivate()', 'privacySensitive', 'raw = ""', 'cameraEnabled: false']:
 assert text in ui,text
assert 'SessionNativeVerificationView()' in read('App/PlayerJourneyViews.swift')
assert 'nativeVerificationDestination' in read('App/AccountView.swift')
support=read('Core/ParticipationSupport.swift')
assert 'approvedURLs.contains(url)' in support and 'parts.query == nil' in support
assert 'configuration: ParticipationSupportConfiguration? = nil' in read('App/ParticipationSupportView.swift')
fixture=read('App/NativeVerificationFixtureView.swift')
assert fixture.startswith('#if DEBUG') and 'verification.test' in fixture
assert '--native-verification-fixture' in read('App/QuestifyApp.swift')
strings=json.loads(read('Resources/Localizable.xcstrings'))['strings']
for prefix in ['verification.', 'participationSupport.']:
 keys=[k for k in strings if k.startswith(prefix)]; assert keys
 assert all(all(loc in strings[k]['localizations'] for loc in ['en','zh-Hans']) for k in keys)
print('PASS: exact dormant verification flow, frozen review/store, lifecycle/replay locks, native entries, optional configured support, synthetic fixture, bilingual keys')
print('Swift tests, Apple compile, visual/accessibility, camera and backend/provider acceptance: NOT_RUN')
