-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What other mods may call: the table `game.exports("tiamot_default_ui")`
-- answers to a mod that lists this one in `depends` or `optional_depends`.
-- The README's "For other mods" section is the contract, with examples.
--
-- # Every function here runs in THIS mod's sandbox
--
-- The engine disables whichever mod wrote the code that errors. An error in a
-- function below would disable the inventory because another mod passed it a
-- number where a table belongs, so none of them raise: they check what they
-- are given and answer `nil` and a reason instead. The functions another mod
-- passes IN (a tab's `build`, a button's `on_press`) are that mod's; if they
-- error, that mod is disabled and the call answers `nil` here, which
-- screen.lua is written to expect.
--
-- Bump `version` when a change would break a reader, and only then.

local S, T = tdi.screen, tdi.theme

local function player_ok(player)
    return type(player) == "string"
end

-- Qualified ids of this mod's own tabs, for `open` and a button's `tab`.
local tabs = {
    items = game.mod_id .. ":items",
    shapes = game.mod_id .. ":shapes",
}

return {
    version = 1,

    tabs = tabs,

    -- `{ id = "my_mod:name", label, build = function(player) -> widget,
    --    on_event = function(player, event) -> true to redraw, order = integer }`
    add_tab = function(spec)
        return S.add_external_tab(spec)
    end,

    -- `{ id = "my_mod:name", label, on_press = function(player), tab = tab id }`.
    -- Without `tab`, the button shows under the tab strip on every tab.
    add_button = function(spec)
        return S.add_external_button(spec)
    end,

    -- Opens the screen for `player`, on `tab` (a qualified tab id) if given.
    -- Answers whether it is open.
    open = function(player, tab)
        if not player_ok(player) then return nil, "open takes a player UUID" end
        local key
        if tab ~= nil then
            key = type(tab) == "string" and S.key_of(tab) or nil
            if not key then return nil, "no tab " .. tostring(tab) end
        end
        return S.open(player, key)
    end,

    close = function(player)
        if player_ok(player) then S.close(player) end
    end,

    -- Rebuilds the screen if `player` has it open: call after changing what
    -- your tab or button shows.
    redraw = function(player)
        if player_ok(player) then S.redraw(player) end
    end,

    is_open = function(player)
        return player_ok(player) and S.is_open(player)
    end,

    -- The qualified id of the tab `player` has selected, or nil.
    current_tab = function(player)
        if not player_ok(player) then return nil end
        return S.tab_id(player)
    end,

    -- The look, for a tab that wants to match it.
    theme = {
        font = T.font,
        colours = T.colours,
        frames = T.frames,
    },

    -- The builders this mod's own tabs are made of. What they answer is
    -- read-only on your side: build a new table around it rather than
    -- changing a field.
    widgets = {
        label = function(text, size, colour)
            return T.label(tostring(text), size, colour)
        end,
        button = function(name, text, active)
            return T.button(name, tostring(text), active)
        end,
        section = function(title, children)
            return T.section(tostring(title), type(children) == "table" and children or {})
        end,
        slot = function(view, index, active)
            return T.slot(view, index, active)
        end,
        box = function(direction, children, gap, padding)
            return T.box(direction, type(children) == "table" and children or {}, gap, padding)
        end,
        well = function(child, padding)
            return T.well(child, padding)
        end,
    },
}
