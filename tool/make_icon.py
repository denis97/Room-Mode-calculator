"""Generates the launcher icon set: an isometric cube whose three visible
faces show a room mode's pressure field (mode indices (2,0,2)), in the app's
diverging cyan/pink field palette -- the same rendering language as the
in-app 3D pressure view, turned into a mark.

Outputs (into assets/icon/):
  icon.png            1024x1024 full icon, full-bleed square (no pre-baked
                       corner rounding -- the OS/launcher applies its own
                       mask on top of this)
  icon_foreground.png 1024x1024 adaptive foreground (art in the safe zone,
                       transparent background)
Colors match lib/ui/app_theme.dart: bg #0A0B0E, cyan #29C4FF, pink #FF5E7A.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

S = 1024
SS = 4  # supersampling factor
BG = (10, 11, 14, 255)          # AppColors.background
GLOW = (22, 24, 31, 255)        # AppColors.backgroundGlow
CYAN = np.array([41, 196, 255])       # fieldNegative
MID = np.array([16, 19, 26])          # fieldMid (near-black)
PINK = np.array([255, 94, 122])       # fieldPositive
EDGE = (255, 255, 255)

COS30 = math.cos(math.radians(30))
SIN30 = math.sin(math.radians(30))

# Mode indices (p,q,r) chosen for the mark: q=0 leaves the top/right faces as
# clean single-axis bands while the left face gets a full 2D checker -- a
# deliberately asymmetric, recognizable pattern rather than any specific
# room's literal computed mode.
MODE = (2, 0, 2)


def field_color(v):
    """Signed pressure array -> diverging glow, saturation-boosted so cells
    pop. v is a numpy array in [-1, 1]; returns an (..., 3) uint8 array."""
    t = (np.minimum(1.0, np.abs(v)) ** 0.7)[..., None]
    base = np.where((v >= 0)[..., None], PINK, CYAN)
    return MID + (base - MID) * t


def radial_bg(size):
    img = Image.new("RGBA", (size, size), BG)
    glow = Image.new("L", (size, size), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy, r = size / 2, -size * 0.1, size * 1.05
    for i in range(60, 0, -1):
        a = int(70 * (i / 60) ** 2)
        rr = r * i / 60
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=a)
    tint = Image.new("RGBA", (size, size), GLOW)
    return Image.composite(tint, img, glow)


def coord(axis, val, a, b):
    if axis == "Z":            # top face
        return (a, b, val)
    if axis == "X":            # right wall
        return (val, a, b)
    return (a, val, b)          # left wall (Y fixed)


def make_projector(size, margin):
    corners = [(x, y, z) for x in (0, 1) for y in (0, 1) for z in (0, 1)]

    def raw(p):
        X, Y, Z = p
        return ((X - Y) * COS30, (X + Y) * SIN30 - Z)

    pts = [raw(c) for c in corners]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    scale = size * (1 - 2 * margin) / max(w, h)
    cx = size / 2 - (min(xs) + max(xs)) / 2 * scale
    cy = size / 2 - (min(ys) + max(ys)) / 2 * scale

    def project(p):
        rx, ry = raw(p)
        return (cx + rx * scale, cy + ry * scale)

    return project


def render_face(canvas, axis, val, sh, project, size):
    """Paint one face's pressure field continuously (per-pixel, no tile
    seams) into the RGBA canvas array, alpha-blending on the parallelogram
    the face projects to."""
    p, q, r = MODE
    O = np.array(project(coord(axis, val, 0, 0)))
    U = np.array(project(coord(axis, val, 1, 0))) - O
    V = np.array(project(coord(axis, val, 0, 1))) - O

    xs = [O[0], (O + U)[0], (O + V)[0], (O + U + V)[0]]
    ys = [O[1], (O + U)[1], (O + V)[1], (O + U + V)[1]]
    x0, x1 = max(0, int(min(xs)) - 1), min(size, int(max(xs)) + 2)
    y0, y1 = max(0, int(min(ys)) - 1), min(size, int(max(ys)) + 2)
    if x1 <= x0 or y1 <= y0:
        return

    px, py = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    d = px - O[0], py - O[1]
    det = U[0] * V[1] - U[1] * V[0]
    a = (d[0] * V[1] - d[1] * V[0]) / det
    b = (U[0] * d[1] - U[1] * d[0]) / det

    # Soft-edged mask (1px feather) so adjoining faces meet without seams.
    feather = 1.2 / max(np.hypot(*U), np.hypot(*V))
    mask = (np.clip(np.minimum(a, b) / feather, 0, 1) *
            np.clip(np.minimum(1 - a, 1 - b) / feather, 0, 1))
    if not np.any(mask > 0):
        return

    x, y, z = coord(axis, val, a, b)
    v = np.cos(p * math.pi * x) * np.cos(q * math.pi * y) * np.cos(r * math.pi * z)
    col = field_color(v) * sh

    # Straight-alpha "over" compositing (correct for both the opaque
    # background pass and the transparent adaptive-foreground pass).
    region = canvas[y0:y1, x0:x1]
    src_a = mask[..., None]
    dst_a = region[..., 3:4] / 255.0
    out_a = src_a + dst_a * (1 - src_a)
    out_rgb = np.divide(col * src_a + region[..., :3] * dst_a * (1 - src_a),
                         out_a, out=np.zeros_like(col), where=out_a > 1e-6)
    region[..., :3] = out_rgb
    region[..., 3:4] = out_a * 255


def draw_cube(img, margin):
    size = img.size[0]
    project = make_projector(size, margin)
    canvas = np.array(img, dtype=np.float64)

    faces = [("Z", 1.0, 1.00), ("X", 1.0, 0.82), ("Y", 1.0, 0.62)]
    for axis, val, sh in faces:
        render_face(canvas, axis, val, sh, project, size)

    out = Image.fromarray(canvas.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(out, "RGBA")
    lw = int(SS * 3)
    for axis, val, _ in faces:
        ring = [project(coord(axis, val, 0, 0)),
                project(coord(axis, val, 1, 0)),
                project(coord(axis, val, 1, 1)),
                project(coord(axis, val, 0, 1))]
        d.line(ring + [ring[0]], fill=(*EDGE, 60), width=lw, joint="curve")
    return out


def main():
    out = "assets/icon"
    os.makedirs(out, exist_ok=True)
    big = S * SS

    # Full icon: background + cube, modest margin. No corner rounding baked
    # in -- iOS/Android apply their own mask on top of the full-bleed square.
    img = radial_bg(big)
    img = draw_cube(img, margin=0.08)
    img = img.resize((S, S), Image.LANCZOS)
    img.save(f"{out}/icon.png")

    # Adaptive foreground: transparent bg, cube filling the ~66% safe zone
    # (launchers may mask up to ~33% of each edge) -- margin=0.16 puts the
    # cube's long axis at ~68% of the canvas, right at that limit without
    # risking clipping by a circular/squircle mask.
    fg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    fg = draw_cube(fg, margin=0.16)
    fg = fg.resize((S, S), Image.LANCZOS)
    fg.save(f"{out}/icon_foreground.png")
    print("wrote", out)


if __name__ == "__main__":
    main()
