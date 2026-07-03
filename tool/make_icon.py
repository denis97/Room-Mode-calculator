"""Generates the launcher icon set: a dark room outline with a standing
half-wave in the app's diverging cyan/pink pressure palette.

Outputs (into assets/icon/):
  icon.png            1024x1024 full icon (legacy/round source)
  icon_foreground.png 1024x1024 adaptive foreground (art in safe zone)
Colors match lib/ui/app_theme.dart: bg #0A0B0E, cyan #29C4FF, pink #FF5E7A.
"""
import math
import os

from PIL import Image, ImageDraw

S = 1024
BG = (10, 11, 14, 255)          # AppColors.background
GLOW = (22, 24, 31, 255)        # AppColors.backgroundGlow
CYAN = (41, 196, 255, 255)      # fieldNegative
PINK = (255, 94, 122, 255)      # fieldPositive
GRID = (255, 255, 255, 12)
ROOM = (255, 255, 255, 38)

SS = 4  # supersampling factor


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def draw_art(d, w, h, inset_frac, line_scale):
    """Room box + standing wave, centered, sized by inset_frac."""
    x0, y0 = w * inset_frac, h * (inset_frac + 0.04)
    x1, y1 = w - x0, h - y0

    # Room outline (top-down), slightly rounded.
    d.rounded_rectangle([x0, y0, x1, y1], radius=w * 0.03,
                        outline=ROOM, width=int(line_scale * 7))

    # Faint 1m-style gridlines.
    for i in range(1, 4):
        gx = x0 + (x1 - x0) * i / 4
        d.line([gx, y0, gx, y1], fill=GRID, width=int(line_scale * 5))
    for i in range(1, 3):
        gy = y0 + (y1 - y0) * i / 3
        d.line([x0, gy, x1, gy], fill=GRID, width=int(line_scale * 5))

    # Standing half-wave (fundamental mode): pressure high at walls, null in
    # the middle -- drawn as a thick cos curve, colored by sign (pink +,
    # cyan -), the app's field gradient.
    mid = (y0 + y1) / 2
    amp = (y1 - y0) * 0.30
    n = 400
    pts = []
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        v = math.cos(math.pi * t)  # +1 at left wall, -1 at right wall
        pts.append((x, mid - v * amp, v))
    lw = int(line_scale * 34)
    for i in range(n):
        (xa, ya, va), (xb, yb, _) = pts[i], pts[i + 1]
        # v in [-1,1] -> color: pink for +, cyan for -; fade near the null.
        v = va
        neutral = (238, 241, 246, 255)
        base = PINK if v >= 0 else CYAN
        c = lerp(neutral, base, min(1.0, abs(v) * 1.5))
        d.line([xa, ya, xb, yb], fill=c, width=lw)
        r = lw / 2
        d.ellipse([xa - r, ya - r, xa + r, ya + r], fill=c)
    # Node dot at the center null.
    d.ellipse([(x0 + x1) / 2 - lw * 0.7, mid - lw * 0.7,
               (x0 + x1) / 2 + lw * 0.7, mid + lw * 0.7],
              fill=(238, 241, 246, 255))
    # Antinode ticks at the walls.
    for x, v in ((x0, 1), (x1, -1)):
        base = PINK if v > 0 else CYAN
        d.ellipse([x - lw * 0.55, mid - v * amp - lw * 0.55,
                   x + lw * 0.55, mid - v * amp + lw * 0.55], fill=base)


def radial_bg(size):
    img = Image.new("RGBA", (size, size), BG)
    # Soft glow toward the top center, echoing the app background gradient.
    glow = Image.new("L", (size, size), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy, r = size / 2, -size * 0.1, size * 1.05
    for i in range(60, 0, -1):
        a = int(70 * (i / 60) ** 2)
        rr = r * i / 60
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=a)
    tint = Image.new("RGBA", (size, size), GLOW)
    img = Image.composite(tint, img, glow)
    return img


def main():
    out = "assets/icon"
    os.makedirs(out, exist_ok=True)
    big = S * SS

    # Full icon: background + art with a modest inset.
    img = radial_bg(big)
    d = ImageDraw.Draw(img)
    draw_art(d, big, big, 0.14, SS)
    img = img.resize((S, S), Image.LANCZOS)
    img.save(f"{out}/icon.png")

    # Adaptive foreground: transparent bg, art shrunk into the ~66% safe
    # zone (launchers mask up to 33% of each edge).
    fg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    draw_art(d, big, big, 0.27, SS)
    fg = fg.resize((S, S), Image.LANCZOS)
    fg.save(f"{out}/icon_foreground.png")
    print("wrote", out)


if __name__ == "__main__":
    main()
