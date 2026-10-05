"""Reconstruct pre-P057 timing evidence for historical budget assertions only.

Current planning always uses the complete live inventory and profile. These
helpers undo only the explicitly identified P057 additions/observation replacement.
"""
from copy import deepcopy
from decimal import Decimal

METHOD = 'ClubGovernanceFlowTests.testClubStoryUsesOwnRouteAndProtectedAnswer'
CLASSES = {'ClubStoryFlowTests', 'ClubStoryNavigationFlowTests'}


def before_club_story(profile):
    result = deepcopy(profile)
    replan = result['planning_budget'].pop('club_story_replan')
    methods = set(replan['new_methods']) | {METHOD}
    for method in methods:
        del result['estimated_method_seconds'][method]
    result['estimate_provenance']['methods'] = [record for record in result['estimate_provenance']['methods']
                                              if record['method'] not in methods]
    observations = [record for record in result['superseded_method_observations'] if record['method'] == METHOD]
    if len(observations) != 1 or METHOD in result['method_seconds']:
        raise AssertionError('Ambiguous superseded P057 observation')
    result['method_seconds'][METHOD] = observations[0]['seconds']
    result['superseded_method_observations'] = [record for record in result['superseded_method_observations']
                                              if record['method'] != METHOD]
    return result


def before_club_story_costs(costs, profile):
    result = dict(costs)
    for case in CLASSES:
        del result[case]
    prior = before_club_story(profile)
    delta = Decimal(str(profile['estimated_method_seconds'][METHOD])) - Decimal(str(prior['method_seconds'][METHOD]))
    result['ClubGovernanceFlowTests'] -= float(delta)
    return result
