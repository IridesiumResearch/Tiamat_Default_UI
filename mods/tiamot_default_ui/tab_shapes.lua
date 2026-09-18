-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Crafting tab, the shape crafter: choose a loose material, carve a shape, craft it.
-- The rules are in crafting.lua; this is the screen and its buttons.

local C, T = tdi.config, tdi.theme
local K = T.colours
local craft = tdi.crafting

-- `data`: `mask` being carved, block id of the chosen `material`, `options`
-- (dropdown index -> block id, or false for a placeholder) and `message`.
local function fresh()
    return { mask = craft.FULL, material = nil, options = {}, message = "" }
end

local function dropdown(names, selected)
    return { type = "dropdown", name = "material", options = names, selected = selected,
        size = C.row_height, style = { background = K.clear, border = K.brass, text_colour = K.ink,
            font = T.font, text_size = 15, nine_slice = T.frames.slot } }
end

local function heading(text)
    local label = T.label(text, 16, K.brass)
    label.size = C.label_height
    return label
end

-- Nothing to carve: the whole body says so, and nothing else is offered.
local function empty()
    return T.box("column", {
        T.space(1),
        heading("MATERIAL NEEDED"),
        T.hint("Dig some material to begin shaping."),
        T.hint("Existing shapes and named items are kept intact."),
        T.space(1),
    })
end

-- # One screen, no scrolling
--
-- The editor sits in a well on the left, as tall as the body; every control
-- is in the column on the right. The column's rows have fixed heights and a
-- spacer between the options and the craft buttons, so it fills the body
-- exactly and a small window shrinks it rather than pushing Craft off the
-- bottom.
local function build(player, data)
    local list = craft.stock(player)
    local names, selected, entry = {}, nil, nil
    data.options = {}
    for i, item in ipairs(list) do
        names[i] = craft.friendly(item.id) .. "  -  " .. item.units
        data.options[i] = item.id
        if item.id == data.material then selected, entry = i, item end
    end
    if not data.material and list[1] then
        selected, entry, data.material = 1, list[1], list[1].id
    end
    if #list == 0 then return empty() end
    if not entry then
        -- The chosen material ran out. Require an explicit choice, so a queued
        -- double-click never silently crafts from the next material instead.
        table.insert(names, 1, "Choose a material >")
        table.insert(data.options, 1, false)
        selected = 1
    end

    local editor
    if entry then
        editor = { type = "shape_editor", name = "cut", shape = data.mask, material = entry.material,
            grow = 1, size = 0, style = { background = K.clear } }
    else
        editor = T.box("column", { T.space(1), T.hint("Choose a material to carve."), T.space(1) })
        editor.grow, editor.size = 1, 0
    end
    local well = T.well(editor, 10)
    well.size = C.editor_width

    local message = T.label(data.message, 15, K.accent)
    message.size = C.label_height
    local controls = T.box("column", {
        heading("MATERIAL"),
        dropdown(names, selected),
        T.row({ T.wide_button("slab", "Slab"), T.wide_button("stairs", "Stairs") }, C.row_height),
        T.row({ T.wide_button("pillar", "Pillar"), T.wide_button("reset", "Full block") }, C.row_height),
        -- The editor owns its live mask, and a redraw echoing an older one
        -- would undo newer clicks, so there is no live cost here: a fixed
        -- rule that is always true instead.
        T.hint("Left: carve   /   Right: restore"),
        T.hint("Arrows: turn   /   1 unit a cell"),
        T.space(1),
        message,
        T.row({ T.wide_button("make", "Craft one", true, 15),
            T.wide_button("make_stack", "Craft stack", true, 15) }, C.row_height + 6),
    })
    controls.grow, controls.size = 1, 0
    return T.box("row", { well, controls }, 16)
end

local function on_event(player, data, event)
    local name = event.name
    if event.kind == "chiselled" and name == "cut" then
        -- Not redrawn: see the note on the cost line above.
        if math.type(event.shape) == "integer" and event.shape >= 0 and event.shape <= craft.FULL then
            data.mask, data.message = event.shape, ""
        end
        return false
    end
    if event.kind == "chose" and name == "material" then
        local id = data.options[event.index]
        if not id then return false end
        data.material, data.message = id, ""
        return true
    end
    if event.kind ~= "pressed" then return false end
    if name == "reset" then
        data.mask, data.message = craft.FULL, ""
    elseif craft.preset(name) then
        data.mask, data.message = craft.preset(name), ""
    elseif name == "make" or name == "make_stack" then
        data.message = craft.craft(player, data.material, data.mask, name == "make_stack")
    else
        return false
    end
    return true
end

tdi.screen.add_tab{
    id = "shapes",
    label = "Crafting",
    order = C.tab_order_shapes,
    fresh = fresh,
    on_enter = function(_, data) data.message = "" end,
    build = build,
    on_event = on_event,
}

return {}
