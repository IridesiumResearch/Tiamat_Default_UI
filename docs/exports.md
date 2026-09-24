<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Exports

What Tiamat Default UI deliberately offers other mods. This is the document
`LICENSE.EXCEPTION` names as "the Exports": a mod that reaches this one only
through what is listed here, the engine's scripting API or the network
protocol is an independent work. Copying or adapting this mod's code or assets
is not covered and stays under the GPL.

The README's [For other mods](../README.md#for-other-mods) section explains how
to use these, with a worked example; this file is the list. Keep it current:
a change to `mods/tiamat_default_ui/exports.lua` or to a registration below
changes it in the same commit.

## The exported table

`game.exports("tiamat_default_ui")`, for a mod that lists `tiamat_default_ui`
in `depends` or `optional_depends`. Built in `exports.lua`.

| Field | What it is |
|---|---|
| `version` | `1`. Bumped only when a change would break a reader. |
| `tabs` | Qualified ids of the built-in tabs: `tabs.items` (`tiamat_default_ui:items`), `tabs.shapes` (`tiamat_default_ui:shapes`). |
| `add_tab{ id, label, build, on_event?, order? }` | Adds a tab to the screen. Answers `true` or `nil` and a reason. |
| `add_button{ id, label, on_press, tab? }` | Adds a button to the header, or to one tab. Answers `true` or `nil` and a reason. |
| `open(player, tab?)` | Opens the screen for a player, on a tab if named. |
| `close(player)` | Closes it. |
| `redraw(player)` | Rebuilds it if open. |
| `is_open(player)` | Whether it is open. |
| `current_tab(player)` | The qualified id of the selected tab, or `nil`. |
| `theme` | `font`, `text_font`, `colours` (`clear`, `edge`, `brass`, `ink`, `muted`, `accent`), `frames` (`panel`, `slot`, as content hashes). |
| `widgets` | Builders: `label`, `text`, `hint`, `button`, `wide_button`, `section`, `slot`, `box`, `row`, `space`, `well`. |
| `sizes` | `cell`, `cell_gap`, `row`, `label`, `hint`, `gap`. |

## Callbacks it accepts

Functions another mod passes in, which run in that mod's sandbox:

- a tab's `build(player)`, answering a widget tree, and `on_event(player,
  event)`, answering `true` to redraw;
- a button's `on_press(player)`.

A tab's tree is rebuilt into this mod's tables; only the widget and style
fields the engine documents are kept, every widget `name` is prefixed with the
tab's id, and a tree deeper than 20 or larger than 1024 widgets is refused.
Dialog events from a tab's widgets are routed back to that tab's `on_event`
with the names as the tab wrote them.

## Identifiers it registers

| Identifier | Kind |
|---|---|
| `tiamat_default_ui:inventory` | action (default key E): open and close the screen |
| `tiamat_default_ui:display` | font, Cinzel Decorative Bold |
| `tiamat_default_ui:text` | font, Spectral Regular |
| `tiamat_default_ui:click` | sound |
| `tiamat_default_ui:hotbar_slot` | picture, the hotbar's slot frame |
| `tiamat_default_ui:items`, `tiamat_default_ui:shapes` | the built-in tabs |

It also registers a HUD script (`hud.lua`, with a `reserve` of 138) and
declares a `[theme]` in `mod.toml` for the engine's own screens.

## Data

It stores nothing and reads or writes no data format for other mods. The
inventory it draws is the engine's, and the HUD script is sent only the
hotbar frame's content hash (`slot_frame`).
