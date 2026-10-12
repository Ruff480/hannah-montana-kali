#!/usr/bin/env bash
# Remove hannah-montana-kali: turn the theme off, unbind the hotkey, undo the
# system theming and delete every installed file.
#
#   ./uninstall.sh   (or /usr/share/hannah-montana-kali/uninstall.sh)
set -uo pipefail

PREFIX=/usr/share/hannah-montana-kali
BIN=/usr/local/bin/hannah-montana-kali
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }

if [ -x "$BIN" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        say "Restoring your desktop"
        "$BIN" off || true
        "$BIN" hotkey off || true
    else
        say "Running as root: each user should run 'hannah-montana-kali off' first to restore their desktop."
    fi
    say "Undoing login/boot theming"
    $SUDO "$BIN" system off || true
fi

[ -r "$PREFIX/manifest" ] || { echo "nothing to uninstall ($PREFIX/manifest missing)" >&2; exit 1; }
say "Removing files"
# Read the manifest before deleting the directory that holds it.
mapfile -t paths < "$PREFIX/manifest"
for p in "${paths[@]}"; do
    case "$p" in
        /usr/share/*|/usr/local/bin/*|/etc/xdg/autostart/*) $SUDO rm -rf -- "$p" ;;
        *) echo "skipping unexpected manifest entry: $p" >&2 ;;
    esac
done
$SUDO rm -rf /var/lib/hannah-montana-kali
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/hannah-montana-kali" \
       "${XDG_CONFIG_HOME:-$HOME/.config}/hannah-montana-kali"
say "Hannah Montana has left the building."
