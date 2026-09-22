-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The hotbar, drawn on the player's machine.
--
-- A HUD script is sandboxed hard: no `require`, no files, instruction and
-- memory caps. So this file stands alone, with its own palette, and the slot
-- frame's content hash reaches it as a value hotbar.lua sends. It draws and
-- does not compute: counts, shapes and the selection come from the engine,
-- and a hole in the hotbar never collapses or moves another slot.
--
-- Geometry is in virtual pixels, anchored to the bottom centre.

local SLOT, GAP, SLOTS = 72, 6, 9
local PITCH = SLOT + GAP

-- Brighter than the dialog palette in theme.lua: this is drawn over the world.
local C = {
    shadow = { 0, 0, 0, 90 }, base = { 17, 20, 23, 235 },
    edge = { 84, 91, 93, 255 }, bevel = { 117, 120, 116, 255 },
    brass = { 181, 155, 108, 255 }, muted = { 160, 169, 168, 255 },
    ink = { 235, 223, 196, 255 }, accent = { 119, 202, 187, 255 },
}

-- The status line is trimmed to this many bytes, inside the HUD's text budget.
local LINE_BYTES = 64

local function rect(x, y, w, h, colour)
    hud.rect{ anchor = "bottom", x = x, y = y, w = w, h = h, colour = colour }
end

local function text(x, y, value, size, colour)
    hud.text{ anchor = "bottom", x = x, y = y, text = value, size = size, colour = colour }
end

-- Three rectangles make a small clipped corner without an image.
local function chamfer(x, y, w, h, colour)
    rect(x + 2, y, w - 4, h, colour)
    rect(x + 1, y - 1, 1, h - 2, colour)
    rect(x + w - 2, y - 1, 1, h - 2, colour)
end

-- Loose material is whole blocks and spare nodes ("1+13"); a cut is a count.
local function quantity(slot)
    if slot.count then return tostring(slot.count) end
    if slot.nodes == 0 then return tostring(slot.blocks) end
    if slot.blocks == 0 then return "+" .. slot.nodes end
    return slot.blocks .. "+" .. slot.nodes
end

local function draw_slot(x, key, stack, selected, frame)
    local y = SLOT + 24
    chamfer(x - 2, y + 2, SLOT + 4, SLOT + 4, C.shadow)
    chamfer(x, y, SLOT, SLOT, selected and C.brass or C.edge)
    -- Nothing to draw until the hash arrives: the rectangles above are the
    -- slot either way, so an empty first frame is a plainer one, not a hole.
    if frame then
        hud.image{ anchor = "bottom", x = x + 2, y = y - 2, w = SLOT - 4, h = SLOT - 4, hash = frame }
    end
    rect(x + 4, y - 2, SLOT - 8, 1, selected and C.ink or C.bevel)
    if selected then
        rect(x + 13, 25, SLOT - 26, 2, C.accent)
    end
    if stack then
        hud.icon{ anchor = "bottom", x = x + 13, y = y - 13, size = SLOT - 26,
            material = stack.material, shape = stack.shape }
        -- A dark backing keeps the quantity readable over a pale icon.
        local q = quantity(stack)
        local width = #q * 11 + 6
        rect(x + SLOT - width - 4, 43, width, 17, C.base)
        text(x + SLOT - width - 1, 43, q, 17, C.ink)
    end
    text(x + 5, y - 4, key, 14, selected and C.ink or C.muted)
end

-- Cuts a line to `LINE_BYTES` on a whole UTF-8 character, with an ellipsis.
local function trim(line)
    if #line <= LINE_BYTES then return line end
    local last = LINE_BYTES - 3
    while line:byte(last + 1) >= 128 and line:byte(last + 1) < 192 do
        last = last - 1
    end
    return line:sub(1, last) .. "..."
end

hud.on_draw(function(state)
    local width = SLOTS * PITCH - GAP
    local left = -(width // 2)
    chamfer(left - 12, SLOT + 35, width + 24, SLOT + 28, C.shadow)
    chamfer(left - 8, SLOT + 32, width + 16, SLOT + 22, C.base)
    rect(left + 6, SLOT + 31, width - 12, 1, C.edge)
    local frame = state.values.slot_frame
    for index = 1, SLOTS do
        draw_slot(left + (index - 1) * PITCH, tostring(index), state.carried[index], index == state.selected, frame)
    end
    if state.offhand then
        draw_slot(left - PITCH - 12, "II", state.offhand, false, frame)
    end
    local line = state.tool and state.tool.name or "Empty hand"
    if state.looking_at then line = line .. "  /  " .. state.looking_at.name end
    text(left + 6, SLOT + 58, trim(line), 18, C.muted)
end)
