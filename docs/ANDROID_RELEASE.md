# War of Love — Android release build (AAB for Google Play)

Debug builds still use **preset "Android"** (prebuilt template, APK, target
SDK 34, Godot debug key) — see `ANDROID.md`. This doc covers the **release
AAB** only. Nothing here changes the debug flow.

## What is configured (committed)

`game/export_presets.cfg` — added **`[preset.1]` "Android Release"**, debug
preset untouched:

| field | value |
|---|---|
| `gradle_build/use_gradle_build` | `true` (required for target SDK 35 + AAB) |
| `gradle_build/export_format` | `1` (Android App Bundle) |
| `gradle_build/target_sdk` | `"35"` (Google Play requirement for new apps) |
| `gradle_build/min_sdk` | `""` → template default **21** (unchanged device support) |
| `export_path` | `../build/war-of-love-release.aab` |
| `version/code` / `version/name` | `1` / `1.0.0` |
| `package/unique_name` | `com.colorclash.game` (unchanged) |
| architectures | `arm64-v8a` + `armeabi-v7a` |
| permissions | `VIBRATE` only — `INTERNET`/`ACCESS_NETWORK_STATE`/`WAKE_LOCK` all false |
| launcher icons | same 4 as debug (`icon_512` / `icon_fg` / `icon_bg` / `icon_mono`) |

## What is NOT committed (local, regenerable)

`game/android/` — the custom Gradle build template (~580 MB of binaries),
`.gitignore`d. Recreate it on any machine:

```
godot4 --headless --path game --install-android-build-template --export-release "Android Release"
```
(it will stop at the keystore error — that is expected, the template is
installed by then), then re-apply this patch to
`game/android/build/config.gradle`:

| line | from | to | why |
|---|---|---|---|
| `compileSdk` | `34` | `35` | AGP needs compileSdk ≥ targetSdk |
| `targetSdk` | `34` | `35` | Google Play requirement |
| `buildTools` | `'34.0.0'` | `'36.0.0'` | 34.0.0 not installed; 36.0.0 is |
| `ndkVersion` | `'23.2.8568313'` | `'28.2.13676358'` | 23.x not installed; 28.x is |

## SDK components (installed on the build machine)

- Android platform **android-35** ✅ (also 34, 36)
- Build-tools **36.0.0** ✅ (also 30.0.3). *Recommended: also install
  `35.0.0` to silence Godot's "build tools that matches Target SDK" notice.*
- NDK **28.2.13676358** ✅
- JDK **17** ✅ (`C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot`)
- Gradle cache warm at `~/.gradle` (~3.5 GB)

## Release signing (NOT configured — you must create the upload key)

No War of Love upload/release keystore exists. Create one (keep it forever,
back it up, never commit it):

```
keytool -genkeypair -v ^
  -keystore "%USERPROFILE%\keystores\war-of-love-upload.jks" ^
  -alias war-of-love-upload -keyalg RSA -keysize 2048 -validity 10000 ^
  -storetype JKS ^
  -dname "CN=Rectangle Studio, OU=War of Love, O=Rectangle Studio, C=IN"
```

Then point Godot at it **via environment variables** (never in the repo):

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH     = %USERPROFILE%\keystores\war-of-love-upload.jks
GODOT_ANDROID_KEYSTORE_RELEASE_USER     = war-of-love-upload
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = <your password>
```

(or Editor Settings → Export → Android → Release Keystore/User/Password —
that file lives outside the repo). Enrol in **Google Play App Signing** so
this is only the *upload* key.

## Build

```
godot4 --headless --path game --export-release "Android Release" build\war-of-love-release.aab
```

First run resolves Gradle/AGP (mostly cached) — needs **~1.5 GB free disk**
for the build output. Verify the result:

```
%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\aapt2.exe dump badging build\war-of-love-release.aab   # (or use bundletool)
```
Expect: `package: com.colorclash.game`, `versionCode 1` / `versionName 1.0.0`,
`targetSdkVersion 35`, `native-code 'arm64-v8a' 'armeabi-v7a'`,
`uses-permission VIBRATE` only.
