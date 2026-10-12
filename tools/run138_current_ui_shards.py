"""Current-only UI units: retain whole classes except six independently reset classes.

Every split unit remains one complete XCTest method, including its own setUp and
tearDown. No historical source, cost, method exception or partition is modified.
"""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re

SPLIT_CLASSES = frozenset({
    'MerchantTemplateRuleStepsFlowTests', 'MerchantTemplateHintsFlowTests',
    'MerchantTemplateStoryTimelineFlowTests', 'MerchantTemplateCategoryFlowTests',
    'MerchantStoreIndustryFlowTests', 'MerchantRegistrationAvailabilityFlowTests',
})
METHOD_LIMIT = 900
SHARD_LIMIT = 1500
MINIMUM_SHARDS = 79


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_inventory(directory):
    result = {}
    for path in sorted(Path(directory).glob('*.swift')):
        text = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
        if not methods:
            continue
        owners = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
        if len(owners) != 1 or len(methods) != len(set(methods)) or owners[0] in result:
            raise ValueError('Ambiguous complete XCTest method inventory')
        result[owners[0]] = sorted(owners[0] + '/' + method for method in methods)
    return result


def execution_units(class_costs, inventory, product_budget):
    if set(class_costs) != set(inventory):
        raise ValueError('Class costs omit or invent an actual test class')
    if {name for name, cost in class_costs.items() if cost > SHARD_LIMIT} != SPLIT_CLASSES:
        raise ValueError('Changed current oversized-class allowlist')
    units, expansion = {}, {}
    for name, cost in sorted(class_costs.items()):
        if type(cost) not in (int, float) or not math.isfinite(cost) or cost <= 0:
            raise ValueError('Invalid complete-class cost')
        methods = inventory[name]
        if not methods or len(methods) != len(set(methods)):
            raise ValueError('Empty or duplicated class methods')
        if name not in SPLIT_CLASSES:
            units[name], expansion[name] = cost, methods
            continue
        rows = {key.replace('.', '/', 1): row for key, row in product_budget['methods'].items()
                if key.split('.')[0] == name}
        if set(rows) != set(methods):
            raise ValueError('Split class lacks an exact complete-method cost')
        total = 0
        for method in methods:
            row = rows[method]
            seconds = row['seconds']
            if (row['existing_method_increment'] is not False or row['measured'] is not False
                    or type(seconds) not in (int, float) or not math.isfinite(seconds)
                    or not 0 < seconds <= METHOD_LIMIT):
                raise ValueError('Only complete source-bound <=900-second methods may split')
            units[method], expansion[method] = seconds, [method]
            total += seconds
        if not math.isclose(total, cost, rel_tol=0, abs_tol=1e-9):
            raise ValueError('Split methods lost part of their original class allowance')
    return units, expansion


def partition(units, count):
    if type(count) is not int or not 1 <= count <= len(units):
        raise ValueError('Invalid current UI shard count')
    groups, totals = [[] for _ in range(count)], [0] * count
    for name, seconds in sorted(units.items(), key=lambda row: (-row[1], row[0])):
        target = min(range(count), key=lambda index: (totals[index], index))
        groups[target].append(name)
        totals[target] += seconds
    return groups


def validate_partition(groups, units, expansion, inventory):
    if not isinstance(groups, list) or not groups or any(not isinstance(g, list) or not g for g in groups):
        raise ValueError('Missing or empty current UI shard')
    selected = [unit for group in groups for unit in group]
    if Counter(selected) != Counter({unit: 1 for unit in units}) or set(expansion) != set(units):
        raise ValueError('Missing, repeated or foreign current execution unit')
    methods = [method for unit in selected for method in expansion[unit]]
    expected = [method for values in inventory.values() for method in values]
    if len(expected) != len(set(expected)) or Counter(methods) != Counter({m: 1 for m in expected}):
        raise ValueError('Current methods must run exactly once, without class/method overlap')
    loads = [sum(units[unit] for unit in group) for group in groups]
    if any(not math.isfinite(cost) or not 0 < cost <= SHARD_LIMIT for cost in loads):
        raise ValueError('Current UI shard exceeds unchanged 1500-second allowance')
    return loads


def make_plan(class_costs, inventory, product_budget):
    units, expansion = execution_units(class_costs, inventory, product_budget)
    for count in range(MINIMUM_SHARDS, len(units) + 1):
        groups = partition(units, count)
        if max(sum(units[u] for u in g) for g in groups) <= SHARD_LIMIT:
            break
    else:
        raise ValueError('No bounded current UI partition')
    loads = validate_partition(groups, units, expansion, inventory)
    return {'version': 1, 'measured': False, 'method_limit_seconds': METHOD_LIMIT,
            'shard_limit_seconds': SHARD_LIMIT, 'startup_reserve_seconds': 300,
            'split_classes': sorted(SPLIT_CLASSES), 'class_count': len(class_costs),
            'method_count': sum(map(len, inventory.values())), 'unit_seconds': units,
            'unit_methods': expansion, 'shards': groups, 'shard_count': count,
            'shard_seconds': loads,
            'shard_method_counts': [sum(len(expansion[u]) for u in g) for g in groups]}


def current_plan(class_costs, root):
    from tools import run138_editor_readiness as readiness
    root = Path(root)
    c = readiness.contract(root)
    inventory = source_inventory(root / 'Tests/AppUITests')
    plan = make_plan(class_costs, inventory, c['product_ui_budget'])
    expected = c['current_ui_sharding']
    if (canonical(plan) != expected['plan_sha256'] or plan['shard_count'] != c['shard_count']
            or plan['split_classes'] != expected['split_classes']
            or plan['method_count'] != c['method_count'] or plan['class_count'] != c['class_count_after']):
        raise ValueError('Actual current UI plan differs from authenticated planning contract')
    return plan
