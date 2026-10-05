"""Run template-assist source contracts in the ordinary CI discovery suite."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('merchant_template_assist_source_checks', ROOT / 'tools/check_merchant_template_assist.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
MerchantTemplateAssistSourceTests = module.MerchantTemplateAssistSourceTests
