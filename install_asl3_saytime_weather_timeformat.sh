#!/usr/bin/env bash
set -euo pipefail

REPO="KD5FMU/Saytime-Weather-TimeFormat-ASL3"
BRANCH="main"

CONFIG_DIR="/etc/asterisk/local"
CONFIG_FILE="$CONFIG_DIR/weatherapi.ini"
SBIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"
CACHE_DIR="/var/cache/asl3-saytime-weather"
SOUNDS_DIR="/usr/local/share/asterisk/sounds/custom"
ORIGINAL_SOUND_ZIP_URL="http://198.58.124.150/tw/sound_files.zip"
WORKDIR="/tmp/asl3-saytime-weather-timeformat.$$"

LOCATION_ARG="${1:-}"
NODE_ARG="${2:-}"
TIME_FORMAT_ARG="${3:-}"

log(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') installer: $*"
}

die(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') installer ERROR: $*" >&2
  exit 1
}

need_root(){
  [ "$(id -u)" -eq 0 ] || die "Please run with sudo or as root."
}

backup_file(){
  if [ -f "$1" ]; then
    cp -a "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  return 0
}

install_packages(){
  log "Installing required packages: curl jq cron ca-certificates perl unzip sox"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq cron ca-certificates perl unzip sox
}

download_repo_files(){
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR/bin" "$WORKDIR/config" "$WORKDIR/systemd"

  local base
  base="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

  for f in \
    bin/asl3-weatherapi-update.sh \
    bin/show_weatherapi.sh \
    bin/saytime.pl \
    config/weatherapi.ini \
    systemd/asl3-weatherapi-update.service \
    systemd/asl3-weatherapi-update.timer
  do
    mkdir -p "$WORKDIR/$(dirname "$f")"
    curl -fsSL "$base/$f" -o "$WORKDIR/$f" || die "Could not download $f"
  done
}

install_files(){
  mkdir -p "$CONFIG_DIR" "$CACHE_DIR" "$SOUNDS_DIR"

  install -m 0755 "$WORKDIR/bin/asl3-weatherapi-update.sh" "$SBIN_DIR/asl3-weatherapi-update.sh"
  install -m 0755 "$WORKDIR/bin/show_weatherapi.sh" "$SBIN_DIR/show_weatherapi.sh"

  backup_file "$SBIN_DIR/saytime.pl"
  install -m 0755 "$WORKDIR/bin/saytime.pl" "$SBIN_DIR/saytime.pl"

  if [ ! -f "$CONFIG_FILE" ]; then
    install -m 0640 "$WORKDIR/config/weatherapi.ini" "$CONFIG_FILE"
  else
    log "$CONFIG_FILE already exists; preserving existing config. New sample saved as ${CONFIG_FILE}.sample"
    install -m 0640 "$WORKDIR/config/weatherapi.ini" "${CONFIG_FILE}.sample"
  fi

  if [ -n "$LOCATION_ARG" ]; then
    sed -i "s/^LOCATION=.*/LOCATION=\"$LOCATION_ARG\"/" "$CONFIG_FILE"
  fi

  if [ -n "$NODE_ARG" ]; then
    sed -i "s/^NODE=.*/NODE=\"$NODE_ARG\"/" "$CONFIG_FILE"
  fi

  if [ "$TIME_FORMAT_ARG" = "12" ] || [ "$TIME_FORMAT_ARG" = "24" ]; then
    sed -i "s/^TIME_FORMAT=.*/TIME_FORMAT=\"$TIME_FORMAT_ARG\"/" "$CONFIG_FILE"
  fi

  chown -R asterisk:asterisk "$CACHE_DIR" 2>/dev/null || true
}

