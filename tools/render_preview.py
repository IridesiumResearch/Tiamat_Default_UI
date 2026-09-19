# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Draw docs/preview.png from the screens the native check laid out.

An approximate illustration, not a game screenshot. Every rectangle comes from
the engine's own `ui::layout`, run by the native check on the real trees at a
1280x720 and an 800x600 window, so where things sit is the engine's answer.
What is stood in for is what only the client draws: item icons, the chiselled
block, and the client's own face for hint text (Go Mono here).

It reads tests/native/target/preview.json, which the native check writes:

    cargo run --manifest-path tests/native/Cargo.toml
    python tools/render_preview.py

Pillow is the only dependency. The engine checkout must sit beside this
repository as ../Tiamot, for its monospace font.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parent / 'Tiamot'
DATA = ROOT / 'tests/native/target/preview.json'
OUT = ROOT / 'docs/preview.png'

if not DATA.exists():
    sys.exit(f'{DATA} is missing: run the native check first (see this file\'s docstring)')
data = json.loads(DATA.read_text())

DISPLAY = 'tiamot_default_ui:display'
FONTS = {name: str(ROOT / path) for name, path in data['fonts'].items()}
MONO = str(ENGINE / 'crates/client/assets/third-party/go-font/Go-Mono.ttf')
textures = {h: Image.open(ROOT / p).convert('RGB') for h, p in data['textures'].items()}

MARGIN, GAP, BAR = 48, 56, 36
FRAME_BORDER = 18  # client::panel's, whatever the art's resolution
screens = data['screens']
W = MARGIN * 2 + GAP + 2 * screens[0]['room'][0]
H = MARGIN + sum(BAR + 44 + s["room"][1] + GAP for s in screens) + 190
im = Image.new('RGB', (W, H), '#101417')
d = ImageDraw.Draw(im)


def font(size, name=None):
    """The face a widget names, or the engine's monospace for one it does not."""
    return ImageFont.truetype(FONTS.get(name, MONO), max(7, round(size)))


def colour(value, fallback):
    return tuple(value[:3]) if value else fallback


def style(node, key):
    return (node.get('style') or {}).get(key)


# --- Stand-ins for what the GPU draws ------------------------------------------

def cube(cx, cy, size, base=(115, 119, 116)):
    dx, dy, h = size * .48, size * .24, size * .53
    top = [(cx, cy - dy), (cx + dx, cy), (cx, cy + dy), (cx - dx, cy)]
    left = [top[3], top[2], (cx, cy + dy + h), (cx - dx, cy + h)]
    right = [top[2], top[1], (cx + dx, cy + h), (cx, cy + dy + h)]
    for points, shade in [(left, .68), (right, .86), (top, 1.16)]:
        d.polygon(points, fill=tuple(min(255, int(v * shade)) for v in base), outline='#252c2e')


def shape(x, y, w, h, mask):
    s = min(w * .18, h * .25)
    cx, cy = x + w / 2, y + h * .32
    for z in range(2, -1, -1):
        for yy in range(3):
            for xx in range(3):
                if mask & (1 << (xx + 3 * yy + 9 * z)):
                    cube(cx + (xx - z) * s * .49, cy + (xx + z) * s * .245 - yy * s * .53, s)


def frame(hash_, x, y, w, h, sliced=True, border=None):
    """A nine-slice, or the whole image: the corners are the outer third,
    drawn `border` pixels deep if given, or at the art's own size."""
    source = textures[hash_]
    x, y, w, h = map(round, (x, y, w, h))
    if w < 2 or h < 2:
        return
    if not sliced:
        im.paste(source.resize((w, h), Image.Resampling.LANCZOS), (x, y))
        return
    ex, ey = (border or source.width / 3), (border or source.height / 3)
    ex, ey = min(ex, w / 2), min(ey, h / 2)
    xs, ys, uv = [0, ex, w - ex, w], [0, ey, h - ey, h], [0, 1 / 3, 2 / 3, 1]
    for row in range(3):
        for column in range(3):
            a, b, c, e = map(round, (xs[column], ys[row], xs[column + 1], ys[row + 1]))
            if c <= a or e <= b:
                continue
            box = (uv[column] * source.width, uv[row] * source.height,
                   uv[column + 1] * source.width, uv[row + 1] * source.height)
            crop = source.crop(tuple(round(v) for v in box))
            im.paste(crop.resize((c - a, e - b), Image.Resampling.LANCZOS), (x + a, y + b))


def text_in(text, x, y, w, h, node, centred=False, inset=0):
    """Text vertically centred in its box, clipped to it as the client clips."""
    size = style(node, 'text_size') or 14
    face = font(size, style(node, 'font'))
    room = w - 2 * inset
    while text and d.textlength(text, font=face) > room:
        text = text[:-1]
    width = d.textlength(text, font=face)
    left = x + (w - width) / 2 if centred else x + inset
    d.text((left, y + (h - size) / 2 - 2), text, font=face,
           fill=colour(style(node, 'text_colour'), '#e0d8c4'))


# Slots with something in them, as the picture's representative inventory.
FILLED = {1: '4+16', 2: '10', 3: '8', 6: '8', 10: '12', 11: '2', 14: '1', 20: '5', 23: '9', 28: '1'}
CUT = (3, 14)


