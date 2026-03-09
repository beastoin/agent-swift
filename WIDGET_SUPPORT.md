# Widget Support Matrix

Coverage of macOS Accessibility roles in agent-swift's `ROLE_MAP` (source: `Sources/AgentSwiftLib/AX/AXClient.swift`).

## Coverage Summary

- **Total role mappings:** 66
- **Display types:** ~40
- **Interactive roles (appear in `snapshot -i`):** 27

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

## Controls: Disclosure & Navigation

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXDisclosureTriangle` | `disclosure` | Yes |
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

## System & Misc

| AX Role | Display Type | Interactive |
|---------|-------------|-------------|
| `AXApplication` | `application` | No |
| `AXSystemWide` | `system` | No |
| `AXUnknown` | `unknown` | No |
| `AXWebArea` | `webarea` | No |
| `AXPopover` | `popover` | No |
| `AXHelpTag` | `helptag` | No |
| `AXTextMarkerRange` | `textmarkerrange` | No |

## Subrole Handling

Subroles are captured (`AXNode.subrole`) but not used for classification. Common subroles:
- `AXCloseButton`, `AXZoomButton`, `AXMinimizeButton` — window control buttons
- `AXToolbarButton` — toolbar buttons
- `AXIncrementArrow`, `AXDecrementArrow` — stepper arrows
- `AXToggleButton` — stateful on/off button

These appear as their parent role's display type (e.g., `button`).

## Fallback Behavior

Unknown AX roles strip the `AX` prefix and lowercase: `AXCustomWidget` → `customwidget`.

## Action-Based Interactivity

Elements not in `INTERACTIVE_ROLES` are still interactive if they expose `AXPress` or `AXConfirm` actions.
