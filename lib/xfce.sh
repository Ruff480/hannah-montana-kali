# shellcheck shell=bash
# XFCE (Kali's default desktop): everything goes through xfconf, which every
# XFCE component watches, so changes show up live without restarting anything.

# Key format in the snapshot: xfconf|<channel>|<property>|<type>
xf_get() { xfconf-query -c "$1" -p "$2" 2>/dev/null; }

xf_set() {   # xf_set <channel> <property> <type> <value>
    xfconf-query -c "$1" -p "$2" -s "$4" 2>/dev/null ||
        xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4"
}

# Save the current value (or its absence) and then change it.
xf_change() { # xf_change <channel> <property> <type> <new value>
    local old
    if old="$(xf_get "$1" "$2")"; then :; else old="$HM_UNSET"; fi
    snap_put xfce "xfconf|$1|$2|$3" "$old"
    xf_set "$1" "$2" "$3" "$4"
}

xf_wallpaper_props() {
    local props
    props="$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$')"
    if [ -z "$props" ]; then
        # Fresh profile: xfdesktop has not written anything yet. Create the
        # property for every connected monitor, workspace 0.
        local mon
        if have xrandr; then
            for mon in $(xrandr --listmonitors 2>/dev/null | awk 'NR > 1 { print $NF }'); do
                props="$props /backdrop/screen0/monitor$mon/workspace0/last-image"
            done
        fi
        [ -n "$props" ] || props="/backdrop/screen0/monitor0/workspace0/last-image"
    fi
    # shellcheck disable=SC2086  # one property per word
    printf '%s\n' $props
}

xfce_on() {
    have xfconf-query || die "xfconf-query not found; is XFCE installed?"
    snap_reset xfce

    # GTK + icons + window manager decorations (xfwm4 "Default" follows GTK colours)
    xf_change xsettings /Net/ThemeName string "$HM_GTK_THEME"
    xf_change xsettings /Net/IconThemeName string "$HM_ICON_THEME"
    xf_change xfwm4 /general/theme string "Default"

    # Wallpaper on every monitor/workspace xfdesktop knows about.
    local prop
    for prop in $(xf_wallpaper_props); do
        xf_change xfce4-desktop "$prop" string "$HM_WALLPAPER"
        xf_change xfce4-desktop "${prop%/last-image}/image-style" int 5   # zoomed
    done

    # Let the GTK theme paint the panels (style 0 = "None (use system style)").
    for prop in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/panels/panel-[0-9]+/background-style$'); do
        xf_change xfce4-panel "$prop" uint 0
    done

    qterm_on xfce
}

xf_restore_one() {
    local key="$1" val="$2" kind channel prop type
    IFS='|' read -r kind channel prop type <<< "$key"
    case "$kind" in
        xfconf)
            if [ "$val" = "$HM_UNSET" ]; then
                xfconf-query -c "$channel" -p "$prop" -r 2>/dev/null || true
            else
                xf_set "$channel" "$prop" "$type" "$val" || warn "could not restore $channel $prop"
            fi ;;
        qterm) qterm_restore "$val" ;;
    esac
}

xfce_off() {
    have xfconf-query || die "xfconf-query not found; is XFCE installed?"
    snap_each xfce xf_restore_one
}

# --- Hotkey ---------------------------------------------------------------
xfce_hotkey_on() {
    have xfconf-query || return 1
    local key prop cur
    key="$(hm_hotkey_gtk)"
    prop="/commands/custom/$key"
    if cur="$(xf_get xfce4-keyboard-shortcuts "$prop")" && [ "$cur" != "$HM_TOGGLE_CMD" ]; then
        warn "$HM_HOTKEY is already bound to '$cur' in XFCE; leaving it alone."
        warn "Pick another key with: $HM_NAME hotkey on --key Super+Alt+H"
        return 1
    fi
    xfce_hotkey_off   # drop any binding we made on a previous key
    xf_set xfce4-keyboard-shortcuts "$prop" string "$HM_TOGGLE_CMD"
}

xfce_hotkey_off() {
    have xfconf-query || return 0
    local prop
    # Remove every binding that points at us, whatever key it was on.
    while read -r prop; do
        [ "$(xf_get xfce4-keyboard-shortcuts "$prop")" = "$HM_TOGGLE_CMD" ] &&
            xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r
    done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null | grep '^/commands/custom/')
    return 0
}

xfce_hotkey_status() {
    local prop
    while read -r prop; do
        [ "$(xf_get xfce4-keyboard-shortcuts "$prop")" = "$HM_TOGGLE_CMD" ] &&
            printf '%s\n' "${prop#/commands/custom/}"
    done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null | grep '^/commands/custom/')
}
