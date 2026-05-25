#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/asterisk/local/weatherapi.ini"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${API_KEY:=}"
: "${LOCATION:=}"
: "${CACHE_DIR:=/var/cache/asl3-saytime-weather}"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "PUT_YOUR_WEATHERAPI_KEY_HERE" ]; then
  echo "WeatherAPI key is not set in $CONFIG_FILE" >&2
  exit 1
fi

if [ -z "$LOCATION" ]; then
  echo "LOCATION is not set in $CONFIG_FILE" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

TMP_JSON="$CACHE_DIR/weather.json.tmp"
OUT_JSON="$CACHE_DIR/weather.json"
OUT_ENV="$CACHE_DIR/current.env"

URL="https://api.weatherapi.com/v1/current.json?key=${API_KEY}&q=$(printf '%s' "$LOCATION" | jq -sRr @uri)&aqi=no"

curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 "$URL" -o "$TMP_JSON"

# Validate JSON before replacing the good cache.
jq -e '.current.condition.text and .current.temp_f and .location.name' "$TMP_JSON" >/dev/null

mv "$TMP_JSON" "$OUT_JSON"

jq -r '
  "LOCATION_NAME=\(.location.name)",
  "REGION=\(.location.region // "")",
  "COUNTRY=\(.location.country // "")",
  "TEMP_F=\(.current.temp_f | round)",
  "TEMP_C=\(.current.temp_c | round)",
  "FEELSLIKE_F=\(.current.feelslike_f | round)",
  "FEELSLIKE_C=\(.current.feelslike_c | round)",
  "HUMIDITY=\(.current.humidity // "")",
  "CONDITION=\(.current.condition.text)",
  "UPDATED_EPOCH=\(.current.last_updated_epoch // now | floor)"
' "$OUT_JSON" > "$OUT_ENV"

chmod 0644 "$OUT_JSON" "$OUT_ENV"

echo "Weather cache updated for $LOCATION"
