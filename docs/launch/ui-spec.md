# Questify iOS UI rules

Every UI change follows this document. Goal: one coherent native app, recognisably the same product as the mini-program.

## Order of reference

1. **The mini-program is the main reference.** Page structure, section order, entry positions, fields, copy and visual tokens all come from `chengyinhub-xcx` in `liboyang42-cpu/hengyin`. Read the matching `.wxml`, `.wxss` and `.js` before changing a screen. Keep what it shows and in what order.
2. **Apple native components render it.** `NavigationStack`, `TabView`, `List`, `Form`, `Section`, `LabeledContent`, `Picker(.segmented)`, `.sheet` with detents, `.searchable`, `.toolbar`, `.confirmationDialog`, `.swipeActions`, `ContentUnavailableView`. Do not port `cy-*` components as custom views when a native one does the job.
3. **Revolut guides polish only**, where the mini-program gives no answer or is wrong: spacing, grouping, hierarchy.

If mini-program UI is clearly wrong (clipped, unreadable, confusing, WeChat-only workarounds), fix it rather than copy it, and say so in the PR. Business rules never change in a UI pass.

## Fixed rules

- **Merchant is light. Player is dark.** Set once at the roots with `.themeDomain`. Never change this, never force another scheme in a screen.
- **No secondary labels.** No helper captions, subtitles explaining a screen, or descriptions under rows, unless the mini-program has that exact content and it carries real data. The layout explains. Real values (date, status, price) are data, not captions.
- **No engineering language on any user-visible string:** synthetic, fixture, source, contract, approval as a system term, dormant, adapter, endpoint, capability, backend, receipt as jargon, read-only, preview only. Say what it means to a user, or remove it.
- **Nothing disabled as a placeholder.** If a feature doesn't work, hide its entry. Don't show "not available yet".
- **No fake data.** A missing value shows "—". Marketing figures may show 0.
- **Both languages.** Every string is a localized key with English and Chinese. No Chinese literals in `Text`. Backend-mirrored messages keep their wording.
- **Keep your hands off logic.** Don't change requests, state, permissions, recovery or `accessibilityIdentifier` values; tests depend on them. Business assertions stay valid.

## Layout

| Element | Rule |
|---|---|
| Top-right | No WeChat capsule in the app, so use it. Up to 2 toolbar actions; more goes in a `…` menu |
| Page | Native inset grouped `List` or `Form` by default. Rounded groups on the system background |
| Section title | Outside the group, as a native `Section` header. No footer text unless legally needed |
| Row | Leading icon only if the mini-program has one. Label left, value right with `LabeledContent`. Chevron only when it opens something |
| Detail page | `QuestifyHeroValue` for the one number or title that matters. Up to four `QuestifyRoundAction` below it. Then grouped sections |
| Primary action | One per screen, `.buttonStyle(.questifyPrimary)`. Pin with `.questifyBottomAction` when it ends a flow |
| Secondary actions | `.bordered` or plain. Destructive actions in red and separate from the rest |
| Tabs in a page | Native segmented `Picker`, replacing custom bars |
| Sheets | `.presentationDetents`, sized to the content, drag indicator visible. Title and one action |
| States | Loading, empty, error and offline on every data screen. `ContentUnavailableView` for empty and error, with a retry when it can work. Input errors are red text under the field |
| Type | Semantic `Theme.Font` or system styles. Fixed sizes only for numbers. Must survive the largest Dynamic Type without clipping |
| Colour | Semantic system colours or `Theme.Color`. Accent stays `QuestifyPalette.accent`. No hard-coded RGB |
| Motion | Native transitions. `QuestifyReduceMotion` for anything custom |
| Images | Real covers. A clean placeholder with no text when there is none |

Keep custom visuals where they are the product: play and game screens, map, badges, story and chapter transitions, QR tickets. Don't flatten them into forms.

## Messages

This is the page the mini-program doesn't define the same way. Base it on these structures, using native components.

- **List:** large title 消息 / Messages. Segmented All, Channels, Direct. Search. Channels grouped under Theme, Club and Team section headers. Direct and system conversations listed by recency, with avatar, name, last message, time and unread badge. System notices appear under 城瘾小助手.
- **Chat:** title and up to 2 toolbar actions. Grouped messages with avatar and sender name in groups; own messages trailing in a high-contrast bubble. Composer pinned at the bottom: `+` on the left, rounded field, send inside the field. No refresh button; pull or live update instead. Unknown message types show a neutral placeholder.
- **Channels:** Discord structure adapted to iOS: space header, channel list by category, unread state, member list, roles and settings in pushed native pages. Render from server permissions only.

## Definition of done for a screen

- Same structure and order as its mini-program page, or a stated reason.
- Follows every rule above in both languages, at normal and largest text, on small and large iPhones.
- Compiles. Identifiers and behaviour unchanged. No new files unless the lane says so.
