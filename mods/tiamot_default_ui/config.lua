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

C.columns = 6                  -- cells per row; six fits a narrow sheet
C.cell = 58
C.cell_gap = 5
C.button_height = 44
C.tab_underline = 4
C.editor_size = 190

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
