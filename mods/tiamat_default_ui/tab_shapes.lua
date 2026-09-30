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
-- The engine reports which click it was as `event.click`: "left", "right" or
-- "double"; an engine from before that sends none, read as a plain click.
--
-- # Mix
--
-- With Mix ticked the editor keeps each cell's own material (Sub-Node
-- Contract 9.1): a row is the BRUSH a right-click in the editor paints with,
-- and Make crafts the cut, with the same three clicks, taking one unit of
-- each cell's own material an item.
--
-- # The editor's own copy
--
-- The client draws its own copy of the cut so a click lands at once, and
-- adopts the tree's shape (or cells) only when it differs from the one the
-- tree last carried, keyed by the editor's NAME. So:
--
-- - every redraw sends the shape as last DELIBERATELY set (`sent`), never the
--   latest carve, and the client keeps what the player made — which is what
--   lets the tab redraw on every carve and show a live cost;
-- - setting a shape on purpose (a preset, Mix on or off) renames the editor
--   (`gen`), so the client adopts it even when it equals the last one sent —
--   Block, carve, Block again resets — and a carve event from the old name,
--   sent before the new tree arrived, is recognised as stale and ignored.

local C, T = tdi.config, tdi.theme
local K = T.colours
local craft = tdi.crafting

local ROW = "m/"          -- a material row's name: "m/" .. block id
local EDITOR = "cut/"     -- the editor's name: "cut/" .. gen
local PER_CLICK = 10
local PRESET_TEXT = 12    -- small enough for four eight-letter presets a row at 800x600
local COST_BYTES = 30     -- a cost line longer than this says less, to fit at 800x600

-- `data`: the latest carve (`mask`, or `cells` with Mix on) and the one the
-- tree carries (`sent`), the editor's generation `gen`, the chosen material
-- or brush (`material`, a block id), `mix`, the last craft (`last`, for a
-- double-click to top up) and the result `message`.
local function fresh()
    return { mask = craft.FULL, cells = nil, sent = craft.FULL, gen = 1, mix = false,
        material = nil, last = nil, message = "" }
end

-- Sets the cut on purpose: the tree carries it and the editor adopts it.
local function set(data, shape)
    if data.mix then
        data.cells, data.sent = shape, shape
    else
        data.mask, data.sent = shape, shape
    end
    data.gen, data.last = data.gen + 1, nil
end

local function heading(text)
    local label = T.label(text, 16, K.brass)
    label.size = C.label_height
    return label
end

local function line(text, colour)
    local label = T.text(text, 15, colour)
    label.size = C.label_height
    return label
end

-- Nothing to carve: the whole body says so, and nothing else is offered but
-- the result of the craft that used the last of it.
local function empty(data)
    return T.box("column", {
        T.space(1),
        heading("MATERIAL NEEDED"),
        T.hint("Dig some material to begin shaping."),
        T.hint("Existing shapes and named items are kept intact."),
        line(data.message, K.accent),
        T.space(1),
    })
end

