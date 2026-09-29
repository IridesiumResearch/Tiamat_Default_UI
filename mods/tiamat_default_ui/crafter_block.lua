-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The shape crafter as a block: placed like any block, and right-clicked to
-- open the screen on its tab, the way a crafting table opens its grid. The
-- tab is not in the inventory a player carries (screen.lua, `station`).
--
-- How a player comes by one is a recipe, and recipes are Tiamat Default
-- Craft's: it depends on this mod, so this mod cannot depend back and
-- register one itself (docs/sibling-asks.md, C1). Without Craft, it is had
-- the way any block is: an operator's give, or a creative world.

local BLOCK = "shape_crafter"

game.register_block{
    id = BLOCK,
    name = "Shape crafter",
    description = "Carves loose material into slabs, stairs and any shape you cut.",
    hardness = 2.0,
    tags = { "station", "crafting" },
    textures = { all = "textures/shape-crafter.png" },
}

game.register_on_use(function(event)
    if tdi.screen.open_station(event.player, "shapes") then return "" end
end, { materials = { BLOCK } })

return { block = game.mod_id .. ":" .. BLOCK }
