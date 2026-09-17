-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tiamot Default UI: the inventory screen, the shape crafter and the
-- hotbar. This file only decides load order and publishes the exports.
--
-- Every file below is loaded exactly once and hangs what it offers off the
-- `tdi` global, which the sandbox shares between this mod's own files and no
-- one else's. The engine's `require` is confined to this directory and does
-- not cache, so a file required twice would run twice; nothing but this file
-- calls it.
--
-- Presentation and recipes belong to this mod. The engine owns slot
-- transfers, input bindings, shape interaction and authoritative stacks.

tdi = {}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("%s: %s.lua failed: %s", game.mod_id, name, tostring(result)))
        error(result, 0)
    end
    return result
end

tdi.config = load("config")
tdi.theme = load("theme")         -- palette, frames, the display font, widget helpers
load("hooks")                     -- one engine registration per hook, many subscribers
tdi.crafting = load("crafting")   -- loose stock, shape masks and the craft transaction
tdi.screen = load("screen")       -- sessions, the tab and button registries, the dialog
load("tab_items")                 -- Inventory: quick access, pack pages, off-hand
load("tab_shapes")                -- Shape crafter

-- What other mods may call. One export per mod, so it is built whole first.
game.export(load("exports"))

-- The hotbar: the script, drawn on the player's machine from the engine's own
-- HUD state, and the one value it needs from this side.
game.register_hud_script("hud.lua")
load("hotbar")

game.register_sound{ id = "click", file = "sounds/click.wav", gain = 0.35 }
game.bind_sound("engine:ui_click", "click")
game.bind_sound("engine:ui_close", "click")
