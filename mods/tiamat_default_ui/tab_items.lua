-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Inventory tab: the pack, then quick access with the off-hand beside it.
-- Twenty-eight fillable slots in all, 1-28 of `player:main`.
--
-- The engine moves every item. This tab only says which slots are on screen.
--
-- # Every row is the same width
--
-- The quick-access row is nine cells, a gap and the off-hand. The pack rows
-- are nine cells, the same gap and an empty space where the off-hand would
-- be. A window too narrow for the block shrinks each row by the same factor,
-- so the pack's columns stay over the hotbar's instead of drifting apart.

local C, T = tdi.config, tdi.theme
local K = T.colours

local VIEW = "player:main"

-- Nine cells from `first`, then the off-hand's place: `tail` is the off-hand
-- slot, or nil for an empty space.
local function cells(first, tail)
    local row = {}
    for n = 0, C.columns - 1 do
        row[#row + 1] = T.slot(VIEW, first + n)
    end
    row[#row + 1] = T.space(0, C.offhand_gap)
    row[#row + 1] = tail or T.space(0, C.cell)
    return T.row(row, C.cell, C.cell_gap)
end

-- The width of every row above, for the block that centres them.
local WIDTH = (C.columns + 1) * C.cell + (C.columns + 1) * C.cell_gap + C.offhand_gap

local function build(player, data)
    local rows = {}
    for n = 0, C.pack_count // C.columns - 1 do
        rows[#rows + 1] = cells(C.pack_first + n * C.columns)
    end

    local pack_heading = T.row({ T.label("PACK", 16, K.brass) }, C.label_height)
    local quick_heading = T.row({
        T.label("QUICK ACCESS", 16, K.brass),
        T.space(1),
        T.label("OFF-HAND", 14, K.muted),
    }, C.label_height)

    local grid = T.box("column", rows, C.cell_gap)
    grid.size = #rows * C.cell + (#rows - 1) * C.cell_gap

    local block = T.box("column", {
        pack_heading,
        grid,
        T.space(0, C.gap),
        quick_heading,
        cells(C.hotbar_first, T.slot(VIEW, C.offhand_slot, true)),
        T.space(0, C.gap),
        T.hint("Left-click: move a stack   /   Right-click: split, or place one"),
    })
    block.size = WIDTH
    -- Centred across the body; top-aligned so switching tabs never moves it.
    return T.box("row", { T.space(1), block, T.space(1) }, 0)
end

-- Nothing on this tab raises an event: the slots are the engine's own.
local function on_event(player, data, event)
    return false
end

tdi.screen.add_tab{
    id = "items",
    label = "Inventory",
    order = C.tab_order_items,
    build = build,
    on_event = on_event,
}

return {}
