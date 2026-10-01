import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('importer',pathlib.Path(__file__).parents[1]/'import_arb_catalog.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ImportTests(unittest.TestCase):
    def test_literal_pair_remains_review_candidate(self):
        catalog,review=module.convert({'ok':'OK'},{'ok':'确定'},['ok'])
        self.assertFalse(review)
        unit=catalog['strings']['ok']['localizations']['en']['stringUnit']
        self.assertEqual(unit,{'state':'needs_review','value':'OK'})
    def test_icu_is_never_flattened(self):
        catalog,review=module.convert({'count':'{n, plural, one{one} other{many}}'},{'count':'{n}个'},['count'])
        self.assertFalse(catalog['strings']);self.assertEqual(len(review),1)
    def test_metadata_placeholders_and_percent_are_queued(self):
        catalog,review=module.convert({'a':'name','@a':{'placeholders':{'user':{}}},'b':'100%'},{'a':'姓名','b':'100%'},['a','b'])
        self.assertFalse(catalog['strings']);self.assertEqual(len(review),2)
    def test_missing_locale_is_queued(self):
        catalog,review=module.convert({'a':'Name'},{},['a'])
        self.assertFalse(catalog['strings']);self.assertEqual(review[0]['reason'],'missing-or-empty-locale')
    def test_metadata_keys_are_rejected(self):
        with self.assertRaises(ValueError): module.convert({}, {}, ['@@locale'])
    def test_duplicate_keys_are_deduplicated(self):
        catalog,_=module.convert({'a':'A'},{'a':'甲'},['a','a'])
        self.assertEqual(len(catalog['strings']),1)
if __name__=='__main__':unittest.main()
