# Map alternative-list accessibility role

Base: reviewed local tree c564496180f9d15f07aab1efab64aa9a567e43ec. This follow-on changes only the existing map row's explicit accessibility button trait, adds source negative controls, and records the evidence. No frozen package is edited.

Run129 job112729146750, source7dd74b54a9aff8260198e5c00bc2feaac68337fe: all three SearchMapAlternativeListFlowTests failed waiting for a Button with identifier mapList.pin.list-first. The original AX log contains that exact identifier as Other in both ordinary and maximum-size presentations. The existing SwiftUI Button uses accessibilityElement(children: .ignore), then restores selected state but not button role.

Add accessibilityAddTraits(.isButton) while retaining isSelected, disabled state, complete title, accessibility value/hint, source binding and the original action closure exactly. This addresses the observed AX-role mismatch. The final runtime role still needs Apple verification; no Apple execution is claimed.

All three complete UI methods and their helpers remain byte-for-byte unchanged. No Any/Other locator fallback, extra wait, new launch, loop reduction, cost reduction, grant, origin, map business capability, or real action is introduced. Existing planning profile, all source-required floors and runner/workflow remain exact. The source test rejects removal of the role or changes to disabled/selected/title behavior and original UI assertions.
