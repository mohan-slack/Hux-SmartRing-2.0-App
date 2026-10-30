"""HUX 'Glass Charge' mark: a liquid-glass ring, charge light flowing inside it,
ending in a pearl that lines up with the H's floating crossbar."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from studio import (hexc, h_mask, h_stroke_px, solid, glow_of, squircle_mask, masked, dot, H_W, H_H, H_S, H_SEGS,
                    PINK_HI, PINK, CHERRY, PURPLE, INDIGO, stroke)

# ---------- palettes (alternate icons) ----------
THEMES = {
    'aurora':   dict(base='#1A0B30', blobs=[(0.10, 0.06, 0.38, '#F567B5', .85), (1.0, 1.0, 0.46, '#4453D6', .9),
                                            (0.0, 1.0, 0.24, '#E8573B', .35), (0.58, 0.42, 0.30, '#6B2E9A', .8)],
                     fill=['#FF8FCB', '#F567B5', '#C93B86', '#8B3FD0', '#5B6CF0'], ink='#FFFFFF', glass=0.16, light=False),
    'midnight': dict(base='#0A0A0D', blobs=[(0.5, 0.42, 0.42, '#3A1240', .9), (0.5, 0.75, 0.22, '#F567B5', .25)],
                     fill=['#FF8FCB', '#F567B5', '#C93B86', '#8B3FD0', '#5B6CF0'], ink='#FFFFFF', glass=0.10, light=False),
    'daylight': dict(base='#F6F4FA', blobs=[(0.1, 0.05, 0.36, '#F7B6D9', .9), (1.0, 1.0, 0.45, '#C9B8F5', .9),
                                            (0.55, 0.45, 0.3, '#FFFFFF', .7)],
                     fill=['#F567B5', '#C93B86', '#8B3FD0', '#4453D6'], ink='#2A1640', glass=0.35, light=True),
    'blush':    dict(base='#3A0D2A', blobs=[(0.15, 0.1, 0.45, '#FF8FCB', .95), (0.9, 0.95, 0.4, '#E8573B', .7),
                                            (0.6, 0.5, 0.3, '#C93B86', .7)],
                     fill=['#FFFFFF', '#FFD1E8', '#FF8FCB', '#F567B5'], ink='#FFFFFF', glass=0.18, light=False),
    'calm':     dict(base='#0B1A33', blobs=[(0.1, 0.1, 0.4, '#5B6CF0', .9), (0.95, 0.95, 0.45, '#0E9F9A', .85),
                                            (0.55, 0.45, 0.3, '#4453D6', .6)],
                     fill=['#9FE8E2', '#0E9F9A', '#5B6CF0', '#8B3FD0'], ink='#FFFFFF', glass=0.16, light=False),
    'spectrum': dict(base='#15102A', blobs=[(0.1, 0.08, 0.36, '#F567B5', .7), (0.95, 0.95, 0.4, '#4453D6', .8),
                                            (0.0, 1.0, 0.25, '#1FA463', .45), (1.0, 0.0, 0.25, '#E9B400', .45)],
                     fill=['#E5484D', '#F28C28', '#E9B400', '#1FA463', '#0E9F9A', '#5B6CF0', '#8B3FD0', '#F567B5'],
                     ink='#FFFFFF', glass=0.16, light=False),
}

START, SWEEP = -90.0, 270.0      # from 12 o'clock to 9 o'clock: the pearl lands level with the crossbar
R_F, T_F, HW_F = 0.335, 0.082, 0.33   # ring radius, tube thickness, H width (fractions of the icon)

def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return x, y

def background(n, theme, t=0.0, grain=2.2, seed=3):
    th = THEMES[theme]
    x, y = grid(n); x /= n; y /= n
    img = np.zeros((n, n, 3), np.float32) + np.array(hexc(th['base']), np.float32)
    for i, (bx, by, r, col, a) in enumerate(th['blobs']):
        bx += 0.03 * math.sin(t * 0.8 + i * 1.7); by += 0.03 * math.cos(t * 0.6 + i)
        g = np.exp(-(((x - bx) ** 2 + (y - by) ** 2) / (2 * r * r)))[..., None] * a
        img = img * (1 - g) + np.array(hexc(col), np.float32) * g
    if not th['light']:
        img *= (1 - 0.30 * np.clip(((x - .5) ** 2 + (y - .5) ** 2) * 2.2, 0, 1))[..., None]
    img += np.random.default_rng(seed).normal(0, grain, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert('RGBA')

def _lut(stops):
    cols = [np.array(hexc(c), np.float32) for c in stops]
    out = []
    for i in range(256):
        u = i / 255 * (len(cols) - 1); k = min(int(u), len(cols) - 2); f = u - k
        out.append(cols[k] * (1 - f) + cols[k + 1] * f)
    return np.array(out, np.float32)

def _arr(img): return np.asarray(img).astype(np.float32)

def glass_ring(canvas, cx, cy, r, t, theme, ss=2, progress=1.0, track_alpha=1.0, pearl=True, fill_alpha=1.0):
    """Draws the glass tube, the charge light inside it and the pearl, onto `canvas` (RGBA, modified)."""
    th = THEMES[theme]; n = canvas.width; m_ = canvas.height
    N, M = n * ss, m_ * ss
    y, x = np.mgrid[0:M, 0:N].astype(np.float32) / ss
    dx, dy = x - cx, y - cy
    dist = np.sqrt(dx * dx + dy * dy)
    ang = (np.degrees(np.arctan2(dy, dx)) - START) % 360.0
    s = (dist - r) / (t / 2)                                  # -1 inner edge … +1 outer edge
    band = np.clip((1 - np.abs(s)) * (t / 2) + 0.5, 0, 1)     # anti-aliased tube mask

    def down(a): return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), 'L').resize((n, m_), Image.LANCZOS)

    if track_alpha > 0:
        # 1) frosted glass: blurred, brightened copy of what's behind
        tube = down(band * track_alpha)
        frost = canvas.filter(ImageFilter.GaussianBlur(max(2, t * 0.6)))
        wash = Image.new('RGBA', canvas.size, (255, 255, 255, 255))
        frost = Image.blend(frost, wash, th['glass'])
        canvas.paste(frost, (0, 0), tube)
        # 2) lighting: light from top-left. Rim light on both edges, strongest facing the light.
        facing = (np.cos(np.radians(np.degrees(np.arctan2(dy, dx)) - 225)) + 1) / 2   # 1 = faces top-left
        rim = np.exp(-((np.abs(s) - 0.86) / 0.09) ** 2) * band
        spec = np.exp(-((s + 0.35) / 0.22) ** 2) * np.clip(facing - 0.55, 0, 1) / 0.45 * band
        shade = np.clip(s, 0, 1) ** 2 * (1 - facing) * band
        light = down((rim * (0.35 + 0.55 * facing) + spec * 0.85) * track_alpha)
        canvas.alpha_composite(solid(light, (255, 255, 255)))
        canvas.alpha_composite(solid(down(shade * 0.35 * track_alpha), (10, 0, 25)))

    if progress > 0:
        sweep = SWEEP * progress
        w = t * 0.48                                           # light core, thinner than the tube
        core = np.clip(w / 2 - np.abs(dist - r) + 0.5, 0, 1) * (ang <= sweep)
        for a_deg in (START, START + sweep):
            ex, ey = cx + r * math.cos(math.radians(a_deg)), cy + r * math.sin(math.radians(a_deg))
            core = np.maximum(core, np.clip(w / 2 - np.sqrt((x - ex) ** 2 + (y - ey) ** 2) + 0.5, 0, 1))
        u = np.clip(ang / SWEEP, 0, 1); u = np.where(ang > 315, 0.0, u)
        col = _lut(th['fill'])[(u * 255).astype(np.int32)]
        core_img = Image.fromarray(np.dstack([col, core * 255 * fill_alpha]).astype(np.uint8), 'RGBA').resize((n, m_), Image.LANCZOS)
        g = core_img.filter(ImageFilter.GaussianBlur(t * 0.7)); g.putalpha(g.split()[3].point(lambda v: int(v * 0.9)))
        canvas.alpha_composite(g); canvas.alpha_composite(core_img)
        # inner hot line: makes it read as light, not paint
        hot = np.exp(-((dist - r) / (w * 0.16)) ** 2) * (ang <= sweep) * 0.55 * fill_alpha
        canvas.alpha_composite(solid(down(hot), (255, 255, 255)))
        if pearl:
            ex, ey = cx + r * math.cos(math.radians(START + sweep)), cy + r * math.sin(math.radians(START + sweep))
            draw_pearl(canvas, ex, ey, t * 0.62, fill_alpha)
    return canvas

def draw_pearl(canvas, x, y, rad, alpha=1.0):
    n, m_ = canvas.size
    d = Image.new('L', (n, m_), 0); ImageDraw.Draw(d).ellipse((x - rad * 2.6, y - rad * 2.6, x + rad * 2.6, y + rad * 2.6), fill=255)
    canvas.alpha_composite(solid(d.filter(ImageFilter.GaussianBlur(rad * 1.6)), (255, 214, 238), 0.55 * alpha))
    ss = 4
    big = Image.new('RGBA', (int(rad * 2 * ss) + 8, int(rad * 2 * ss) + 8), (0, 0, 0, 0))
    S = big.width; c = S / 2; R = rad * ss
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rr = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / R
    a = np.clip((1 - rr) * R, 0, 1)
    shade = 1 - 0.18 * np.clip((xx - c + (yy - c)) / (2 * R) + 0.5, 0, 1)        # darker bottom-right
    base = np.dstack([255 * shade, 238 * shade, 248 * shade])
    hl = np.exp(-(((xx - c + R * 0.35) ** 2 + (yy - c + R * 0.38) ** 2) / (2 * (R * 0.22) ** 2)))[..., None]
    rgb = base * (1 - hl) + 255 * hl
    big = Image.fromarray(np.dstack([rgb, a * 255 * alpha]).clip(0, 255).astype(np.uint8), 'RGBA')
    sm = big.resize((max(1, round(S / ss)), max(1, round(S / ss))), Image.LANCZOS)
    canvas.alpha_composite(sm, (round(x - sm.width / 2), round(y - sm.height / 2)))

def draw_h(canvas, cx, cy, width, theme, weight=1.12, alpha=1.0, glow=0.3):
    th = THEMES[theme]; n, m_ = canvas.size; S = max(n, m_)
    m = h_mask(S, cx + (S - n) / 2, cy + (S - m_) / 2, width, weight=weight).crop(((S - n) // 2, (S - m_) // 2, (S - n) // 2 + n, (S - m_) // 2 + m_))
    if not th['light'] and glow:
        canvas.alpha_composite(glow_of(m, width / 22, glow * alpha))
    if th['light']:
        canvas.alpha_composite(glow_of(m, width / 30, 0.18 * alpha, (80, 30, 110)), (0, int(width / 60)))
    canvas.alpha_composite(solid(m, hexc(th['ink']), alpha))
    return m

def icon(theme='aurora', n=1024, bg=True, mark=True):
    c = background(n, theme) if bg else Image.new('RGBA', (n, n), (0, 0, 0, 0))
    if mark:
        glass_ring(c, n / 2, n / 2, n * R_F, n * T_F, theme)
        draw_h(c, n / 2, n / 2, n * HW_F, theme)
    return c

def mono_mark(n, scale=1.0, ring_w=None):
    """Single-colour mark (alpha only): ring arc + pearl + H. For tinted / themed / notification icons."""
    ss = 4; N = n * ss
    m = Image.new('L', (N, N), 0); d = ImageDraw.Draw(m)
    r = n * R_F * scale * ss; w = (ring_w or n * T_F * 0.42 * scale) * ss; c = N / 2
    d.arc((c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2), START, START + SWEEP, fill=255, width=int(w))
    for a in (START,):
        ex, ey = c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a)); d.ellipse((ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=255)
    ex, ey = c + r * math.cos(math.radians(START + SWEEP)), c + r * math.sin(math.radians(START + SWEEP))
    pr = w * 0.95; d.ellipse((ex - pr, ey - pr, ex + pr, ey + pr), fill=255)
    m = m.resize((n, n), Image.LANCZOS)
    hm = h_mask(n, n / 2, n / 2, n * HW_F * scale, weight=1.15)
    return ImageChops.lighter(m, hm)
