# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Draw docs/preview.png from the trees the native check built.

An approximate layout illustration, not a game screenshot: this lays the
widgets out the way the client would and stands in for the parts only a GPU
does — item icons, the chiselled block, the real font metrics.

It reads tests/native/target/preview.json, which the native check writes, so
the picture comes from the same trees the engine's own checker passed and
there is no second copy of the mod's layout to keep in step. Run:

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
W, H = 1800, 1400

if not DATA.exists():
    sys.exit(f'{DATA} is missing: run the native check first (see this file\'s docstring)')
data = json.loads(DATA.read_text())

im = Image.new('RGB', (W, H), '#101417')
d = ImageDraw.Draw(im)
DISPLAY = str(ROOT / data['font'])
MONO = str(ENGINE / 'crates/client/assets/third-party/go-font/Go-Mono.ttf')
textures = {h: Image.open(ROOT / p).convert('RGB') for h, p in data['textures'].items()}


def font(size):
    return ImageFont.truetype(DISPLAY, max(8, round(size)))


def mono(size):
    return ImageFont.truetype(MONO, max(8, round(size)))


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


def frame(hash_, x, y, w, h, sliced=True):
    """A nine-slice, or the whole image: the corners are the outer third."""
    source = textures[hash_]
    x, y, w, h = map(round, (x, y, w, h))
    if not sliced:
        im.paste(source.resize((max(1, w), max(1, h)), Image.Resampling.LANCZOS), (x, y))
        return
    ex, ey = min(source.width / 3, w / 2), min(source.height / 3, h / 2)
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


# --- Layout ---------------------------------------------------------------------

def text_of(node):
    if node['type'] == 'dropdown':
        return node['options'][node['selected'] - 1]
    return node.get('text', '')


