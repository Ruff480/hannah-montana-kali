# shellcheck shell=bash
# GNOME (kali-desktop-gnome). gsettings values are stored as GVariant text,
# which "gsettings set" accepts back verbatim.

HM_GNOME_KB_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
HM_GNOME_KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$HM_NAME/"

gs_change() { # gs_change <schema> <key> <new GVariant>
    local old
    old="$(gsettings get "$1" "$2" 2>/dev/null)" || return 0   # key absent on this GNOME
    snap_put gnome "$1|$2" "$old"
    gsettings set "$1" "$2" "$3"
}

gnome_on() {
    have gsettings || die "gsettings not found"
    snap_reset gnome
    gs_change org.gnome.desktop.background picture-uri "'file://$HM_WALLPAPER'"
    gs_change org.gnome.desktop.background picture-uri-dark "'file://$HM_WALLPAPER'"
    gs_change org.gnome.desktop.background picture-options "'zoom'"
    gs_change org.gnome.desktop.screensaver picture-uri "'file://$HM_LOCKSCREEN'"
    gs_change org.gnome.desktop.interface gtk-theme "'$HM_GTK_THEME'"
    gs_change org.gnome.desktop.interface icon-theme "'$HM_ICON_THEME'"
    if [ "$HM_VARIANT" = dark ]; then
        gs_change org.gnome.desktop.interface color-scheme "'prefer-dark'"
    else
        gs_change org.gnome.desktop.interface color-scheme "'default'"
    fi
    gs_change org.gnome.desktop.interface accent-color "'pink'"
}

gnome_restore_one() {
    local schema key
    IFS='|' read -r schema key <<< "$1"
    gsettings set "$schema" "$key" "$2" 2>/dev/null || warn "could not restore $schema $key"
}

gnome_off() {
    have gsettings || die "gsettings not found"
    snap_each gnome gnome_restore_one
}

# --- Hotkey ---------------------------------------------------------------
gnome_hotkey_on() {
    have gsettings || return 1
    local list sub="$HM_GNOME_KB_SCHEMA.custom-keybinding:$HM_GNOME_KB_PATH"
    list="$(gsettings get "$HM_GNOME_KB_SCHEMA" custom-keybindings)"
    case "$list" in
        *"'$HM_GNOME_KB_PATH'"*) ;;
        "@as []"|"[]") list="['$HM_GNOME_KB_PATH']" ;;
        *) list="${list%]}, '$HM_GNOME_KB_PATH']" ;;
    esac
    gsettings set "$HM_GNOME_KB_SCHEMA" custom-keybindings "$list"
    gsettings set "$sub" name "Toggle Hannah Montana"
    gsettings set "$sub" command "$HM_TOGGLE_CMD"
    gsettings set "$sub" binding "$(hm_hotkey_gtk)"
}

gnome_hotkey_off() {
    have gsettings || return 0
    local list
    list="$(gsettings get "$HM_GNOME_KB_SCHEMA" custom-keybindings)"
    list="$(printf '%s' "$list" | sed -e "s|, '$HM_GNOME_KB_PATH'||" -e "s|'$HM_GNOME_KB_PATH', ||" -e "s|'$HM_GNOME_KB_PATH'||")"
    [ "$list" = "[]" ] && list="@as []"
    gsettings set "$HM_GNOME_KB_SCHEMA" custom-keybindings "$list"
    gsettings reset-recursively "$HM_GNOME_KB_SCHEMA.custom-keybinding:$HM_GNOME_KB_PATH" 2>/dev/null
    return 0
}

gnome_hotkey_status() {
    have gsettings || return 0
    case "$(gsettings get "$HM_GNOME_KB_SCHEMA" custom-keybindings 2>/dev/null)" in
        *"'$HM_GNOME_KB_PATH'"*)
            gsettings get "$HM_GNOME_KB_SCHEMA.custom-keybinding:$HM_GNOME_KB_PATH" binding | tr -d "'" ;;
    esac
}
