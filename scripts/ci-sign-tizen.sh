#!/usr/bin/env bash
# Optional CI helper: install Tizen Web CLI, materialize cert secrets, sign dist-tizen/.
# Expects env: TIZEN_AUTHOR_P12, TIZEN_AUTHOR_PASSWORD, TIZEN_DISTRIBUTOR_P12,
# TIZEN_DISTRIBUTOR_PASSWORD (base64 for *.p12). Optional: TIZEN_SECURITY_PROFILE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${TIZEN_SECURITY_PROFILE:-Prairie}"
STUDIO="${TIZEN_STUDIO_DIR:-$HOME/tizen-studio}"
WORK="${RUNNER_TEMP:-/tmp}/prairie-tizen-sign"
mkdir -p "$WORK"

if [[ -z "${TIZEN_AUTHOR_P12:-}" || -z "${TIZEN_AUTHOR_PASSWORD:-}" || -z "${TIZEN_DISTRIBUTOR_P12:-}" || -z "${TIZEN_DISTRIBUTOR_PASSWORD:-}" ]]; then
  echo "Tizen signing secrets not fully configured; skipping signed .wgt."
  exit 0
fi

if [[ ! -x "$STUDIO/tools/ide/bin/tizen" ]]; then
  echo "Installing Tizen Studio Web CLI into $STUDIO…"
  sudo apt-get update -qq
  sudo apt-get install -y -qq pciutils zip libncurses5 python3 libpython3.12 >/dev/null || \
    sudo apt-get install -y -qq pciutils zip libncurses5 python3 >/dev/null
  INSTALLER="$WORK/tizen-studio.bin"
  curl -fsSL -o "$INSTALLER" \
    "https://download.tizen.org/sdk/Installer/tizen-studio_5.5/web-cli_Tizen_Studio_5.5_ubuntu-64.bin"
  chmod +x "$INSTALLER"
  "$INSTALLER" --accept-license "$STUDIO"
  "$STUDIO/package-manager/package-manager-cli.bin" install --accept-license \
    Certificate-Manager TV-SAMSUNG-Public-WebAppDevelopment-CLI || \
    "$STUDIO/package-manager/package-manager-cli.bin" install --accept-license Certificate-Manager
fi

export PATH="$STUDIO/tools/ide/bin:$PATH"

AUTHOR_P12="$WORK/author.p12"
DIST_P12="$WORK/distributor.p12"
PROFILES="$WORK/profiles.xml"
echo -n "$TIZEN_AUTHOR_P12" | base64 -d >"$AUTHOR_P12"
echo -n "$TIZEN_DISTRIBUTOR_P12" | base64 -d >"$DIST_P12"

# profiles.xml passwords are plain here for headless CI; file stays in $RUNNER_TEMP.
cat >"$PROFILES" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<profiles active="$PROFILE" version="3.1">
  <profile name="$PROFILE">
    <profileitem ca="" distributor="0" key="$AUTHOR_P12" password="$TIZEN_AUTHOR_PASSWORD" rootca=""/>
    <profileitem ca="" distributor="1" key="$DIST_P12" password="$TIZEN_DISTRIBUTOR_PASSWORD" rootca=""/>
  </profile>
</profiles>
EOF

tizen cli-config -g "default.profiles.path=$PROFILES"
export TIZEN_SECURITY_PROFILE="$PROFILE"
export TIZEN_PROFILES_PATH="$PROFILES"
node "$ROOT/scripts/sign-tizen.mjs"

rm -f "$AUTHOR_P12" "$DIST_P12" "$PROFILES"
echo "Signed Tizen package ready under artifacts/"
