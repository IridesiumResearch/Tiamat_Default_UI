-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- How the screen looks: the palette, the frames, the display font, and the
-- few widget builders every tab is made of. Another mod's tab can use the
-- same builders through the exports, so it matches without copying numbers.

local C = tdi.config

local T = {}

game.register_font{ id = "display", file = "fonts/CinzelDecorative-Bold.ttf" }
T.font = game.mod_id .. ":display"

-- The dialog palette. The HUD keeps its own, brighter copy in hud.lua: a HUD
-- script cannot load files, and it is drawn over the world, not a dark panel.
T.colours = {
    clear = { 0, 0, 0, 0 },
    edge = { 89, 94, 94, 255 },
    brass = { 154, 132, 92, 255 },
    ink = { 225, 215, 191, 255 },
    muted = { 157, 164, 162, 255 },
    accent = { 121, 195, 184, 255 },
}
local K = T.colours

-- The frames, by content hash. A dialog's tree is its own manifest, so the
-- client fetches these when the screen arrives and asking for the hash is
-- enough; the hotbar's picture is REGISTERED below, because a HUD script names
-- a picture only as it draws it and nothing would have fetched the bytes.
T.frames = {
    panel = game.content_hash("textures/ornate-panel.png"),
    slot = game.content_hash("textures/iron-slot.png"),
}

-- The hotbar's slot frame, for hud.lua. hotbar.lua hands this hex to the
-- script with `game.set_hud`; nothing is pasted by hand or can go stale.
T.hotbar_frame = game.register_picture{ id = "hotbar_slot", file = "textures/hotbar-slot.png" }

-- Builders --------------------------------------------------------------------
--
-- Framed widgets set a CLEAR background: the engine paints a nine-slice
-- under `background`, so any fill would cover the frame.

function T.label(text, size, colour)
    return { type = "label", text = text,
        style = { font = T.font, text_size = size or 17, text_colour = colour or K.ink } }
end

function T.box(direction, children, gap, padding, style)
    return { type = "container", direction = direction, children = children,
        gap = gap or 8, padding = padding or 0, align = "stretch", style = style }
end

-- An `active` button is drawn in brass: the selected tab, or the action a
-- screen is for.
function T.button(name, text, active)
    return { type = "button", name = name, text = text, cross_size = C.button_height,
        style = { background = K.clear, border = active and K.brass or K.edge,
            text_colour = active and K.ink or K.muted, font = T.font, text_size = 19,
            nine_slice = T.frames.slot } }
end

-- A tab: its button over an underline, thick and brass when it is selected.
function T.tab_button(name, text, active)
    local button = T.button(name, text, active)
    button.size, button.cross_size = C.button_height, nil
    local underline = { type = "spacer", size = C.tab_underline,
        style = { background = active and K.brass or K.edge } }
    local tab = T.box("column", { button, underline }, 0)
    tab.cross_size = C.button_height + C.tab_underline
    return tab
end

-- A titled panel in the ornate frame. `children` is not modified.
function T.section(title, children)
    local list = { T.label(title, 18, K.brass) }
    for _, child in ipairs(children) do
        list[#list + 1] = child
    end
    return T.box("column", list, 10, 32,
        { background = K.clear, border = K.edge, nine_slice = T.frames.panel })
end

-- One inventory cell. `active` gives it a brass edge, as the off-hand has.
function T.slot(view, index, active)
    return { type = "item_slot", view = view, index = index, size = C.cell, cross_size = C.cell,
        style = { background = K.clear, border = active and K.brass or K.edge,
            text_colour = K.ink, text_size = 15, nine_slice = T.frames.slot } }
end

-- A frame of `padding` around one widget, as the shape editor sits in.
function T.well(child, padding)
    return T.box("column", { child }, 0, padding or 12,
        { background = K.clear, nine_slice = T.frames.slot })
end

-- The whole screen: the ornate outer frame.
function T.frame(children)
    return T.box("column", children, 10, 32,
        { background = K.clear, border = K.brass, nine_slice = T.frames.panel })
end

return T
