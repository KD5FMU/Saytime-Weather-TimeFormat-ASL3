#!/usr/bin/env bash
set -euo pipefail
CONFIG_FILE="/etc/asterisk/local/weatherapi.ini"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
CACHE_DIR="${CACHE_DIR:-/var/cache/asl3-saytime-weather}"
ENV_FILE="$CACHE_DIR/current.env"
[ -f "$ENV_FILE" ] || { echo "No weather cache found. Run: sudo /usr/local/sbin/asl3-weatherapi-update.sh"; exit 1; }
source "$ENV_FILE"
echo "Location: ${LOCATION_NAME:-unknown} ${REGION:-} ${COUNTRY:-}"
echo "Condition: ${CONDITION:-unknown}"
echo "Temperature: ${TEMP_F:-?} F / ${TEMP_C:-?} C"
echo "Feels like: ${FEELSLIKE_F:-?} F / ${FEELSLIKE_C:-?} C"
echo "Humidity: ${HUMIDITY:-?}%"
