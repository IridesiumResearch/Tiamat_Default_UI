# Artwork and typography

The frames derive from the ornate iron/brass and ivory-corner artwork generated
for revision 0.2. They are compiled to the engine's fixed equal-third layout:

- `ornate-panel.png`: 108×108, 36-pixel corners.
- `iron-slot.png`: 36×36, 12-pixel corners.
- `hotbar-slot.png`: 144×144, drawn whole into square HUD cells.

The old source split at 25% and 75%. Each of those nine source regions was
resampled into one equal tile of the new atlas, preserving which region forms
each corner and rail. Only the runtime rails and center stretch. This prevents
the original 1254-pixel artwork from producing 418-point corners.

All hashes are BLAKE3 of `tiamot:content:v1` followed by the exact file bytes.
Nothing writes one down: `theme.lua` asks `game.content_hash` for the dialog
frames, and `game.register_picture` answers the hotbar's and puts it in the
table clients fetch on join, which `hotbar.lua` passes to the HUD script with
`game.set_hud`. The native check confirms the registration and that the hash
the script is sent is the shipped file's; the preview resolves both dialog and
HUD references through the same hashes.

Framed widgets specify transparent backgrounds, because the native renderer
paints their backgrounds after the frame. Text and borders remain separate.

`mods/tiamot_default_ui/fonts/CinzelDecorative-Bold.ttf` is unchanged from Google Fonts:
https://github.com/google/fonts/tree/main/ofl/cinzeldecorative
Its SIL Open Font License is included as `fonts/OFL.txt`.

The mod registers `tiamot_default_ui:display` and selects it through `style.font`.
This changes dialog text only; native menus and HUD labels retain engine fonts.
A client that cannot load the font uses the engine fallback.