def slot(index, x, y, w, h):
    if index not in FILLED:
        return
    side = min(w, h)
    if index in CUT:
        shape(x + 6, y + 3, w - 12, h - 12, 0x7)
    else:
        cube(x + w / 2, y + h * .31, side * .49, (158, 147, 121) if index % 2 else (107, 121, 122))
    quantity = FILLED[index]
    face = font(13)
    d.text((x + w - 5 - d.textlength(quantity, font=face), y + h - 19), quantity, font=face, fill='#ebdfc4')


def paint(node, ox, oy):
    x, y, w, h = node['rect']
    x, y = x + ox, y + oy
    kind = node['type']
    background = style(node, 'background')
    if background and background[3] > 0:
        d.rectangle((x, y, x + w - 1, y + h - 1), fill=colour(background, '#161a1d'))
    if style(node, 'border') and kind != 'container':
        d.rounded_rectangle((x, y, x + w - 1, y + h - 1), radius=3,
                            outline=colour(style(node, 'border'), '#5b605f'), width=1)
    if style(node, 'nine_slice'):
        frame(style(node, 'nine_slice'), x, y, w, h)
    if kind == 'label':
        text_in(node['text'], x, y, w, h, node)
    elif kind == 'button':
        text_in(node['text'], x, y, w, h, node, centred=True, inset=4)
    elif kind == 'dropdown':
        text_in(node['options'][node['selected'] - 1] + '', x, y, w - 20, h, node, inset=12)
        d.text((x + w - 22, y + h / 2 - 8), 'v', font=font(12), fill='#c9bd9f')
    elif kind == 'checkbox':
        d.rectangle((x + 2, y + h / 2 - 7, x + 16, y + h / 2 + 7), outline='#9aa4a2')
        text_in(node['text'], x + 22, y, w - 22, h, node)
    elif kind == 'item_slot':
        slot(node['index'], x, y, w, h)
    elif kind == 'item_grid':
        columns = node['columns']
        cell = min(w / columns, 40)
        for n in range(node['count']):
            cx, cy = x + (n % columns) * cell, y + (n // columns) * cell
            d.rectangle((cx + 1, cy + 1, cx + cell - 2, cy + cell - 2), outline='#59605f')
    elif kind == 'shape_editor':
        side = min(w, h)
        shape(x + (w - side) / 2, y + (h - side) / 2, side, side, node['shape'])
        for at, arrow in [(x + 4, '<'), (x + w - 30, '>')]:
            d.rounded_rectangle((at, y + 4, at + 26, y + 30), radius=3, fill='#404344')
            d.text((at + 8, y + 7), arrow, font=font(13), fill='#ded6c3')
    for child in node.get('children', []):
        paint(child, ox, oy)


# The theme's pictures, found by file name: mod.toml's [theme] names them.
THEMED = {Path(p).name: h for h, p in data['textures'].items()}


def sheet(x, y, w, h):
    """The engine's own chrome around a screen, wearing mod.toml's [theme]:
    the ornate frame around the whole sheet, the iron frame on Close.

    The frame goes where the client paints it: FRAME_BORDER (18) deep, its
    art scaled to that depth, around contents inset by the same 18."""
    left, top, right, bottom = x - 20, y - BAR - 20, x + w + 19, y + h + 19
    d.rectangle((left, top, right, bottom), fill='#131619')
    frame(THEMED['ornate-panel.png'], left, top, right - left, bottom - top, border=FRAME_BORDER)
    frame(THEMED['iron-slot.png'], x, y - BAR + 4, 78, 24)
    d.text((x + 10, y - BAR + 8), '<  Close', font=font(12, DISPLAY), fill='#e1d7bf')


top = MARGIN
for n, screen in enumerate(screens):
    rw, rh = screen['room']
    ww, wh = screen['window']
    label = f"{'01' if n == 0 else '02'}  /  A {int(ww)}x{int(wh)} WINDOW  /  INVENTORY AND CRAFTING, AS LAID OUT BY THE ENGINE"
    d.text((MARGIN, top), label, font=font(14, DISPLAY), fill='#ad956b')
    y = top + 44 + BAR
    for column, key in enumerate(('inventory', 'crafter')):
        x = MARGIN + column * (rw + GAP)
        sheet(x, y, rw, rh)
        paint(screen[key], x, y)
    top = y + rh + GAP

d.text((MARGIN, top), '03  /  QUICK ACCESS HUD', font=font(14, DISPLAY), fill='#ad956b')
base = top + 170
for command in data['hud']:
    # The HUD anchors to the bottom centre of the window.
    x, y = W / 2 + command['x'], base - command['y']
    ink = colour(command.get('colour'), '#ddd4bf')
    if command['kind'] == 'rect':
        d.rectangle((x, y, x + command['w'] - 1, y + command['h'] - 1), fill=ink)
    elif command['kind'] == 'text':
        d.text((x, y), command['text'], font=font(command['size']), fill=ink)
    elif command['kind'] == 'image':
        frame(command['hash'], x, y, command['w'], command['h'], sliced=False)
    elif command['kind'] == 'icon':
        if command.get('shape'):
            shape(x, y, command['size'], command['size'], command['shape'])
        else:
            cube(x + command['size'] / 2, y + command['size'] * .25, command['size'] * .7)

im.save(OUT)
print(OUT)
