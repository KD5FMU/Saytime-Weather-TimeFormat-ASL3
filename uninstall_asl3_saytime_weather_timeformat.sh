#!/usr/bin/env bash
#
# uninstall_asl3_saytime_weather_timeformat.sh
#
# KD5FMU Saytime-Weather-TimeFormat-ASL3 Uninstaller
# For Debian 12 Bookworm / Debian 13 Trixie running AllStarLink Version 3
#
# This removes everything installed by:
#   install_asl3_saytime_weather_timeformat.sh
#
# IMPORTANT:
#   This uninstaller intentionally DOES NOT remove the sound files from:
#     /usr/local/share/asterisk/sounds/custom
#
# Usage:
#   sudo ./uninstall_asl3_saytime_weather_timeformat.sh
#   sudo ./uninstall_asl3_saytime_weather_timeformat.sh --yes
#
# Options:
#   -y, --yes      Run without asking for confirmation
#   -h, --help     Show this help text
#

set -u

APP_NAME="KD5FMU Saytime-Weather-TimeFormat-ASL3"

CONFIG_DIR="/etc/asterisk/local"
CONFIG_FILE="$CONFIG_DIR/weatherapi.ini"

SBIN_DIR="/usr/local/sbin"

SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="asl3-weatherapi-update.service"
TIMER_NAME="asl3-weatherapi-update.timer"

CACHE_DIR="/var/cache/asl3-saytime-weather"
SOUNDS_DIR="/usr/local/share/asterisk/sounds/custom"

YES=0

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') uninstaller: $*"
}

warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') uninstaller WARNING: $*" >&2
}

die() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') uninstaller ERROR: $*" >&2
    exit 1
}

show_help() {
    sed -n '1,32p' "$0" | sed 's/^# \{0,1\}//'
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -y|--yes)
                YES=1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "Please run this uninstaller with sudo or as root."
}

confirm_uninstall() {
    if [ "$YES" -eq 1 ]; then
        return 0
    fi

    echo
    echo "======================================================================"
    echo " $APP_NAME Uninstaller"
    echo "======================================================================"
    echo
    echo "This will remove:"
    echo
    echo "  Scripts:"
    echo "    $SBIN_DIR/asl3-weatherapi-update.sh"
    echo "    $SBIN_DIR/show_weatherapi.sh"
    echo "    $SBIN_DIR/saytime.pl"
    echo
    echo "  Config:"
    echo "    $CONFIG_FILE"
    echo "    $CONFIG_FILE.sample"
    echo
    echo "  Cache:"
    echo "    $CACHE_DIR"
    echo
    echo "  Systemd:"
    echo "    $SYSTEMD_DIR/$SERVICE_NAME"
    echo "    $SYSTEMD_DIR/$TIMER_NAME"
    echo
    echo "  Root crontab block/lines for:"
    echo "    ASL3 Saytime Weather TimeFormat"
    echo "    /usr/local/sbin/saytime.pl"
    echo
    echo "This will NOT remove sound files from:"
    echo "    $SOUNDS_DIR"
    echo
    read -r -p "Continue with uninstall? [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            die "Uninstall cancelled."
            ;;
    esac
}

remove_file() {
    local target="$1"

    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target" && log "Removed $target"
    else
        log "Not found, skipping $target"
    fi
}

remove_directory() {
    local target="$1"

    if [ -d "$target" ]; then
        rm -rf "$target" && log "Removed directory $target"
    else
        log "Directory not found, skipping $target"
    fi
}

backup_root_crontab() {
    local backup_file="/root/crontab.before-saytime-weather-timeformat-uninstall.$(date +%Y%m%d-%H%M%S).bak"

    if crontab -l >/dev/null 2>&1; then
        crontab -l > "$backup_file" || warn "Could not back up root crontab."
        log "Backed up root crontab to $backup_file"
    else
        log "No root crontab found to back up."
    fi
}

