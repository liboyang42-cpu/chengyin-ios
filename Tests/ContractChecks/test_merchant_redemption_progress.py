import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class RedemptionProgressContract(unittest.TestCase):
    def test_normal_noncompact_host(self):
        text=(ROOT/'App/MerchantBusinessRecordViews.swift').read_text()
        self.assertIn('if row.kind == .redemption, !compact,\n           let progress = MerchantRedemptionProgress(record: row, access: access)',text)
        self.assertIn('MerchantRedemptionProgressView(progress: progress)',text)
        self.assertIn('MerchantPersonalIncomeEntry(row: row',text)
    def test_permission_and_projection_gates(self):
        text=(ROOT/'Core/MerchantRedemptionProgress.swift').read_text()
        for token in ['access.allows("merchant:finance:read")','record.kind == .redemption','"CHAPTER_OFFER"','fields.mbText("settlementState")','fields.mbText("displayState")']:self.assertIn(token,text)
    def test_state_not_time_controls_progress(self):
        text=(ROOT/'Core/MerchantRedemptionProgress.swift').read_text()
        for token in ['switch settlement','"SETTLED", "ADJUSTED", "ADJUSTMENT_PENDING"','default: done = 1; current = false','state == .done ?']:self.assertIn(token,text)
        for token in ['Date()', 'addingTimeInterval', 'URLSession','sendRequest','settlementAmount']:self.assertNotIn(token,text)
    def test_existing_timestamp_display_and_native_cases(self):
        view=(ROOT/'App/MerchantRedemptionProgressView.swift').read_text()
        self.assertIn('MerchantSettlementTimestampText(raw: raw)',view)
        self.assertNotIn('Button',view)
        self.assertNotIn('@State',view)
        tests=(ROOT/'Tests/CoreTests/MerchantRedemptionProgressTests.swift').read_text()
        self.assertEqual(tests.count('func test'),8)
if __name__=='__main__':unittest.main()
