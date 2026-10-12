# shellcheck shell=bash
# Shared helpers for hannah-montana-kali. Sourced, never executed directly.

HM_NAME="hannah-montana-kali"
HM_PREFIX="${HM_PREFIX:-/usr/share/$HM_NAME}"
HM_STATE_DIR="${HM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$HM_NAME}"
HM_CONFIG_FILE="${HM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/$HM_NAME/config}"

# Defaults; overridable from the config file or the environment.
HM_VARIANT="${HM_VARIANT:-light}"          # light | dark
HM_HOTKEY="${HM_HOTKEY:-Super+Shift+H}"    # neutral notation, translated per desktop
HM_TOGGLE_CMD="${HM_TOGGLE_CMD:-/usr/local/bin/$HM_NAME toggle}"

# shellcheck source=/dev/null
[ -r "$HM_CONFIG_FILE" ] && . "$HM_CONFIG_FILE"

log()  { printf '\033[1;35m[hannah]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[hannah]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[hannah]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

notify() {
    have notify-send || return 0
    notify-send -a "Hannah Montana" -i "$HM_PREFIX/H.png" "Hannah Montana" "$1" 2>/dev/null || true
}

# Names of the theme pieces for the selected variant (used by the desktop modules).
# shellcheck disable=SC2034
hm_variant_names() {
    case "$HM_VARIANT" in
        dark)
            HM_GTK_THEME="HannahMontanaDark"
            HM_ICON_THEME="HannahMontanaDark"
            HM_KDE_LNF="org.hmldark.desktop"
            HM_KDE_COLORS="PrettyPinkDark"
            HM_KDE_PLASMA="hannah-montana-theme-dark"
            ;;
        *)
            HM_GTK_THEME="HannahMontana"
            HM_ICON_THEME="HannahMontana"
            HM_KDE_LNF="org.hml.desktop"
            HM_KDE_COLORS="PrettyPink"
            HM_KDE_PLASMA="hannah-montana-theme"
            ;;
    esac
    HM_WALLPAPER="$HM_PREFIX/wallpaper/1920x1080.png"
    HM_LOCKSCREEN="$HM_PREFIX/lockscreen/1920x1080.png"
}

# Which desktop is this session running? Prints xfce | kde | gnome | unknown.
hm_detect_desktop() {
    local d="${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}"
    d="$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')"
    case "$d" in
        *xfce*)            echo xfce ;;
        *kde*|*plasma*)    echo kde ;;
        *gnome*|*ubuntu*)  echo gnome ;;
        *)
            if pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1; then echo xfce
            elif pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then echo kde
            elif pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1; then echo gnome
            else echo unknown
            fi ;;
    esac
}

# Translate "Super+Shift+H" into each desktop's shortcut syntax.
hm_hotkey_gtk() {   # <Super><Shift>h  (XFCE, GNOME)
    local out="" part IFS=+
    for part in $HM_HOTKEY; do
        case "$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')" in
            super|meta|win) out="$out<Super>" ;;
            ctrl|control|primary) out="$out<Primary>" ;;
            alt) out="$out<Alt>" ;;
            shift) out="$out<Shift>" ;;
            *) out="$out$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')" ;;
        esac
    done
    printf '%s\n' "$out"
}

hm_hotkey_kde() {   # Meta+Shift+H
    local out="" part IFS=+
    for part in $HM_HOTKEY; do
        case "$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')" in
            super|meta|win) part=Meta ;;
            ctrl|control|primary) part=Ctrl ;;
            alt) part=Alt ;;
            shift) part=Shift ;;
            *) part="$(printf '%s' "$part" | tr '[:lower:]' '[:upper:]')" ;;
        esac
        out="${out:+$out+}$part"
    done
    printf '%s\n' "$out"
}

# --- Snapshot store -------------------------------------------------------
# Before the theme is applied, every setting we are about to change is saved
# as "key<TAB>value" lines so that "off" puts things back exactly. A value of
# the literal string __UNSET__ means the key did not exist beforehand.
HM_UNSET="__UNSET__"
hm_snapshot_file() { printf '%s/snapshot-%s\n' "$HM_STATE_DIR" "$1"; }

snap_reset() { mkdir -p "$HM_STATE_DIR"; : > "$(hm_snapshot_file "$1")"; }

snap_put() {  # snap_put <desktop> <key> <value>
    printf '%s\t%s\n' "$2" "$3" >> "$(hm_snapshot_file "$1")"
}

snap_each() { # snap_each <desktop> <callback>; callback receives key value
    local f key val
    f="$(hm_snapshot_file "$1")"
    [ -r "$f" ] || return 0
    while IFS=$'\t' read -r key val; do
        [ -n "$key" ] && "$2" "$key" "$val"
    done < "$f"
}

hm_state_get() { cat "$HM_STATE_DIR/state" 2>/dev/null || echo off; }
hm_state_set() { mkdir -p "$HM_STATE_DIR"; printf '%s\n' "$1" > "$HM_STATE_DIR/state"; }

# --- QTerminal (Kali's default terminal on XFCE and KDE) -----------------
HM_QTERM_INI="${HM_QTERM_INI:-${XDG_CONFIG_HOME:-$HOME/.config}/qterminal.org/qterminal.ini}"

qterm_on() {   # qterm_on <desktop>; new terminal windows pick it up
    local old
    old="$(ini_get "$HM_QTERM_INI" General colorScheme)" || old="$HM_UNSET"
    snap_put "$1" "qterm|colorScheme" "$old"
    ini_set "$HM_QTERM_INI" General colorScheme HannahMontana
}

qterm_restore() {
    if [ "$1" = "$HM_UNSET" ]; then
        ini_del "$HM_QTERM_INI" General colorScheme
    else
        ini_set "$HM_QTERM_INI" General colorScheme "$1"
    fi
}

# --- Minimal INI editing (for qterminal and friends) ----------------------
ini_get() {   # ini_get <file> <section> <key>
    [ -r "$1" ] || return 1
    awk -v s="[$2]" -v k="$3" '
        $0 == s { in_s = 1; next }
        /^\[/   { in_s = 0 }
        in_s && index($0, k "=") == 1 { print substr($0, length(k) + 2); found = 1; exit }
        END { exit !found }' "$1"
}

ini_set() {   # ini_set <file> <section> <key> <value>
    local tmp
    mkdir -p "$(dirname "$1")"
    [ -e "$1" ] || : > "$1"
    tmp="$(mktemp)"
    awk -v s="[$2]" -v k="$3" -v v="$4" '
        BEGIN { done = 0 }
        $0 == s { print; in_s = 1; seen = 1; next }
        /^\[/ { if (in_s && !done) { print k "=" v; done = 1 } in_s = 0 }
        in_s && index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
        { print }
        END {
            if (!done) { if (!seen) print s; print k "=" v }
        }' "$1" > "$tmp" && cat "$tmp" > "$1"
    rm -f "$tmp"
}

ini_del() {   # ini_del <file> <section> <key>
    local tmp
    [ -e "$1" ] || return 0
    tmp="$(mktemp)"
    awk -v s="[$2]" -v k="$3" '
        $0 == s { in_s = 1; print; next }
        /^\[/ { in_s = 0 }
        in_s && index($0, k "=") == 1 { next }
        { print }' "$1" > "$tmp" && cat "$tmp" > "$1"
    rm -f "$tmp"
}
