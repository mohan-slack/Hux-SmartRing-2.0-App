"""Exports every HUX icon asset: masters, iOS (light/dark/tinted + alternates), Android (legacy, round,
adaptive, monochrome, notification), Play/App Store."""
import json, os, shutil
from glass import *
K = '/mnt/user-data/outputs/HUX_Brand_Kit'
def P(*a):
    p = os.path.join(K, *a); os.makedirs(os.path.dirname(p), exist_ok=True); return p
def save(img, path, rgb=False):
    (img.convert('RGB') if rgb else img).save(path, optimize=True)

shutil.rmtree(K, ignore_errors=True)
# ---- masters ----
masters = {}
for th in THEMES:
    masters[th] = icon(th, 1024)
    save(masters[th], P('01_App_Icon', 'masters', f'HUX_icon_{th}_1024.png'), rgb=True)

# transparent-background mark (for dark appearance, adaptive foreground, overlays)
def mark_only(n, theme='aurora', scale=1.0, track=True):
    c = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    glass_ring(c, n / 2, n / 2, n * R_F * scale, n * T_F * scale, theme, track_alpha=0.9 if track else 0)
    draw_h(c, n / 2, n / 2, n * HW_F * scale, theme)
    return c
save(mark_only(1024), P('01_App_Icon', 'masters', 'HUX_mark_transparent_1024.png'))
mono = mono_mark(1024)
save(solid(mono, (255, 255, 255)), P('01_App_Icon', 'masters', 'HUX_mark_mono_white_1024.png'))
save(solid(mono, hexc('#2A1640')), P('01_App_Icon', 'masters', 'HUX_mark_mono_ink_1024.png'))

# ---- iOS ----
ios = P('02_iOS', 'AppIcon.appiconset', 'x'); ios = os.path.dirname(ios)
save(masters['aurora'], f'{ios}/icon-1024.png', rgb=True)
dark = background(1024, 'midnight'); dark.alpha_composite(mark_only(1024, 'aurora', track=True))
save(dark, f'{ios}/icon-1024-dark.png', rgb=True)
tinted = Image.new('RGBA', (1024, 1024), (0, 0, 0, 255)); tinted.alpha_composite(solid(mono, (255, 255, 255)))
save(tinted.convert('L'), f'{ios}/icon-1024-tinted.png')
json.dump({"images": [
    {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon-1024-dark.png",
     "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon-1024-tinted.png",
     "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}}, open(f'{ios}/Contents.json', 'w'), indent=2)
legacy = {'20@2x': 40, '20@3x': 60, '29@2x': 58, '29@3x': 87, '40@2x': 80, '40@3x': 120, '60@2x': 120, '60@3x': 180,
          'ipad-20': 20, 'ipad-29': 29, 'ipad-40': 40, 'ipad-76': 76, 'ipad-76@2x': 152, 'ipad-83.5@2x': 167, 'marketing': 1024}
for name, px in legacy.items():
    save(masters['aurora'].resize((px, px), Image.LANCZOS), P('02_iOS', 'legacy_sizes', f'Icon-{name}-{px}px.png'), rgb=True)
for th in THEMES:
    if th == 'aurora': continue
    for suf, px in (('@2x', 120), ('@3x', 180), ('-ipad@2x', 152), ('-ipad-pro@2x', 167)):
        save(masters[th].resize((px, px), Image.LANCZOS), P('02_iOS', 'alternate_icons', f'AppIcon-{th.title()}{suf}.png'), rgb=True)

# ---- Android ----
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
# adaptive: 108dp canvas, mark kept inside the 66dp safe circle (ring outer edge ≈ 30dp)
AD_SCALE = 0.70
fg = mark_only(1024, 'aurora', scale=AD_SCALE)
bgA = background(1024, 'aurora')
mono_ad = solid(mono_mark(1024, scale=AD_SCALE), (255, 255, 255))
for d, k in dens.items():
    a = round(108 * k)
    save(fg.resize((a, a), Image.LANCZOS), P('03_Android', 'res', f'mipmap-{d}', 'ic_launcher_foreground.png'))
    save(bgA.resize((a, a), Image.LANCZOS), P('03_Android', 'res', f'mipmap-{d}', 'ic_launcher_background.png'), rgb=True)
    save(mono_ad.resize((a, a), Image.LANCZOS), P('03_Android', 'res', f'mipmap-{d}', 'ic_launcher_monochrome.png'))
    l = round(48 * k)
    save(masked(masters['aurora'], l), P('03_Android', 'res', f'mipmap-{d}', 'ic_launcher.png'))
    save(masked(masters['aurora'], l, 'circle'), P('03_Android', 'res', f'mipmap-{d}', 'ic_launcher_round.png'))
    nz = round(24 * k)
    nm = mono_mark(nz * 4, scale=1.12, ring_w=nz * 4 * 0.075).resize((nz, nz), Image.LANCZOS)
    save(solid(nm, (255, 255, 255)), P('03_Android', 'res', f'drawable-{d}', 'ic_stat_hux.png'))
xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''
for f in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    open(P('03_Android', 'res', 'mipmap-anydpi-v26', f), 'w').write(xml)
for th in THEMES:
    if th == 'aurora': continue
    for d, k in dens.items():
        save(masked(masters[th], round(48 * k)), P('03_Android', 'alternate_icons', f'mipmap-{d}', f'ic_launcher_{th}.png'))

# ---- stores ----
save(masters['aurora'].resize((512, 512), Image.LANCZOS), P('04_Store', 'play_store_icon_512.png'), rgb=True)
save(masters['aurora'], P('04_Store', 'app_store_icon_1024.png'), rgb=True)
print('icons done')
