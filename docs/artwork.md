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

Two faces, both unchanged from Google Fonts and under the SIL Open Font
License, each with its licence beside it:

- `fonts/CinzelDecorative-Bold.ttf`, the display face, for titles, headings and
  buttons: https://github.com/google/fonts/tree/main/ofl/cinzeldecorative
  (`fonts/OFL-Cinzel.txt`).
- `fonts/Spectral-Regular.ttf`, the text face, for anything read as a sentence:
  https://github.com/google/fonts/tree/main/ofl/spectral
  (`fonts/OFL-Spectral.txt`). A serif drawn for screens, it is about 0.46 em a
  character over this mod's strings, against Cinzel's 0.83, and its lowercase
  is lowercase where Cinzel's is small capitals.

The mod registers them as `tiamot_default_ui:display` and `tiamot_default_ui:text`
and selects them through `style.font`. `[theme] font` is Cinzel, so the engine's
own screens, chat included, draw everything in it, and a widget that names no
font does too. That is why hints name the text face. Chat cannot yet be given
Spectral: see ask 9 in `docs/engine-asks.md`. A client that cannot load a font
uses the engine's fallback.
