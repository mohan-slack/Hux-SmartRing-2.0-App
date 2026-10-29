# Branding: app icon, splash, notification icon, store graphics

All images come from **one source**, `images/logo.png` (the HUX wordmark),
via `tool/generate_brand_assets.py`. To change the look, edit the script or
the logo, then run all three commands again:

```bash
python3 tool/generate_brand_assets.py      # masters (needs: pip3 install pillow)
dart run flutter_launcher_icons            # writes iOS AppIcon set + Android mipmaps
dart run flutter_native_splash:create      # writes iOS LaunchScreen + Android splash (incl. 12+)
```

Commit what these commands generate under `ios/Runner/Assets.xcassets`,
`android/app/src/main/res` and the storyboard.

| Asset | File | Notes |
|---|---|---|
| App icon (iOS, Android legacy) | `assets/icon/app_icon.png` | 1024px, no alpha. Dark glow background with a white wordmark |
| Android adaptive icon | `assets/icon/app_icon_{background,foreground}.png` | Wordmark inside the 66dp safe zone |
| Android 13 themed icon | `assets/icon/app_icon_monochrome.png` | Uses the alpha channel only |
| Splash | `assets/splash/splash_logo.png`, `splash_android12.png` | Background `#0A0A0D`, the same as the app, so there's no white flash |
| Notification icon | `android/app/src/main/res/drawable-*/ic_stat_hux.png` | White "H" on transparent, tinted pink by Android. Kept by `res/raw/keep.xml` |
| Play feature graphic | `assets/store/play_feature_graphic.png` | 1024×500 |
| App name | "HUX" | `Info.plist` (`CFBundleName`, `CFBundleDisplayName`) and the Android label |

## Still needed (design / marketing)

- **Store screenshots.** Take them from a real device using demo data.
  - Play: phone screenshots, at least 2 (aim for 4–8), 1080×1920 or more.
  - App Store: 6.9" (1320×2868) and 6.5" (1284×2778).
  - Show Today (HUX Charge), Trends, Coach, Food, Plans and Streaks.
  - Leave out the DEMO banner: use `HUX_SOURCE=health` with real data, or
    crop the banner.
- **Register the logo.** Trademark application No. 6922267 is pending. Use
  "HUX" without the ® mark until it is registered.
