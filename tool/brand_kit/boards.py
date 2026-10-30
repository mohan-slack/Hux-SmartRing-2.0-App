import sys, math, os
_a = sys.argv; sys.argv = ['x', '/mnt/user-data/uploads/Hux-SmartRing-2.0-App/images/logo.png', '-']
import brand
sys.argv = _a
from glass import *
from PIL import ImageFont
K = '/mnt/user-data/outputs/HUX_Brand_Kit'
B = f'{K}/00_Boards'; os.makedirs(B, exist_ok=True)
FD = '/tmp/claude-0/-home-claude/4cca0ce5-52d4-5448-ab9c-46b40312f1e4/scratchpad/fonts/'
def F(w, s): return ImageFont.truetype(f'{FD}Urbanist-{w}.ttf', s)
INK, MUTED, PAPER, HAIR = hexc('#1B1925'), hexc('#6E6A7C'), hexc('#F6F4FA'), hexc('#E4E0EC')
W, H = 2400, 1500
MAST = {t: Image.open(f'{K}/01_App_Icon/masters/HUX_icon_{t}_1024.png').convert('RGBA') for t in THEMES}
MONO = Image.open(f'{K}/01_App_Icon/masters/HUX_mark_mono_white_1024.png').split()[3]

def wordmark(height, color):
    a = brand.A.crop(brand.A.getbbox())
    s = height / a.height
    a = a.resize((round(a.width * s), round(height)), Image.LANCZOS)
    return solid(a, color)

def board(title, kicker, num, dark=False):
    bg = background(W, 'aurora').resize((W, W)).crop((0, 0, W, H)) if dark else Image.new('RGBA', (W, H), PAPER + (255,))
    d = ImageDraw.Draw(bg)
    fg = (255, 255, 255) if dark else INK; mu = (220, 210, 235) if dark else MUTED
    bg.alpha_composite(wordmark(34, fg), (120, 96))
    d.text((W - 120, 100), f'BRAND KIT  ·  {num:02d}', font=F(700, 22), fill=mu, anchor='ra')
    d.text((120, 190), kicker.upper(), font=F(700, 24), fill=hexc('#C93B86') if not dark else (255, 170, 215))
    d.text((120, 228), title, font=F(800, 76), fill=fg)
    d.line((120, H - 90, W - 120, H - 90), fill=(255, 255, 255, 60) if dark else HAIR, width=2)
    d.text((120, H - 70), 'HUX · Viveon Gizit Pvt Ltd · v1.0 · Oct 2026', font=F(500, 20), fill=mu)
    d.text((W - 120, H - 70), 'Know your charge.', font=F(700, 20), fill=mu, anchor='ra')
    return bg, d

