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

-- Presets other mods add (`exports.add_preset`), in the order they came.
-- Each is `{ id, label, mask, visible }`; `visible(player)` runs in the
-- adding mod's sandbox, so an error there disables that mod, answers nil
-- here, and hides the preset.
M.added = {}
local added_ids = {}

-- Checks and keeps another mod's preset. Never errors: `true`, or `nil` and why.
function M.add_preset(spec)
    if type(spec) ~= "table" then return nil, "add_preset takes a table" end
    local id, label, mask, visible = spec.id, spec.label, spec.mask, spec.visible
    if type(id) ~= "string" or not id:match("^[%w_]+:[%w_]+$") then
        return nil, "preset id must be qualified, like \"my_mod:gear\""
    end
    if added_ids[id] then return nil, "a preset with id " .. id .. " already exists" end
    if type(label) ~= "string" or #label < 1 or #label > tdi.config.max_preset_label then
        return nil, "preset label must be 1 to " .. tdi.config.max_preset_label .. " bytes"
    end
    if math.type(mask) ~= "integer" or mask <= 0 or mask >= M.FULL then
        return nil, "preset mask must be a 27-bit mask with at least one cell and not all 27"
    end
    if visible ~= nil and type(visible) ~= "function" then
        return nil, "preset visible must be a function or nil"
    end
    added_ids[id] = true
    M.added[#M.added + 1] = { id = id, label = label, mask = mask, visible = visible }
    return true
end

-- The added presets `player` is shown, at most `most` of them.
function M.presets_for(player, most)
    local list = {}
    for _, preset in ipairs(M.added) do
        if #list >= most then break end
        if preset.visible == nil or preset.visible(player) == true then list[#list + 1] = preset end
    end
    return list
end

-- Loose material a player carries, as `{ id, material, units }`, sorted by
-- block id.
--
-- The order is canonical so that using up one material never moves the
-- others under the pointer. Already-cut stacks and stacks with a
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

-- Crafts up to `want` of `mask` from block `id`: as many as the material and
-- one stack allow, so asking for ten with enough for three makes three.
-- Returns the line to show the player, one short sentence that must fit the
-- crafter's column at 800x600 (the native check measures every one), and how
-- many were made.
--
-- Take first, then give. The engine's take is partial by design, so a short
-- take is returned whole, and a give that fails returns what was taken:
-- whatever happens, the player ends with the units they started with or with
-- the shapes those units paid for.
function M.craft(player, id, mask, want)
    local cost = M.cells(mask)
    if cost == 0 then return "Restore a cell first.", 0 end
    if cost == 27 then return "Carve a cell or pick a preset.", 0 end

    local entry
    for _, item in ipairs(M.stock(player)) do
        if item.id == id then entry = item; break end
    end
    if not entry then return "None of that left.", 0 end

    local count = math.min(want, game.ITEMS_PER_STACK, entry.units // cost)
    if count < 1 then return "Not enough for that shape.", 0 end

    local price = count * cost
    local spent = game.take(player, { material = entry.material, units = price })
    if spent ~= price then
        if spent > 0 then game.give(player, { material = entry.material, units = spent }) end
        return "Nothing crafted. Try again.", 0
    end
    -- A full pack can take PART of the stack (`player:main` is fixed at 28).
    -- All or nothing: what went in comes back out, and then the material,
    -- which fits because the pack is as it was before the take.
    local gave, left = game.give(player, { material = entry.material, shape = mask, count = count })
    if not gave then
        local placed = price - (left or price)
        if placed > 0 then
            game.take(player, { material = entry.material, shape = mask, units = placed })
        end
        game.give(player, { material = entry.material, units = spent })
        return "No room. Material returned.", 0
    end
    local body = game.player_entity(player)
    local e = body and game.entity(body)
    if e then game.cue{ cue = "craft", pos = e.pos, radius = 12 } end
    return "Made " .. count .. " " .. M.friendly(id), count
end

return M
