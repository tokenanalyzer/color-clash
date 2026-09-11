# Color Clash — Android build

Portrait mobile game, `gl_compatibility` renderer, offline. Target: smooth
60 FPS on a normal Android phone.

## Toolchain (what this build needs)

| Component | Version used | Where |
|---|---|---|
| Godot | 4.4.1-stable (standard, not Mono) | any location; CLI export |
| Godot export templates | 4.4.1.stable | `%APPDATA%\Godot\export_templates\4.4.1.stable\` (`android_debug.apk`, `android_release.apk`, `version.txt`; `android_source.zip` only for custom/Gradle builds) |
| JDK | 17 (Microsoft OpenJDK 17.0.19) | `C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot` |
| Android SDK | platform 35, build-tools 30.0.3 + 36.0.0, cmdline-tools `latest`, platform-tools 37 | `%LOCALAPPDATA%\Android\Sdk` |
| Debug keystore | Godot standard debug keystore | `%APPDATA%\Godot\keystores\debug.keystore` (pass `android`, alias `androiddebugkey`) |

Godot editor settings (`%APPDATA%\Godot\editor_settings-4.4.tres`) point at the
JDK, SDK and debug keystore — the headless CLI export reads them.

The current preset uses **`gradle_build/use_gradle_build = false`** (repacks
the prebuilt template APK). That needs only the export templates + a
keystore + build-tools `apksigner`/`zipalign` — no Gradle/NDK. Switch to
Gradle custom build later only if a native plugin (billing, ads, Firebase)
is added; that will also need `android_source.zip` in the templates dir and
an NDK whose version matches `config.gradle`.

## Build a debug APK

```
godot4 --headless --path game --export-debug "Android" <abs-path>\build\color-clash-debug.apk
```

Output: `build/color-clash-debug.apk` (~55 MB, arm64-v8a + armeabi-v7a,
minSdk 21, targetSdk 34, `com.colorclash.game`, only the `VIBRATE`
permission). `build/` is git-ignored.

Verify:
```
%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\aapt2.exe dump badging build\color-clash-debug.apk
%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --print-certs build\color-clash-debug.apk
```

## Install on a physical phone

1. On the phone: Settings → About phone → tap *Build number* 7× to unlock
   Developer options, then Developer options → enable **USB debugging**.
2. Plug the phone into this PC by USB, accept the "Allow USB debugging"
   prompt on the phone.
3. From the repo root:
   ```
   C:\Android\platform-tools\adb.exe devices          # should list your phone
   C:\Android\platform-tools\adb.exe install -r build\color-clash-debug.apk
   C:\Android\platform-tools\adb.exe shell am start -n com.colorclash.game/com.godot.game.GodotApp
   ```
   `-r` reinstalls over a previous build (the debug signature is stable, so
   updates don't need an uninstall).
4. Or copy the `.apk` to the phone and tap it (allow "install unknown apps"
   for your file manager).

Live logs while playing:
```
C:\Android\platform-tools\adb.exe logcat -s godot GodotApp Godot
```

## Release (AAB) — later

Set up a real upload keystore, then:
```
godot4 --headless --path game --export-release "Android" build\color-clash-release.aab
```
with `gradle_build/export_format = 1` (AAB) in `export_presets.cfg`. This
needs a Play Console app, an upload key, and a version bump each upload.
Do **not** commit the release keystore.
