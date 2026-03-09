# Widget Support Matrix

Coverage of macOS Accessibility roles in agent-swift's `ROLE_MAP` (source: `Sources/AgentSwiftLib/AX/AXClient.swift`).

## Coverage Summary

- **Total role mappings:** 66
- **Display types:** ~40
- **Interactive roles (appear in `snapshot -i`):** 28

## Controls: Buttons

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXButton` | `button` | Yes |
| `AXMenuButton` | `menubutton` | Yes |

## Controls: Text Input

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXTextField` | `textfield` | Yes |
| `AXTextArea` | `textfield` | Yes |
| `AXSearchField` | `searchfield` | Yes |
| `AXDateField` | `datefield` | Yes |

## Controls: Selection

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXCheckBox` | `checkbox` | Yes |
| `AXRadioButton` | `radio` | Yes |
| `AXRadioGroup` | `radiogroup` | Yes |
| `AXPopUpButton` | `dropdown` | Yes |
| `AXComboBox` | `dropdown` | Yes |
| `AXSegmentedControl` | `segmented` | Yes |

## Controls: Value

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXSlider` | `slider` | Yes |
| `AXSwitch` | `switch` | Yes |
| `AXToggle` | `switch` | Yes |
| `AXIncrementor` | `stepper` | Yes |
| `AXStepper` | `stepper` | Yes |
| `AXColorWell` | `colorwell` | Yes |
| `AXLevelIndicator` | `levelindicator` | Yes |

## Controls: Disclosure

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXDisclosureTriangle` | `disclosure` | Yes |

## Navigation & Links

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXLink` | `link` | Yes |
| `AXTab` | `tab` | Yes |
| `AXTabGroup` | `tabgroup` | Yes |

## Menus

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXMenu` | `menu` | No |
| `AXMenuBar` | `menubar` | No |
| `AXMenuBarItem` | `menubaritem` | Yes |
| `AXMenuItem` | `menuitem` | Yes |
| `AXMenuItemCheckbox` | `menuitem` | Yes |
| `AXMenuItemRadio` | `menuitem` | Yes |

## Containers & Layout

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXGroup` | `group` | No |
| `AXWindow` | `window` | No |
| `AXToolbar` | `toolbar` | No |
| `AXScrollArea` | `scrollarea` | No |
| `AXSplitGroup` | `splitgroup` | No |
| `AXSplitter` | `splitter` | No |
| `AXSheet` | `sheet` | No |
| `AXDrawer` | `drawer` | No |
| `AXLayoutArea` | `layoutarea` | No |
| `AXLayoutItem` | `layoutitem` | No |

## Table/List Structure

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXTable` | `table` | No |
| `AXList` | `list` | No |
| `AXOutline` | `outline` | No |
| `AXBrowser` | `browser` | No |
| `AXRow` | `row` | No |
| `AXColumn` | `column` | No |
| `AXCell` | `cell` | No |

## Content & Display

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXStaticText` | `label` | No |
| `AXImage` | `image` | No |
| `AXHeading` | `heading` | No |
| `AXProgressIndicator` | `progressbar` | No |
| `AXBusyIndicator` | `busyindicator` | No |
| `AXValueIndicator` | `valueindicator` | No |
| `AXRelevanceIndicator` | `relevanceindicator` | No |
| `AXRuler` | `ruler` | No |
| `AXRulerMarker` | `rulermarker` | No |
| `AXMatte` | `matte` | No |
| `AXGrowArea` | `growarea` | No |

## Scroll Components

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXScrollBar` | `scrollbar` | No |
| `AXHandle` | `handle` | No |

## System-Level

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXApplication` | `application` | No |
| `AXSystemWide` | `system` | No |
| `AXUnknown` | `unknown` | No |

## Web & Misc

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXWebArea` | `webarea` | No |
| `AXPopover` | `popover` | No |
| `AXHelpTag` | `helptag` | No |
| `AXTextMarkerRange` | `textmarkerrange` | No |

## Interactive vs Non-Interactive

**Interactive** (included in `snapshot -i`):
`button`, `menubutton`, `textfield`, `searchfield`, `datefield`, `checkbox`, `radio`, `radiogroup`, `dropdown`, `segmented`, `slider`, `switch`, `stepper`, `colorwell`, `levelindicator`, `disclosure`, `link`, `tab`, `tabgroup`, `menuitem`, `menubaritem`

**Non-interactive** (excluded from `snapshot -i`):
`label`, `image`, `heading`, `progressbar`, `busyindicator`, `valueindicator`, `relevanceindicator`, `ruler`, `rulermarker`, `matte`, `growarea`, `menu`, `menubar`, `group`, `window`, `toolbar`, `scrollarea`, `splitgroup`, `splitter`, `sheet`, `drawer`, `layoutarea`, `layoutitem`, `table`, `list`, `outline`, `browser`, `row`, `column`, `cell`, `scrollbar`, `handle`, `application`, `system`, `unknown`, `webarea`, `popover`, `helptag`, `textmarkerrange`

## Subrole Handling

Subroles are captured in the AX tree traversal (`AXNode.subrole`) and stored in session data, but are **not currently used for classification**. Common subroles include:

- `AXCloseButton`, `AXZoomButton`, `AXMinimizeButton` — window control buttons
- `AXToolbarButton` — toolbar-specific buttons
- `AXIncrementArrow`, `AXDecrementArrow` — stepper arrows
- `AXSearchFieldSearchButton`, `AXSearchFieldCancelButton` — search field sub-buttons
- `AXToggleButton` — stateful button (on/off)

These all appear as their parent role's display type (e.g., `button`).

## Fallback Behavior

Unknown AX roles not in `ROLE_MAP` strip the `AX` prefix and lowercase: `AXCustomWidget` → `customwidget`. This ensures forward compatibility with custom accessibility roles.

## Action-Based Interactivity

Elements not in `INTERACTIVE_ROLES` are still treated as interactive if they expose `AXPress` or `AXConfirm` actions. This catches custom controls that implement standard accessibility actions.
