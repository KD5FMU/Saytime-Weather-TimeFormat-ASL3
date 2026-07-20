#!/usr/bin/env bash
set -euo pipefail

# KD5FMU ASL3 Saytime Weather TimeFormat - saytime.pl updater
# Backs up the existing /usr/local/sbin/saytime.pl and downloads the latest corrected version.

URL="https://raw.githubusercontent.com/KD5FMU/Saytime-Weather-TimeFormat-ASL3/refs/heads/main/bin/saytime.pl"
TARGET="/usr/local/sbin/saytime.pl"
TMP_FILE="/tmp/saytime.pl.new.$$"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') saytime-update: $*"
}

die() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') saytime-update ERROR: $*" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  die "Please run this script with sudo or as root."
fi

command -v curl >/dev/null 2>&1 || die "curl is required. Install it with: sudo apt install curl"
command -v perl >/dev/null 2>&1 || die "perl is required."

log "Downloading corrected saytime.pl..."
curl -fsSL "$URL" -o "$TMP_FILE" || die "Download failed."

log "Checking downloaded Perl syntax..."
perl -c "$TMP_FILE" >/dev/null || die "Downloaded saytime.pl failed Perl syntax check."

if [ -f "$TARGET" ]; then
  BACKUP_FILE="$TARGET.bak.$(date '+%Y%m%d-%H%M%S')"
  log "Backing up existing saytime.pl to $BACKUP_FILE"
  cp -a "$TARGET" "$BACKUP_FILE"
else
  log "No existing $TARGET found. A backup was not needed."
fi

log "Installing corrected saytime.pl to $TARGET"
install -m 0755 "$TMP_FILE" "$TARGET"

chown root:root "$TARGET" 2>/dev/null || true

rm -f "$TMP_FILE"

log "Final syntax check..."
perl -c "$TARGET"

log "Update complete."
echo
echo "You can test it with:"
echo "  sudo /usr/bin/perl /usr/local/sbin/saytime.pl"
echo
echo "Or with location and node:"
echo "  sudo /usr/bin/perl /usr/local/sbin/saytime.pl 74437 YOUR_NODE_NUMBER"
