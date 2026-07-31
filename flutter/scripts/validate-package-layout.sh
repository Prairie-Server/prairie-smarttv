#!/usr/bin/env bash
# Validate Flutter package layouts / manifests for both release artifacts
# (webOS .ipk, Tizen .tpk) without needing flutter-tizen or flutter-webos
# SDKs.
#
# Checks:
#   - prairie_webos appinfo.json (transparent + requiredACG)
#   - prairie_tizen tizen-manifest.xml privileges + fixed api-version
#   - package-version stamp script works and restores the checked-in default
#
# Exit 0 on success. Intended for CI on ubuntu-latest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEBOS_APPINFO="${ROOT}/packages/prairie_webos/webos/meta/appinfo.json"
TIZEN_MANIFEST="${ROOT}/packages/prairie_tizen/tizen/tizen-manifest.xml"
STAMP="${SCRIPT_DIR}/stamp-tizen-package-version.sh"
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
# Fixed at 6.5 (spans Tizen 6.5-9.0+) — video_player_videohole compiles from
# source with no per-api-version binaries, so unlike the old video_player_avplay
# setup there is no need to vary this per Store submission.
grep -q 'api-version="6.5"' "$TIZEN_MANIFEST" || fail "tizen-manifest api-version should be 6.5"
pass "Tizen manifest privileges"

# --- Package-version stamp works (against a copy; $STAMP never touches $TIZEN_MANIFEST directly) ---
cp -f "$TIZEN_MANIFEST" "$TMP_MANIFEST"
bash "$STAMP" "9.9.9" --manifest "$TMP_MANIFEST" >/dev/null
grep -q 'version="9.9.9"' "$TMP_MANIFEST" || fail "stamp did not set package version"
pass "package-version stamp"

# --- Required Dart entrypoints / scripts exist ---
for f in \
  packages/pubspec.yaml \
  packages/prairie_webos/lib/main.dart \
  packages/prairie_webos/lib/platform/webos_video_backend.dart \
  packages/prairie_webos/lib/platform/device_tier_webos.dart \
  packages/prairie_tizen/lib/main.dart \
  packages/prairie_tizen/lib/platform/videohole_video_backend.dart \
  packages/flutter_secure_storage_webos/lib/flutter_secure_storage_webos.dart \
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
grep -q 'flutter_secure_storage_webos:' "${ROOT}/packages/prairie_webos/pubspec.yaml" \
  || fail "prairie_webos missing flutter_secure_storage_webos"
grep -q 'resolution: workspace' "${ROOT}/packages/flutter_secure_storage_webos/pubspec.yaml" \
  || fail "flutter_secure_storage_webos missing resolution: workspace"
grep -q 'video_player_videohole:' "${ROOT}/packages/prairie_tizen/pubspec.yaml" \
  || fail "prairie_tizen missing video_player_videohole"
if grep -q 'path_provider_tizen:' "${ROOT}/packages/prairie_tizen/pubspec.yaml"; then
  fail "prairie_tizen still depends on unused path_provider_tizen"
fi
pass "pubspec dependency shape"

echo
echo "Both release variants are layout-valid:"
echo "  1) webOS (.ipk) — appinfo ready"
echo "  2) Tizen (.tpk) — api-version 6.5 (spans 6.5-9.0+)"
echo "Native SDK builds: flutter/scripts/build-{webos,tizen}.sh"
