#!/usr/bin/env bash
# Validate Flutter package layouts / manifests for all four release artifacts
# without needing flutter-tizen or flutter-webos SDKs.
#
# Checks:
#   - prairie_webos appinfo.json (transparent + requiredACG)
#   - prairie_tizen tizen-manifest.xml privileges + stampable api-version
#   - stamp script produces 6.0 / 6.5 / 10.0 variants and restores default
#
# Exit 0 on success. Intended for CI on ubuntu-latest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEBOS_APPINFO="${ROOT}/packages/prairie_webos/webos/meta/appinfo.json"
TIZEN_MANIFEST="${ROOT}/packages/prairie_tizen/tizen/tizen-manifest.xml"
STAMP="${SCRIPT_DIR}/stamp-tizen-api-version.sh"
TMP_MANIFEST="$(mktemp)"
trap 'rm -f "$TMP_MANIFEST"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -f "$WEBOS_APPINFO" ]] || fail "missing $WEBOS_APPINFO"
[[ -f "$TIZEN_MANIFEST" ]] || fail "missing $TIZEN_MANIFEST"
[[ -x "$STAMP" || -f "$STAMP" ]] || fail "missing $STAMP"

# --- webOS appinfo ---
python3 - <<'PY' "$WEBOS_APPINFO" || fail "webOS appinfo validation"
import json, sys
path = sys.argv[1]
with open(path) as f:
    info = json.load(f)
assert info.get("transparent") is True, "transparent must be true for video plane"
acg = info.get("requiredACG") or []
for need in ("systemconfig.query", "securitykey.operation"):
    assert need in acg, f"requiredACG missing {need}"
assert info.get("id"), "id required"
assert info.get("main"), "main required"
print("webOS appinfo.json ok")
PY
pass "webOS appinfo.json (transparent + ACGs)"

# --- Tizen manifest baseline ---
grep -q 'privilege>http://tizen.org/privilege/internet' "$TIZEN_MANIFEST" \
  || fail "tizen-manifest missing internet privilege"
grep -q 'api-version=' "$TIZEN_MANIFEST" || fail "tizen-manifest missing api-version"
pass "Tizen manifest privileges"

# --- Stamp all three Store variants (on a copy; restore source unchanged) ---
cp -f "$TIZEN_MANIFEST" "$TMP_MANIFEST"
ORIG_API="$(grep -oE 'api-version="[^"]+"' "$TIZEN_MANIFEST" | head -1)"

for ver in 6.0 6.5 10.0; do
  bash "$STAMP" "$ver" --manifest "$TMP_MANIFEST" >/dev/null
  grep -q "api-version=\"${ver}\"" "$TMP_MANIFEST" \
    || fail "stamp did not set api-version=${ver}"
  pass "stamp api-version=${ver}"
done

# Default checked-in manifest should remain 6.5 (dev default spanning 6.5–9.0).
grep -q 'api-version="6.5"' "$TIZEN_MANIFEST" \
  || fail "checked-in tizen-manifest.xml should default to api-version=6.5 (was ${ORIG_API})"
pass "checked-in default api-version=6.5"

# --- Required Dart entrypoints / scripts exist ---
for f in \
  packages/prairie_webos/lib/main.dart \
  packages/prairie_webos/lib/platform/webos_video_backend.dart \
  packages/prairie_webos/lib/platform/device_tier_webos.dart \
  packages/prairie_tizen/lib/main.dart \
  packages/prairie_tizen/lib/platform/videohole_video_backend.dart \
  scripts/build-tizen.sh \
  scripts/build-webos.sh
do
  [[ -f "${ROOT}/${f}" ]] || fail "missing ${f}"
done
pass "required Dart entrypoints and build scripts present"

# --- pubspec deps presence (lightweight grep, no pub get) ---
grep -q 'video_player_drm:' "${ROOT}/packages/prairie_webos/pubspec.yaml" \
  || fail "prairie_webos missing video_player_drm"
grep -q 'device_info_plus_webos:' "${ROOT}/packages/prairie_webos/pubspec.yaml" \
  || fail "prairie_webos missing device_info_plus_webos"
grep -q 'video_player_videohole:' "${ROOT}/packages/prairie_tizen/pubspec.yaml" \
  || fail "prairie_tizen missing video_player_videohole"
if grep -q 'path_provider_tizen:' "${ROOT}/packages/prairie_tizen/pubspec.yaml"; then
  fail "prairie_tizen still depends on unused path_provider_tizen"
fi
pass "pubspec dependency shape"

echo
echo "All four release variants are layout-valid:"
echo "  1) webOS (.ipk) — appinfo ready"
echo "  2) Tizen api-version 6.0"
echo "  3) Tizen api-version 6.5"
echo "  4) Tizen api-version 10.0"
echo "Native SDK builds: flutter/scripts/build-{webos,tizen}.sh"
