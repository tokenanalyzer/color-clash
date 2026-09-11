#!/usr/bin/env bash
# Re-apply the War of Love native AdMob integration onto a freshly generated
# Godot Android build template.
#
# The template (game/android/) is NOT vendored — it is regenerated with
#   godot4 --headless --path game --install-android-build-template
# which OVERWRITES AndroidManifest.xml / build.gradle and does not know about
# our plugin source. Run this script once after every such regeneration.
#
# Idempotent: it checks for markers before touching anything.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$(cd "$HERE/../../android/build" && pwd)"

echo "template: $BUILD"

# 1. plugin source
mkdir -p "$BUILD/src/com/colorclash/admob"
cp "$HERE/src/com/colorclash/admob/ColorClashAdMob.kt" \
   "$BUILD/src/com/colorclash/admob/ColorClashAdMob.kt"
echo "  + src/com/colorclash/admob/ColorClashAdMob.kt"

# 2. AndroidManifest.xml meta-data (App ID + plugin singleton)
if grep -q "org.godotengine.plugin.v1.ColorClashAdMob" "$BUILD/AndroidManifest.xml"; then
    echo "  = AndroidManifest.xml already patched"
else
    ( cd "$BUILD" && patch -p0 < "$HERE/patches/AndroidManifest.xml.patch" )
    echo "  + AndroidManifest.xml meta-data"
fi

# 3. build.gradle: play-services-ads dependency + admob_app_id resValue
if grep -q "play-services-ads" "$BUILD/build.gradle"; then
    echo "  = build.gradle already patched"
else
    ( cd "$BUILD" && patch -p0 < "$HERE/patches/build.gradle.patch" )
    echo "  + build.gradle dependency + resValue"
fi

# 4. build.gradle: user-messaging-platform (UMP consent SDK) dependency —
#    separate idempotent patch so re-running this script never touches the
#    already-applied AdMob patch above.
if grep -q "user-messaging-platform" "$BUILD/build.gradle"; then
    echo "  = build.gradle already has the UMP dependency"
else
    ( cd "$BUILD" && patch -p0 < "$HERE/patches/build_gradle_ump.patch" )
    echo "  + build.gradle UMP (consent) dependency"
fi

echo "done. AdMob App ID: \$ADMOB_APP_ID or Google's test id by default."
