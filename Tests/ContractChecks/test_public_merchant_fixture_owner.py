from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PublicMerchantFixtureOwnerChecks(unittest.TestCase):
 def test_synthetic_host_retains_transport_session_and_journal_in_swiftui_state(self):
  source=(ROOT/'App/PublicMerchantHomeFixtureView.swift').read_text()
  self.assertTrue(source.startswith('#if DEBUG'))
  view=source.split('struct PublicMerchantHomeFixtureView',1)[1].split('final class PublicMerchantHomeFixtureState',1)[0]
  self.assertIn('@State private var fixture: PublicMerchantHomeFixtureState',view)
  self.assertIn('_fixture = State(initialValue: PublicMerchantHomeFixtureState(scenario: scenario))',view)
  self.assertIn('let transport = fixture.transport, configuration = fixture.configuration',view)
  self.assertIn('let session = fixture.session, journal = fixture.journal',view)
  self.assertNotIn('private let transport:',view)
  self.assertNotIn('PublicMerchantHomeFixtureTransport(scenario:',view)
  self.assertIn('Button("Change fixture session") { featuredScope = UUID() }',view)
  self.assertIn('requests > 1 ? 602 : 601',source)
 def test_optional_hosted_owner_probe_is_synthetic_and_noninteractive(self):
  source=(ROOT/'App/PublicMerchantHomeFixtureView.swift').read_text()
  self.assertIn('ownerObserver: ((PublicMerchantHomeFixtureState) -> Void)? = nil',source)
  self.assertIn('if let ownerObserver {',source)
  self.assertIn('.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)',source)
  probe=source.split('struct PublicMerchantHomeFixtureOwnerProbe',1)[1].split('final class PublicMerchantHomeFixtureTransport',1)[0]
  for forbidden in ['URLSession','transport.send','Task {','Button(']:self.assertNotIn(forbidden,probe)
  self.assertIn('func updateUIView(_ uiView: UIView, context: Context) { observe(owner) }',probe)
 def test_real_readers_and_actual_swiftui_parent_reconstruction_are_authored(self):
  source=(ROOT/'Tests/AppUnitTests/PublicMerchantFixtureOwnershipTests.swift').read_text()
  for name in ['testReaderReconstructionRetriesSameSyntheticRequestSequence','testChangingReadScopeKeepsCounterAndReturnsNewExactFeaturedID','testSeparateMountedFixtureOwnersDoNotShareFirstRequestState','testActualHostedParentRedrawRetainsTransportSessionAndJournalOwner']:
   self.assertIn('func '+name,source)
  self.assertIn('UIHostingController(rootView: Host(',source)
  self.assertIn('refresh.revision += 1',source)
  self.assertIn('XCTAssertTrue(current === original)',source)
  self.assertIn('.activity(601)',source);self.assertIn('.activity(602)',source)
if __name__=='__main__':unittest.main()
