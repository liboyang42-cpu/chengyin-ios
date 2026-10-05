"""Supplementary adapter source checks; no Swift/runtime execution."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('nearby_write_repair',Path(__file__).resolve().parents[2]/'tools/check_nearby_write_repair.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
NearbyWriteRepairChecks=module.NearbyWriteRepairChecks