remove_crontab_entries() {
    local tmpfile
    local before_count
    local after_count

    tmpfile="$(mktemp)"
    before_count="$(crontab -l 2>/dev/null | wc -l | awk '{print $1}')"

    # The installer adds a marked block:
    #   ASL3 Saytime Weather TimeFormat
    #
    # This awk section removes that marked block safely.
    #
    # The grep lines after that also remove any leftover manual or older lines
    # that call /usr/local/sbin/saytime.pl.
    crontab -l 2>/dev/null | \
        awk '
            /ASL3 Saytime Weather TimeFormat/ { inblock=1; next }
            inblock && /END ASL3 Saytime Weather TimeFormat/ { inblock=0; next }
            !inblock { print }
        ' | \
        grep -v "/usr/local/sbin/saytime\.pl" > "$tmpfile" || true

    if [ -s "$tmpfile" ]; then
        crontab "$tmpfile" || warn "Could not install cleaned root crontab."
    else
        crontab -r 2>/dev/null || true
        log "Root crontab is now empty and was removed."
    fi

    after_count="$(crontab -l 2>/dev/null | wc -l | awk '{print $1}')"
    rm -f "$tmpfile"

    log "Root crontab cleanup complete. Lines before: $before_count, lines after: $after_count"
}

stop_disable_systemd() {
    if command -v systemctl >/dev/null 2>&1; then
        log "Stopping and disabling systemd timer/service if present."

        systemctl stop "$TIMER_NAME" 2>/dev/null || true
        systemctl disable "$TIMER_NAME" 2>/dev/null || true

        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    else
        warn "systemctl not found; skipping systemd stop/disable."
    fi
}

remove_systemd_files() {
    log "Removing systemd files."

    remove_file "$SYSTEMD_DIR/$SERVICE_NAME"
    remove_file "$SYSTEMD_DIR/$TIMER_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null || true
        systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
        systemctl reset-failed "$TIMER_NAME" 2>/dev/null || true
        log "Reloaded systemd daemon."
    fi
}

remove_scripts() {
    log "Removing installed scripts."

    remove_file "$SBIN_DIR/asl3-weatherapi-update.sh"
    remove_file "$SBIN_DIR/show_weatherapi.sh"
    remove_file "$SBIN_DIR/saytime.pl"
}

remove_config() {
    log "Removing installed config files."

    remove_file "$CONFIG_FILE"
    remove_file "$CONFIG_FILE.sample"

    # Leave /etc/asterisk/local itself alone.
    # Other ASL3 local scripts commonly use this directory.
}

remove_cache() {
    log "Removing cache and temporary files."

    remove_directory "$CACHE_DIR"

    remove_file "/tmp/current-time.gsm"
    remove_file "/tmp/condition.gsm"
    remove_file "/tmp/temperature"
}

show_sound_file_notice() {
    echo
    echo "======================================================================"
    echo " Sound files were preserved"
    echo "======================================================================"
    echo
    echo "Per your request, this uninstaller did NOT remove anything from:"
    echo
    echo "  $SOUNDS_DIR"
    echo
    echo "That is the right move because those recorded GSM files may be shared"
    echo "with other KD5FMU / ASL3 time and weather projects."
    echo
    echo "======================================================================"
}

show_done_message() {
    echo
    echo "======================================================================"
    echo " $APP_NAME uninstall complete"
    echo "======================================================================"
    echo
    echo "Useful checks:"
    echo
    echo "  systemctl status $TIMER_NAME"
    echo "  systemctl status $SERVICE_NAME"
    echo "  sudo crontab -l"
    echo "  ls -l /usr/local/sbin/saytime.pl"
    echo "  ls -l /usr/local/sbin/*weatherapi*"
    echo
    echo "The sound files should still be present here:"
    echo
    echo "  $SOUNDS_DIR"
    echo
    echo "73!"
    echo "======================================================================"
    echo
}

main() {
    parse_args "$@"
    require_root
    confirm_uninstall

    backup_root_crontab
    remove_crontab_entries
    stop_disable_systemd
    remove_systemd_files
    remove_scripts
    remove_config
    remove_cache
    show_sound_file_notice
    show_done_message
}

main "$@"
