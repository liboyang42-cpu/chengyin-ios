"""Structural connection checks only, not Swift overload-resolution execution."""
from pathlib import Path
import re,unittest
R=Path(__file__).resolve().parents[2]
class GrowthNormalSelectionChecks(unittest.TestCase):
 def test_concrete_child_initializer_selects_anonymous_without_recursion(self):
  source=(R/'App/GrowthNormalReadCompositionTransport.swift').read_text()
  extension=source.split('extension GrowthCenterService {',1)[1]
  self.assertIn('init(configuration: APIConfiguration, transport: GrowthNormalReadTransport)',extension)
  self.assertIn('transport: transport as any HTTPTransport',extension)
  self.assertIn('leaderboardContract: .anonymous',extension)
  self.assertNotIn('GrowthNormalReadApproval(',extension)
 def test_normal_caller_retains_concrete_child_type(self):
  root=(R/'App/AppCompositionRoot.swift').read_text()
  session=(R/'App/AppSession.swift').read_text()
  self.assertRegex(root,r'func growthNormalReadTransport\([^\n]+\) -> GrowthNormalReadTransport')
  self.assertIn('let transport = transport.growthNormalReadTransport(approval: composition.growthNormalReadApproval)\n                growthCenterService=GrowthCenterService(configuration:configuration,transport:transport)',session)
 def test_generic_initializer_keeps_legacy_and_routes_stay_closed(self):
  core=(R/'Core/GrowthCenterService.swift').read_text()
  self.assertIn('transport: any HTTPTransport,',core)
  self.assertIn('leaderboardContract: GrowthLeaderboardReadContract = .legacy',core)
  gate=(R/'Core/GrowthNormalReadTransport.swift').read_text()
  self.assertEqual(re.findall(r'case \w+ = "(api/[^"\s]+)"',gate),['api/growth/center','api/play/growth','api/play/my-completed'])
 def test_native_checks_cover_selection_compatibility_and_no_wire(self):
  tests=(R/'Tests/AppUnitTests/GrowthNormalContractSelectionTests.swift').read_text()
  self.assertEqual(tests.count('func test'),3)
  for phrase in ['case .anonymous?','case .legacy?','XCTAssertEqual(wire.count, 0)']:self.assertIn(phrase,tests)
if __name__=='__main__':unittest.main()
