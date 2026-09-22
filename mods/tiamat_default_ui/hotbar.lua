-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The server's half of the hotbar: what hud.lua needs and cannot work out.
--
-- Counts, shapes, the selection and the off-hand are the ENGINE's, and reach
-- the script without this mod touching them. All that is left is the slot
-- frame's content hash, which a script cannot compute and cannot be told any
-- other way, so it is sent on join. `set_hud` replaces this mod's whole set
-- for that player, which is what it should do: there is one value.

local T = tdi.theme

tdi.on_join(function(event)
    game.set_hud(event.player, { slot_frame = T.hotbar_frame })
end)

return {}
