#!/usr/bin/env bash
# Offline tests: toggles the theme on a fake XFCE (xfconf stub) and checks
# that "off" restores every setting exactly, plus hotkey binding and helpers.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

export PATH="$here/fake-bin:$PATH"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
export FAKE_XFCONF="$tmp/xfconf" XDG_CURRENT_DESKTOP=XFCE
export HM_PREFIX="$tmp/prefix"
mkdir -p "$HOME" "$HM_PREFIX/wallpaper" "$HM_PREFIX/lockscreen"
touch "$HM_PREFIX/wallpaper/1920x1080.png" "$HM_PREFIX/lockscreen/1920x1080.png"
hm="$root/bin/hannah-montana-kali"

fails=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
    else printf '  FAIL %s\n       expected: %q\n       actual:   %q\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}
xq() { xfconf-query -c "$1" -p "$2" 2>/dev/null || echo "<unset>"; }

echo "Kali-like starting point"
xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Kali-Dark
xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s Flat-Remix-Blue-Dark
xfconf-query -c xfwm4 -p /general/theme -n -t string -s Kali-Dark
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorVirtual1/workspace0/last-image -n -t string -s /usr/share/backgrounds/kali-16x9/default
xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -n -t uint -s 1
mkdir -p "$XDG_CONFIG_HOME/qterminal.org"
printf '[General]\nfontSize=11\ncolorScheme=Kali-Dark\n\n[Shortcuts]\nCopy=Ctrl+Shift+C\n' > "$XDG_CONFIG_HOME/qterminal.org/qterminal.ini"
cp "$XDG_CONFIG_HOME/qterminal.org/qterminal.ini" "$tmp/qterminal.orig"
before="$(cat "$FAKE_XFCONF"/* | sort)"

echo "toggle -> on"
"$hm" toggle 2>/dev/null
check "state on"        "on xfce light" "$("$hm" status | awk -F':   ' '/^theme/ { print $2 }')"
check "gtk theme"       HannahMontana "$(xq xsettings /Net/ThemeName)"
check "icon theme"      HannahMontana "$(xq xsettings /Net/IconThemeName)"
check "xfwm theme"      Default "$(xq xfwm4 /general/theme)"
check "wallpaper"       "$HM_PREFIX/wallpaper/1920x1080.png" "$(xq xfce4-desktop /backdrop/screen0/monitorVirtual1/workspace0/last-image)"
check "wallpaper style" 5 "$(xq xfce4-desktop /backdrop/screen0/monitorVirtual1/workspace0/image-style)"
check "panel style"     0 "$(xq xfce4-panel /panels/panel-1/background-style)"
check "qterminal"       HannahMontana "$(sed -n 's/^colorScheme=//p' "$XDG_CONFIG_HOME/qterminal.org/qterminal.ini")"

echo "on again is a no-op (snapshot must not be overwritten)"
"$hm" on 2>/dev/null
echo "toggle -> off"
"$hm" toggle 2>/dev/null
check "state off" off "$(cat "$XDG_STATE_HOME/hannah-montana-kali/state")"
check "xfconf restored exactly" "$before" "$(cat "$FAKE_XFCONF"/* | sort)"
check "qterminal.ini restored" "$(cat "$tmp/qterminal.orig")" "$(cat "$XDG_CONFIG_HOME/qterminal.org/qterminal.ini")"

echo "variant dark while on"
"$hm" on 2>/dev/null
"$hm" variant dark 2>/dev/null
check "dark gtk theme" HannahMontanaDark "$(xq xsettings /Net/ThemeName)"
"$hm" off 2>/dev/null
check "restored after variant switch" "$before" "$(cat "$FAKE_XFCONF"/* | sort)"

echo "hotkey"
"$hm" hotkey on 2>/dev/null
check "Super+Shift+H bound" "/usr/local/bin/hannah-montana-kali toggle" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Super><Shift>h')"
"$hm" hotkey on --key Ctrl+Alt+P 2>/dev/null
check "old key removed" "<unset>" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Super><Shift>h')"
check "new key bound" "/usr/local/bin/hannah-montana-kali toggle" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Primary><Alt>p')"
check "status shows key" "<Primary><Alt>p" "$("$hm" status | awk -F':  ' '/^hotkey/ { print $2 }')"
xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>q' -n -t string -s xkill
HM_HOTKEY=Super+Q "$hm" hotkey on --key Super+Q 2>/dev/null
check "won't steal a taken key" xkill "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Super>q')"
check "failed rebind keeps old key" "/usr/local/bin/hannah-montana-kali toggle" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Primary><Alt>p')"
"$hm" hotkey off 2>/dev/null
check "hotkey off" "<unset>" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Primary><Alt>p')"
"$hm" login 2>/dev/null
check "login respects hotkey off" "<unset>" "$(xq xfce4-keyboard-shortcuts '/commands/custom/<Primary><Alt>p')"

echo "hotkey notation"
# shellcheck source=../lib/common.sh
. "$root/lib/common.sh"
HM_HOTKEY=Super+Shift+H; check "gtk"  "<Super><Shift>h" "$(hm_hotkey_gtk)"
HM_HOTKEY=Super+Shift+H; check "kde"  "Meta+Shift+H"    "$(hm_hotkey_kde)"
HM_HOTKEY=ctrl+alt+h;    check "kde2" "Ctrl+Alt+H"      "$(hm_hotkey_kde)"

echo "ini helpers"
f="$tmp/t.ini"; printf '[a]\nx=1\n[greeter]\nbackground=/old.png\n' > "$f"
ini_set "$f" greeter background /new.png; check "replace" /new.png "$(ini_get "$f" greeter background)"
ini_set "$f" greeter theme-name HM;       check "add"     HM "$(ini_get "$f" greeter theme-name)"
ini_set "$f" new k v;                     check "new section" v "$(ini_get "$f" new k)"
ini_del "$f" greeter theme-name;          check "delete" "" "$(ini_get "$f" greeter theme-name)"
check "other section untouched" 1 "$(ini_get "$f" a x)"

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
