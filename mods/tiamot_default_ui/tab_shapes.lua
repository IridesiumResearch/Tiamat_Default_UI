-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The Shape crafter tab: choose a loose material, carve a shape, craft it.
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
        size = C.button_height, style = { background = K.clear, border = K.brass, text_colour = K.ink,
            font = T.font, text_size = 19, nine_slice = T.frames.slot } }
end

local function build(player, data)
    local list = craft.stock(player)
    local names, selected, entry = {}, nil, nil
    data.options = {}
    for i, item in ipairs(list) do
        names[i] = craft.friendly(item.id) .. "  /  " .. item.units .. " units"
        data.options[i] = item.id
        if item.id == data.material then selected, entry = i, item end
    end
    if not data.material and list[1] then
        selected, entry, data.material = 1, list[1], list[1].id
    end
    if not entry then
        -- The chosen material ran out. Require an explicit choice, so a queued
        -- double-click never silently crafts from the next material instead.
        table.insert(names, 1, #list == 0 and "No loose material" or "Choose a material >")
        table.insert(data.options, 1, false)
        selected = 1
    end

    local children = {
        T.label("Choose material, then carve your shape.", 17, K.muted),
        dropdown(names, selected),
    }
    if #list == 0 then
        children[#children + 1] = T.section("MATERIAL NEEDED", {
            T.label("Dig some material to begin shaping.", 16),
            T.label("Existing shapes and named items are kept intact.", 12, K.muted),
        })
    elseif entry then
        children[#children + 1] = T.well({ type = "shape_editor", name = "cut", shape = data.mask,
            material = entry.material, size = C.editor_size, style = { background = K.clear } })
        children[#children + 1] = T.box("row", {
            T.button("slab", "Slab"), T.button("stairs", "Stairs"),
            T.button("pillar", "Pillar"), T.button("reset", "Full block"),
        }, 6)
        children[#children + 1] = T.label("Left: carve   /   Right: restore   /   Arrows: turn", 16, K.muted)
        -- The editor owns its live mask, and a redraw echoing an older one
        -- would undo newer clicks, so there is no live cost here: a fixed
        -- rule that is always true instead.
        children[#children + 1] = T.label("Each remaining cell costs 1 unit per shape.", 17)
        children[#children + 1] = T.box("row", {
            T.button("make", "Craft one", true), T.button("make_stack", "Craft stack", true),
        }, 8)
    end
    if data.message ~= "" then
        children[#children + 1] = T.label(data.message, 17, K.accent)
    end
    return T.section("SHAPE CRAFTER", children)
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
    label = "Shape crafter",
    order = C.tab_order_shapes,
    fresh = fresh,
    on_enter = function(_, data) data.message = "" end,
    build = build,
    on_event = on_event,
}

return {}
