#!/usr/bin/env bash
# Build the prairie_tizen TPK.
#
# Requires flutter-tizen + Tizen Studio on PATH (not available on stock
# ubuntu-latest GitHub runners — see .github/workflows/release-packages.yml).
#
# A single TPK covers the whole supported range (tizen-manifest.xml's
# checked-in api-version="6.5" spans Tizen 6.5-9.0+) — there is no per-Tizen-
# version variant to build. That split only ever applied to
# video_player_avplay's precompiled, api-version-specific native libraries;
# this app uses video_player_videohole, which compiles from source with no
# such split.
#
# Usage:
#   ./build-tizen.sh
#   ./build-tizen.sh --package-version 1.0.1
#   ./build-tizen.sh --security-profile Prairie_Server
#   ./build-tizen.sh --obfuscate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT}/packages/prairie_tizen"
OUT_DIR="${ROOT}/artifacts"
PACKAGE_VERSION=""
RELEASE=1
OBFUSCATE=0
DEVICE_PROFILE="tv"
SECURITY_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-version) PACKAGE_VERSION="${2:?}"; shift 2 ;;
    --debug) RELEASE=0; shift ;;
    --release) RELEASE=1; shift ;;
    --obfuscate) OBFUSCATE=1; shift ;;
    --device-profile) DEVICE_PROFILE="${2:?}"; shift 2 ;;
    --security-profile) SECURITY_PROFILE="${2:?}"; shift 2 ;;
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unexpected argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v flutter-tizen >/dev/null 2>&1; then
  echo "flutter-tizen not found on PATH. Install from https://github.com/flutter-tizen/flutter-tizen" >&2
  exit 127
fi

if [[ -n "$PACKAGE_VERSION" ]]; then
  "${SCRIPT_DIR}/stamp-tizen-package-version.sh" "$PACKAGE_VERSION"
fi

mkdir -p "$OUT_DIR"
cd "$APP_DIR"

BUILD_ARGS=(tpk --device-profile "$DEVICE_PROFILE")
if [[ "$RELEASE" -eq 1 ]]; then
  BUILD_ARGS+=(--release)
fi
if [[ -n "$SECURITY_PROFILE" ]]; then
  BUILD_ARGS+=(--security-profile "$SECURITY_PROFILE")
fi
# Dart obfuscation shrinks AOT size; keep --split-debug-info for crash symbolication.
if [[ "$OBFUSCATE" -eq 1 ]]; then
  BUILD_ARGS+=(--obfuscate --split-debug-info="${OUT_DIR}/symbols-tizen")
fi

echo "+ flutter-tizen build ${BUILD_ARGS[*]}"
flutter-tizen build "${BUILD_ARGS[@]}"

TPK="$(find build/tizen -name '*.tpk' 2>/dev/null | head -1 || true)"
if [[ -z "$TPK" ]]; then
  echo "No .tpk produced under build/tizen" >&2
  exit 1
fi

DEST="${OUT_DIR}/Prairie-tizen.tpk"
cp -f "$TPK" "$DEST"
echo "Wrote $DEST"
ls -lh "$DEST"
