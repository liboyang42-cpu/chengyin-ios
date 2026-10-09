"""Owned exact inverses for approved follow-on drivers and Review availability.

These leaf inverses never replace full current admission or invent timing data.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]


def story():
    try:
        from . import story_reveal_arrival_inverse as value
    except ImportError:
        import story_reveal_arrival_inverse as value
    return value


def remaining():
    try:
        from . import remaining_editor_drivers_inverse as value
    except ImportError:
        import remaining_editor_drivers_inverse as value
    return value


def coupon():
    try:
        from . import ci138_coupon_square_publication_driver as value
    except ImportError:
        import ci138_coupon_square_publication_driver as value
    return value


def availability():
    try:
        from . import review_availability_inverse as value
    except ImportError:
        import review_availability_inverse as value
    return value


def story_paths():
    return {'Tests/AppUITests/ProjectStoryMediaGapFlowSupport.swift', 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'}


def remaining_paths():
    return {'Tests/AppUITests/ProjectStoryAudioRecoveryFlowTests.swift', 'Tests/AppUITests/ApprovedTopicReviewPersistenceFlowTests.swift'}


def coupon_paths():
    return {'Tests/AppUITests/ApprovedTopicFrozenCoverPublicationFlowTests.swift', 'Tests/AppUITests/OwnedCouponCodeJourneyUITests.swift', 'Tests/AppUITests/SquareWorkspaceFlowTests.swift'}


def owned_ui_paths():
    return story_paths() | remaining_paths() | coupon_paths()


def source_before_followons(relative, raw):
    if relative == 'Questify.xcodeproj/project.pbxproj':
        try:
            from .run138_current_source_projection import original_description_bytes
        except ImportError:
            from run138_current_source_projection import original_description_bytes
        return original_description_bytes(relative, raw)
    if relative in story_paths():
        return story().inverse(relative, raw)
    if relative in remaining_paths():
        return remaining().inverse(relative, raw)
    if relative in coupon_paths():
        return coupon().previous_source(relative, raw)
    return raw


def historical_app_source(relative, raw, root=ROOT):
    plan = availability().contract()['scope']
    if relative not in plan:
        return raw
    value = raw.encode() if isinstance(raw, str) else raw
    if hashlib.sha256(value).hexdigest() == plan[relative]['before_sha256']:
        return raw
    return availability().original_source(relative, raw, root)


def validate_owned_ui(directory, root=ROOT):
    directory = Path(directory)
    if ({row['path'] for row in story().contract()['changes']} != story_paths()
            or {row['path'] for row in remaining().contract()['changes']} != remaining_paths()
            or set(coupon().contract()['files']) != coupon_paths()):
        raise ValueError('Follow-on owned source scope changed')
    for relative in owned_ui_paths():
        source_before_followons(relative, (directory / Path(relative).name).read_bytes())
    availability().verify_current(root)
    return coupon().complete_method_costs()