def natural(node):
    """What a widget asks for, along the parent's direction and across it."""
    kind = node['type']
    size = style(node, 'text_size') or 14
    if kind in ('container', 'scroll'):
        children = node['children']
        if kind == 'scroll':
            return natural(children[0]) if children else (0, 0)
        row = node.get('direction') == 'row'
        pad, gap = node.get('padding', 0), node.get('gap', 0)
        sizes = [c.get('size') or natural(c)[0 if row else 1] for c in children]
        cross = [c.get('cross_size') or natural(c)[1 if row else 0] for c in children]
        along = sum(sizes) + max(0, len(children) - 1) * gap + 2 * pad
        across = max(cross, default=0) + 2 * pad
        return (along, across) if row else (across, along)
    if kind == 'item_slot':
        return 36, 36
    if kind == 'shape_editor':
        return 192, 192
    if kind == 'item_grid':
        return node['columns'] * 40, -(-node['count'] // node['columns']) * 40
    if kind == 'spacer':
        return 0, 0
    text = text_of(node)
    width = d.textlength(text, font=font(size))
    padding = 32 if kind == 'dropdown' else (40 if style(node, 'nine_slice') else 16) if kind == 'button' else 0
    return width + padding, size * 1.2 + (8 if kind in ('button', 'dropdown') else 0)


# Slots with something in them, as the picture's representative inventory.
FILLED = {1: '4+16', 2: '10', 3: '8', 6: '8', 10: '12', 11: '2', 14: '1', 20: '5', 23: '9', 28: '1'}
CUT = (3, 14)


def paint(node, x, y, w, h):
    kind = node['type']
    box = (round(x), round(y), round(x + w), round(y + h))
    background = style(node, 'background')
    if background and background[3] > 0:
        d.rounded_rectangle(box, radius=3, fill=colour(background, '#161a1d'))
    if style(node, 'border'):
        d.rounded_rectangle(box, radius=3, outline=colour(style(node, 'border'), '#5b605f'), width=1)
    if style(node, 'nine_slice'):
        frame(style(node, 'nine_slice'), x, y, w, h)

    if kind == 'scroll':
        child = node['children'][0]
        paint(child, x, y, w, max(h, natural(child)[1]))
    elif kind == 'container':
        row = node.get('direction') == 'row'
        pad, gap = node.get('padding', 0), node.get('gap', 0)
        children = node['children']
        along = (w if row else h) - 2 * pad
        across = (h if row else w) - 2 * pad
        wants = [natural(c) for c in children]
        sizes = [c.get('size') or n[0 if row else 1] for c, n in zip(children, wants)]
        space = along - max(0, len(children) - 1) * gap
        used = sum(sizes)
        grow = sum(c.get('grow', 0) for c in children)
        if used > space and used:
            sizes = [v * max(0, space) / used for v in sizes]
        elif grow:
            sizes = [v + (space - used) * c.get('grow', 0) / grow for c, v in zip(children, sizes)]
        at = 0
        for child, size, want in zip(children, sizes, wants):
            other = child.get('cross_size')
            if other is None:
                other = across if node.get('align') == 'stretch' else min(across, want[1 if row else 0])
            off = (across - other) / 2 if node.get('align') == 'center' else 0
            paint(child,
                  x + pad + (at if row else off), y + pad + (off if row else at),
                  size if row else other, other if row else size)
            at += size + gap
    elif kind in ('label', 'button', 'dropdown'):
        text = text_of(node)
        size = style(node, 'text_size') or 14
        face = font(size)
        width = d.textlength(text, font=face)
        left = x + (w - width) / 2 if kind == 'button' else x + (16 if kind == 'dropdown' else 0)
        d.text((left, y + (h - size) / 2 - 2), text, font=face, fill=colour(style(node, 'text_colour'), '#e0d8c4'))
    elif kind == 'item_slot':
        slot(node['index'], x, y, w, h)
    elif kind == 'item_grid':
        cell = min(w / node['columns'], 40)
        for n in range(node['count']):
            slot(node['first'] + n, x + (n % node['columns']) * cell, y + (n // node['columns']) * cell, cell, cell)
    elif kind == 'shape_editor':
        shape(x, y, w, h, node['shape'])
        for at, arrow in [(x + 2, '<'), (x + w - 28, '>')]:
            d.rounded_rectangle((at, y + 2, at + 26, y + 28), radius=3, fill='#404344')
            d.text((at + 8, y + 5), arrow, font=mono(13), fill='#ded6c3')


def slot(index, x, y, w, h):
    if index not in FILLED:
        return
    if index in CUT:
        shape(x + 6, y + 3, w - 12, h - 12, 0x7)
    else:
        cube(x + w / 2, y + h * .31, min(w, h) * .49, (158, 147, 121) if index % 2 else (107, 121, 122))
    quantity = FILLED[index]
    face = mono(15)
    d.text((x + w - 4 - d.textlength(quantity, font=face), y + h - 21), quantity, font=face, fill='#ebdfc4')


# --- The page ---------------------------------------------------------------------

for left, tree, title in [(48, data['inventory'], '01  /  INVENTORY'),
                          (936, data['crafter'], '02  /  SHAPE CRAFTER')]:
    d.text((left, 38), title, font=font(14), fill='#ad956b')
    paint(tree, left, 80, 816, 1030)

d.text((48, 1140), '03  /  QUICK ACCESS HUD', font=font(14), fill='#ad956b')
for command in data['hud']:
    # The HUD anchors to the bottom centre; the page puts that at y = 1340.
    x, y = W / 2 + command['x'], 1340 - command['y']
    ink = colour(command.get('colour'), '#ddd4bf')
    if command['kind'] == 'rect':
        d.rectangle((x, y, x + command['w'] - 1, y + command['h'] - 1), fill=ink)
    elif command['kind'] == 'text':
        d.text((x, y), command['text'], font=mono(command['size']), fill=ink)
    elif command['kind'] == 'image':
        frame(command['hash'], x, y, command['w'], command['h'], sliced=False)
    elif command['kind'] == 'icon':
        if command.get('shape'):
            shape(x, y, command['size'], command['size'], command['shape'])
        else:
            cube(x + command['size'] / 2, y + command['size'] * .25, command['size'] * .7)

d.text((48, 1372),
       'LUA LAYOUT PREVIEW  /  Representative items  /  In-game appearance and interaction pending verification',
       font=font(12), fill='#82928e')
im.save(OUT)
print(OUT)