install_recorded_sound_files(){
  mkdir -p "$SOUNDS_DIR"

  local count zip
  count="$(find "$SOUNDS_DIR" -type f -name '*.gsm' 2>/dev/null | wc -l | awk '{print $1}')"

  if [ "$count" -ge 20 ]; then
    log "Recorded voice files already appear to exist in $SOUNDS_DIR; skipping download."
    return 0
  fi

  log "Downloading original recorded voice files from $ORIGINAL_SOUND_ZIP_URL"
  zip="/tmp/sound_files.zip"

  curl -fL "$ORIGINAL_SOUND_ZIP_URL" -o "$zip" || die "Could not download recorded voice files."
  unzip -o "$zip" -d "$SOUNDS_DIR" >/dev/null || die "Could not extract recorded voice files to $SOUNDS_DIR"

  chown -R asterisk:asterisk "$SOUNDS_DIR" 2>/dev/null || true
  chmod -R a+rX "$SOUNDS_DIR"

  sox -n -r 8000 -c 1 "$SOUNDS_DIR/pause-350ms.gsm" trim 0.0 1.0
  chmod 644 "$SOUNDS_DIR/pause-350ms.gsm"
  chown asterisk:asterisk "$SOUNDS_DIR/pause-350ms.gsm" 2>/dev/null || true
}

install_systemd(){
  install -m 0644 "$WORKDIR/systemd/asl3-weatherapi-update.service" "$SYSTEMD_DIR/asl3-weatherapi-update.service"
  install -m 0644 "$WORKDIR/systemd/asl3-weatherapi-update.timer" "$SYSTEMD_DIR/asl3-weatherapi-update.timer"

  systemctl daemon-reload
  systemctl enable --now asl3-weatherapi-update.timer || true
}

cron_has_block(){
  crontab -l 2>/dev/null | grep -q "ASL3 Saytime Weather TimeFormat"
}

install_cron_template(){
  if cron_has_block; then
    log "Crontab block already exists; leaving it unchanged."
    return 0
  fi

  local active_line comment_line

  if [ -n "$LOCATION_ARG" ] && [ -n "$NODE_ARG" ]; then
    active_line="0 * * * * /usr/bin/nice -19 /usr/bin/perl /usr/local/sbin/saytime.pl $LOCATION_ARG $NODE_ARG >/dev/null 2>&1"
    comment_line="# Active hourly announcement installed by setup script."
  else
    active_line="# 0 * * * * /usr/bin/nice -19 /usr/bin/perl /usr/local/sbin/saytime.pl YOUR_ZIP_CITY_OR_AIRPORT YOUR_NODE_NUMBER >/dev/null 2>&1"
    comment_line="# Edit the line below, remove the leading #, and add your ZIP/city/airport and node number."
  fi

  (
    crontab -l 2>/dev/null || true
    cat <<EOF

# ASL3 Saytime Weather TimeFormat
# Runs the recorded-voice time/weather announcement hourly.
# Config file: /etc/asterisk/local/weatherapi.ini
$comment_line
$active_line
# Optional examples:
# 0 * * * * /usr/bin/nice -19 /usr/bin/perl /usr/local/sbin/saytime.pl 74437 576339 >/dev/null 2>&1
# 0 * * * * /usr/bin/nice -19 /usr/bin/perl /usr/local/sbin/saytime.pl KTUL 576339 >/dev/null 2>&1
# End ASL3 Saytime Weather TimeFormat
EOF
  ) | crontab -
}

print_done(){
  cat <<EOF

Install complete.

Config file:
  $CONFIG_FILE

Edit your WeatherAPI key, location, node, and time format:
  sudo nano $CONFIG_FILE

Valid TIME_FORMAT values:
  12
  24

Manual WeatherAPI cache update:
  sudo /usr/local/sbin/asl3-weatherapi-update.sh

Manual announcement test:
  sudo /usr/bin/perl /usr/local/sbin/saytime.pl LOCATION NODE

Example:
  sudo /usr/bin/perl /usr/local/sbin/saytime.pl 74437 576339

Edit root crontab:
  sudo crontab -e

EOF
}

main(){
  need_root
  install_packages
  download_repo_files
  install_files
  install_recorded_sound_files
  install_systemd
  install_cron_template
  print_done
}

main "$@"
