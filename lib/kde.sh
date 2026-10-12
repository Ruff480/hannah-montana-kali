# shellcheck shell=bash
# KDE Plasma (kali-desktop-kde). The Hannah Montana Linux theme is a Plasma
# theme at heart, so this path uses the upstream look-and-feel package as-is.

kread() {
    if have kreadconfig6; then kreadconfig6 "$@"; elif have kreadconfig5; then kreadconfig5 "$@"; fi
}
kwrite() {
    if have kwriteconfig6; then kwriteconfig6 "$@"; elif have kwriteconfig5; then kwriteconfig5 "$@"; fi
}

kde_plasma_major() {
    if have plasmashell; then
        plasmashell --version 2>/dev/null | awk '{ split($2, v, "."); print v[1]; exit }'
    elif have kwriteconfig6; then echo 6
    else echo 5
    fi
}

# Run a Plasma scripting snippet and print what it print()s.
kde_eval() {
    if have qdbus6; then qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
    elif have qdbus; then qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
    elif have gdbus; then
        gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
            --method org.kde.PlasmaShell.evaluateScript "$1" | sed -E "s/^\\('(.*)',\\)$/\\1/"
    fi 2>/dev/null
}

kde_current_wallpaper() {
    kde_eval "var d = desktops()[0]; d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; print(d.readConfig('Image'));" |
        head -n1 | sed 's|^file://||'
}

kde_changeicons() {
    local helper
    for helper in /usr/lib/*/libexec/plasma-changeicons /usr/libexec/plasma-changeicons /usr/lib/libexec/plasma-changeicons; do
        [ -x "$helper" ] && { "$helper" "$1"; return; }
    done
    kwrite --file kdeglobals --group Icons --key Theme "$1"
}

kde_save() { # kde_save <key> <value-or-empty>
    snap_put kde "$1" "${2:-$HM_UNSET}"
}

kde_on() {
    have plasma-apply-lookandfeel || die "plasma-apply-lookandfeel not found; is KDE Plasma installed?"
    snap_reset kde
    kde_save lnf       "$(kread --file kdeglobals --group KDE --key LookAndFeelPackage)"
    kde_save colors    "$(kread --file kdeglobals --group General --key ColorScheme)"
    kde_save icons     "$(kread --file kdeglobals --group Icons --key Theme)"
    kde_save plasma    "$(kread --file plasmarc --group Theme --key name)"
    kde_save splash    "$(kread --file ksplashrc --group KSplash --key Theme)"
    kde_save lock      "$(kread --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image)"
    kde_save wallpaper "$(kde_current_wallpaper)"

    # Applies colours, Plasma style, icons and splash; leaves the panel layout alone.
    plasma-apply-lookandfeel -a "$HM_KDE_LNF" >/dev/null
    # Be explicit about the pieces in case the look-and-feel skipped any.
    have plasma-apply-colorscheme && plasma-apply-colorscheme "$HM_KDE_COLORS" >/dev/null
    have plasma-apply-desktoptheme && plasma-apply-desktoptheme "$HM_KDE_PLASMA" >/dev/null
    kde_changeicons "$HM_ICON_THEME"
    have plasma-apply-wallpaperimage && plasma-apply-wallpaperimage "$HM_WALLPAPER" >/dev/null
    kwrite --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$HM_LOCKSCREEN"

    qterm_on kde
}

kde_restore_one() {
    local key="$1" val="$2"
    # An empty/unset value means "whatever the look-and-feel provides", which
    # restoring "lnf" (always the first entry) has already taken care of.
    [ "$val" = "$HM_UNSET" ] && val=""
    case "$key" in
        lnf)       [ -n "$val" ] || val="$(kread --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage)"
                   plasma-apply-lookandfeel -a "${val:-org.kde.breeze.desktop}" >/dev/null ;;
        colors)    [ -n "$val" ] && have plasma-apply-colorscheme && plasma-apply-colorscheme "$val" >/dev/null ;;
        plasma)    [ -n "$val" ] && have plasma-apply-desktoptheme && plasma-apply-desktoptheme "$val" >/dev/null ;;
        icons)     [ -n "$val" ] && kde_changeicons "$val" ;;
        splash)    [ -n "$val" ] && kwrite --file ksplashrc --group KSplash --key Theme "$val" ;;
        lock)      if [ -n "$val" ]; then
                       kwrite --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "$val"
                   else
                       kwrite --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --delete
                   fi ;;
        wallpaper) [ -n "$val" ] && have plasma-apply-wallpaperimage && plasma-apply-wallpaperimage "$val" >/dev/null ;;
        qterm*)    qterm_restore "$2" ;;
    esac
    return 0
}

kde_off() {
    have plasma-apply-lookandfeel || die "plasma-apply-lookandfeel not found; is KDE Plasma installed?"
    snap_each kde kde_restore_one
}

# --- Hotkey ---------------------------------------------------------------
# KDE binds global shortcuts to .desktop files. The launcher is installed to
# /usr/share/applications; here we register the key for this user.
HM_KDE_DESKTOP_ID="$HM_NAME-toggle.desktop"

kde_hotkey_on() {
    local key
    key="$(hm_hotkey_kde)"
    if [ "$(kde_plasma_major)" -ge 6 ]; then
        kwrite --file kglobalshortcutsrc --group services --group "$HM_KDE_DESKTOP_ID" --key _launch "$key"
    else
        kwrite --file kglobalshortcutsrc --group "$HM_KDE_DESKTOP_ID" --key _k_friendly_name "Toggle Hannah Montana"
        kwrite --file kglobalshortcutsrc --group "$HM_KDE_DESKTOP_ID" --key _launch "$key,none,Toggle Hannah Montana"
    fi
    warn "KDE reads new global shortcuts at login: log out and back in once for $key to work."
}

kde_hotkey_off() {
    kwrite --file kglobalshortcutsrc --group services --group "$HM_KDE_DESKTOP_ID" --key _launch --delete 2>/dev/null
    kwrite --file kglobalshortcutsrc --group "$HM_KDE_DESKTOP_ID" --key _launch --delete 2>/dev/null
    kwrite --file kglobalshortcutsrc --group "$HM_KDE_DESKTOP_ID" --key _k_friendly_name --delete 2>/dev/null
    return 0
}

kde_hotkey_status() {
    local v
    v="$(kread --file kglobalshortcutsrc --group services --group "$HM_KDE_DESKTOP_ID" --key _launch)"
    [ -n "$v" ] || v="$(kread --file kglobalshortcutsrc --group "$HM_KDE_DESKTOP_ID" --key _launch | cut -d, -f1)"
    [ -n "$v" ] && printf '%s\n' "$v"
}
