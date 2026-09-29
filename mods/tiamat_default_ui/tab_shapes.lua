-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The shape crafter's tab: carve a shape on the left, then click a material on
-- the right to make it from that material. The rules are in crafting.lua; this
-- is the screen. It is a STATION's tab, shown only while the screen was opened
-- by right-clicking a shape crafter block (crafter_block.lua).
--
-- # Clicks, not buttons
--
-- Every material the player carries is one row, and the row IS the craft:
-- click for ten, right-click for one, double-click to fill a stack. So there
-- is no dropdown and no craft button, and a queued click can never craft from
-- a material the player did not point at, because each row names its own.
--
-- The engine reports which click it was as `event.click` (engine ask 17):
-- "left", "right" or "double". An engine from before it sends none, which is
-- read as a plain click, so a row crafts ten.

local C, T = tdi.config, tdi.theme
local K = T.colours
local craft = tdi.crafting

local ROW = "m/"          -- a material row's name: "m/" .. block id
local PER_CLICK = 10
local PRESET_TEXT = 12      -- small enough for four eight-letter presets a row at 800x600

-- `data`: the `mask` being carved, the block id the editor shows
-- (`material`), the last craft (`last`, for a double-click to top up) and
-- the result `message`.
local function fresh()
    return { mask = craft.FULL, material = nil, last = nil, message = "" }
end

local function heading(text)
    local label = T.label(text, 16, K.brass)
    label.size = C.label_height
    return label
end

local function result_line(data)
    local message = T.text(data.message, 15, K.accent)
    message.size = C.label_height
    return message
end

-- Nothing to carve: the whole body says so, and nothing else is offered but
-- the result of the craft that used the last of it.
local function empty(data)
    return T.box("column", {
        T.space(1),
        heading("MATERIAL NEEDED"),
        T.hint("Dig some material to begin shaping."),
        T.hint("Existing shapes and named items are kept intact."),
        result_line(data),
        T.space(1),
    })
end

-- The presets, four to a row: the built-in four, then those other mods added
-- that this player is shown. Remembers which added preset each button is, so
-- a press after the list changed still sets the mask the player saw.
local function presets(player, data)
    local buttons = {
        T.wide_button("reset", "Block", false, PRESET_TEXT),
        T.wide_button("slab", "Slab", false, PRESET_TEXT),
        T.wide_button("stairs", "Stairs", false, PRESET_TEXT),
        T.wide_button("pillar", "Pillar", false, PRESET_TEXT),
    }
    data.added = {}
    for n, preset in ipairs(craft.presets_for(player, C.max_added_presets)) do
        data.added[n] = preset.mask
        buttons[#buttons + 1] = T.wide_button("preset/" .. n, preset.label, false, PRESET_TEXT)
    end
    local rows = {}
    for first = 1, #buttons, C.preset_columns do
        local row = {}
        for n = first, first + C.preset_columns - 1 do
            row[#row + 1] = buttons[n] or T.space(1)
        end
        rows[#rows + 1] = T.row(row, C.row_height, C.cell_gap)
    end
    return rows
end

local function material_row(item, shown)
    local row = T.button(ROW .. item.id, craft.friendly(item.id) .. "   " .. item.units,
        item.id == shown, 15)
    row.size = C.material_row
    return row
end

-- # Layout
--
-- The editor in a well on the left, as tall as the body, with how to carve
-- under it. On the right the presets, then the materials, which scroll: a
-- pack can hold twenty-eight of them and the sheet has room for a handful.
-- Only the list scrolls, so the presets and the result line never move.
local function build(player, data)
    local list = craft.stock(player)
    if #list == 0 then return empty(data) end

    local shown
    for _, item in ipairs(list) do
        if item.id == data.material then shown = item end
    end
    shown = shown or list[1]
    data.material = shown.id

    -- The editor owns its live mask, and a redraw echoing an older one would
    -- undo newer clicks, so nothing here shows a live cost: the rule is fixed
    -- and printed instead.
    local editor = { type = "shape_editor", name = "cut", shape = data.mask, material = shown.material,
        grow = 1, size = 0, style = { background = K.clear } }
    local well = T.well(editor, 10)
    well.grow, well.size = 1, 0
    local left = T.box("column", {
        well,
        T.hint("Left cuts / right restores"),
        T.hint("Arrows turn / a unit a cell"),
    })
    left.size = C.editor_width

    local rows = {}
    for i, item in ipairs(list) do
        rows[i] = material_row(item, shown.id)
    end
    local materials = { type = "scroll", grow = 1, size = 0,
        children = { T.box("column", rows, C.cell_gap) } }

    local right = presets(player, data)
    for _, widget in ipairs({
        heading("MATERIALS"),
        T.hint("Click 10 / right 1 / double: stack"),
        materials,
        result_line(data),
    }) do right[#right + 1] = widget end
    right = T.box("column", right)
    right.grow, right.size = 1, 0
    return T.box("row", { left, right }, 16)
end

-- How many a click asks for. A double-click tops up to a stack: egui reports
-- the first half of a double-click as a click of its own, which has already
-- made ten, so the double makes the rest rather than a whole stack more.
local function wanted(data, id, click)
    if click == "right" then return 1 end
    if click == "double" then
        local last = data.last
        local made = last and last.id == id and last.mask == data.mask and last.made or 0
        return game.ITEMS_PER_STACK - made
    end
    return PER_CLICK
end

local function on_event(player, data, event)
    local name = event.name
    if event.kind == "chiselled" and name == "cut" then
        -- Not redrawn: see the note on the editor above.
        if math.type(event.shape) == "integer" and event.shape >= 0 and event.shape <= craft.FULL then
            data.mask, data.message, data.last = event.shape, "", nil
        end
        return false
    end
    if event.kind ~= "pressed" or type(name) ~= "string" then return false end

    if name:sub(1, #ROW) == ROW then
        local id = name:sub(#ROW + 1)
        local want = wanted(data, id, event.click)
        data.material = id
        if want < 1 then
            data.message, data.last = "That stack is full.", nil
            return true
        end
        local message, made = craft.craft(player, id, data.mask, want)
        data.message = message
        -- Only a plain click is topped up by the double-click that follows it.
        data.last = (event.click == nil or event.click == "left")
            and { id = id, mask = data.mask, made = made } or nil
        return true
    end

    local added = name:match("^preset/(%d+)$")
    local mask
    if added then
        mask = data.added and data.added[tonumber(added)]
    else
        mask = name == "reset" and craft.FULL or craft.preset(name)
    end
    if not mask then return false end
    data.mask, data.message, data.last = mask, "", nil
    return true
end

tdi.screen.add_tab{
    id = "shapes",
    label = "Shape crafter",
    station = true,
    order = C.tab_order_shapes,
    fresh = fresh,
    on_enter = function(_, data) data.message = "" end,
    build = build,
    on_event = on_event,
}

return {}
