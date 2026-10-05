"""Nearby-team supplementary source checks, not Swift runtime evidence."""
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('nearby_team_source', Path(__file__).resolve().parents[2] / 'tools/check_nearby_team_module.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
NearbySourceChecks = module.NearbySourceChecks
