-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Every number that shapes the screen, in one place.
--
-- Slot numbers are indices into `player:main`, and the first 28 are the
-- ENGINE's layout: 1-9 are what the number keys select and 28 is what the HUD
-- is handed as the off-hand. Paging here changes what the screen shows, never
-- where an item is stored.

local C = {}

-- Slots --------------------------------------------------------------------

C.hotbar_first = 1
C.hotbar_count = 9
C.pack_first = 10              -- page one is 10..27
C.page_size = 18
C.offhand_slot = 28
C.later_pages_first = 29       -- page two onward starts past the off-hand
C.last_slot = 65535            -- the highest index `player:main` has

-- Page one, then as many pages of `page_size` as reach `last_slot`.
C.last_page = 1 + (C.last_slot - C.later_pages_first + C.page_size) // C.page_size

-- Layout, in virtual pixels ---------------------------------------------------
--
-- The engine gives a screen a fixed 4:3 sheet, three quarters of the window's
-- height, and lays the tree into exactly that room. Nothing here scrolls:
-- every size below is what the screen wants, and a smaller window shrinks the
-- whole screen proportionally rather than cutting it off. These are chosen to
-- fit a 1280x720 window at full size and an 800x600 one only slightly
-- squeezed; the native check lays every screen out at both to prove it.
--
-- Nothing sets `cross_size`: the engine never caps it, so a squeezed row would
-- have spilled whatever had one.

C.frame_padding = 24           -- keeps the contents clear of the theme frame's corners
C.header_height = 30
C.tab_height = 40
C.tab_underline = 3
C.row_height = 34              -- a line of buttons, a heading with controls
C.label_height = 20
C.hint_height = 18
C.gap = 6

C.columns = 9                  -- the pack in rows as wide as the hotbar
C.cell = 52
C.cell_gap = 4
C.offhand_gap = 12             -- between slot nine and the off-hand
C.editor_width = 212           -- the shape editor's well; the controls take the rest

-- The HUD -------------------------------------------------------------------

-- How much of the bottom of the screen the hotbar needs, in the HUD's own
-- virtual pixels (1080 tall on every monitor). A bottom-anchored command is
-- drawn DOWN from its `y`, so this is the highest `y` in hud.lua, the status
-- line at 130, plus a little air. The engine keeps its sheets above the
-- tallest reserve any mod declares, so Life's hearts above this get theirs.
C.hud_reserve = 138

-- Tabs ----------------------------------------------------------------------

-- Where the built-in tabs sit in the strip. Another mod's tab defaults to
-- `tab_order_default`, after both; lower numbers go further left.
C.tab_order_items = 10
C.tab_order_shapes = 20
C.tab_order_default = 100

-- Limits on what another mod hands in. Past these a tab is refused here, with
-- a log line, rather than by `update_dialog`, whose error would be this mod's.
C.max_label_bytes = 48
C.max_tree_depth = 20          -- the engine allows 32; the frame around a tab uses the rest
C.max_tree_nodes = 1024

return C
