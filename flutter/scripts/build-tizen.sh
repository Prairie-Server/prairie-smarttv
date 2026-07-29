#!/usr/bin/env bash
# Build a prairie_tizen TPK for one video_player_avplay api-version variant.
#
# Requires flutter-tizen + Tizen Studio on PATH (not available on stock
# ubuntu-latest GitHub runners — see .github/workflows/release-packages.yml).
#
# Usage:
#   ./build-tizen.sh 6.0
#   ./build-tizen.sh 6.5 --package-version 1.0.1
#   ./build-tizen.sh 10.0 --release --obfuscate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT}/packages/prairie_tizen"
OUT_DIR="${ROOT}/artifacts"
API_VERSION=""
PACKAGE_VERSION=""
RELEASE=1
OBFUSCATE=0
DEVICE_PROFILE="tv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-version) PACKAGE_VERSION="${2:?}"; shift 2 ;;
    --debug) RELEASE=0; shift ;;
    --release) RELEASE=1; shift ;;
    --obfuscate) OBFUSCATE=1; shift ;;
    --device-profile) DEVICE_PROFILE="${2:?}"; shift 2 ;;
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *)
      if [[ -z "$API_VERSION" ]]; then API_VERSION="$1"; shift
      else echo "Unexpected argument: $1" >&2; exit 1; fi
      ;;
  esac
done

if [[ -z "$API_VERSION" ]]; then
  echo "Usage: $0 <6.0|6.5|10.0> [options]" >&2
  exit 1
fi

if ! command -v flutter-tizen >/dev/null 2>&1; then
  echo "flutter-tizen not found on PATH. Install from https://github.com/flutter-tizen/flutter-tizen" >&2
  exit 127
fi

STAMP_ARGS=("$API_VERSION")
if [[ -n "$PACKAGE_VERSION" ]]; then
  STAMP_ARGS+=(--package-version "$PACKAGE_VERSION")
fi
"${SCRIPT_DIR}/stamp-tizen-api-version.sh" "${STAMP_ARGS[@]}"

mkdir -p "$OUT_DIR"
cd "$APP_DIR"

BUILD_ARGS=(tpk --device-profile "$DEVICE_PROFILE")
if [[ "$RELEASE" -eq 1 ]]; then
  BUILD_ARGS+=(--release)
fi
# Dart obfuscation shrinks AOT size; keep --split-debug-info for crash symbolication.
if [[ "$OBFUSCATE" -eq 1 ]]; then
  BUILD_ARGS+=(--obfuscate --split-debug-info="${OUT_DIR}/symbols-tizen-${API_VERSION}")
fi

echo "+ flutter-tizen build ${BUILD_ARGS[*]}"
flutter-tizen build "${BUILD_ARGS[@]}"

TPK="$(find build/tizen -name '*.tpk' 2>/dev/null | head -1 || true)"
if [[ -z "$TPK" ]]; then
  echo "No .tpk produced under build/tizen" >&2
  exit 1
fi

DEST="${OUT_DIR}/Prairie-tizen-api${API_VERSION}.tpk"
cp -f "$TPK" "$DEST"
echo "Wrote $DEST"
ls -lh "$DEST"