-- What one item of the current cut costs, as a line. Shortened when the
-- names are long, so it never runs past the column.
local function cost_line(data, shown)
    if data.mix then
        local cost = craft.cost_of(data.cells)
        if #cost == 0 then return "" end
        local parts, total = {}, 0
        for _, c in ipairs(cost) do
            parts[#parts + 1] = c.units .. " " .. craft.friendly(game.block_of(c.material) or "?")
            total = total + c.units
        end
        local text = table.concat(parts, ", ") .. " each"
        if #text > COST_BYTES then text = total .. " units each, " .. #cost .. " materials" end
        return text
    end
    local n = craft.cells(data.mask)
    if n == 0 or n == 27 then return "" end
    local text = n .. " " .. craft.friendly(shown.id) .. " each"
    if #text > COST_BYTES then text = n .. " units each" end
    return text
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

local function mix_box(data)
    return { type = "checkbox", name = "mix", text = "Mix", checked = data.mix,
        style = { font = T.text_font, text_size = 14, text_colour = K.ink } }
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

    local editor = { type = "shape_editor", name = EDITOR .. data.gen, material = shown.material,
        grow = 1, size = 0, style = { background = K.clear } }
    if data.mix then
        editor.cells = data.sent
    else
        editor.shape = data.sent
    end
    local well = T.well(editor, 10)
    well.grow, well.size = 1, 0
    local left = T.box("column", {
        well,
        T.hint(data.mix and "Left cuts / right paints" or "Left cuts / right restores"),
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
    local tail = {
        T.row({ T.label("MATERIALS", 16, K.brass), T.space(1), mix_box(data) }, C.label_height),
        T.hint(data.mix and "Click a material to paint with it" or "Click 10 / right 1 / double: stack"),
        materials,
    }
    if data.mix then
        local button = T.wide_button("make", "Make", true, 15)
        button.tooltip = "Click 10 / right 1 / double: stack"
        tail[#tail + 1] = T.row({ button }, C.row_height)
    end
    -- The result of the last craft, or, until there is one, what an item costs.
    if data.message ~= "" then
        tail[#tail + 1] = line(data.message, K.accent)
    else
        tail[#tail + 1] = line(cost_line(data, shown), K.muted)
    end
    for _, widget in ipairs(tail) do right[#right + 1] = widget end
    right = T.box("column", right)
    right.grow, right.size = 1, 0
    return T.box("row", { left, right }, 16)
end

-- How many a click asks for. A double-click tops up to a stack: egui reports
-- the first half of a double-click as a click of its own, which has already
-- made ten, so the double makes the rest rather than a whole stack more.
local function wanted(data, key, click)
    if click == "right" then return 1 end
    if click == "double" then
        local last = data.last
        local made = last and last.key == key and last.gen == data.gen and last.made or 0
        return game.ITEMS_PER_STACK - made
    end
    return PER_CLICK
end

-- Crafts with `click` from `key` (a block id, or "mix"), and remembers a plain
-- click for the double-click that may follow it.
local function make(player, data, key, click)
    local want = wanted(data, key, click)
    if want < 1 then
        data.message, data.last = "That stack is full.", nil
        return
    end
    local message, made
    if key == "mix" then
        message, made = craft.craft_cells(player, data.cells, want)
    else
        message, made = craft.craft(player, key, data.mask, want)
    end
    data.message = message
    data.last = (click == nil or click == "left") and { key = key, gen = data.gen, made = made } or nil
end

local function on_event(player, data, event)
    local name = event.name
    if type(name) ~= "string" then return false end

    if event.kind == "chiselled" then
        -- From the editor on screen only: an older name's carve was made
        -- before a preset or Mix replaced it.
        if name ~= EDITOR .. data.gen then return false end
        if data.mix then
            if not craft.valid_cells(event.cells) then return false end
            local cells = {}
            for i = 1, 27 do cells[i] = event.cells[i] end
            data.cells = cells
        else
            if math.type(event.shape) ~= "integer" or event.shape < 0 or event.shape > craft.FULL then
                return false
            end
            data.mask = event.shape
        end
        data.message, data.last = "", nil
        return true   -- the cost line follows the carve; the editor keeps its own copy
    end

    if event.kind == "toggled" and name == "mix" then
        if event.checked == data.mix then return false end
        local brush
        for _, item in ipairs(craft.stock(player)) do
            if item.id == data.material then brush = item.material end
        end
        if event.checked then
            data.mix = true
            set(data, craft.fill(data.mask, brush or 0))
        else
            local mask = craft.occupancy(data.cells or {})
            data.mix, data.cells = false, nil
            set(data, mask)
        end
        data.message = ""
        return true
    end

    if event.kind ~= "pressed" then return false end

    if name:sub(1, #ROW) == ROW then
        local id = name:sub(#ROW + 1)
        data.material = id
        if data.mix then
            data.message = ""     -- the brush: the cells stay as they are
        else
            make(player, data, id, event.click)
        end
        return true
    end

    if name == "make" then
        if not data.mix then return false end
        make(player, data, "mix", event.click)
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
    if data.mix then
        local brush
        for _, item in ipairs(craft.stock(player)) do
            if item.id == data.material then brush = item.material end
        end
        set(data, craft.fill(mask, brush or 0))
    else
        set(data, mask)
    end
    data.message = ""
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
