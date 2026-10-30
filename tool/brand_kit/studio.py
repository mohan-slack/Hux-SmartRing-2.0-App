"""HUX icon studio — vector H (measured from images/logo.png), aurora backgrounds, charge ring."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

def hexc(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5))
PINK_HI, PINK, CHERRY, PURPLE, INDIGO = map(hexc, ['#F567B5', '#C93B86', '#E8573B', '#6B2E9A', '#4453D6'])
PLUM = hexc('#1A0B30')

# ---- the H, measured from the wordmark (units: logo px) ----
H_W, H_H, H_S = 381.0, 334.0, 31.0
H_SEGS = [((15.5, 15.5), (15.5, 318.5)),      # left stem
          ((365.5, 15.5), (365.5, 318.5)),    # right stem
          ((83.5, 166.5), (365.5, 166.5))]    # crossbar: floats free of the left stem (the HUX gap)

def stroke(draw, p0, p1, w, fill=255):
    draw.line([p0, p1], fill=fill, width=int(round(w)))
    r = w / 2
    for (x, y) in (p0, p1):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)

def h_mask(size, cx, cy, width, segs=H_SEGS, ss=4, weight=1.0):
    """Anti-aliased H mask (L) on a size×size canvas."""
    k = width / H_W * ss
    big = Image.new('L', (size * ss, size * ss), 0); d = ImageDraw.Draw(big)
    ox, oy = cx * ss - H_W * k / 2, cy * ss - H_H * k / 2
    for p0, p1 in segs:
        stroke(d, (ox + p0[0] * k, oy + p0[1] * k), (ox + p1[0] * k, oy + p1[1] * k), H_S * k * weight)
    return big.resize((size, size), Image.LANCZOS)

def h_stroke_px(width, weight=1.0): return H_S * width / H_W * weight

# ---- backgrounds ----
def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    return x, y

def aurora(n, blobs, base=PLUM, grain=2.5, seed=7):
    x, y = grid(n)
    img = np.zeros((n, n, 3), np.float32) + np.array(base, np.float32)
    for (bx, by, r, col, a) in blobs:
        g = np.exp(-(((x - bx) ** 2 + (y - by) ** 2) / (2 * r * r)))[..., None] * a
        img = img * (1 - g) + np.array(col, np.float32) * g
    # soft vignette
    v = 1 - 0.28 * np.clip(((x - .5) ** 2 + (y - .5) ** 2) * 2.2, 0, 1)
    img *= v[..., None]
    rng = np.random.default_rng(seed)
    img += rng.normal(0, grain, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert('RGBA')

AURORA = [(0.12, 0.08, 0.36, PINK_HI, 0.80), (0.98, 1.0, 0.45, INDIGO, 0.85),
          (0.0, 1.0, 0.22, CHERRY, 0.30), (0.55, 0.45, 0.32, PURPLE, 0.75)]

def aurora_t(n, t, grain=2.5):
    """Same aurora, blobs drifting slowly (t in seconds)."""
    b = []
    for i, (bx, by, r, c, a) in enumerate(AURORA):
        b.append((bx + 0.03 * math.sin(t * 0.9 + i * 1.7), by + 0.03 * math.cos(t * 0.7 + i), r, c, a))
    return aurora(n, b, grain=grain, seed=int(t * 30) % 7)

# ---- charge ring (conic gradient arc) ----
RING_STOPS = [(0.0, PINK_HI), (0.35, PINK), (0.7, PURPLE), (1.0, INDIGO)]

def stop_color(u, stops=RING_STOPS):
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if u <= b:
            t = (u - a) / (b - a) if b > a else 0
            return np.array(ca) * (1 - t) + np.array(cb) * t
    return np.array(stops[-1][1], np.float32)

def ring_layer(n, cx, cy, r, w, start=-90.0, sweep=300.0, ss=2, stops=RING_STOPS, glow=0.5, color_sweep=None):
    """RGBA arc with round caps, colour following the arc, plus an outer glow."""
    N = n * ss
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / ss
    dx, dy = x - cx, y - cy
    dist = np.sqrt(dx * dx + dy * dy)
    ang = (np.degrees(np.arctan2(dy, dx)) - start) % 360.0       # 0 at start, clockwise
    band = np.clip(w / 2 - np.abs(dist - r) + 0.5, 0, 1)
    inside = (ang <= sweep).astype(np.float32)
    mask = band * inside
    for a_deg in (start, start + sweep):                           # round caps
        ex, ey = cx + r * math.cos(math.radians(a_deg)), cy + r * math.sin(math.radians(a_deg))
        cap = np.clip(w / 2 - np.sqrt((x - ex) ** 2 + (y - ey) ** 2) + 0.5, 0, 1)
        mask = np.maximum(mask, cap)
    u = np.clip(ang / max(color_sweep or sweep, 1e-3), 0, 1)
    u = np.where(ang > sweep + (360 - sweep) / 2, 0.0, u)          # start cap gets start colour
    lut = np.array([stop_color(i / 255, stops) for i in range(256)], np.float32)
    col = lut[(u * 255).astype(np.int32)]
    rgba = np.dstack([col, mask * 255]).astype(np.uint8)
    lay = Image.fromarray(rgba, 'RGBA').resize((n, n), Image.LANCZOS)
    if glow:
        g = lay.filter(ImageFilter.GaussianBlur(w * 0.9))
        a = g.split()[3].point(lambda v: int(v * glow))
        g.putalpha(a)
        out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.alpha_composite(g); out.alpha_composite(lay)
        return out
    return lay

def ring_end(cx, cy, r, start, sweep):
    a = math.radians(start + sweep); return cx + r * math.cos(a), cy + r * math.sin(a)

# ---- compositing helpers ----
def solid(mask, color, opacity=1.0):
    out = Image.new('RGBA', mask.size, color + (0,))
    out.putalpha(mask if opacity >= 1 else mask.point(lambda v: int(v * opacity)))
    return out

def glow_of(mask, radius, amount, color=(255, 255, 255)):
    return solid(mask.filter(ImageFilter.GaussianBlur(radius)), color, amount)

def dot(n, x, y, r, color=(255, 255, 255), ss=4):
    m = Image.new('L', (n * ss, n * ss), 0)
    ImageDraw.Draw(m).ellipse(((x - r) * ss, (y - r) * ss, (x + r) * ss, (y + r) * ss), fill=255)
    return m.resize((n, n), Image.LANCZOS)

def squircle_mask(n, ss=4):
    """iOS-style continuous-corner mask (superellipse, exponent 5)."""
    N = n * ss
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    u, v = np.abs((x + .5) / N * 2 - 1), np.abs((y + .5) / N * 2 - 1)
    m = ((u ** 5 + v ** 5) <= 1).astype(np.uint8) * 255
    return Image.fromarray(m, 'L').resize((n, n), Image.LANCZOS)

def masked(img, n, shape='squircle'):
    im = img.resize((n, n), Image.LANCZOS)
    m = squircle_mask(n) if shape == 'squircle' else Image.new('L', (n, n), 0)
    if shape == 'circle': ImageDraw.Draw(m).ellipse((0, 0, n - 1, n - 1), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.paste(im, (0, 0), m); return out
