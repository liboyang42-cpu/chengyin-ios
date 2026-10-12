import pathlib,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[2]
class LedgerNetContracts(unittest.TestCase):
    def setUp(self): self.s=(ROOT/'Core/MerchantLedgerNetPresentation.swift').read_text()
    def test_no_financial_recalculation(self):
        self.assertIn('MerchantBusinessMoney(value, strictString: true)',self.s)
        self.assertIn('amount = money.display',self.s)
        for t in ['Double(','Float(','Decimal(','personalArrivedThisMonthGross','sendRequest','URLRequest']:self.assertNotIn(t,self.s)
    def test_sign_zero_and_pending(self):
        self.assertIn('raw.hasPrefix("-") && nonzero',self.s)
        self.assertIn('kind = .pending; amount = nil',self.s)
        self.assertIn('raw.utf8.contains',self.s)
    def test_narrow_normal_overview_host(self):
        h=(ROOT/'App/MerchantBusinessViews.swift').read_text()
        self.assertIn('document.query == .overview, key == "personalArrivedThisMonthNet"',h)
        self.assertIn('!document.summary.isEmpty || document.query == .overview',h)
        self.assertIn('MerchantLedgerNetSummary(presentation: .init(value: document.summary[key]))',h)
    def test_exact_amount_and_labels(self):
        v=(ROOT/'App/MerchantLedgerNetSummary.swift').read_text()
        self.assertIn('Text(verbatim: amount)',v)
        self.assertIn('merchant.business.field.personalArrivedThisMonthNet',v)
        self.assertIn('merchant.business.amountPending',v)
        f=json.loads((ROOT/'Resources/MerchantLedgerNetLocalizations.fragment.json').read_text())
        self.assertEqual(len(f),3)
        for x in f.values():self.assertEqual(set(x['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
