#!/usr/bin/env python3
"""
VoxelMage - Generateur d'assets procedural.
Tous les assets du jeu (textures de blocs, icones d'items, skins des personnages,
icone de l'application) sont generes ici. Aucun asset externe n'est utilise.

Usage:  python3 tools/generate_assets.py
Sortie: assets/textures/*.png
"""
import os
import math
import random
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
os.makedirs(OUT, exist_ok=True)

TILE = 16          # taille d'une tuile en pixels
GRID = 16          # 16x16 tuiles par atlas
ATLAS = TILE * GRID

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def rnd(seed):
    return random.Random(seed)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + ((c[3],) if len(c) > 4 else ())


def rgb(c, f=1.0, a=255):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))), a)


def noise_tile(base, amp=0.18, seed=0, size=TILE):
    """Tuile bruitee facon pixel-art."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    r = rnd(seed)
    for y in range(size):
        for x in range(size):
            f = 1.0 + (r.random() - 0.5) * 2 * amp
            px[x, y] = rgb(base, f)
    return img


def speckle(img, color, count, seed, sizes=(1, 2)):
    px = img.load()
    r = rnd(seed)
    w, h = img.size
    for _ in range(count):
        s = r.choice(sizes)
        x, y = r.randrange(w), r.randrange(h)
        f = 1.0 + (r.random() - 0.5) * 0.25
        for dy in range(s):
            for dx in range(s):
                px[(x + dx) % w, (y + dy) % h] = rgb(color, f)
    return img


def blob(img, color, cx, cy, rad, seed, jitter=0.35):
    """Tache organique (minerais, cristaux)."""
    px = img.load()
    r = rnd(seed)
    w, h = img.size
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy)
            if d <= rad * (1.0 + (r.random() - 0.5) * jitter):
                px[x, y] = rgb(color, 0.85 + r.random() * 0.3)
    return img


def frame(img, color, thickness=1):
    d = ImageDraw.Draw(img)
    w, h = img.size
    for t in range(thickness):
        d.rectangle([t, t, w - 1 - t, h - 1 - t], outline=color)
    return img


# --------------------------------------------------------------------------
# Textures de blocs
# --------------------------------------------------------------------------

STONE = (128, 128, 132)
DIRT = (134, 96, 67)
GRASS = (94, 157, 62)
SAND = (219, 205, 158)
WOOD = (109, 82, 50)
WOOD_IN = (162, 130, 86)
LEAF = (60, 130, 55)
PLANK = (162, 124, 78)
COBBLE = (118, 118, 122)
WATER = (52, 108, 196)
SNOW = (240, 246, 250)
CACTUS = (72, 130, 62)
COAL = (34, 34, 38)
IRON = (196, 154, 118)
GOLD = (238, 196, 74)
MANA = (128, 92, 232)
OBSID = (36, 26, 54)
BEDROCK = (58, 58, 62)
GRAVEL = (140, 134, 130)
ICE = (166, 208, 240)
ARC = (86, 200, 210)


def t_stone():
    t = noise_tile(STONE, 0.13, 1)
    return speckle(t, shade(STONE, 0.82), 26, 2)


def t_dirt():
    t = noise_tile(DIRT, 0.16, 3)
    return speckle(t, shade(DIRT, 0.78), 22, 4)


def t_grass_top():
    t = noise_tile(GRASS, 0.14, 5)
    speckle(t, shade(GRASS, 1.18), 30, 6)
    return speckle(t, shade(GRASS, 0.8), 22, 7)


def t_grass_side():
    t = t_dirt()
    px = t.load()
    r = rnd(8)
    for x in range(TILE):
        depth = 3 + r.randrange(3)
        for y in range(depth):
            px[x, y] = rgb(GRASS, 0.85 + r.random() * 0.3)
    return t


def t_sand():
    t = noise_tile(SAND, 0.10, 9)
    return speckle(t, shade(SAND, 0.9), 18, 10)


def t_log_side():
    t = noise_tile(WOOD, 0.10, 11)
    px = t.load()
    r = rnd(12)
    for x in range(TILE):
        if x % 4 == 0 or (x * 7) % 11 == 0:
            for y in range(TILE):
                px[x, y] = rgb(WOOD, 0.75 + r.random() * 0.15)
    return t


def t_log_top():
    t = noise_tile(WOOD_IN, 0.08, 13)
    px = t.load()
    c = TILE / 2 - 0.5
    for y in range(TILE):
        for x in range(TILE):
            d = math.hypot(x - c, y - c)
            ring = math.sin(d * 2.0) * 0.5 + 0.5
            px[x, y] = rgb(WOOD_IN, 0.78 + ring * 0.35)
    return frame(t, rgb(WOOD, 0.8))


def t_leaves():
    t = noise_tile(LEAF, 0.22, 15)
    px = t.load()
    r = rnd(16)
    for _ in range(24):
        x, y = r.randrange(TILE), r.randrange(TILE)
        px[x, y] = (0, 0, 0, 0)          # trous -> feuillage aere
    return speckle(t, shade(LEAF, 1.25), 18, 17)


def t_planks():
    t = noise_tile(PLANK, 0.08, 18)
    d = ImageDraw.Draw(t)
    for y in (3, 7, 11, 15):
        d.line([(0, y), (TILE, y)], fill=rgb(PLANK, 0.68))
    for i, x in enumerate((5, 11, 2)):
        y0 = i * 4
        d.line([(x, y0), (x, y0 + 3)], fill=rgb(PLANK, 0.72))
    return t


def t_cobble():
    t = noise_tile(shade(COBBLE, 0.75), 0.10, 19)
    r = rnd(20)
    for _ in range(14):
        cx, cy = r.randrange(TILE), r.randrange(TILE)
        blob(t, COBBLE, cx, cy, r.uniform(1.6, 3.0), r.randrange(999))
    return t


def t_glass():
    t = Image.new("RGBA", (TILE, TILE), (210, 236, 250, 60))
    frame(t, (232, 248, 255, 190))
    d = ImageDraw.Draw(t)
    d.line([(3, 12), (11, 4)], fill=(255, 255, 255, 130))
    return t


def t_water():
    t = noise_tile(WATER, 0.10, 21)
    px = t.load()
    for y in range(TILE):
        for x in range(TILE):
            w = math.sin((x + y * 0.6) * 0.9) * 0.5 + 0.5
            c = rgb(WATER, 0.88 + w * 0.28)
            px[x, y] = (c[0], c[1], c[2], 190)
    return t


def t_snow():
    t = noise_tile(SNOW, 0.05, 23)
    return speckle(t, (255, 255, 255), 20, 24)


def t_snow_side():
    t = t_dirt()
    px = t.load()
    r = rnd(25)
    for x in range(TILE):
        for y in range(4 + r.randrange(2)):
            px[x, y] = rgb(SNOW, 0.95 + r.random() * 0.08)
    return t


def t_cactus_side():
    t = noise_tile(CACTUS, 0.12, 26)
    d = ImageDraw.Draw(t)
    d.line([(1, 0), (1, TILE)], fill=rgb(CACTUS, 0.72))
    d.line([(14, 0), (14, TILE)], fill=rgb(CACTUS, 0.72))
    r = rnd(27)
    for _ in range(10):
        x, y = r.randrange(3, 13), r.randrange(TILE)
        t.putpixel((x, y), (226, 232, 200, 255))
    return t


def t_cactus_top():
    t = noise_tile(shade(CACTUS, 1.1), 0.10, 28)
    return frame(t, rgb(CACTUS, 0.7))


def t_ore(mineral, seed, n=4):
    t = t_stone()
    r = rnd(seed)
    for i in range(n):
        blob(t, mineral, r.randrange(2, 14), r.randrange(2, 14), r.uniform(1.4, 2.6), seed * 31 + i)
    return t


def t_obsidian():
    t = noise_tile(OBSID, 0.16, 40)
    speckle(t, (120, 80, 200), 10, 41)
    return speckle(t, shade(OBSID, 1.5), 14, 42)


def t_bedrock():
    t = noise_tile(BEDROCK, 0.22, 43)
    return speckle(t, shade(BEDROCK, 0.55), 30, 44)


def t_gravel():
    t = noise_tile(GRAVEL, 0.16, 45)
    r = rnd(46)
    for _ in range(20):
        blob(t, shade(GRAVEL, 0.8 + r.random() * 0.4), r.randrange(TILE), r.randrange(TILE), 1.3, r.randrange(9999))
    return t


def t_ice():
    t = noise_tile(ICE, 0.08, 47)
    d = ImageDraw.Draw(t)
    d.line([(2, 13), (13, 2)], fill=rgb(ICE, 1.15))
    d.line([(1, 6), (7, 1)], fill=rgb(ICE, 1.1))
    px = t.load()
    for y in range(TILE):
        for x in range(TILE):
            c = px[x, y]
            px[x, y] = (c[0], c[1], c[2], 225)
    return t


def t_stone_bricks():
    t = noise_tile(shade(STONE, 0.95), 0.09, 48)
    d = ImageDraw.Draw(t)
    for y in (5, 10, 15):
        d.line([(0, y), (TILE, y)], fill=rgb(STONE, 0.65))
    d.line([(7, 0), (7, 5)], fill=rgb(STONE, 0.65))
    d.line([(12, 6), (12, 10)], fill=rgb(STONE, 0.65))
    d.line([(3, 11), (3, 15)], fill=rgb(STONE, 0.65))
    return t


def t_crafting_top():
    t = t_planks()
    d = ImageDraw.Draw(t)
    d.rectangle([2, 2, 13, 13], outline=rgb(PLANK, 0.55))
    d.line([(2, 6), (13, 6)], fill=rgb(PLANK, 0.55))
    d.line([(2, 10), (13, 10)], fill=rgb(PLANK, 0.55))
    d.line([(6, 2), (6, 13)], fill=rgb(PLANK, 0.55))
    d.line([(10, 2), (10, 13)], fill=rgb(PLANK, 0.55))
    return t


def t_crafting_side():
    t = t_planks()
    d = ImageDraw.Draw(t)
    d.rectangle([2, 8, 13, 13], outline=rgb(PLANK, 0.55))
    d.line([(2, 4), (13, 4)], fill=rgb(PLANK, 0.6))
    return t


def t_furnace_side():
    return t_cobble()


def t_furnace_front(lit=False):
    t = t_cobble()
    d = ImageDraw.Draw(t)
    d.rectangle([3, 7, 12, 13], fill=(28, 26, 26, 255), outline=rgb(STONE, 0.5))
    if lit:
        d.rectangle([4, 10, 11, 12], fill=(240, 150, 40, 255))
        d.rectangle([5, 9, 10, 10], fill=(250, 205, 80, 255))
    d.rectangle([4, 3, 11, 5], fill=rgb(STONE, 0.6))
    return t


def t_chest_front():
    t = noise_tile(WOOD, 0.08, 60)
    d = ImageDraw.Draw(t)
    d.rectangle([0, 0, 15, 4], fill=rgb(WOOD, 1.1))
    d.rectangle([0, 5, 15, 15], fill=rgb(WOOD, 0.95))
    d.rectangle([0, 0, 15, 15], outline=rgb(WOOD, 0.6))
    d.rectangle([6, 4, 9, 8], fill=(212, 176, 72, 255), outline=(120, 96, 32, 255))
    return t


def t_chest_side():
    t = noise_tile(WOOD, 0.08, 61)
    d = ImageDraw.Draw(t)
    d.rectangle([0, 0, 15, 4], fill=rgb(WOOD, 1.1))
    d.rectangle([0, 0, 15, 15], outline=rgb(WOOD, 0.6))
    return t


def t_chest_top():
    t = noise_tile(WOOD, 0.08, 62)
    return frame(t, rgb(WOOD, 0.6))


def t_altar_top():
    t = t_stone_bricks()
    d = ImageDraw.Draw(t)
    d.ellipse([3, 3, 12, 12], outline=(150, 110, 250, 255))
    d.ellipse([6, 6, 9, 9], fill=(190, 160, 255, 255))
    for a in range(6):
        ang = a * math.pi / 3
        x = 7.5 + math.cos(ang) * 5.5
        y = 7.5 + math.sin(ang) * 5.5
        d.point((x, y), fill=(210, 190, 255, 255))
    return t


def t_altar_side():
    t = t_stone_bricks()
    d = ImageDraw.Draw(t)
    d.line([(4, 3), (4, 12)], fill=(150, 110, 250, 255))
    d.line([(11, 3), (11, 12)], fill=(150, 110, 250, 255))
    d.line([(4, 7), (11, 7)], fill=(180, 150, 255, 255))
    return t


def t_rune_top():
    t = t_planks()
    d = ImageDraw.Draw(t)
    d.rectangle([2, 2, 13, 13], fill=(48, 40, 78, 255), outline=(150, 110, 250, 255))
    for p in ((5, 5), (10, 5), (7, 8), (5, 11), (10, 11)):
        d.point(p, fill=(120, 240, 230, 255))
    d.line([(5, 5), (7, 8)], fill=(120, 240, 230, 255))
    d.line([(10, 5), (7, 8)], fill=(120, 240, 230, 255))
    return t


def t_rune_side():
    t = t_planks()
    d = ImageDraw.Draw(t)
    d.rectangle([1, 1, 14, 6], fill=(48, 40, 78, 255), outline=(150, 110, 250, 255))
    d.line([(3, 3), (12, 5)], fill=(120, 240, 230, 255))
    return t


def t_mana_block():
    t = noise_tile(shade(MANA, 0.75), 0.10, 70)
    r = rnd(71)
    for i in range(5):
        blob(t, MANA, r.randrange(3, 13), r.randrange(3, 13), r.uniform(2.0, 3.4), 700 + i)
    return speckle(t, (220, 200, 255), 12, 72)


def t_void_rock():
    t = noise_tile((58, 42, 78), 0.18, 73)
    return speckle(t, (140, 90, 220), 16, 74)


def t_arcanite_block():
    t = noise_tile(shade(ARC, 0.7), 0.10, 75)
    r = rnd(76)
    for i in range(4):
        blob(t, ARC, r.randrange(3, 13), r.randrange(3, 13), r.uniform(2.0, 3.2), 800 + i)
    return t


def t_dark_planks():
    t = noise_tile((86, 62, 52), 0.08, 77)
    d = ImageDraw.Draw(t)
    for y in (3, 7, 11, 15):
        d.line([(0, y), (TILE, y)], fill=(60, 42, 36, 255))
    return t


def t_red_sand():
    t = noise_tile((196, 118, 68), 0.10, 78)
    return speckle(t, (160, 92, 54), 18, 79)


def t_torch():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.rectangle([7, 8, 8, 15], fill=rgb(WOOD, 1.0))
    d.rectangle([6, 5, 9, 8], fill=(250, 190, 70, 255))
    d.rectangle([7, 4, 8, 5], fill=(255, 236, 150, 255))
    return t


# ordre = index de tuile dans l'atlas (doit correspondre a scripts/core/Blocks.gd)
BLOCK_TILES = [
    t_stone, t_dirt, t_grass_top, t_grass_side, t_sand, t_log_side, t_log_top,
    t_leaves, t_planks, t_cobble, t_glass, t_water, t_snow, t_snow_side,
    t_cactus_side, t_cactus_top,
    lambda: t_ore(COAL, 30), lambda: t_ore(IRON, 31), lambda: t_ore(GOLD, 32),
    lambda: t_ore(MANA, 33, 5), lambda: t_ore(ARC, 34, 3),
    t_obsidian, t_bedrock, t_gravel, t_ice, t_stone_bricks,
    t_crafting_top, t_crafting_side, t_furnace_front, lambda: t_furnace_front(True),
    t_furnace_side, t_chest_front, t_chest_side, t_chest_top,
    t_altar_top, t_altar_side, t_rune_top, t_rune_side,
    t_mana_block, t_void_rock, t_arcanite_block, t_dark_planks, t_red_sand, t_torch,
]


def build_atlas():
    atlas = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    for i, fn in enumerate(BLOCK_TILES):
        tile = fn().convert("RGBA")
        atlas.paste(tile, ((i % GRID) * TILE, (i // GRID) * TILE))
    atlas.save(os.path.join(OUT, "blocks.png"))
    print("blocks.png : %d tuiles" % len(BLOCK_TILES))


# --------------------------------------------------------------------------
# Icones d'items
# --------------------------------------------------------------------------

def _tool_head(d, kind, col, dark):
    if kind == "pick":
        d.line([(3, 6), (12, 6)], fill=col)
        d.line([(2, 7), (4, 5)], fill=col)
        d.line([(11, 5), (13, 7)], fill=col)
        d.line([(3, 5), (12, 5)], fill=dark)
    elif kind == "sword":
        d.line([(5, 11), (12, 4)], fill=col, width=2)
        d.line([(11, 3), (13, 5)], fill=dark)
        d.line([(3, 11), (7, 7)], fill=(120, 92, 54, 255))
        d.line([(4, 13), (6, 11)], fill=(120, 92, 54, 255))
    elif kind == "axe":
        d.polygon([(6, 3), (12, 4), (12, 9), (6, 9)], fill=col, outline=dark)
        d.line([(6, 5), (6, 8)], fill=dark)
    elif kind == "shovel":
        d.polygon([(7, 3), (11, 3), (11, 8), (9, 10), (7, 8)], fill=col, outline=dark)


def i_tool(kind, col):
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    if kind != "sword":
        d.line([(4, 13), (11, 6)], fill=(120, 92, 54, 255), width=2)
        d.line([(4, 13), (11, 6)], fill=(150, 118, 72, 255))
    _tool_head(d, kind, col, shade(col, 0.65) + (255,))
    return t


def i_stick():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.line([(5, 12), (10, 4)], fill=(150, 118, 72, 255), width=2)
    d.line([(5, 12), (10, 4)], fill=(178, 142, 92, 255))
    return t


def i_nugget(col, seed):
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.polygon([(4, 8), (6, 4), (11, 5), (12, 10), (7, 12)], fill=col + (255,),
              outline=shade(col, 0.6) + (255,))
    d.line([(6, 7), (9, 6)], fill=shade(col, 1.3) + (255,))
    return t


def i_ingot(col):
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.polygon([(3, 10), (5, 6), (12, 6), (13, 10), (11, 11), (4, 11)],
              fill=col + (255,), outline=shade(col, 0.6) + (255,))
    d.line([(6, 8), (11, 8)], fill=shade(col, 1.25) + (255,))
    return t


def i_crystal(col):
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.polygon([(8, 1), (12, 7), (8, 14), (4, 7)], fill=col + (255,),
              outline=shade(col, 0.55) + (255,))
    d.line([(8, 2), (8, 13)], fill=shade(col, 1.35) + (255,))
    d.line([(5, 7), (11, 7)], fill=shade(col, 1.2) + (255,))
    return t


def i_wand(tier):
    cols = [(150, 120, 90), (140, 190, 220), (150, 110, 250), (250, 170, 70), (250, 80, 120)]
    c = cols[min(tier - 1, 4)]
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.line([(4, 13), (10, 6)], fill=(120, 92, 54, 255), width=2)
    d.line([(4, 13), (10, 6)], fill=(160, 128, 82, 255))
    d.ellipse([8, 2, 13, 7], fill=c + (255,), outline=shade(c, 0.6) + (255,))
    d.point((10, 4), fill=(255, 255, 255, 255))
    if tier >= 3:
        for p in ((7, 2), (14, 6), (6, 6)):
            d.point(p, fill=c + (255,))
    return t


def i_tome():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.rectangle([2, 3, 13, 12], fill=(72, 46, 110, 255), outline=(38, 24, 60, 255))
    d.rectangle([7, 3, 8, 12], fill=(38, 24, 60, 255))
    d.rectangle([3, 4, 6, 11], fill=(226, 214, 240, 255))
    d.rectangle([9, 4, 12, 11], fill=(226, 214, 240, 255))
    d.line([(4, 6), (5, 6)], fill=(120, 100, 160, 255))
    d.line([(10, 8), (11, 8)], fill=(120, 100, 160, 255))
    return t


def i_potion(col):
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.rectangle([6, 2, 9, 5], fill=(200, 200, 210, 255))
    d.ellipse([3, 5, 12, 14], fill=(210, 226, 236, 160), outline=(160, 176, 190, 255))
    d.ellipse([4, 8, 11, 13], fill=col + (255,))
    d.point((6, 10), fill=(255, 255, 255, 200))
    return t


def i_bread():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.ellipse([2, 5, 13, 12], fill=(196, 142, 72, 255), outline=(146, 100, 48, 255))
    for x in (5, 8, 11):
        d.line([(x, 7), (x - 1, 9)], fill=(232, 186, 116, 255))
    return t


def i_apple():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.ellipse([3, 4, 12, 13], fill=(206, 56, 56, 255), outline=(140, 32, 32, 255))
    d.line([(8, 2), (8, 5)], fill=(110, 82, 46, 255))
    d.point((6, 7), fill=(255, 180, 180, 255))
    return t


def i_void_heart():
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.ellipse([2, 3, 13, 14], fill=(42, 26, 66, 255), outline=(150, 110, 250, 255))
    d.ellipse([6, 6, 10, 11], fill=(180, 120, 255, 255))
    d.point((8, 8), fill=(255, 255, 255, 255))
    return t


def i_block_icon(tile_fn):
    """Icone d'item pour un bloc : petite projection isometrique."""
    src = tile_fn().convert("RGBA")
    t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    small = src.resize((10, 10), Image.NEAREST)
    t.paste(small, (3, 3), small)
    d = ImageDraw.Draw(t)
    d.rectangle([3, 3, 12, 12], outline=(0, 0, 0, 90))
    return t


