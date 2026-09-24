-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The shape crafter's rules, apart from its screen: which stacks count as
-- material, what the presets are, and the craft itself.
--
-- A shape costs one unit of loose material per occupied cell, so a craft
-- neither creates nor destroys units.

local M = {}

M.FULL = game.OCCUPANCY_FULL

-- How many of a mask's 27 cells are occupied. Masks use the engine's
-- x + 3*y + 9*z indexing.
function M.cells(mask)
    local n = 0
    for bit = 0, 26 do
        if mask & (1 << bit) ~= 0 then n = n + 1 end
    end
    return n
end

-- The mask a preset button sets, or nil for a name that is not one.
-- Slab 9 cells, stairs 18, pillar 3.
function M.preset(kind)
    local rule
    if kind == "slab" then
        rule = function(x, y, z) return y == 0 end
    elseif kind == "stairs" then
        rule = function(x, y, z) return y <= z end
    elseif kind == "pillar" then
        rule = function(x, y, z) return x == 1 and z == 1 end
    else
        return nil
    end
    local mask = 0
    for z = 0, 2 do
        for y = 0, 2 do
            for x = 0, 2 do
                if rule(x, y, z) then mask = mask | (1 << (x + 3 * y + 9 * z)) end
            end
        end
    end
    return mask
end

-- Loose material a player carries, as `{ id, material, units }`, sorted by
-- block id.
--
-- The order is canonical so that using up one material never shifts a
-- dropdown index onto a different one. Already-cut stacks and stacks with a
-- `detail` (named, worn, enchanted: another mod's business) are left out, so
-- the crafter never consumes them.
function M.stock(player)
    local result = {}
    for _, entry in ipairs(game.inventory(player)) do
        local id = game.block_of(entry.material)
        if id and not entry.shape and not entry.detail and entry.units > 0 then
            result[#result + 1] = { id = id, material = entry.material, units = entry.units }
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

-- A block id as a player reads it: "core:rough_stone" is "rough stone".
function M.friendly(id)
    local name = (id:match(":(.+)$") or id):gsub("_", " ")
    return name
end

-- Crafts one of `mask` from block `id`, or as many as fit a stack. Returns
-- the line to show the player: one short sentence, which must fit the
-- crafter's column at 800x600 (the native check measures every one).
--
-- Take first, then give. The engine's take is partial by design, so a short
-- take is returned whole, and a give that fails returns what was taken:
-- whatever happens, the player ends with the units they started with or with
-- the shapes those units paid for.
function M.craft(player, id, mask, stack)
    local cost = M.cells(mask)
    if cost == 0 then return "Restore at least one cell first." end
    if cost == 27 then return "Carve a cell or pick a preset." end

    local entry
    for _, item in ipairs(M.stock(player)) do
        if item.id == id then entry = item; break end
    end
    if not entry then return "Choose a material you have." end

    local count = stack and math.min(game.ITEMS_PER_STACK, entry.units // cost) or 1
    if count < 1 or entry.units < cost * count then return "Not enough material for that." end

    local price = count * cost
    local spent = game.take(player, { material = entry.material, units = price })
    if spent ~= price then
        if spent > 0 then game.give(player, { material = entry.material, units = spent }) end
        return "Nothing crafted. Try again."
    end
    if not game.give(player, { material = entry.material, shape = mask, count = count }) then
        game.give(player, { material = entry.material, units = spent })
        return "No room. Material returned."
    end
    local body = game.player_entity(player)
    local e = body and game.entity(body)
    if e then game.cue{ cue = "craft", pos = e.pos, radius = 12 } end
    return "Crafted " .. count .. "  /  " .. price .. " units used"
end

return M
