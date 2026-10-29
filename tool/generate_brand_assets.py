#!/usr/bin/env python3
"""Generate HUX icon / splash / notification-icon master images.

Source: images/logo.png (black HUX wordmark on transparent).
Run from the repo root:  python3 tool/generate_brand_assets.py
Then:  dart run flutter_launcher_icons  &&  dart run flutter_native_splash:create
(see docs/release/BRANDING.md). Needs Pillow (pip install pillow).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "images" / "logo.png"

BG = (0x0A, 0x0A, 0x0D)          # HuxColors.bg
GLOW_PURPLE = (0x3A, 0x12, 0x40)  # HuxColors.vividPinkPurpleMid
GLOW_PINK = (0xF5, 0x67, 0xB5)    # HuxColors.accentPink
WHITE = (255, 255, 255)


def white_mark(img: Image.Image) -> Image.Image:
    """Same shape, white, keeping the original alpha (anti-aliasing)."""
    alpha = img.convert("RGBA").split()[3]
    out = Image.new("RGBA", img.size, WHITE + (0,))
    out.putalpha(alpha)
    return out


def trimmed(img: Image.Image) -> Image.Image:
    return img.crop(img.split()[3].getbbox())


def fit_width(mark: Image.Image, width: int) -> Image.Image:
    h = round(mark.height * width / mark.width)
    return mark.resize((width, h), Image.LANCZOS)


def fit_box(mark: Image.Image, box: int) -> Image.Image:
    s = box / max(mark.width, mark.height)
    return mark.resize((max(1, round(mark.width * s)), max(1, round(mark.height * s))), Image.LANCZOS)


def bolder(mark: Image.Image, px: int) -> Image.Image:
    """Thicker strokes so the thin wordmark stays readable at 40-60px icon sizes."""
    alpha = mark.split()[3].filter(ImageFilter.MaxFilter(px | 1))
    out = Image.new("RGBA", mark.size, WHITE + (0,))
    out.putalpha(alpha)
    return out


def centered(canvas: Image.Image, mark: Image.Image, dy: int = 0) -> Image.Image:
    canvas.alpha_composite(mark, ((canvas.width - mark.width) // 2, (canvas.height - mark.height) // 2 + dy))
    return canvas


def glow_background(size: int) -> Image.Image:
    """Near-black with a soft purple/pink glow — the app's HuxBackground look."""
    bg = Image.new("RGBA", (size, size), BG + (255,))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    r = int(size * 0.42)
    c = size // 2
    d.ellipse((c - r, c - r - size // 10, c + r, c + r - size // 10), fill=GLOW_PURPLE + (230,))
    r2 = int(size * 0.22)
    d.ellipse((c - r2, c + size // 6 - r2, c + r2, c + size // 6 + r2), fill=GLOW_PINK + (60,))
    glow = glow.filter(ImageFilter.GaussianBlur(size // 7))
    bg.alpha_composite(glow)
    return bg


def save(img: Image.Image, rel: str, rgb: bool = False) -> None:
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    (img.convert("RGB") if rgb else img).save(p, optimize=True)
    print("wrote", rel, img.size)


def main() -> None:
    logo = trimmed(white_mark(Image.open(SRC)))
    # The "H" glyph alone (left part of the wordmark) for tiny sizes.
    h_glyph = trimmed(logo.crop((0, 0, round(logo.width * 0.312), logo.height)))

    # App icon (iOS + legacy Android): glow background, wordmark 68% wide. No alpha (App Store rule).
    icon = centered(glow_background(1024), bolder(fit_width(logo, 700), 7))
    save(icon, "assets/icon/app_icon.png", rgb=True)

    # Android adaptive icon (108dp canvas, safe zone = central 66dp ≈ 61%).
    save(glow_background(1024), "assets/icon/app_icon_background.png", rgb=True)
    fg = centered(Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)), bolder(fit_width(logo, 560), 5))
    save(fg, "assets/icon/app_icon_foreground.png")
    save(fg, "assets/icon/app_icon_monochrome.png")  # Android 13 themed icons use alpha only

    # In-app wordmark for the light UI (welcome screen, headers): the
    # original black logo, trimmed, as a transparent PNG.
    dark = trimmed(Image.open(SRC).convert("RGBA"))
    save(fit_width(dark, 900), "assets/images/brand/hux-wordmark-dark.png")

    # Splash (pre-Android 12 + iOS): wordmark only, transparent.
    # Light splash (matches the light app): dark wordmark on #F6F4FA.
    save(trimmed(fit_width(dark, 768)), "assets/splash/splash_logo.png")
    # Android 12+ splash icon: 1152px canvas, content inside the central 768px circle.
    s12 = centered(Image.new("RGBA", (1152, 1152), (0, 0, 0, 0)), fit_width(dark, 600))
    save(s12, "assets/splash/splash_android12.png")

    # Google Play feature graphic (1024x500, no alpha). Add a tagline in a
    # design tool if wanted; keep text out of the outer edges (Play crops).
    fgfx = glow_background(1024).resize((1024, 1024)).crop((0, 262, 1024, 762))
    save(centered(fgfx, bolder(fit_width(logo, 520), 5)), "assets/store/play_feature_graphic.png", rgb=True)

    # Notification small icon: white on transparent, 24dp with 2dp padding.
    for folder, px in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
        canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        mark = fit_box(h_glyph, round(px * 20 / 24))
        save(centered(canvas, mark), f"android/app/src/main/res/drawable-{folder}/ic_stat_hux.png")


if __name__ == "__main__":
    main()
