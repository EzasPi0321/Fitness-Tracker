# FitTrack

A calorie and macro tracker built with Flutter. One codebase builds the **Android**, **iPhone**, **Windows** and **web** apps.

- **Today:** the calorie ring and protein, carbs and fat gauges, meals for the day, and a three-week day strip.
- **Food log:** an hourly timeline with a **+** on every hour. Foods appear at the time you ate them, macro bars sit under the day strip, and a search bar covers your foods, past meals and Open Food Facts.
- **Barcode scanning (phone):** the app checks My Foods first, then Open Food Facts. Every result is tagged **Verified** or **Unverified**, with the reason.
- **Nutrition-label photos:** if a barcode isn't in the database, photograph the label. The AI reads the numbers, you check them, and the food is saved under that barcode for next time.
- **Meal photos:** Gemini or OpenAI estimates each item on the plate, and you can edit every item before logging.
- **Progress:** calorie bars against your goal, average macros, and a weight trend.
- **Health sync (phone):** Apple Health on iPhone, Health Connect on Android.
- **Settings:** dark (black) or light theme, kcal or kJ, metric or imperial. Targets come from the Mifflin–St Jeor formula.

## Install

Every push to `main` publishes a GitHub Release (see `.github/workflows/build.yml`):

| File | Platform | How to install |
|---|---|---|
| `FitTrack.apk` | Android | Open it on the phone and allow "Install unknown apps". Updates install over the old version. |
| `FitTrack.ipa` | iPhone | Install with SideStore or AltStore, which re-sign it with your Apple ID. |
| `FitTrack-Windows.zip` | Windows | Unzip it and run `FitTrack.exe`. |
| `FitTrack-Web.zip` | Browser | The web build. Camera features are phone-only. |

**SideStore source** (add it once under Sources → **+** and updates appear by themselves). This only works while the repository is public, because SideStore can't download from a private repo:

```
https://github.com/EzasPi0321/Fitness-Tracker/releases/latest/download/source.json
```

**Android signing.** Add three repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS`. With them, every APK is signed with the same key, which Android requires before it will install an update over the old version.

## Develop

Code lives in `flutter/`:

```
lib/
  design/     OKLCH palette, tokens, motion (squash & stretch, blur icon swaps, faded edges)
  models/     nutrients, foods, profile and Mifflin–St Jeor calculator, units (kcal/kJ)
  data/       app state, storage (file on device, browser storage on web), sample data
  services/   Open Food Facts, AI vision (meals and labels), health, API-key store
  screens/    today, log (food log, search, scan, label, manual, photo), progress, settings, onboarding
  widgets/    rings, cards, inputs, verified/unverified tags
test/         logic and widget tests
```

```bash
cd flutter && flutter pub get && flutter test
```

```bash
flutter run -d windows
```

Flutter 3.47.9. Windows builds need Visual Studio with the "Desktop development with C++" workload.

The earlier SwiftUI version is in git history (commit `7db69ef`).
