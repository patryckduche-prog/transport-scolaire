#!/usr/bin/env sh
set -eu

HEALTH_URL="${HEALTH_URL:-https://bus-scolaire-connect-api.onrender.com/health}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-12}"

if command -v curl >/dev/null 2>&1; then
  RESPONSE="$(curl -fsS --max-time "$TIMEOUT_SECONDS" "$HEALTH_URL")"
else
  RESPONSE="$(wget -qO- --timeout="$TIMEOUT_SECONDS" "$HEALTH_URL")"
fi

echo "$RESPONSE" | grep -q '"ok":true'
echo "OK $HEALTH_URL"
