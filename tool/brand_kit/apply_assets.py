import sys, os
_a = sys.argv; sys.argv = ['x', '/mnt/user-data/uploads/Hux-SmartRing-2.0-App/images/logo.png', '-']
import brand
sys.argv = _a
from glass import *
O = '/mnt/user-data/outputs/hux_apply'
for d in ('assets/splash', 'assets/images/brand', 'assets/icon'): os.makedirs(f'{O}/{d}', exist_ok=True)
# splash background (portrait aurora, no alpha)
w, h = 1290, 2796; S = h
bg = background(S, 'aurora', grain=0).crop(((S - w) // 2, 0, (S - w) // 2 + w, h)).convert('RGB')
bg.save(f'{O}/assets/splash/splash_bg.png', optimize=True)
def mark(n, frac):
    c = Image.new('RGBA', (n, n), (0, 0, 0, 0)); r = n * frac
    glass_ring(c, n / 2, n / 2, r, r * T_F / R_F, 'aurora', track_alpha=0.9)
    draw_h(c, n / 2, n / 2, r * HW_F / R_F, 'aurora'); return c
# splash image: treated as 4x → 800 px ≈ 200 dp. Ring radius 0.42 of canvas leaves room for the glow.
mark(800, 0.33).save(f'{O}/assets/splash/splash_mark.png', optimize=True)
# Android 12+: 1152 canvas, content inside the central 768 circle
a12 = Image.new('RGBA', (1152, 1152), (0, 0, 0, 0)); m = mark(768, 0.33); a12.alpha_composite(m, (192, 192))
a12.save(f'{O}/assets/splash/splash_android12.png', optimize=True)
# intro glyphs (white, alpha) at 2x of the logo's native px; crop box = wordmark rows 14..355
for nm, (x0, x1) in {'U': (420, 844), 'X': (847, 1269)}.items():
    g = brand.A.crop((x0 * brand.UP, 14 * brand.UP, x1 * brand.UP, 355 * brand.UP))
    g = g.resize(((x1 - x0) * 2, (355 - 14) * 2), Image.LANCZOS)
    solid(g, (255, 255, 255)).save(f'{O}/assets/images/brand/intro_{nm.lower()}.png', optimize=True)
# new icon masters in the repo (replace the old wordmark-on-glow masters)
K = '/mnt/user-data/outputs/HUX_Brand_Kit/01_App_Icon/masters/'
import shutil
shutil.copy(K + 'HUX_icon_aurora_1024.png', f'{O}/assets/icon/app_icon.png')
print('ok')
