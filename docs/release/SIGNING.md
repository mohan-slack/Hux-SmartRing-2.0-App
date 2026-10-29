# Release signing — Android + iOS

| | Android | iOS |
|---|---|---|
| ID (permanent once published) | `in.co.hux.hux_app` | `in.co.hux.huxApp` |
| Version | `pubspec.yaml` → `version: 1.0.0+1` (name+build) | same |
| You keep | **Upload key** (`hux-upload.jks`) — Google holds the app-signing key | Nothing — Xcode/Apple manage certificates |

Bump the **build number** (`+1` → `+2`) for every upload to either store.

## 0. One-time: Flutter on the Mac

```bash
brew install --cask flutter            # or follow docs.flutter.dev/get-started
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
brew install cocoapods
flutter doctor                          # fix anything red (Android Studio for the Android SDK)
cd ~/Personal/Hux-SmartRing-2.0-App
flutter pub get && flutter analyze && flutter test
```

## 1. Android — upload key (once, then guard it forever)

```bash
mkdir -p ~/Personal/hux-keys && cd ~/Personal/hux-keys
keytool -genkeypair -v -keystore hux-upload.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload \
  -dname "CN=HUX, O=Viveon Gizit Private Limited, L=Bengaluru, ST=Karnataka, C=IN"
```

(`keytool` missing? Use Android Studio's:
`"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" ...`)

Then:

```bash
cd ~/Personal/Hux-SmartRing-2.0-App
cp android/key.properties.example android/key.properties
# fill storePassword + keyPassword (same password is fine)
```

The key is **outside the repo** (`~/Personal/hux-keys/`). Back up the `.jks` and
both passwords to a password manager **and** an offline copy. If lost, you need
Google support to reset the upload key (days of delay).

Build and upload:

```bash
flutter build appbundle --release --dart-define-from-file=.env
# → build/app/outputs/bundle/release/app-release.aab
```

Play Console → Create app → **Testing → Internal testing → Create release** →
upload the `.aab` → accept **Play App Signing** (Google manages the signing key).
Start with Internal testing, then Closed testing (new personal developer
accounts need 12+ testers for 14 days before Production; organisation
accounts don't — register the Play account as the **company**, Viveon Gizit).

Also in Play Console → Setup → **App signing**: copy the **SHA-1** of the
app-signing key and of the upload key into Google Cloud → the Android OAuth
client, or Google sign-in fails on store builds.

## 2. iOS — signing in Xcode

Needs the **Apple Developer Program** (enrol as an organisation with the
company's D-U-N-S number; yearly fee).

1. developer.apple.com → Identifiers → **+ App ID** `in.co.hux.huxApp`,
   capabilities: **HealthKit**, **Sign in with Apple**.
2. App Store Connect → **My Apps → +** → bundle ID `in.co.hux.huxApp`,
   name "HUX", SKU `hux-ios-1`.
3. `open ios/Runner.xcworkspace` (the workspace, not .xcodeproj) →
   Runner target → **Signing & Capabilities**:
   - Automatically manage signing: **on**; Team: your company team.
   - Check **HealthKit** and **Sign in with Apple** appear (from
     `Runner.entitlements`). Add them with "+ Capability" if not.
4. Run once on your iPhone (connect via cable → select it → ▶) to confirm
   HealthKit permission and sign-in work.
5. Build and upload:

```bash
flutter build ipa --release --dart-define-from-file=.env
open build/ios/archive/Runner.xcarchive    # Xcode Organizer → Distribute App → App Store Connect
```

(or drag `build/ios/ipa/*.ipa` into the **Transporter** app). Then
TestFlight → add yourself as an internal tester.

## 3. Before every store build

- [ ] `version:` build number bumped
- [ ] `flutter analyze` clean, `flutter test` green
- [ ] Built with `--dart-define-from-file=.env` (else "HUX isn't configured")
- [ ] Release default data source = health (automatic in release)
- [ ] Supabase functions deployed with current secrets
