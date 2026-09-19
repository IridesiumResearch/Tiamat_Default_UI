-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- How the screen looks: the palette, the frames, the two fonts, and the
-- few widget builders every tab is made of. Another mod's tab can use the
-- same builders through the exports, so it matches without copying numbers.

local C = tdi.config

local T = {}

-- Two faces: Cinzel Decorative for what is read at a glance (titles,
-- headings, buttons) and Spectral, a serif made for screens, for what is read
-- as sentences. Cinzel's lowercase is small capitals, which is handsome in a
-- heading and hard going in a line of instructions.
game.register_font{ id = "display", file = "fonts/CinzelDecorative-Bold.ttf" }
game.register_font{ id = "text", file = "fonts/Spectral-Regular.ttf" }
T.font = game.mod_id .. ":display"
T.text_font = game.mod_id .. ":text"

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
--
-- A builder sets at most `size`, the length along its parent's direction,
-- because the engine shrinks that when a row or column is over-full. It never
-- sets `cross_size`, which the engine does not cap: a squeezed row would have
-- let it spill out. Across, a widget takes the parent's whole breadth, which is
-- what `align = "stretch"` on every box gives it.

-- Display-font text: titles, headings, buttons.
function T.label(text, size, colour)
    return { type = "label", text = text,
        style = { font = T.font, text_size = size or 17, text_colour = colour or K.ink } }
end

-- Small print in the text face, which is narrower and more legible at hint
-- sizes than the display font. Named rather than left to the client, because
-- the [theme] puts the display font on everything that names none.
function T.hint(text)
    return { type = "label", text = text, size = C.hint_height,
        style = { font = T.text_font, text_size = 13, text_colour = K.muted } }
end

function T.box(direction, children, gap, padding, style)
    return { type = "container", direction = direction, children = children,
        gap = gap or C.gap, padding = padding or 0, align = "stretch", style = style }
end

-- A row `size` tall (or wide, in a row), children stretched across it.
function T.row(children, size, gap)
    local row = T.box("row", children, gap)
    row.size = size
    return row
end

-- Empty space: `grow` shares out what is left, `size` is a fixed gap.
function T.space(grow, size)
    return { type = "spacer", grow = grow or 0, size = size }
end

-- An `active` button is drawn in brass: the selected tab, or the action a
-- screen is for. Its height is whatever row it is in; give it `size` in a
-- column. `text_size` defaults to 17.
function T.button(name, text, active, text_size)
    return { type = "button", name = name, text = text,
        style = { background = K.clear, border = active and K.brass or K.edge,
            text_colour = active and K.ink or K.muted, font = T.font, text_size = text_size or 17,
            nine_slice = T.frames.slot } }
end

-- A button that takes an equal share of its row.
function T.wide_button(name, text, active, text_size)
    local button = T.button(name, text, active, text_size)
    button.grow = 1
    return button
end

-- A tab: its button over an underline, brass when it is selected.
function T.tab_button(name, text, active)
    local button = T.button(name, text, active, 15)
    button.size = C.tab_height - C.tab_underline
    local underline = { type = "spacer", size = C.tab_underline,
        style = { background = active and K.brass or K.edge } }
    return T.box("column", { button, underline }, 0)
end

-- A heading over its contents. No frame: the screen has one, and a frame
-- inside a frame is the "boxes within boxes" this layout exists to remove.
-- `children` is not modified.
function T.section(title, children)
    local heading = T.label(title, 16, K.brass)
    heading.size = C.label_height
    local list = { heading }
    for _, child in ipairs(children) do
        list[#list + 1] = child
    end
    return T.box("column", list)
end

-- One inventory cell, `C.cell` along its row; across, the row's height.
-- `active` gives it a brass edge, as the off-hand has.
function T.slot(view, index, active)
    return { type = "item_slot", view = view, index = index, size = C.cell,
        style = { background = K.clear, border = active and K.brass or K.edge,
            text_colour = K.ink, text_size = 15, nine_slice = T.frames.slot } }
end

-- An iron frame of `padding` around one widget, as the shape editor sits in.
function T.well(child, padding)
    return T.box("column", { child }, 0, padding or 12,
        { background = K.clear, nine_slice = T.frames.slot })
end

-- The whole screen. The ornate frame around it is the engine's: mod.toml's
-- `[theme]` gives every sheet this mod's frame, the inventory's included, so
-- the tree adds only the padding that keeps its contents off the frame's
-- corners. A frame here as well would be a frame inside a frame.
function T.frame(children)
    return T.box("column", children, 10, C.frame_padding)
end

return T
