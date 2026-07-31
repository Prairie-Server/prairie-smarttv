#!/usr/bin/env bash
# Stamp api-version (and optional package version) in prairie_tizen's
# tizen-manifest.xml for video_player_avplay multi-variant Store builds.
#
# video_player_avplay ships api-version-specific native libs:
#   6.0  → Tizen OS 6.0 only
#   6.5  → Tizen OS 6.5–9.0
#   10.0 → Tizen OS 10.0 only
# See: https://github.com/flutter-tizen/plugins/blob/master/packages/video_player_avplay/README.md
#
# Usage:
#   ./stamp-tizen-api-version.sh 6.0
#   ./stamp-tizen-api-version.sh 6.5 --package-version 1.0.1
#   ./stamp-tizen-api-version.sh 10.0 --package-version 1.0.2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/../packages/prairie_tizen/tizen/tizen-manifest.xml"

API_VERSION=""
PACKAGE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-version)
      PACKAGE_VERSION="${2:?}"
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$API_VERSION" ]]; then
        API_VERSION="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$API_VERSION" ]]; then
  echo "Usage: $0 <6.0|6.5|10.0> [--package-version X.Y.Z]" >&2
  exit 1
fi

case "$API_VERSION" in
  6.0|6.5|10.0) ;;
  *)
    echo "Unsupported api-version '$API_VERSION' (expected 6.0, 6.5, or 10.0)" >&2
    exit 1
    ;;
esac

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

_sed_inplace "s/api-version=\"[^\"]+\"/api-version=\"${API_VERSION}\"/" "$MANIFEST"

if [[ -n "$PACKAGE_VERSION" ]]; then
  _sed_inplace "s/(<manifest[^>]*[[:space:]]version=\")[^\"]+(\")/\1${PACKAGE_VERSION}\2/" "$MANIFEST"
fi

echo "Stamped api-version=${API_VERSION}${PACKAGE_VERSION:+ package-version=${PACKAGE_VERSION}} in $MANIFEST"
grep -E 'api-version=|<manifest ' "$MANIFEST" | head -2
