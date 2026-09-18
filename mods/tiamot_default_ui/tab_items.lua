-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Inventory tab: one page of the pack, then quick access with the
-- off-hand beside it.
--
-- The engine moves every item. This tab only says which slots of
-- `player:main` are on screen, so paging never moves anything.
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

local function page_first(page)
    if page == 1 then return C.pack_first end
    return C.later_pages_first + (page - 2) * C.page_size
end

-- Nine cells from `first` (fewer on the last page), then the off-hand's
-- place: `tail` is the off-hand slot, or nil for an empty space.
local function cells(first, count, tail)
    local row = {}
    for n = 0, C.columns - 1 do
        if n < count then
            row[#row + 1] = T.slot(VIEW, first + n)
        else
            row[#row + 1] = T.space(0, C.cell)
        end
    end
    row[#row + 1] = T.space(0, C.offhand_gap)
    row[#row + 1] = tail or T.space(0, C.cell)
    return T.row(row, C.cell, C.cell_gap)
end

-- The width of every row above, for the block that centres them.
local WIDTH = (C.columns + 1) * C.cell + (C.columns + 1) * C.cell_gap + C.offhand_gap

local function build(player, data)
    local first = page_first(data.page)
    local count = math.min(C.page_size, C.last_slot - first + 1)
    local rows = {}
    for n = 0, C.page_size // C.columns - 1 do
        local start = first + n * C.columns
        rows[#rows + 1] = cells(start, math.max(0, math.min(C.columns, count - n * C.columns)))
    end

    local pack_heading = T.row({
        T.label("PACK", 16, K.brass),
        T.space(1),
        T.button("previous", "<", false, 15),
        T.label("Page " .. data.page, 15, K.muted),
        T.button("next", ">", false, 15),
    }, C.row_height, 10)
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
        cells(C.hotbar_first, C.hotbar_count, T.slot(VIEW, C.offhand_slot, true)),
        T.space(0, C.gap),
        T.hint("Left-click: move a stack   /   Right-click: split, or place one"),
    })
    block.size = WIDTH
    -- Centred across the body; top-aligned so switching tabs never moves it.
    return T.box("row", { T.space(1), block, T.space(1) }, 0)
end

local function on_event(player, data, event)
    if event.kind ~= "pressed" then return false end
    if event.name == "previous" then
        data.page = math.max(1, data.page - 1)
    elseif event.name == "next" then
        data.page = math.min(C.last_page, data.page + 1)
    else
        return false
    end
    return true
end

tdi.screen.add_tab{
    id = "items",
    label = "Inventory",
    order = C.tab_order_items,
    fresh = function() return { page = 1 } end,
    build = build,
    on_event = on_event,
}

return {}
