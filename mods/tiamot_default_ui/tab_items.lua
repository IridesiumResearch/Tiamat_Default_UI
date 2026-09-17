-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Inventory tab: quick access, one page of the pack, and the off-hand.
--
-- The engine moves every item. This tab only says which slots of
-- `player:main` are on screen, so paging never moves anything.

local C, T = tdi.config, tdi.theme
local K = T.colours

local VIEW = "player:main"

local function page_first(page)
    if page == 1 then return C.pack_first end
    return C.later_pages_first + (page - 2) * C.page_size
end

-- `count` slots from `first`, in rows of `C.columns`, centred.
local function grid(first, count)
    local rows = {}
    for row = 0, (count - 1) // C.columns do
        local cells = {}
        for col = 0, C.columns - 1 do
            local index = first + row * C.columns + col
            if index < first + count then
                cells[#cells + 1] = T.slot(VIEW, index)
            end
        end
        local line = T.box("row", cells, C.cell_gap)
        line.size = C.cell
        rows[#rows + 1] = line
    end
    local column = T.box("column", rows, C.cell_gap)
    column.align = "center"
    return column
end

local function build(player, data)
    local first = page_first(data.page)
    local navigation = T.box("row", {
        T.button("previous", "< Previous"),
        T.label("Page " .. data.page, 17, K.muted),
        T.button("next", "Next >"),
    }, 12)
    return T.box("column", {
        T.section("QUICK ACCESS", { grid(C.hotbar_first, C.hotbar_count) }),
        T.section("PACK", { grid(first, math.min(C.page_size, C.last_slot - first + 1)), navigation }),
        T.box("row", { T.slot(VIEW, C.offhand_slot, true), T.label("Off-hand", 17, K.muted) }, 12),
        T.label("Left: move stack   /   Right: split or place one", 16, K.muted),
    }, 10)
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
