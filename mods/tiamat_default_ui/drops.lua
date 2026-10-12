-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A held stack clicked outside the sheet lands in the world, and walking over
-- it picks it back up (engine ask 21).
--
-- The engine takes the portion off the cursor and asks this mod what it
-- becomes: all of it on a left-click, a block on a right, a unit on a
-- shift-right. Here it becomes a stack lying on the ground, tossed along the
-- player's `facing`. The engine decides nothing else about it, so how long it
-- lasts and who may take it back are written here, the same shape as the
-- reference `core_gear` loop. Only this mod's own drops are looked after:
-- `entities_in_radius` filters on the mod that spawned them, so Life's drops
-- and core_gear's are theirs.

local M = {}

local LIFT = 1.2               -- blocks above the feet it starts at
local AHEAD = 0.8              -- blocks in front of the body
local THROW = 0.5              -- cells a tick along `facing`: a toss, not a throw
local LOFT = 0.25              -- cells a tick upward on top of the aim
local REACH = 1.5              -- blocks a player picks up from
local SETTLE = 60              -- ticks the dropper waits before it comes back to them
local DESPAWN = 20 * 60 * 5    -- five minutes
local RETRY = 20               -- ticks before a pickup a full pack refused is tried again

local tracked = {}             -- entity id -> { owner, ticks, retry }
local players = {}             -- who is here, to look outward from

-- The stack as `game.give` and an item entity both take it.
local function spec_of(stack, units)
    return { material = stack.material, units = units or stack.units, shape = stack.shape,
        cells = stack.cells, detail = stack.detail }
end

-- Puts `stack` on the ground in front of `player`. Answers whether it did:
-- nothing to stand on (no body, no world) is `false`, and the engine then
-- puts the stack back on the cursor.
function M.throw(player, stack)
    if type(stack) ~= "table" or math.type(stack.units) ~= "integer" or stack.units < 1 then
        return false
    end
    local body = game.player_entity(player)
    local e = body and game.entity(body)
    if not e then return false end
    local f = e.facing
    local id = game.spawn_entity{
        pos = { x = e.pos.x + f.x * AHEAD, y = e.pos.y + LIFT + f.y * AHEAD, z = e.pos.z + f.z * AHEAD },
        item = spec_of(stack),
        collider = { width = 0.5, height = 0.5 },
    }
    if id == nil then return false end
    game.set_entity(id, { velocity = { x = f.x * THROW, y = f.y * THROW + LOFT, z = f.z * THROW } })
    tracked[id] = { owner = player, ticks = 0 }
    return true
end

tdi.on_join(function(event) players[event.player] = true end)
tdi.on_leave(function(event) players[event.player] = nil end)

tdi.on_tick(function(dt)
    -- Anything of ours lying near a player that this session does not
    -- remember (the world was closed and reopened) is adopted as settled.
    for uuid in pairs(players) do
        local body = game.player_entity(uuid)
        local e = body and game.entity(body)
        if e then
            for _, id in ipairs(game.entities_in_radius(e.pos, REACH + 1, game.mod_id)) do
                if tracked[id] == nil then
                    local item = game.entity(id)
                    if item and item.item then tracked[id] = { owner = nil, ticks = SETTLE } end
                end
            end
        end
    end

    -- What a full pack left behind, tracked once the walk is done: Lua's
    -- `pairs` may not meet a key added while it runs.
    local rests = {}
    for id, watch in pairs(tracked) do
        local item = game.entity(id)
        if item == nil or item.item == nil then
            tracked[id] = nil
        else
            watch.ticks = watch.ticks + dt
            if watch.ticks > DESPAWN then
                game.despawn_entity(id)
                tracked[id] = nil
            elseif watch.ticks >= (watch.retry or 0) then
                -- Nearest first, so two players reaching at once resolve the
                -- same way every time.
                for _, near in ipairs(game.entities_in_radius(item.pos, REACH, "engine:player")) do
                    local person = game.entity(near)
                    local who = person and person.owner
                    if who and not (who == watch.owner and watch.ticks < SETTLE) then
                        -- The pack is fixed at 28 slots, so a give can fall
                        -- short: what did not go in stays on the ground.
                        local gave, left = game.give(who, spec_of(item.item))
                        left = left or (gave and 0 or item.item.units)
                        if left >= item.item.units then
                            watch.retry = watch.ticks + RETRY
                        else
                            game.despawn_entity(id)
                            tracked[id] = nil
                            if left > 0 then
                                local rest = game.spawn_entity{ pos = item.pos,
                                    item = spec_of(item.item, left), collider = { width = 0.5, height = 0.5 } }
                                if rest then rests[#rests + 1] = rest end
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    for _, id in ipairs(rests) do tracked[id] = { owner = nil, ticks = SETTLE } end
end)

return M