def shadowed(canvas, img, x, y, radius=40, amount=0.28, shape='squircle'):
    n = img.width
    m = squircle_mask(n) if shape == 'squircle' else Image.new('L', (n, n), 0)
    if shape == 'circle': ImageDraw.Draw(m).ellipse((0, 0, n - 1, n - 1), fill=255)
    pad = Image.new('L', (n + 4 * radius, n + 4 * radius), 0); pad.paste(m, (2 * radius, 2 * radius + radius // 2))
    canvas.alpha_composite(glow_of(pad, radius, amount, (50, 15, 80)), (x - 2 * radius, y - 2 * radius))
    canvas.alpha_composite(masked(img, n, shape), (x, y))

def para(d, xy, text, font, fill, width, spacing=10):
    words, lines, cur = text.split(), [], ''
    for w_ in words:
        t = (cur + ' ' + w_).strip()
        if d.textlength(t, font=font) > width and cur: lines.append(cur); cur = w_
        else: cur = t
    lines.append(cur)
    x, y = xy
    for ln in lines:
        d.text((x, y), ln, font=font, fill=fill); y += font.size + spacing
    return y

# ========== 01 · The idea ==========
def b01():
    c, d = board('Know your charge.', 'The idea', 1, dark=True)
    big = MAST['aurora'].resize((860, 860), Image.LANCZOS)
    shadowed(c, big, 1400, 360, 60, 0.45)
    y = para(d, (120, 360), 'HUX reads the body\'s quiet signals — sleep, heart, steps, cycle — and turns them into one honest number: your charge. The mark is that idea, held in glass.',
             F(500, 38), (245, 238, 252), 1120, 14)
    items = [('Glass ring', 'Clarity and privacy. You see through it; nothing leaves your phone.'),
             ('Charge light', 'Your energy today, flowing from 12 o\'clock. Pink to indigo: active to restful.'),
             ('The pearl', '"Now." It stops level with the H\'s floating crossbar — the charge flows into you.'),
             ('The H', 'Cut from the HUX wordmark. The open crossbar is our signature: room to breathe.')]
    y += 40
    for i, (t, s) in enumerate(items):
        yy = y + i * 150
        d.ellipse((120, yy + 10, 150, yy + 40), fill=(255, 255, 255))
        d.text((180, yy), t, font=F(800, 36), fill=(255, 255, 255))
        para(d, (180, yy + 50), s, F(500, 28), (220, 208, 236), 980, 8)
    c.convert('RGB').save(f'{B}/01_The_Idea.png')

# ========== 02 · Icon family ==========
DESC = {'aurora': ('Aurora', 'Default. The brand at full voice.'), 'midnight': ('Midnight', 'For dark home screens. Calm, low glow.'),
        'daylight': ('Daylight', 'Light and airy. Matches the app UI.'), 'blush': ('Blush', 'Warm and soft. A favourite for Cycle users.'),
        'calm': ('Calm', 'Teal and indigo. Recovery and sleep.'), 'spectrum': ('Spectrum', 'Every colour, every body. HUX is for all.')}
def b02():
    c, d = board('One mark, six moods.', 'App icon family · user-selectable', 2)
    for i, th in enumerate(THEMES):
        x = 120 + (i % 3) * 740; y = 380 + (i // 3) * 520
        shadowed(c, MAST[th].resize((300, 300), Image.LANCZOS), x, y, 30, 0.25)
        n, s = DESC[th]
        d.text((x + 340, y + 70), n, font=F(800, 44), fill=INK)
        para(d, (x + 340, y + 130), s, F(500, 26), MUTED, 330, 6)
        d.text((x + 340, y + 220), 'Default' if th == 'aurora' else 'Alternate icon', font=F(700, 20), fill=hexc('#C93B86'))
    c.convert('RGB').save(f'{B}/02_Icon_Family.png')

# ========== 03 · Platforms ==========
def b03():
    c, d = board('Built for iOS 18 and Android 13+.', 'Platforms & appearances', 3)
    ios = f'{K}/02_iOS/AppIcon.appiconset/'
    trio = [('Light', Image.open(ios + 'icon-1024.png').convert('RGBA')), ('Dark', Image.open(ios + 'icon-1024-dark.png').convert('RGBA')),
            ('Tinted', Image.open(ios + 'icon-1024-tinted.png').convert('RGBA'))]
    d.text((120, 360), 'iOS', font=F(800, 40), fill=INK)
    for i, (n, im) in enumerate(trio):
        x = 120 + i * 330
        shadowed(c, im.resize((260, 260), Image.LANCZOS), x, 430, 26, 0.25)
        d.text((x + 130, 720), n, font=F(700, 26), fill=INK, anchor='ma')
    para(d, (120, 780), 'One 1024 px master per appearance (Xcode single-size). Tinted is grayscale; iOS adds the user\'s tint. No alpha on the light icon.',
         F(500, 24), MUTED, 960, 6)
    d.text((1180, 360), 'Android', font=F(800, 40), fill=INK)
    bgA = Image.open(f'{K}/03_Android/res/mipmap-xxxhdpi/ic_launcher_background.png').convert('RGBA')
    fg = Image.open(f'{K}/03_Android/res/mipmap-xxxhdpi/ic_launcher_foreground.png').convert('RGBA')
    ad = bgA.copy(); ad.alpha_composite(fg); ad = ad.resize((240, 240), Image.LANCZOS)
    shapes = [('Circle', 'circle'), ('Squircle', 'squircle'), ('Rounded', 'rounded'), ('Themed', 'themed')]
    for i, (n, sh) in enumerate(shapes):
        x = 1180 + i * 285; y = 430
        if sh == 'themed':
            mono = Image.open(f'{K}/03_Android/res/mipmap-xxxhdpi/ic_launcher_monochrome.png').convert('RGBA').resize((240, 240), Image.LANCZOS)
            t = Image.new('RGBA', (240, 240), hexc('#DCE8DC') + (255,)); t.alpha_composite(solid(mono.split()[3], hexc('#24412B')))
            shadowed(c, t, x, y, 24, 0.2, 'circle')
        elif sh == 'rounded':
            m = Image.new('L', (240, 240), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 239, 239), 44, fill=255)
            pad = Image.new('L', (340, 340), 0); pad.paste(m, (50, 62)); c.alpha_composite(glow_of(pad, 24, 0.2, (50, 15, 80)), (x - 50, y - 50))
            out = Image.new('RGBA', (240, 240), (0, 0, 0, 0)); out.paste(ad, (0, 0), m); c.alpha_composite(out, (x, y))
        else:
            shadowed(c, ad, x, y, 24, 0.22, sh)
        d.text((x + 120, 720), n, font=F(700, 26), fill=INK, anchor='ma')
    para(d, (1180, 780), 'Adaptive icon: aurora background + glass mark foreground, kept inside the 66 dp safe zone so every launcher mask works. Monochrome layer for Material You themed icons.',
         F(500, 24), MUTED, 1080, 6)
    # notification + store
    d.text((120, 930), 'Small marks', font=F(800, 40), fill=INK)
    bar = Image.new('RGBA', (900, 120), (255, 255, 255, 255)); bd = ImageDraw.Draw(bar)
    bd.rounded_rectangle((0, 0, 899, 119), 28, fill=(255, 255, 255), outline=HAIR, width=2)
    ni = solid(MONO.resize((56, 56), Image.LANCZOS), hexc('#C93B86')); bar.alpha_composite(ni, (32, 32))
    bd.text((110, 26), 'HUX · now', font=F(700, 24), fill=INK); bd.text((110, 60), 'Heads-up from HUX', font=F(500, 26), fill=MUTED)
    c.alpha_composite(bar, (120, 1000))
    para(d, (120, 1140), 'Notification icon: the mono mark, white on transparent, tinted HUX Pink by Android. 24 dp, all densities.', F(500, 24), MUTED, 900, 6)
    d.text((1180, 930), 'Stores', font=F(800, 40), fill=INK)
    shadowed(c, MAST['aurora'].resize((200, 200), Image.LANCZOS), 1180, 1000, 22, 0.22, 'circle')
    shadowed(c, MAST['aurora'].resize((200, 200), Image.LANCZOS), 1430, 1000, 22, 0.22)
    d.text((1280, 1225), 'Google Play 512', font=F(700, 22), fill=INK, anchor='ma'); d.text((1530, 1225), 'App Store 1024', font=F(700, 22), fill=INK, anchor='ma')
    c.convert('RGB').save(f'{B}/03_Platforms.png')

# ========== 04 · Sizes ==========
def b04():
    c, d = board('Crisp from 1024 down to 20.', 'App icon sizes', 4)
    ios = [(1024, 'App Store'), (180, 'iPhone @3x'), (167, 'iPad Pro'), (152, 'iPad @2x'), (120, 'iPhone @2x'), (87, 'Settings @3x'),
           (80, 'Spotlight @2x'), (60, 'Notif. @3x'), (40, 'Notif. @2x'), (29, 'Settings'), (20, 'Notif.')]
    d.text((120, 360), 'iOS', font=F(800, 40), fill=INK)
    x = 120; base = 700
    for px, lab in ios:
        s = 300 if px == 1024 else px
        im = MAST['aurora'].resize((px, px), Image.LANCZOS).resize((s, s), Image.NEAREST if px < s else Image.LANCZOS)
        shadowed(c, im, x, base - s, max(6, s // 10), 0.2)
        d.text((x + s / 2, base + 24), f'{px}', font=F(800, 26), fill=INK, anchor='ma')
        d.text((x + s / 2, base + 58), lab, font=F(500, 18), fill=MUTED, anchor='ma')
        x += s + (60 if px > 100 else 50)
    d.text((120, 860), 'Android', font=F(800, 40), fill=INK)
    x = 120; base = 1240
    for dn, k in [('xxxhdpi', 4), ('xxhdpi', 3), ('xhdpi', 2), ('hdpi', 1.5), ('mdpi', 1)]:
        px = round(48 * k)
        shadowed(c, MAST['aurora'].resize((px, px), Image.LANCZOS), x, base - px, 12, 0.2, 'circle')
        d.text((x + px / 2, base + 24), f'{px}', font=F(800, 26), fill=INK, anchor='ma'); d.text((x + px / 2, base + 58), dn, font=F(500, 18), fill=MUTED, anchor='ma')
        x += px + 70
    para(d, (1300, 960), 'Adaptive layers: 108 dp (432 px xxxhdpi) foreground, background and monochrome at every density. Play Store: 512 px. Every file is in the kit, named for drop-in use.',
         F(500, 26), MUTED, 960, 8)
    c.convert('RGB').save(f'{B}/04_Icon_Sizes.png')

# ========== 05 · Logo ==========
def b05():
    c, d = board('The H, measured.', 'Logo & construction', 5)
    # construction of H (unit = stroke)
    S = 560; ox, oy = 160, 400; k = S / H_W
    gc = Image.new('RGBA', (W, H), (0, 0, 0, 0)); gd = ImageDraw.Draw(gc)
    for i in range(0, 13):
        x = ox + i * H_S * k; gd.line((x, oy - 30, x, oy + H_H * k + 30), fill=(201, 59, 134, 40), width=1)
    for j in range(0, 12):
        y = oy + j * H_S * k; gd.line((ox - 30, y, ox + H_W * k + 30, y), fill=(201, 59, 134, 40), width=1)
    c.alpha_composite(gc)
    m = h_mask(W, ox + H_W * k / 2, oy + H_H * k / 2, S)
    c.alpha_composite(solid(m, INK))
    gx0 = ox + (15.5 + 15.5) * k; gx1 = ox + (83.5 - 15.5) * k; gy = oy + 166.5 * k
    d.line((gx0, gy - 60, gx0, gy + 60), fill=hexc('#C93B86'), width=3); d.line((gx1, gy - 60, gx1, gy + 60), fill=hexc('#C93B86'), width=3)
    d.text(((gx0 + gx1) / 2, gy - 100), '1.2 u', font=F(800, 24), fill=hexc('#C93B86'), anchor='ma')
    para(d, (160, 940), '1 unit (u) = stroke width. H = 12.3 × 10.8 u. Round caps everywhere. The crossbar floats 1.2 u from the left stem — never close the gap.',
         F(500, 26), MUTED, 700, 8)
    # lockups
    x0 = 1000
    d.text((x0, 360), 'Lockups', font=F(800, 40), fill=INK)
    wm = wordmark(130, INK); c.alpha_composite(wm, (x0, 440))
    mk = MAST['aurora'].resize((170, 170), Image.LANCZOS)
    shadowed(c, mk, x0, 650, 18, 0.2); c.alpha_composite(wordmark(90, INK), (x0 + 210, 690))
    dk = Image.new('RGBA', (560, 260), (0, 0, 0, 0)); dk.paste(background(560, 'aurora').crop((0, 150, 560, 410)), (0, 0))
    rm = Image.new('L', (560, 260), 0); ImageDraw.Draw(rm).rounded_rectangle((0, 0, 559, 259), 30, fill=255)
    tile = Image.new('RGBA', (560, 260), (0, 0, 0, 0)); tile.paste(dk, (0, 0), rm); c.alpha_composite(tile, (x0 + 700, 440))
    c.alpha_composite(wordmark(80, (255, 255, 255)), (x0 + 760, 530))
    # clear space + min size
    d.text((x0, 930), 'Clear space & minimum size', font=F(800, 40), fill=INK)
    wm2 = wordmark(100, INK); bx, by = x0 + 60, 1050
    d.rectangle((bx - 50, by - 50, bx + wm2.width + 50, by + 150), outline=hexc('#C93B86'), width=2)
    c.alpha_composite(wm2, (bx, by))
    d.text((bx + wm2.width + 80, by + 20), 'Clear space = height of the H crossbar gap ×4\n(about half the wordmark height) on every side.', font=F(500, 24), fill=MUTED, spacing=8)
    d.text((bx + wm2.width + 80, by + 120), 'Minimum: wordmark 64 px / 12 mm wide · mark 24 px', font=F(700, 24), fill=INK)
    c.convert('RGB').save(f'{B}/05_Logo.png')

# ========== 06 · Colour ==========
def contrast(c1, c2):
    def L(c):
        v = [x / 255 for x in c]; v = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in v]
        return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
    a, b = sorted([L(c1), L(c2)], reverse=True); return (a + 0.05) / (b + 0.05)
PAL = [('HUX Pink', '#C93B86', 'Primary · actions, charge'), ('Vivid Pink', '#F567B5', 'Glow · highlights'), ('Plum', '#6B2E9A', 'Depth · gradients'),
       ('Indigo', '#4453D6', 'Calm · sleep end of charge'), ('Cherry', '#E8573B', 'Warmth · accents'), ('Midnight', '#1A0B30', 'Aurora base'),
       ('Ink', '#1B1925', 'Text'), ('Mist', '#F6F4FA', 'App background')]
STATUS = [('Recharged', '#1FA463'), ('Steady', '#0E9F9A'), ('Stretched', '#D98400'), ('Run down', '#DE4C36')]
def b06():
    c, d = board('Colour with a pulse.', 'Colour', 6)
    for i, (n, hx, role) in enumerate(PAL):
        x = 120 + (i % 4) * 545; y = 360 + (i // 4) * 330
        col = hexc(hx)
        d.rounded_rectangle((x, y, x + 500, y + 180), 26, fill=col, outline=HAIR if n == 'Mist' else None, width=2)
        on = (255, 255, 255) if contrast(col, (255, 255, 255)) >= contrast(col, INK) else INK
        d.text((x + 28, y + 24), n, font=F(800, 34), fill=on)
        cr = contrast(col, (255, 255, 255)) if on == (255, 255, 255) else contrast(col, INK)
        d.text((x + 28, y + 130), f'{"white" if on == (255,255,255) else "ink"} text {cr:.1f}:1', font=F(600, 20), fill=on)
        d.text((x, y + 196), f'{hx}  ·  RGB {col[0]} {col[1]} {col[2]}', font=F(700, 22), fill=INK)
        d.text((x, y + 230), role, font=F(500, 22), fill=MUTED)
    # gradients
    y = 1040
    d.text((120, y), 'Charge gradient', font=F(800, 30), fill=INK)
    g = Image.new('RGBA', (1000, 90)); stops = THEMES['aurora']['fill']; lut = [np.array(hexc(s)) for s in stops]
    gd = ImageDraw.Draw(g)
    for x in range(1000):
        u = x / 999 * (len(lut) - 1); k = min(int(u), len(lut) - 2); f = u - k; cc = lut[k] * (1 - f) + lut[k + 1] * f
        gd.line((x, 0, x, 89), fill=tuple(int(v) for v in cc))
    m = Image.new('L', (1000, 90), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 999, 89), 45, fill=255); g.putalpha(m); c.alpha_composite(g, (120, y + 50))
    d.text((120, y + 156), '#FF8FCB  >  #F567B5  >  #C93B86  >  #8B3FD0  >  #5B6CF0   ·   from 12 o\'clock to 9 o\'clock', font=F(600, 22), fill=MUTED)
    d.text((1260, y), 'Readout status', font=F(800, 30), fill=INK)
    for i, (n, hx) in enumerate(STATUS):
        x = 1260 + i * 255
        d.rounded_rectangle((x, y + 50, x + 230, y + 140), 45, fill=hexc(hx))
        d.text((x + 115, y + 80), n, font=F(800, 24), fill=(255, 255, 255), anchor='ma')
        d.text((x + 115, y + 156), hx, font=F(600, 20), fill=MUTED, anchor='ma')
    d.text((1260, y + 200), 'Status never relies on colour alone: always a word + icon.', font=F(600, 22), fill=INK)
    c.convert('RGB').save(f'{B}/06_Colour.png')

# ========== 07 · Type & voice ==========
def b07():
    c, d = board('Urbanist, warm and clear.', 'Typography & voice', 7)
    scale = [('Display', 800, 96, 'Know your charge.'), ('Headline', 800, 56, 'You\'re steady today'), ('Title', 700, 36, 'Sleep vs your normal'),
             ('Body', 500, 28, 'HRV is a little below your usual. Keep today easy.'), ('Label', 700, 22, 'DAY 18 · LUTEAL')]
    y = 370
    for n, w, s, sample in scale:
        d.text((120, y + 8), f'{n}\n{w} · {s}', font=F(600, 20), fill=MUTED, spacing=6)
        d.text((380, y), sample, font=F(w, s), fill=INK)
        y += s + 70
    x0 = 1500
    d.text((x0, 370), 'Voice', font=F(800, 40), fill=INK)
    rules = [('Plain words', '"Your sleep was shorter than usual" — not "sleep debt detected".'),
             ('Kind, never alarming', 'A dip is information, not failure.'),
             ('India-first', 'Dal, chai, terrace walks. Hinglish welcome.'),
             ('Honest', 'Ranges, not promises. Say what we don\'t know.'),
             ('For everyone', 'Any body, any age, any language. Opt-in for anything sensitive.')]
    y = 440
    for t, s in rules:
        d.text((x0, y), t, font=F(800, 30), fill=hexc('#C93B86'))
        y = para(d, (x0, y + 42), s, F(500, 26), INK, 780, 6) + 26
    c.convert('RGB').save(f'{B}/07_Type_and_Voice.png')

# ========== 08 · Inclusion & rules ==========
def b08():
    c, d = board('Designed for every body.', 'Inclusion · do & don\'t', 8)
    pts = [('Contrast', 'Text meets WCAG AA (4.5:1). White on HUX Pink is 4.7:1; ink on Mist is 15.9:1.'),
           ('Not colour alone', 'Charge also shows as a number and a word. The pearl marks "now" for colour-blind users.'),
           ('Text scaling', 'Layouts reflow up to 200% text size. Nothing important lives in an image.'),
           ('Languages', 'English, Hinglish, Hindi, Telugu, Tamil, Kannada. Leave room: Indic scripts run taller.'),
           ('Privacy as design', 'Sensitive features (Cycle) are opt-in, lockable, and never in share cards.'),
           ('Motion', 'Respect "Reduce motion": the intro becomes a 300 ms fade.')]
    for i, (t, s) in enumerate(pts):
        x = 120 + (i % 3) * 730; y = 380 + (i // 3) * 260
        d.text((x, y), t, font=F(800, 34), fill=INK); para(d, (x, y + 52), s, F(500, 26), MUTED, 640, 6)
    # do / don't icons
    y = 960
    d.text((120, y), 'Do', font=F(800, 34), fill=hexc('#1FA463')); d.text((1260, y), 'Don\'t', font=F(800, 34), fill=hexc('#DE4C36'))
    shadowed(c, MAST['aurora'].resize((200, 200), Image.LANCZOS), 120, y + 70, 20, 0.2)
    shadowed(c, MAST['midnight'].resize((200, 200), Image.LANCZOS), 380, y + 70, 20, 0.2)
    shadowed(c, MAST['daylight'].resize((200, 200), Image.LANCZOS), 640, y + 70, 20, 0.2)
    d.text((120, y + 300), 'Use the family as made. Pick by mood, not by whim.', font=F(600, 24), fill=INK)
    bad = []
    a = MAST['aurora'].resize((200, 200), Image.LANCZOS).transpose(Image.FLIP_LEFT_RIGHT); bad.append((a, 'Mirror it'))
    b = MAST['aurora'].resize((200, 200), Image.LANCZOS); b = Image.eval(b.convert('RGB'), lambda v: 255 - v).convert('RGBA'); bad.append((b, 'Recolour it'))
    cc = MAST['aurora'].resize((200, 200), Image.LANCZOS).resize((260, 160), Image.LANCZOS).resize((200, 200)); bad.append((cc, 'Stretch it'))
    e = MAST['aurora'].resize((200, 200), Image.LANCZOS); ed = ImageDraw.Draw(e); ed.rectangle((50, 92, 70, 108), fill=(255, 255, 255)); bad.append((e, 'Close the gap'))
    for i, (im, lab) in enumerate(bad):
        x = 1260 + i * 250
        shadowed(c, im, x, y + 70, 20, 0.2)
        d.line((x + 10, y + 80, x + 190, y + 260), fill=hexc('#DE4C36'), width=6)
        d.text((x + 100, y + 300), lab, font=F(600, 22), fill=INK, anchor='ma')
    c.convert('RGB').save(f'{B}/08_Inclusion_and_Rules.png')

# ========== phone mock & in-context ==========
def phone(theme_wall='light', icon_theme='aurora', w=520):
    h = int(w * 2.05); ph = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), int(w * 0.13), fill=255)
    if theme_wall == 'light':
        wall = background(h, 'daylight').crop(((h - w) // 2, 0, (h - w) // 2 + w, h))
    else:
        wall = background(h, 'midnight').crop(((h - w) // 2, 0, (h - w) // 2 + w, h))
    ph.paste(wall, (0, 0), m)
    d = ImageDraw.Draw(ph); fg = INK if theme_wall == 'light' else (255, 255, 255)
    d.text((40, 26), '9:41', font=F(700, 22), fill=fg)
    d.rounded_rectangle((w / 2 - 70, 18, w / 2 + 70, 52), 17, fill=(0, 0, 0))
    cols = ['#34C759', '#FF9500', '#007AFF', '#FF3B30', '#5856D6', '#FFCC00', '#5AC8FA', '#8E8E93', '#AF52DE', '#FF2D55', '#30B0C7', '#A2845E']
    size = int(w * 0.165); gap = (w - 4 * size) / 5
    k = 0
    for r in range(4):
        for col in range(4):
            x = int(gap + col * (size + gap)); y = int(120 + r * (size + 62))
            if (r, col) == (1, 1):
                ic = MAST[icon_theme] if theme_wall == 'light' else Image.open(f'{K}/02_iOS/AppIcon.appiconset/icon-1024-dark.png').convert('RGBA')
                ph.alpha_composite(masked(ic, size), (x, y))
                d.text((x + size / 2, y + size + 10), 'HUX', font=F(700, 17), fill=fg, anchor='ma')
            else:
                t = Image.new('RGBA', (size, size), hexc(cols[k % 12]) + (255 if theme_wall == 'light' else 200,)); k += 1
                ph.alpha_composite(masked(t, size), (x, y))
                d.rounded_rectangle((x + size * 0.2, y + size + 14, x + size * 0.8, y + size + 24), 5, fill=fg + (90,))
    dock = Image.new('RGBA', (w - 40, size + 40), (255, 255, 255, 90 if theme_wall == 'light' else 40))
    dm = Image.new('L', dock.size, 0); ImageDraw.Draw(dm).rounded_rectangle((0, 0, dock.width - 1, dock.height - 1), 40, fill=255)
    dk = Image.new('RGBA', dock.size, (0, 0, 0, 0)); dk.paste(dock, (0, 0), ImageChops.multiply(dm, dock.split()[3]))
    ph.alpha_composite(dk, (20, h - size - 80))
    for col in range(4):
        x = int(gap + col * (size + gap)); y = h - size - 60
        t = Image.new('RGBA', (size, size), hexc(cols[(k + col) % 12]) + (255,)); ph.alpha_composite(masked(t, size), (x, y))
    frame = Image.new('RGBA', (w + 24, h + 24), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, w + 23, h + 23), int(w * 0.14), fill=(24, 22, 30))
    frame.alpha_composite(ph, (12, 12))
    return frame

def b09():
    c, d = board('Living on the home screen.', 'In context', 9, dark=False)
    p1 = phone('light', w=420); p2 = phone('dark', w=420)
    for i, p in enumerate((p1, p2)):
        x = 160 + i * 560; y = 360
        sh = Image.new('L', (p.width + 160, p.height + 160), 0); ImageDraw.Draw(sh).rounded_rectangle((80, 100, p.width + 80, p.height + 80), 80, fill=255)
        c.alpha_composite(glow_of(sh, 40, 0.3, (50, 15, 80)), (x - 80, y - 80)); c.alpha_composite(p, (x, y))
    # splash
    sw = 420; sh_ = int(sw * 2.05)
    spl = background(sh_, 'aurora').crop(((sh_ - sw) // 2, 0, (sh_ - sw) // 2 + sw, sh_))
    glass_ring(spl, sw / 2, sh_ / 2, sw * 0.28, sw * 0.068, 'aurora'); draw_h(spl, sw / 2, sh_ / 2, sw * 0.275, 'aurora')
    sd = ImageDraw.Draw(spl); sd.text((sw / 2, sh_ - 110), 'Know your charge.', font=F(700, 26), fill=(255, 255, 255), anchor='ma')
    fr = Image.new('RGBA', (sw + 24, sh_ + 24), (0, 0, 0, 0)); ImageDraw.Draw(fr).rounded_rectangle((0, 0, sw + 23, sh_ + 23), int(sw * 0.14), fill=(24, 22, 30))
    m = Image.new('L', (sw, sh_), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh_ - 1), int(sw * 0.13), fill=255)
    fr.paste(spl, (12, 12), m)
    x = 1280; y = 360
    sh = Image.new('L', (fr.width + 160, fr.height + 160), 0); ImageDraw.Draw(sh).rounded_rectangle((80, 100, fr.width + 80, fr.height + 80), 80, fill=255)
    c.alpha_composite(glow_of(sh, 40, 0.3, (50, 15, 80)), (x - 80, y - 80)); c.alpha_composite(fr, (x, y))
    for i, lab in enumerate(['Light home screen', 'Dark home screen', 'Launch screen']):
        d.text(([160, 720, 1280][i] + 222, 1270), lab, font=F(700, 24), fill=INK, anchor='ma')
    para(d, (1860, 420), 'Icon, launch screen and intro share one aurora and one mark — tap, and the ring keeps charging.', F(600, 30), INK, 420, 10)
    c.convert('RGB').save(f'{B}/09_In_Context.png')

# ========== posters ==========
def posters():
    P = f'{K}/05_Social'; os.makedirs(P, exist_ok=True)
    for name, (w, h) in {'portrait_1080x1920': (1080, 1920), 'square_1080': (1080, 1080), 'story_cover_1080x1350': (1080, 1350)}.items():
        S = max(w, h); c = background(S, 'aurora').crop(((S - w) // 2, (S - h) // 2, (S - w) // 2 + w, (S - h) // 2 + h))
        cy = h * (0.42 if h > w else 0.42); r = w * 0.27
        glass_ring(c, w / 2, cy, r, w * 0.066, 'aurora'); draw_h(c, w / 2, cy, w * 0.265, 'aurora')
        d = ImageDraw.Draw(c)
        wm = wordmark(w * 0.07, (255, 255, 255)); c.alpha_composite(wm, (int(w / 2 - wm.width / 2), int(cy + r + w * 0.12)))
        d.text((w / 2, cy + r + w * 0.24), 'Know your charge.', font=F(700, int(w * 0.05)), fill=(255, 255, 255), anchor='ma')
        if h > w:
            d.text((w / 2, h - 140), 'Sleep · Heart · Steps · Food · Cycle', font=F(600, 34), fill=(235, 220, 245), anchor='ma')
        c.convert('RGB').save(f'{P}/HUX_{name}.png')

if __name__ == '__main__':
    for f in (b01, b02, b03, b04, b05, b06, b07, b08, b09, posters):
        f(); print(f.__name__)

def b10():
    c, d = board('Tap the icon. Watch it charge.', 'Motion · intro, 4.4 s', 10, dark=True)
    FRs = '/tmp/claude-0/-home-claude/4cca0ce5-52d4-5448-ab9c-46b40312f1e4/scratchpad/logo/fr_square/'
    steps = [(6, '0.2 s', 'Glass appears'), (24, '0.8 s', 'Charge flows'), (42, '1.4 s', 'Pearl pulses'), (62, '2.1 s', 'Flows into the H'),
             (80, '2.7 s', 'H glides, U rises'), (96, '3.2 s', 'X turns in'), (130, '4.3 s', 'Know your charge.')]
    for i, (f, ts, lab) in enumerate(steps):
        x = 120 + i * 312; y = 400
        im = Image.open(f'{FRs}f{f:03d}.png').convert('RGBA').resize((280, 280), Image.LANCZOS)
        m = Image.new('L', (280, 280), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 279, 279), 28, fill=255)
        t = Image.new('RGBA', (280, 280), (0, 0, 0, 0)); t.paste(im, (0, 0), m); c.alpha_composite(t, (x, y))
        d.text((x, y + 300), ts, font=F(800, 30), fill=(255, 255, 255)); d.text((x, y + 342), lab, font=F(500, 24), fill=(225, 210, 240))
    d.line((120, 790, 2280, 790), fill=(255, 255, 255, 70), width=2)
    rules = [('Easing', 'Cubic in-out for travel, cubic out for arrivals, a soft back-out for letters.'),
             ('Durations', 'Micro 150–250 ms · moves 400–600 ms · the intro once, 4.4 s, skippable with a tap.'),
             ('Physics of light', 'The charge always flows clockwise from 12 o\'clock. The pearl never jumps; it travels.'),
             ('Reduce motion', 'Replace the intro with a 300 ms cross-fade to the final wordmark.')]
    for i, (t_, s) in enumerate(rules):
        x = 120 + (i % 2) * 1100; y = 860 + (i // 2) * 200
        d.text((x, y), t_, font=F(800, 34), fill=(255, 255, 255)); para(d, (x, y + 50), s, F(500, 26), (225, 210, 240), 1000, 6)
    c.convert('RGB').save(f'{B}/10_Motion.png')

b10(); print('b10')