ITEM_TILES = [
    i_stick,                                    # 0
    lambda: i_nugget(COAL, 1),                  # 1 charbon
    lambda: i_ingot(IRON),                      # 2 lingot de fer
    lambda: i_ingot(GOLD),                      # 3 lingot d'or
    lambda: i_crystal(MANA),                    # 4 cristal de mana
    lambda: i_crystal(ARC),                     # 5 arcanite
    lambda: i_tool("pick", (162, 124, 78)),     # 6 pioche bois
    lambda: i_tool("pick", STONE),              # 7 pioche pierre
    lambda: i_tool("pick", IRON),               # 8 pioche fer
    lambda: i_tool("pick", ARC),                # 9 pioche arcanite
    lambda: i_tool("sword", (162, 124, 78)),    # 10
    lambda: i_tool("sword", STONE),             # 11
    lambda: i_tool("sword", IRON),              # 12
    lambda: i_tool("sword", ARC),               # 13
    lambda: i_tool("axe", (162, 124, 78)),      # 14
    lambda: i_tool("axe", STONE),               # 15
    lambda: i_tool("axe", IRON),                # 16
    lambda: i_tool("axe", ARC),                 # 17
    lambda: i_tool("shovel", STONE),            # 18
    lambda: i_tool("shovel", IRON),             # 19
    lambda: i_wand(1),                          # 20
    lambda: i_wand(2),                          # 21
    lambda: i_wand(3),                          # 22
    lambda: i_wand(4),                          # 23
    lambda: i_wand(5),                          # 24
    i_tome,                                     # 25
    lambda: i_potion((214, 58, 74)),            # 26 potion de vie
    lambda: i_potion((92, 110, 240)),           # 27 potion de mana
    i_bread,                                    # 28
    i_apple,                                    # 29
    i_void_heart,                               # 30
]


