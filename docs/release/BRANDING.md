# Branding — "Glass Charge" (brand kit v1.0)

**Idea:** Know your charge. A liquid-glass ring, charge light flowing clockwise
from 12 o'clock (pink → indigo), ending in a pearl ("now") level with the H's
floating crossbar. Full guidelines: the HUX Brand Kit page and `HUX_Brand_Kit.zip`
(boards, all icon themes, social, motion, generator scripts in `07_Source`).

## Where the files live (committed, not generated)

| Asset | Location | Notes |
|---|---|---|
| iOS app icon | `ios/Runner/Assets.xcassets/AppIcon.appiconset` | Xcode single-size: light (no alpha), dark, tinted (grayscale) |
| Android launcher | `android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png` | Legacy + round |
| Android adaptive | `mipmap-*/ic_launcher_{foreground,background,monochrome}.png` + `mipmap-anydpi-v26/*.xml` | Mark inside the 66 dp safe zone; monochrome for themed icons |
| Notification icon | `drawable-*/ic_stat_hux.png` | White mono mark, tinted HUX Pink. Kept by `res/raw/keep.xml` |
| Icon master | `assets/icon/app_icon.png` | Aurora 1024 (reference / store) |
| Launch screen | `assets/splash/splash_bg.png`, `splash_mark.png`, `splash_android12.png` | Run `dart run flutter_native_splash:create` after changing |
| Intro letters | `assets/images/brand/intro_u.png`, `intro_x.png` | Used by `lib/widgets/hux_intro.dart` |

**Do not run `flutter_launcher_icons`** — it would overwrite the iOS dark/tinted
icons. It has been removed from `pubspec.yaml`.

## Intro
`lib/widgets/hux_intro.dart` continues the launch screen: pearl pulses, ring
releases, pearl flows into the crossbar, H glides left, U rises, X turns in,
"Know your charge." Full (~3 s) on first launch, then a quick fade. Tap skips.
"Reduce motion" always gets the quick fade. Ring radius 66 pt must match
`splash_mark.png` (800 px, ring radius 0.33) — change both together.

## Colours
HUX Pink `#C93B86` · Vivid Pink `#F567B5` · Plum `#6B2E9A` · Indigo `#4453D6` ·
Cherry `#E8573B` · Midnight `#1A0B30` · Ink `#1B1925` · Mist `#F6F4FA`.
Charge gradient `#FF8FCB → #F567B5 → #C93B86 → #8B3FD0 → #5B6CF0`.

## Still to do
- Alternate app icons (Midnight, Daylight, Blush, Calm, Spectrum) — files are in
  the kit (`02_iOS/alternate_icons`, `03_Android/alternate_icons`); wiring needs
  Info.plist `CFBundleAlternateIcons` + Android `activity-alias`.
- Store screenshots from a real device (no DEMO banner).
- Trademark application No. 6922267 pending — use "HUX" without ®.
