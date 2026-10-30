"""HUX intro — glass charge. python3 anim3.py square|portrait"""
import sys, os, shutil, subprocess
tag = sys.argv[1]
_a = sys.argv; sys.argv = ['x', '/mnt/user-data/uploads/Hux-SmartRing-2.0-App/images/logo.png', '-']
import brand
sys.argv = _a
from glass import *
from PIL import ImageFont
FD = '/tmp/claude-0/-home-claude/4cca0ce5-52d4-5448-ab9c-46b40312f1e4/scratchpad/fonts/'
OUT = '/mnt/user-data/outputs/HUX_Brand_Kit/06_Motion'; os.makedirs(OUT, exist_ok=True)
FR = f'/tmp/claude-0/-home-claude/4cca0ce5-52d4-5448-ab9c-46b40312f1e4/scratchpad/logo/fr_{tag}'
W, H = (1080, 1920) if tag == 'portrait' else (1080, 1080)
FPS, DUR = 30, 4.4
S = max(W, H); cx, cy = W / 2, H / 2
n0 = min(W, H) * (0.9 if tag == 'portrait' else 1.0)
R0, T0, HW0 = n0 * R_F, n0 * T_F, n0 * HW_F
WMW = 1249.0; k = min(W, H) * 0.64 / WMW; wm_left = cx - WMW * k / 2
H1w = H_W * k; H1cx = wm_left + (23 - 20 + H_W / 2) * k
def ease_io(t): return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def ease_out(t): return 1 - (1 - t) ** 3
def back_out(t, s=1.5): t -= 1; return t * t * ((s + 1) * t + s) + 1
def Pr(t, a, b): return 0.0 if t <= a else 1.0 if t >= b else (t - a) / (b - a)
def lerp(a, b, t): return a + (b - a) * t
def glyph_place(nm):
    g = brand.glyph[nm]; x0 = {'U': 420, 'X': 847}[nm]
    return g, wm_left + (x0 - 20) * k + g.width / brand.UP * k / 2, (355 - 14) * k
