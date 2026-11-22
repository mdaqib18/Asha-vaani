#!/usr/bin/env bash
# Build an Android release APK pinned to the deployed backend domain via --dart-define.
# Usage: bash deploy/build-apk.sh ashavaani.duckdns.org

set -euo pipefail

if [[ $# -lt 1 || -z "${1// }" ]]; then
  echo "Usage: $0 <DOMAIN or https://DOMAIN>" >&2
  exit 1
fi

RAW_TARGET="$1"
if [[ "$RAW_TARGET" == http://* || "$RAW_TARGET" == https://* ]]; then
  API_BASE_URL="${RAW_TARGET%/}"
else
  API_BASE_URL="https://${RAW_TARGET%/}"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/mobile"

echo "==> Building release APK for API_BASE_URL=${API_BASE_URL}..."
flutter build apk --release --dart-define="API_BASE_URL=${API_BASE_URL}"

echo ""
echo "APK built at: mobile/build/app/outputs/flutter-apk/app-release.apk"
