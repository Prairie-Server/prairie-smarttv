#!/usr/bin/env bash
# Fails when a Prairie playback invariant listed in scripts/prairie-invariants.txt
# stops holding. A cheap, build-free tripwire that runs on every PR (same
# format as the Apple client's scripts/prairie-invariants.txt).
#
# The count column is either N (the regex must match at least N lines) or =N
# (exactly N lines; =0 means the pattern must be absent).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
manifest=scripts/prairie-invariants.txt
failures=0
checked=0
while IFS=$'\t' read -r path count pattern why || [[ -n "${path:-}" ]]; do
  [[ -z "${path// }" || "$path" == \#* ]] && continue
  checked=$((checked + 1))
  if [[ ! -f "$path" ]]; then
    echo "::error file=$path::Prairie invariant: file missing ($why)"
    failures=$((failures + 1))
    continue
  fi
  matched=$(grep -cE -- "$pattern" "$path" || true)
  if [[ "$count" == =* ]]; then
    want=${count#=}
    if (( matched != want )); then
      echo "::error file=$path::Prairie invariant: /$pattern/ matched $matched, need exactly $want ($why)"
      failures=$((failures + 1))
    fi
  elif (( matched < count )); then
    echo "::error file=$path::Prairie invariant: /$pattern/ matched $matched, need $count ($why)"
    failures=$((failures + 1))
  fi
done < "$manifest"
if (( failures > 0 )); then
  echo "$failures of $checked Prairie invariants failed. Restore the code; do not delete the invariant." >&2
  exit 1
fi
echo "All $checked Prairie invariants hold."
