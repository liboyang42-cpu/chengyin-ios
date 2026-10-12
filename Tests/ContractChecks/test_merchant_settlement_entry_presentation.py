import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class SettlementEntryContract(unittest.TestCase):
    def test_batch_only_host(self):
        text=(ROOT/'App/MerchantBusinessViews.swift').read_text()
        self.assertIn('settlementEntries: { if case .batch = query { return true }; return false }()',text)
        self.assertEqual(text.count('settlementEntries:'),1)
    def test_raw_fields_and_scope_retained(self):
        text=(ROOT/'App/MerchantBusinessRecordViews.swift').read_text()
        self.assertIn('var settlementEntries = false',text)
        self.assertIn('if settlementEntries, row.kind == .entry, key == "signedAmount"',text)
        self.assertIn('case .entry: return ["entryKind", "settlementRoute", "source", "destination", "signedAmount"',text)
        self.assertIn('merchant.settlementEntry.meaning',text)
        self.assertIn('merchant.business.amountPending',text)
    def test_no_recalculation_or_requests(self):
        text=(ROOT/'Core/MerchantSettlementEntryPresentation.swift').read_text()
        self.assertIn('strictString: true',text)
        self.assertIn('raw.utf8.contains',text)
        for token in ['Double(', 'Float(', 'Decimal(', 'URLSession', 'sendRequest', '.reduce(']:self.assertNotIn(token,text)
    def test_all_semantics_and_native_boundaries_authored(self):
        core=(ROOT/'Core/MerchantSettlementEntryPresentation.swift').read_text()
        for token in ['REVERSAL','CLAWBACK','REDEMPTION_FEE','COOP_SHARE','ACTIVITY_SHARE']:self.assertIn(token,core)
        native=(ROOT/'Tests/CoreTests/MerchantSettlementEntryPresentationTests.swift').read_text()
        self.assertEqual(native.count('func test'),7)
if __name__=='__main__':unittest.main()
