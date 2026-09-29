<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Asks of the sibling mods

What the interface needs from the OTHER mods beside the engine, as
`docs/engine-asks.md` holds what it needs from the engine. Each says what was
wanted, what stands in for it today, and the smallest change that would
answer it. Newest first.

## Tiamat Default Craft

### C2. The hand tab where the Crafting tab was (2026-09-29): OPEN, low

**Wanted.** The shape crafter has left the inventory for its block, so the
strip a player carries is Inventory and Craft's hand tab. Craft's tab is
labelled "Craft" at `order = 25`; at `order = 20` it takes the place the
Crafting tab had, next to Inventory, whatever else is loaded.

**Standing in.** Nothing needed: at 25 it is already second whenever no
other mod's tab sits between 10 and 25.

### C1. A recipe for the shape crafter (2026-09-29): OPEN

**Wanted.** A way to make the shape crafter block
(`tiamat_default_ui:shape_crafter`, also `exports.shape_crafter`). It is the
building table, not a step in progression, so it wants to come early: at the
workbench, from wood and stone, soon after the workbench itself.

**Why here and not in the interface.** Recipes are Craft's registry, and
Craft lists the interface in `optional_depends`, so the interface cannot list
Craft back to call `register`: that is a dependency cycle. The recipe has to
be registered from Craft's side.

**Standing in.** An operator's give, or a creative world. The block works as
soon as a player has one.
