# shellcheck shell=bash
# System-wide pieces that need root and only show up outside a desktop
# session: the login screen, GRUB menu and boot splash. These are switched
# with "sudo hannah-montana-kali system on|off", not by the hotkey.

HM_SYS_STATE_DIR="${HM_SYS_STATE_DIR:-/var/lib/$HM_NAME}"
HM_LIGHTDM_CONF="${HM_LIGHTDM_CONF:-/etc/lightdm/lightdm-gtk-greeter.conf}"
HM_SDDM_DROPIN="${HM_SDDM_DROPIN:-/etc/sddm.conf.d/zz-hannah-montana.conf}"
HM_GRUB_DROPIN="${HM_GRUB_DROPIN:-/etc/default/grub.d/zz-hannah-montana.cfg}"
HM_GRUB_IMAGE="/boot/grub/hannah-montana.png"

sys_require_root() { [ "$(id -u)" -eq 0 ] || die "system mode needs root: sudo $HM_NAME system $*"; }

sys_with_state() { HM_STATE_DIR="$HM_SYS_STATE_DIR" "$@"; }

# -- LightDM GTK greeter (Kali XFCE) ---------------------------------------
# /etc/lightdm/lightdm-gtk-greeter.conf wins over every drop-in, and Kali
# sets its background there, so edit it in place and remember the old values.
lightdm_on() {
    [ -e "$HM_LIGHTDM_CONF" ] || return 0
    local kv k v old
    snap_reset lightdm
    for kv in "background=$HM_PREFIX/login/background.png" \
              "theme-name=$HM_GTK_THEME" \
              "icon-theme-name=$HM_ICON_THEME" \
              "user-background=false"; do
        k="${kv%%=*}"; v="${kv#*=}"
        old="$(ini_get "$HM_LIGHTDM_CONF" greeter "$k")" || old="$HM_UNSET"
        snap_put lightdm "$k" "$old"
        ini_set "$HM_LIGHTDM_CONF" greeter "$k" "$v"
    done
    log "LightDM greeter themed"
}

lightdm_restore_one() {
    if [ "$2" = "$HM_UNSET" ]; then ini_del "$HM_LIGHTDM_CONF" greeter "$1"
    else ini_set "$HM_LIGHTDM_CONF" greeter "$1" "$2"
    fi
}

lightdm_off() {
    [ -e "$(hm_snapshot_file lightdm)" ] || return 0
    snap_each lightdm lightdm_restore_one
    rm -f "$(hm_snapshot_file lightdm)"
    log "LightDM greeter restored"
}

# -- SDDM (Kali KDE) -------------------------------------------------------
sddm_on() {
    [ -d /etc/sddm.conf.d ] || have sddm || return 0
    [ -d /usr/share/sddm/themes/hannah-montana-sddm ] || return 0
    mkdir -p "$(dirname "$HM_SDDM_DROPIN")"
    printf '[Theme]\nCurrent=hannah-montana-sddm\n' > "$HM_SDDM_DROPIN"
    if ini_get /etc/sddm.conf Theme Current >/dev/null 2>&1; then
        warn "/etc/sddm.conf sets [Theme] Current itself and overrides drop-ins; edit it to use hannah-montana-sddm."
    fi
    log "SDDM themed"
}
sddm_off() { [ -e "$HM_SDDM_DROPIN" ] && rm -f "$HM_SDDM_DROPIN" && log "SDDM restored"; return 0; }

# -- GRUB ------------------------------------------------------------------
grub_on() {
    have update-grub || return 0
    install -Dm644 "$HM_PREFIX/grub/grub-16x9.png" "$HM_GRUB_IMAGE"
    mkdir -p "$(dirname "$HM_GRUB_DROPIN")"
    cat > "$HM_GRUB_DROPIN" <<EOF
# Added by $HM_NAME. Remove with: sudo $HM_NAME system off
# Kali's GRUB theme would hide the background, so switch it off.
unset GRUB_THEME
GRUB_BACKGROUND="$HM_GRUB_IMAGE"
GRUB_COLOR_NORMAL="white/black"
GRUB_COLOR_HIGHLIGHT="magenta/black"
EOF
    update-grub >/dev/null 2>&1 || warn "update-grub failed; run it by hand to see why"
    log "GRUB themed"
}
grub_off() {
    [ -e "$HM_GRUB_DROPIN" ] || return 0
    rm -f "$HM_GRUB_DROPIN" "$HM_GRUB_IMAGE"
    update-grub >/dev/null 2>&1 || warn "update-grub failed; run it by hand to see why"
    log "GRUB restored"
}

# -- Plymouth boot splash --------------------------------------------------
plymouth_on() {
    have plymouth-set-default-theme || return 0
    [ -d /usr/share/plymouth/themes/hannah-montana ] || return 0
    local cur
    cur="$(plymouth-set-default-theme 2>/dev/null)"
    if [ "$cur" != hannah-montana ]; then
        mkdir -p "$HM_SYS_STATE_DIR"
        printf '%s\n' "$cur" > "$HM_SYS_STATE_DIR/plymouth.prev"
    fi
    log "Setting Plymouth theme (rebuilds the initramfs, give it a minute)..."
    plymouth-set-default-theme -R hannah-montana >/dev/null || warn "plymouth-set-default-theme failed"
    grep -qw splash /proc/cmdline 2>/dev/null ||
        warn "the kernel command line has no 'splash'; add it to GRUB_CMDLINE_LINUX_DEFAULT to see the boot splash."
}
plymouth_off() {
    [ -r "$HM_SYS_STATE_DIR/plymouth.prev" ] || return 0
    local prev
    prev="$(cat "$HM_SYS_STATE_DIR/plymouth.prev")"
    log "Restoring Plymouth theme '${prev:-default}'..."
    if [ -n "$prev" ]; then plymouth-set-default-theme -R "$prev" >/dev/null
    else plymouth-set-default-theme -r -R >/dev/null
    fi || warn "plymouth-set-default-theme failed"
    rm -f "$HM_SYS_STATE_DIR/plymouth.prev"
}

system_on() {
    sys_require_root on
    if [ -e "$HM_SYS_STATE_DIR/state" ] && [ "$(cat "$HM_SYS_STATE_DIR/state")" = on ]; then
        log "system theme is already on"; return 0
    fi
    sys_with_state lightdm_on
    sddm_on
    grub_on
    plymouth_on
    sys_with_state hm_state_set on
}

system_off() {
    sys_require_root off
    sys_with_state lightdm_off
    sddm_off
    grub_off
    plymouth_off
    sys_with_state hm_state_set off
}

system_status() {
    printf 'system theme: %s\n' "$(cat "$HM_SYS_STATE_DIR/state" 2>/dev/null || echo off)"
}