def paste_alpha(c, alpha, x, y, h, opacity=1.0, rot=0.0):
    s = h / alpha.height
    a = alpha.resize((max(1, round(alpha.width * s)), max(1, round(alpha.height * s))), Image.LANCZOS)
    pad = max(8, a.height // 3); p = Image.new('L', (a.width + 2 * pad, a.height + 2 * pad), 0); p.paste(a, (pad, pad)); a = p
    if rot: a = a.rotate(rot, Image.BICUBIC)
    if opacity < 1: a = a.point(lambda v: int(v * opacity))
    pos = (round(x - a.width / 2), round(y - a.height / 2))
    c.alpha_composite(glow_of(a, max(2, h / 18), 0.3 * opacity), pos); c.alpha_composite(solid(a, (255, 255, 255)), pos)
WM = Image.new('L', (W, H), 0)
WM.paste(h_mask(S, H1cx + (S - W) / 2, cy + (S - H) / 2, H1w).crop(((S - W) // 2, (S - H) // 2, (S - W) // 2 + W, (S - H) // 2 + H)), (0, 0))
for nm in 'UX':
    g, gx, gh = glyph_place(nm); a = g.resize((round(g.width * gh / g.height), round(gh)), Image.LANCZOS)
    WM.paste(a, (round(gx - a.width / 2), round(cy - a.height / 2)), a)
font = ImageFont.truetype(FD + 'Urbanist-600.ttf', int(min(W, H) * 0.045))

shutil.rmtree(FR, ignore_errors=True); os.makedirs(FR)
for i in range(int(DUR * FPS)):
    t = i / FPS
    c = background(S, 'aurora', t=t, grain=2, seed=i % 5).crop(((S - W) // 2, (S - H) // 2, (S - W) // 2 + W, (S - H) // 2 + H))
    pt = ease_out(Pr(t, 0.0, 0.45)); pf = ease_out(Pr(t, 0.25, 1.3)); rel = ease_io(Pr(t, 1.6, 2.1))
    pulse = math.sin(math.pi * Pr(t, 1.3, 1.6))
    if rel < 1:
        r = R0 * lerp(lerp(0.92, 1, pt), 1.22, rel)
        glass_ring(c, cx, cy, r, T0 * lerp(1, 0.6, rel), 'aurora', ss=1, progress=pf, track_alpha=pt * (1 - rel),
                   pearl=False, fill_alpha=1 - rel)
    # pearl: rides the charge, pulses at 9 o'clock, then flows into the crossbar
    pm = ease_io(Pr(t, 1.85, 2.6))
    hw = lerp(HW0, H1w, pm); hx = lerp(cx, H1cx, pm)
    if pf > 0 and pm < 1:
        a = math.radians(START + SWEEP * pf); rr = R0 * lerp(lerp(0.92, 1, pt), 1.22, rel)
        ring_x, ring_y = cx + rr * math.cos(a), cy + rr * math.sin(a)
        flow = ease_io(Pr(t, 1.6, 2.15))
        bar_x = hx - hw / 2 + 83.5 * hw / H_W
        px_, py_ = lerp(ring_x, bar_x, flow), lerp(ring_y, cy, flow)
        size = T0 * 0.62 * (1 + 0.25 * pulse) * lerp(1, 0.4, flow)
        draw_pearl(c, px_, py_, size, 1 - ease_io(Pr(t, 2.05, 2.25)))
    ph = ease_out(Pr(t, 0.45, 1.0))
    if ph > 0:
        glow = 0.3 + 0.35 * ease_out(Pr(t, 2.0, 2.2)) * (1 - Pr(t, 2.2, 2.7))
        draw_h(c, hx, cy, hw * (lerp(0.9, 1, ph) if pm == 0 else 1), 'aurora', weight=lerp(1.12, 1.0, pm), alpha=ph, glow=glow)
    pu = Pr(t, 2.3, 2.85)
    if pu > 0:
        g, ux, gh = glyph_place('U')
        paste_alpha(c, g, ux + (1 - ease_out(pu)) * W * 0.05, cy + (1 - ease_out(pu)) * gh * 0.25, gh * lerp(0.82, 1, back_out(pu)), min(1, pu * 1.7))
    pxx = Pr(t, 2.55, 3.15)
    if pxx > 0:
        g, xx, gh = glyph_place('X')
        paste_alpha(c, g, xx, cy, gh * lerp(0.55, 1, back_out(pxx)), min(1, pxx * 1.7), lerp(90, 0, ease_out(pxx)))
    ps = Pr(t, 3.25, 3.75)
    if 0 < ps < 1:
        band = Image.new('L', (W, H), 0); d = ImageDraw.Draw(band)
        x = lerp(wm_left - W * 0.25, wm_left + WMW * k + W * 0.1, ease_io(ps)); bw = W * 0.06
        d.polygon([(x, cy - H1w), (x + bw, cy - H1w), (x + bw - W * 0.18, cy + H1w), (x - W * 0.18, cy + H1w)], fill=210)
        c.alpha_composite(solid(ImageChops.multiply(band.filter(ImageFilter.GaussianBlur(W / 80)), WM), (255, 225, 240)))
    pg = ease_out(Pr(t, 3.45, 4.0))
    if pg > 0:
        tl = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(tl).text((cx, cy + H1w * 0.62 + (1 - pg) * 20), 'Know your charge.', font=font, fill=(255, 255, 255, int(235 * pg)), anchor='ma')
        c.alpha_composite(tl)
    c.convert('RGB').save(f'{FR}/f{i:03d}.png')

base = f'{OUT}/HUX_intro_{tag}'
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(FPS), '-i', f'{FR}/f%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-movflags', '+faststart', base + '.mp4'], check=True)
keys = [6, 20, 36, 46, 56, 64, 74, 84, 96, 120]
tw = 220; th_ = int(tw * H / W)
sb = Image.new('RGB', (len(keys) * tw, th_))
for j, f in enumerate(keys): sb.paste(Image.open(f'{FR}/f{f:03d}.png').resize((tw, th_), Image.LANCZOS), (j * tw, 0))
sb.save(base + '_storyboard.png'); print('ok', tag)
