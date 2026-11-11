#!/usr/bin/env bash
# Idempotent toolchain setup for Aircraft Crash Lab (Linux x86_64, needs root for apt).
# Installs anything missing: Godot 4.4.1 headless, export templates, JDK 17,
# Android SDK (platform-tools, build-tools, platform, NDK), debug keystore, and
# points Godot's editor settings at them. Safe to re-run; present pieces are skipped.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1}"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_BIN="${GODOT_BIN:-/usr/local/bin/godot}"
ANDROID_SDK="${ANDROID_HOME:-$HOME/android-sdk}"
JDK17="${JDK17:-/usr/lib/jvm/java-17-openjdk-amd64}"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
KEYSTORE="$HOME/.android/debug.keystore"
EDITOR_SETTINGS="$HOME/.config/godot/editor_settings-${GODOT_VERSION%.*}.tres"
REL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say() { printf '\n== %s\n' "$*"; }

say "Godot ${GODOT_VERSION}"
if ! { [ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version 2>/dev/null | grep -q "^${GODOT_VERSION}"; }; then
  curl -fsSL -o "$TMP/godot.zip" "$REL/Godot_v${GODOT_TAG}_linux.x86_64.zip"
  unzip -q "$TMP/godot.zip" -d "$TMP"
  install -m 0755 "$TMP/Godot_v${GODOT_TAG}_linux.x86_64" "$GODOT_BIN"
fi
"$GODOT_BIN" --version | tail -1

say "Export templates"
if [ ! -f "$TEMPLATES_DIR/android_debug.apk" ]; then
  curl -fsSL -o "$TMP/templates.tpz" "$REL/Godot_v${GODOT_TAG}_export_templates.tpz"
  unzip -q "$TMP/templates.tpz" -d "$TMP"
  mkdir -p "$TEMPLATES_DIR"
  mv "$TMP"/templates/* "$TEMPLATES_DIR/"
fi
ls "$TEMPLATES_DIR" | grep android

say "JDK 17"
if [ ! -x "$JDK17/bin/java" ]; then
  apt-get update -qq && apt-get install -y -qq openjdk-17-jdk-headless
fi
"$JDK17/bin/java" -version 2>&1 | grep version

say "Android SDK at $ANDROID_SDK"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  curl -fsSL -o "$TMP/cmdline.zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q "$TMP/cmdline.zip" -d "$TMP"
  mkdir -p "$ANDROID_SDK/cmdline-tools"
  mv "$TMP/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
fi
need=()
[ -d "$ANDROID_SDK/platform-tools" ] || need+=("platform-tools")
ls "$ANDROID_SDK/build-tools" >/dev/null 2>&1 || need+=("build-tools;35.0.1")
ls "$ANDROID_SDK/platforms" >/dev/null 2>&1 || need+=("platforms;android-35")
ls "$ANDROID_SDK/ndk" >/dev/null 2>&1 || need+=("ndk;28.1.13356709")
if [ "${#need[@]}" -gt 0 ]; then
  yes | JAVA_HOME="$JDK17" "$SDKMANAGER" --sdk_root="$ANDROID_SDK" --licenses >/dev/null || true
  JAVA_HOME="$JDK17" "$SDKMANAGER" --sdk_root="$ANDROID_SDK" "${need[@]}"
fi
ls "$ANDROID_SDK"

say "Debug keystore"
if [ ! -f "$KEYSTORE" ]; then
  mkdir -p "$(dirname "$KEYSTORE")"
  "$JDK17/bin/keytool" -genkeypair -keyalg RSA -keysize 2048 -validity 10000 \
    -alias androiddebugkey -keystore "$KEYSTORE" -storepass android -keypass android \
    -dname "CN=Android Debug,O=Android,C=US"
fi

say "Godot editor settings -> $EDITOR_SETTINGS"
mkdir -p "$(dirname "$EDITOR_SETTINGS")"
cat > "$EDITOR_SETTINGS" <<CFG
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_SDK"
export/android/java_sdk_path = "$JDK17"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
CFG

say "Toolchain ready"
