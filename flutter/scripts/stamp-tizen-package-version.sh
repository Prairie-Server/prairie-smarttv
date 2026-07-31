#!/usr/bin/env bash
# Stamp the package version (semver) in prairie_tizen's tizen-manifest.xml.
#
# Used to be stamp-tizen-api-version.sh, which also rewrote api-version for
# per-TizenOS-version TPK variants — that existed only because
# video_player_avplay ships precompiled, api-version-specific native .so
# libraries and needs a separate Store submission per TizenOS range. This
# app uses video_player_videohole instead, which compiles from source at
# build time with no per-version binaries, so that split no longer applies:
# tizen-manifest.xml's checked-in api-version="6.5" covers the whole
# supported range (Tizen 6.5-9.0+) in one TPK. This script now only stamps
# the release version string, unconditionally at the default api-version.
#
# Usage:
#   ./stamp-tizen-package-version.sh 1.0.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/../packages/prairie_tizen/tizen/tizen-manifest.xml"

PACKAGE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$PACKAGE_VERSION" ]]; then
        PACKAGE_VERSION="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$PACKAGE_VERSION" ]]; then
  echo "Usage: $0 <X.Y.Z> [--manifest path]" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

# Portable in-place sed (GNU and BSD).
_sed_inplace() {
  local expr="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i -E "$expr" "$file"
  else
    sed -i '' -E "$expr" "$file"
  fi
}

_sed_inplace "s/(<manifest[^>]*[[:space:]]version=\")[^\"]+(\")/\1${PACKAGE_VERSION}\2/" "$MANIFEST"

echo "Stamped package version=${PACKAGE_VERSION} in $MANIFEST"
grep -E 'api-version=|<manifest ' "$MANIFEST" | head -2
