-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One of each engine hook for the whole mod, with subscribers.
--
-- The engine keeps ONE callback per hook per mod: a second registration is
-- an error. So every file that wants an action, a dialog event or a player
-- joining or leaving subscribes here, and this file holds the single
-- registration of each.

local actions = {}
local joins = {}
local dialogs = {}
local leaves = {}

-- Runs `fn(event)` when a player presses or releases the qualified action `id`.
function tdi.on_action(id, fn)
    actions[id] = actions[id] or {}
    local list = actions[id]
    list[#list + 1] = fn
end

-- Runs `fn(event)` for events from the dialog this mod showed as `form`
-- (unqualified; the engine reports it qualified).
function tdi.on_dialog(form, fn)
    local qualified = game.mod_id .. ":" .. form
    assert(not dialogs[qualified], "dialog subscribed twice: " .. form)
    dialogs[qualified] = fn
end

function tdi.on_join(fn)
    joins[#joins + 1] = fn
end

function tdi.on_leave(fn)
    leaves[#leaves + 1] = fn
end

game.register_on_action(function(event)
    local list = actions[event.id]
    if list == nil then return end
    for _, fn in ipairs(list) do
        fn(event)
    end
end)

game.register_on_dialog_event(function(event)
    local fn = dialogs[event.form]
    if fn then fn(event) end
end)

game.register_on_player_join(function(event)
    for _, fn in ipairs(joins) do
        fn(event)
    end
end)

game.register_on_player_leave(function(event)
    for _, fn in ipairs(leaves) do
        fn(event)
    end
end)

return {}
