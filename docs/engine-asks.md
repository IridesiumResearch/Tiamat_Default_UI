# Engine asks from the Inventory mod

What the inventory has needed from the engine, found by building it. Each entry
says what was seen, why the mod cannot fix it, and the smallest engine change
that would. Newest first. Items are removed when they land.

Nothing open. Landed so far, all asserted by the native check:

- **1**, a table handed back to its owner iterates, and **2**, a disabled
  mod's functions stop — engine 823aac3.
- **4**, a picture a HUD script draws is fetched, and **0**, a mod can ask for
  a content hash — engine 6aae28c, protocol v61. `game.register_picture` puts
  the hotbar's slot frame in the table every client fetches on join and answers
  its hash, which `hotbar.lua` sends to the script with `game.set_hud`;
  `game.content_hash` gives the dialog frames theirs. No hash is written by
  hand anywhere in this mod.