def build_items():
    sheet = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    for i, fn in enumerate(ITEM_TILES):
        sheet.paste(fn().convert("RGBA"), ((i % GRID) * TILE, (i // GRID) * TILE))
    sheet.save(os.path.join(OUT, "items.png"))
    print("items.png  : %d icones" % len(ITEM_TILES))


# --------------------------------------------------------------------------
# Skins de personnages (layout 64x64 facon skin classique)
# --------------------------------------------------------------------------

def _box_uv(d, ox, oy, w, h, dep, col, top=None, seed=0):
    """Remplit les 6 faces d'une boite dans le layout du skin."""
    r = rnd(seed)
    top = top or shade(col, 1.12)
    faces = [
        (ox + dep, oy, w, dep, top),                 # top
        (ox + dep + w, oy, w, dep, shade(col, 0.7)),  # bottom
        (ox, oy + dep, dep, h, shade(col, 0.86)),     # right
        (ox + dep, oy + dep, w, h, col),              # front
        (ox + dep + w, oy + dep, dep, h, shade(col, 0.86)),  # left
        (ox + dep + w + dep, oy + dep, w, h, shade(col, 0.78)),  # back
    ]
    for (x, y, fw, fh, c) in faces:
        for yy in range(fh):
            for xx in range(fw):
                f = 1.0 + (r.random() - 0.5) * 0.12
                d.point((x + xx, y + yy), fill=rgb(c, f))


def make_skin(name, skin, shirt, pants, eye=(24, 24, 32), extra=None):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # tete 8x8x8 @ (0,0) | corps 8x12x4 @ (16,16) | bras 4x12x4 @ (40,16) et (32,48)
    # jambes 4x12x4 @ (0,16) et (16,48)
    _box_uv(d, 0, 0, 8, 8, 8, skin, seed=1)
    _box_uv(d, 16, 16, 8, 12, 4, shirt, seed=2)
    _box_uv(d, 40, 16, 4, 12, 4, shirt, seed=3)
    _box_uv(d, 32, 48, 4, 12, 4, shirt, seed=4)
    _box_uv(d, 0, 16, 4, 12, 4, pants, seed=5)
    _box_uv(d, 16, 48, 4, 12, 4, pants, seed=6)
    # visage : face avant de la tete = (8,8)-(16,16)
    fx, fy = 8, 8
    d.rectangle([fx + 1, fy + 2, fx + 2, fy + 3], fill=eye + (255,))
    d.rectangle([fx + 5, fy + 2, fx + 6, fy + 3], fill=eye + (255,))
    d.line([(fx + 2, fy + 5), (fx + 5, fy + 5)], fill=shade(skin, 0.65) + (255,))
    # cheveux : haut + arriere
    hair = shade(skin, 0.45)
    for yy in range(2):
        d.line([(fx, fy + yy), (fx + 7, fy + yy)], fill=hair + (255,))
    for yy in range(8):
        d.line([(24, 8 + yy), (31, 8 + yy)], fill=hair + (255,))
    for yy in range(8):
        d.line([(8, yy), (15, yy)], fill=hair + (255,))
    # ceinture / detail torse
    d.line([(20, 26), (27, 26)], fill=shade(shirt, 0.55) + (255,))
    if extra:
        extra(d)
    img.save(os.path.join(OUT, "skin_%s.png" % name))


def rune_marks(d):
    for p in ((21, 22), (24, 21), (26, 24), (22, 25)):
        d.point(p, fill=(150, 240, 230, 255))


def build_skins():
    make_skin("player", (226, 186, 148), (58, 122, 196), (52, 58, 90), extra=rune_marks)
    make_skin("husk", (108, 138, 96), (76, 70, 60), (58, 52, 46), eye=(220, 60, 60))
    make_skin("wraith", (196, 200, 210), (46, 44, 72), (36, 34, 56), eye=(120, 240, 230))
    make_skin("mage", (216, 172, 140), (96, 60, 168), (54, 34, 96), eye=(240, 200, 80))
    make_skin("boss", (66, 48, 92), (44, 30, 66), (34, 22, 52), eye=(255, 120, 60))
    # slime : texture unie translucide
    s = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ds = ImageDraw.Draw(s)
    _box_uv(ds, 0, 0, 8, 8, 8, (96, 200, 108), seed=9)
    ds.rectangle([9, 10, 10, 11], fill=(20, 40, 20, 255))
    ds.rectangle([13, 10, 14, 11], fill=(20, 40, 20, 255))
    ds.line([(10, 13), (13, 13)], fill=(20, 40, 20, 255))
    s.save(os.path.join(OUT, "skin_slime.png"))
    print("skins      : player, husk, wraith, mage, boss, slime")


# --------------------------------------------------------------------------
# Particules, ciel, icone
# --------------------------------------------------------------------------

def build_misc():
    p = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    d.ellipse([0, 0, 7, 7], fill=(255, 255, 255, 255))
    d.ellipse([2, 2, 5, 5], fill=(255, 255, 255, 255))
    p.save(os.path.join(OUT, "particle.png"))

    # icone d'application 512x512 : bloc isometrique + rune
    ico = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    d = ImageDraw.Draw(ico)
    d.rounded_rectangle([8, 8, 503, 503], 90, fill=(26, 22, 40, 255))
    top = t_grass_top().resize((220, 220), Image.NEAREST)
    side = t_dirt().resize((220, 220), Image.NEAREST)
    cube = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    # projection iso simple
    for (src, mat, box) in (
        (top, (1, 0.5, 0, 0, -0.5, 0), (146, 96)),
        (side, (1, 0, 0, 0.5, 1, 0), (146, 206)),
    ):
        tr = src.transform((220, 220), Image.AFFINE, mat, Image.NEAREST)
        cube.paste(tr, box, tr)
    ico = Image.alpha_composite(ico, cube)
    d = ImageDraw.Draw(ico)
    d.ellipse([300, 300, 430, 430], outline=(168, 120, 255, 255), width=10)
    d.ellipse([340, 340, 390, 390], fill=(200, 170, 255, 255))
    ico.save(os.path.join(OUT, "icon.png"))
    ico.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "icon_128.png"))
    print("misc       : particle.png, icon.png")


if __name__ == "__main__":
    build_atlas()
    build_items()
    build_skins()
    build_misc()
    print("Assets generes dans %s" % OUT)
