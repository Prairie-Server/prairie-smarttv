#!/usr/bin/env bash
# Build a prairie_webos .ipk via flutter-webos + ares-package.
#
# Requires flutter-webos + webOS NDK + @webos-tools/cli on a Linux host
# (WSL2 Ubuntu on Windows). Stock ubuntu-latest runners do not ship these —
# see .github/workflows/release-packages.yml.
#
# Usage:
#   ./build-webos.sh
#   ./build-webos.sh --obfuscate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT}/packages/prairie_webos"
OUT_DIR="${ROOT}/artifacts"
OBFUSCATE=0
RELEASE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) RELEASE=0; shift ;;
    --release) RELEASE=1; shift ;;
    --obfuscate) OBFUSCATE=1; shift ;;
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unexpected argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v flutter-webos >/dev/null 2>&1; then
  echo "flutter-webos not found on PATH. Install from https://github.com/lg-flutter-webos/flutter-webos" >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
cd "$APP_DIR"

BUILD_ARGS=()
if [[ "$RELEASE" -eq 1 ]]; then
  BUILD_ARGS+=(--release)
fi
if [[ "$OBFUSCATE" -eq 1 ]]; then
  BUILD_ARGS+=(--obfuscate --split-debug-info="${OUT_DIR}/symbols-webos")
fi

echo "+ flutter-webos build ${BUILD_ARGS[*]}"
flutter-webos build "${BUILD_ARGS[@]}"

# flutter-webos typically emits under build/webos; locate any .ipk produced.
IPK="$(find build -name '*.ipk' 2>/dev/null | head -1 || true)"
if [[ -z "$IPK" ]]; then
  echo "No .ipk found under build/. If flutter-webos only produced a bundle," >&2
  echo "package it with: ares-package <bundle-dir> -o ${OUT_DIR}" >&2
  # Still copy any release bundle for inspection.
  if [[ -d build ]]; then
    echo "build/ contents:" >&2
    find build -maxdepth 3 -type f | head -40 >&2 || true
  fi
  exit 1
fi

DEST="${OUT_DIR}/Prairie-webos.ipk"
cp -f "$IPK" "$DEST"
echo "Wrote $DEST"
ls -lh "$DEST"
