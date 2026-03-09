# Widget Support Matrix

Coverage of macOS Accessibility roles in agent-swift's `ROLE_MAP` (source: `Sources/AgentSwiftLib/AX/AXClient.swift`).

## Coverage Summary

- **Official macOS SDK roles:** 64/64 (100%)
- **Total role mappings:** 74 (64 official + 10 SwiftUI/runtime extras)
- **Display types:** ~42
- **Interactive roles (appear in `snapshot -i`):** 29

## Controls: Buttons

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXButton` | `button` | Yes | Yes |
| `AXMenuButton` | `menubutton` | Yes | Yes |

## Controls: Text Input

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXTextField` | `textfield` | Yes | Yes |
| `AXTextArea` | `textfield` | Yes | Yes |
| `AXSearchField` | `searchfield` | Yes | Extra |
| `AXDateField` | `datefield` | Yes | Yes |
| `AXTimeField` | `timefield` | Yes | Yes |
| `AXDateTimeArea` | `datetimearea` | No | Yes |

## Controls: Selection

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXCheckBox` | `checkbox` | Yes | Yes |
| `AXRadioButton` | `radio` | Yes | Yes |
| `AXRadioGroup` | `radiogroup` | Yes | Yes |
| `AXPopUpButton` | `dropdown` | Yes | Yes |
| `AXComboBox` | `dropdown` | Yes | Yes |
| `AXSegmentedControl` | `segmented` | Yes | Extra |

## Controls: Value

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXSlider` | `slider` | Yes | Yes |
| `AXSwitch` | `switch` | Yes | Extra |
| `AXToggle` | `switch` | Yes | Extra |
| `AXIncrementor` | `stepper` | Yes | Yes |
| `AXStepper` | `stepper` | Yes | Extra |
| `AXColorWell` | `colorwell` | Yes | Yes |
| `AXLevelIndicator` | `levelindicator` | Yes | Yes |

## Controls: Disclosure & Navigation

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXDisclosureTriangle` | `disclosure` | Yes | Yes |
| `AXLink` | `link` | Yes | Yes |
| `AXTab` | `tab` | Yes | Extra |
| `AXTabGroup` | `tabgroup` | Yes | Yes |

## Menus

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXMenu` | `menu` | No | Yes |
| `AXMenuBar` | `menubar` | No | Yes |
| `AXMenuBarItem` | `menubaritem` | Yes | Yes |
| `AXMenuItem` | `menuitem` | Yes | Yes |
| `AXMenuItemCheckbox` | `menuitem` | Yes | Extra |
| `AXMenuItemRadio` | `menuitem` | Yes | Extra |

## Containers & Layout

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXGroup` | `group` | No | Yes |
| `AXWindow` | `window` | No | Yes |
| `AXToolbar` | `toolbar` | No | Yes |
| `AXScrollArea` | `scrollarea` | No | Yes |
| `AXSplitGroup` | `splitgroup` | No | Yes |
| `AXSplitter` | `splitter` | No | Yes |
| `AXSheet` | `sheet` | No | Yes |
| `AXDrawer` | `drawer` | No | Yes |
| `AXLayoutArea` | `layoutarea` | No | Yes |
| `AXLayoutItem` | `layoutitem` | No | Yes |
| `AXGrid` | `grid` | No | Yes |
| `AXPage` | `page` | No | Yes |

## Table/List Structure

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXTable` | `table` | No | Yes |
| `AXList` | `list` | No | Yes |
| `AXOutline` | `outline` | No | Yes |
| `AXBrowser` | `browser` | No | Yes |
| `AXRow` | `row` | No | Yes |
| `AXColumn` | `column` | No | Yes |
| `AXCell` | `cell` | No | Yes |

## Content & Display

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXStaticText` | `label` | No | Yes |
| `AXImage` | `image` | No | Yes |
| `AXHeading` | `heading` | No | Yes |
| `AXProgressIndicator` | `progressbar` | No | Yes |
| `AXBusyIndicator` | `busyindicator` | No | Yes |
| `AXValueIndicator` | `valueindicator` | No | Yes |
| `AXRelevanceIndicator` | `relevanceindicator` | No | Yes |
| `AXRuler` | `ruler` | No | Yes |
| `AXRulerMarker` | `rulermarker` | No | Yes |
| `AXMatte` | `matte` | No | Yes |
| `AXGrowArea` | `growarea` | No | Yes |
| `AXListMarker` | `listmarker` | No | Yes (macOS 26+) |

## Scroll Components

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXScrollBar` | `scrollbar` | No | Yes |
| `AXHandle` | `handle` | No | Yes |

## System & Misc

| AX Role | Display Type | Interactive | SDK Official |
|---------|-------------|-------------|-------------|
| `AXApplication` | `application` | No | Yes |
| `AXSystemWide` | `system` | No | Yes |
| `AXUnknown` | `unknown` | No | Yes |
| `AXDockItem` | `dockitem` | Yes | Yes |
| `AXWebArea` | `webarea` | No | Yes |
| `AXPopover` | `popover` | No | Yes |
| `AXHelpTag` | `helptag` | No | Yes |
| `AXTextMarkerRange` | `textmarkerrange` | No | Extra |

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

## SDK Reference

Official roles sourced from:
- `AXRoleConstants.h` (HIServices framework) — 58 roles
- `NSAccessibilityConstants.h` (AppKit framework) — 6 additional roles (Link, DateTimeArea, ListMarker, Heading, WebArea, Page)
- Deprecated: `AXSortButton` (removed in macOS 10.6) — not mapped
