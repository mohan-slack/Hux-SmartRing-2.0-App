import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
SRC = sys.argv[1]; OUT = sys.argv[2]
UP = 4
PINK_HI=(0xF5,0x67,0xB5); PINK=(0xC9,0x3B,0x86); PURPLE=(0x6B,0x2E,0x9A); BG=(0x0A,0x0A,0x0D); GLOW_PURPLE=(0x3A,0x12,0x40); LIGHT=(0xF6,0xF4,0xFA)

def crisp_alpha():
    a = Image.open(SRC).convert('RGBA').split()[3]
    a = a.resize((a.width*UP, a.height*UP), Image.LANCZOS).filter(ImageFilter.GaussianBlur(UP*0.7))
    return a.point(lambda v: max(0, min(255, int((v-128)*3+128))))

A = crisp_alpha()
A = A.filter(ImageFilter.MaxFilter(5))  # a touch bolder: reads better on small icons
Y0, Y1 = 14*UP, 355*UP
RANGES = {'H': (20, 407), 'U': (420, 844), 'X': (847, 1269)}
glyph = {k: A.crop((x0*UP, Y0, x1*UP, Y1)) for k, (x0, x1) in RANGES.items()}
offs = {k: (x0-20)*UP for k, (x0, _) in RANGES.items()}  # x offset in wordmark (UP px)
WM_W = (1269-20)*UP; WM_H = Y1-Y0

def lerp(a,b,t): return a+(b-a)*t
def mix(c1,c2,t): return tuple(int(lerp(a,b,t)) for a,b in zip(c1,c2))

def gradient_bg(n):
    """Diagonal pink -> purple with a soft top-left highlight."""
    img = Image.new('RGB', (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = (x*0.45 + y*0.55)/n
            c = mix(PINK_HI, PINK, t/0.45) if t < 0.45 else mix(PINK, PURPLE, (t-0.45)/0.55)
            px[x,y] = c
    hl = Image.new('L', (n, n), 0); ImageDraw.Draw(hl).ellipse((-n*0.25, -n*0.35, n*0.75, n*0.55), fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(n//6))
    img = Image.composite(Image.new('RGB',(n,n),(255,255,255)), img, hl)
    sh = Image.new('L', (n, n), 0); ImageDraw.Draw(sh).ellipse((n*0.35, n*0.55, n*1.4, n*1.5), fill=60)
    sh = sh.filter(ImageFilter.GaussianBlur(n//6))
    return Image.composite(Image.new('RGB',(n,n),(40,10,60)), img, sh).convert('RGBA')

def dark_bg(n):
    bg = Image.new('RGBA', (n, n), BG+(255,)); g = Image.new('RGBA', (n, n), (0,0,0,0)); d = ImageDraw.Draw(g)
    r=int(n*0.42); c=n//2
    d.ellipse((c-r, c-r-n//10, c+r, c+r-n//10), fill=GLOW_PURPLE+(230,))
    r2=int(n*0.22); d.ellipse((c-r2, c+n//6-r2, c+r2, c+n//6+r2), fill=PINK_HI+(60,))
    bg.alpha_composite(g.filter(ImageFilter.GaussianBlur(n//7))); return bg

def light_bg(n): return Image.new('RGBA', (n, n), LIGHT+(255,))

def paint(alpha, color):
    if isinstance(color, tuple):
        out = Image.new('RGBA', alpha.size, color+(0,)); out.putalpha(alpha); return out
    out = color.resize(alpha.size).convert('RGBA'); out.putalpha(alpha); return out

def grad_fill(w, h):
    g = Image.new('RGB', (w, h)); d = ImageDraw.Draw(g)
    for y in range(h):
        d.line([(0,y),(w,y)], fill=mix(PINK, PURPLE, y/h))
    return g

def place(canvas, alpha, color, cx, cy, height, glow=True, opacity=1.0, rot=0.0, glow_amt=0.45):
    s = height / alpha.height
    a = alpha.resize((max(1,round(alpha.width*s)), max(1,round(alpha.height*s))), Image.LANCZOS)
    pad = max(8, a.height//4)
    p = Image.new('L', (a.width+2*pad, a.height+2*pad), 0); p.paste(a, (pad, pad)); a = p
    if rot: a = a.rotate(rot, Image.BICUBIC, expand=True)
    if opacity < 1: a = a.point(lambda v: int(v*opacity))
    x, y = round(cx-a.width/2), round(cy-a.height/2)
    if glow:
        gl = paint(a.filter(ImageFilter.GaussianBlur(max(2, height//16))).point(lambda v: int(v*glow_amt)), (255,255,255))
        canvas.alpha_composite(gl, (x, y))
    canvas.alpha_composite(paint(a, color if isinstance(color, tuple) else _padfill(color, a.size, pad)), (x, y))
    return canvas

def _padfill(img, size, pad):
    return img.resize((size[0], size[1]))

def icon(bg, n=1024, color=(255,255,255), glow=True, h_frac=0.50):
    c = bg(n) if bg else Image.new('RGBA', (n,n), (0,0,0,0))
    H = glyph['H']; height = n*h_frac*H.height/H.width  # width = h_frac of canvas
    col = grad_fill(H.width, H.height) if color == 'grad' else color
    return place(c, H, col, n/2, n/2, height, glow=glow)
