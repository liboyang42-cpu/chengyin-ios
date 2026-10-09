"""Standalone CI138 driver inverse and cost proposal; not an active planner.

The scheduling editor must integrate a reviewed layer explicitly. This module
does not edit historical contracts, profiles, workflow gates, or timing evidence.
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'docs/ci138-coupon-square-publication-driver-contract.json'
CONTRACT_SHA256 = '8ccc5a48dbf17ba5ddbfbf4bf96ff3f92e5c51c725c38dd408511e2d428c0f14'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def contract():
    raw = CONTRACT.read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed CI138 driver contract')
    return json.loads(raw)


def previous_source(relative_path, current):
    """Invert only exact reviewed postimages; reject partial/unknown mutations."""
    row = contract()['files'].get(relative_path)
    if row is None or digest(current) != row['after_sha256']:
        raise ValueError('Unknown current CI138 driver source')
    original = current
    for span in reversed(row['inverse_spans']):
        after = span['after'].encode('utf-8')
        before = span['before'].encode('utf-8')
        if not after or original.count(after) != 1:
            raise ValueError('Missing or ambiguous exact inverse span')
        original = original.replace(after, before, 1)
    if digest(original) != row['before_sha256']:
        raise ValueError('CI138 original source was not restored exactly')
    return original


def validate_current(root=ROOT):
    root = Path(root)
    if (root / "Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift").exists():
        try:
            from run138_current_source_projection import validate_coupon_component
        except ModuleNotFoundError:
            from tools.run138_current_source_projection import validate_coupon_component
        return validate_coupon_component(root)
    c = contract()
    for relative_path in c['files']:
        previous_source(relative_path, (root / relative_path).read_bytes())
    for relative_path, expected in c['protected_source_sha256'].items():
        if digest((root / relative_path).read_bytes()) != expected:
            raise ValueError('CI138 shared helper, production, or old planning source changed')
    return c


def complete_method_costs():
    """Return proposed whole-method floors without changing the active profile."""
    c = contract()
    assumptions = c['cost_assumptions']
    iteration_cost = assumptions['reveal_iterations'] * assumptions['reveal_iteration_seconds']
    if assumptions['reveal_iterations'] != assumptions['maximum_swipes'] + 1:
        raise ValueError('Reveal attempt bound is inconsistent')
    result = {}
    for method, row in c['complete_method_costs'].items():
        if method.startswith('OwnedCouponCodeJourneyUITests.'):
            extra = sum(assumptions[key] for key in (
                'coupon_native_cancel_resolution_allowance_seconds', 'coupon_dismissed_wait_seconds',
                'coupon_geometry_query_allowance_seconds'))
        else:
            extra = row['reveal_calls'] * iteration_cost
            if method.startswith('ApprovedTopicFrozenCoverPublicationFlowTests.'):
                extra += assumptions['publication_existence_wait_seconds']
        rounded = math.ceil((row['historical_seconds'] + extra) / assumptions['round_up_seconds']) * assumptions['round_up_seconds']
        if (row['measured'] is not False or extra != row['additional_seconds']
                or rounded != row['candidate_seconds'] or rounded < row['historical_seconds']):
            raise ValueError('CI138 complete-method cost derivation changed')
        result[method] = rounded
    return result


if __name__ == '__main__':
    validate_current()
    print(json.dumps({'status': 'CANDIDATE_ONLY', 'apple_execution': 'NOT_RUN',
                      'complete_method_costs': complete_method_costs()}, indent=2))
