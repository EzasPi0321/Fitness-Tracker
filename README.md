# FitTrack — iOS Fitness & Calorie Tracker

Native SwiftUI + SwiftData app for iOS 17+. Track daily nutrition, scan food barcodes,
estimate meals from a photo with a multimodal AI model, and sync with Apple Health.

## Project structure

```
FitTrack/
├── project.yml                     XcodeGen spec (generates FitTrack.xcodeproj)
├── FitTrack/
│   ├── Info.plist                  Privacy usage strings (Camera, Photos, Health read/write)
│   ├── FitTrack.entitlements       HealthKit (+ optional iCloud/CloudKit notes)
│   ├── App/
│   │   ├── FitTrackApp.swift       @main, ModelContainer, HealthKitManager in environment
│   │   ├── RootView.swift          Onboarding gate + TabView (Today / Progress / Settings)
│   │   └── PreviewData.swift       In-memory sample data for #Preview
│   ├── Models/
│   │   ├── FoodEntry.swift         @Model logged food (portion totals, HealthKit link)
│   │   ├── CustomFood.swift        @Model "My Foods" + offline barcode cache
│   │   ├── UserProfile.swift       @Model profile/targets, @Model WeightEntry
│   │   ├── NutritionCalculator.swift  Mifflin–St Jeor BMR, TDEE, macro split
│   │   ├── Nutrients.swift         Value type + Macro enum
│   │   ├── MealType.swift          Breakfast/Lunch/Dinner/Snacks, EntrySource
│   │   └── Persistence.swift       Schema, ModelContainer factory, settings keys
│   ├── Services/
│   │   ├── OpenFoodFactsService.swift  async/await + lossy Codable OFF client
│   │   ├── FoodProduct.swift       Domain model for a resolved barcode
│   │   ├── AIVisionService.swift   Gemini / OpenAI vision with JSON-schema output
│   │   ├── HealthKitManager.swift  @Observable HKHealthStore wrapper
│   │   ├── FoodLogger.swift        Keeps SwiftData + Apple Health in sync
│   │   └── KeychainStore.swift     API-key storage
│   ├── Scanner/BarcodeScannerView.swift   DataScannerViewController wrapper + haptics
│   ├── Camera/CameraPicker.swift   UIImagePickerController camera wrapper
│   ├── Utilities/                  Image downscale/JPEG, Date & String helpers
│   └── Views/
│       ├── Dashboard/              Rings + Gauges, meal DisclosureGroups, FAB, edit sheet
│       ├── Scan/                   Scan flow, product sheet with portion Stepper/Picker
│       ├── Manual/                 Manual entry form + My Foods picker
│       ├── Photo/                  PhotosPicker/camera, editable AI review
│       ├── Progress/               Swift Charts: intake, macros, body weight; log weight
│       ├── Onboarding/             Health connect → body → activity → goal → plan
│       ├── Settings/               Targets, Health, AI provider/key, units, data
│       └── Components/             ProgressRing, nutrition rows, chart card, theme
└── FitTrackTests/                  XCTest: BMR/TDEE, OFF decoding, AI JSON parsing, rescaling
```

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), then in this folder:
   ```sh
   xcodegen generate
   open FitTrack.xcodeproj
   ```
   (Or create an iOS App project in Xcode and drag the `FitTrack/` folder in.)
2. Select your Team under *Signing & Capabilities* and change `PRODUCT_BUNDLE_IDENTIFIER`
   from `com.example.fittrack`.
3. **Capabilities**
   - **HealthKit** — required (already in `FitTrack.entitlements`). Clinical records and
     background delivery are not needed.
   - **iCloud → CloudKit** — optional. Add a container, enable *Background Modes → Remote
     notifications*, then set `AppConfig.cloudKitSyncEnabled = true` in `Persistence.swift`.
     All models already satisfy CloudKit's rules (defaults on every property, no unique constraints).
4. Run on a **physical iPhone**: the Simulator has no camera, and `DataScannerViewController`
   reports `isSupported == false` there. In the Simulator use *Scan → ⋯ → Type Barcode*
   (try `3017620422003`) and *Snap Meal → Choose from Library*.
5. For AI photo estimates, open **Settings → AI Photo Estimates**, pick Gemini or OpenAI and
   paste an API key (saved to the Keychain).

## Design notes

- **Data flow.** Each `FoodEntry` stores totals for the portion eaten, so daily sums are a
  reduction and edits rescale linearly. `FoodLogger` is the only writer, so SwiftData and
  Apple Health stay in step: each entry is saved as an `HKCorrelation(.food)` of energy,
  protein, carbs and fat samples, and its UUID is kept so the entry can be updated or deleted.
- **Barcode lookup order.** *My Foods* (local, works offline) first, then Open Food Facts.
  An unknown barcode opens the manual form, and with "Save to My Foods" on, the next scan of
  that barcode is found locally.
- **Open Food Facts data quality.** Numbers can arrive as strings (`"6,3"`), and some products
  only list kJ or only per-serving values. Decoding reads each field on its own, so one bad
  field doesn't fail the whole product, and missing values are worked out from the others.
- **AI output.** Both providers are given a JSON schema (Gemini `responseSchema`, OpenAI
  `json_schema` with `strict: true`). Parsing still strips stray code fences and drops
  invalid items. Images are resized to 1024 px and JPEG-compressed to about 900 KB before
  base64 encoding.
- **API keys.** Shipping a provider key inside an app binary is not safe. The app stores a
  key the user enters in the Keychain. For App Store builds, set
  `AIVisionService.endpointOverride` to your own backend proxy, which keeps the key on the server.
- **HealthKit privacy.** Read permission status can't be queried, so reads fail softly to
  zero or empty. Write status is checked through `authorizationStatus(for:)`.
- **HIG.** Uses system colours and materials, so light and dark mode work automatically.
  Includes Dynamic Type, VoiceOver labels and values on the rings and gauges, haptics on scan
  and log, `ContentUnavailableView` for empty and denied states, and destructive actions
  behind confirmation dialogs.
