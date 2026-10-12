#!/usr/bin/env bash
# Install the Hannah Montana theme for Kali Linux and bind the toggle hotkey.
#
#   ./install.sh                  # install, bind Super+Shift+H, turn the theme on
#   ./install.sh --system         # ...and theme the login screen, GRUB and boot splash
#   ./install.sh --variant dark --hotkey Ctrl+Alt+H --no-enable
#
# Run it as your normal user; it asks for sudo for the system-wide files.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# The artwork comes from Hannah Montana Linux v26 (a GPLv3+ remaster of the
# original 2009 Hannah Montana Linux), pinned to a known commit.
HML_REPO="https://gitlab.com/DecaCagle/hannahmontanalinux26"
HML_COMMIT="4b3e191027dedea08473d4322dea20faef0855ea"
HML_TARBALL="$HML_REPO/-/archive/$HML_COMMIT/hannahmontanalinux26-$HML_COMMIT.tar.gz?path=config/includes.chroot/usr/share"

PREFIX=/usr/share/hannah-montana-kali
BIN_LINK=/usr/local/bin/hannah-montana-kali

variant=light
hotkey="Super+Shift+H"
want_system=0
want_enable=1
want_hotkey=1
assets=""

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; cat <<EOF

Options:
  --variant light|dark   Pink (default) or purple flavour
  --hotkey KEY           Toggle hotkey, e.g. Super+Shift+H (default), Ctrl+Alt+H
  --system               Also theme LightDM/SDDM, GRUB and Plymouth
  --no-enable            Install and bind the hotkey but leave the theme off
  --no-hotkey            Do not bind a hotkey
  --assets PATH          Use a local Hannah Montana Linux checkout or tarball
                         instead of downloading ($HML_REPO)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --variant)   variant="${2:?}"; shift 2 ;;
        --hotkey)    hotkey="${2:?}"; shift 2 ;;
        --system)    want_system=1; shift ;;
        --no-enable) want_enable=0; shift ;;
        --no-hotkey) want_hotkey=0; shift ;;
        --assets)    assets="${2:?}"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$variant" in light|dark) ;; *) echo "--variant must be light or dark" >&2; exit 2 ;; esac

say()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; command -v sudo >/dev/null || die "sudo is required"; fi

if [ -r /etc/os-release ] && ! grep -qi kali /etc/os-release; then
    say "This isn't Kali, but any Debian-based XFCE/KDE/GNOME system should work. Carrying on."
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. Get the Hannah Montana Linux assets -------------------------------
fetch_assets() {
    local tarball="$work/hml.tar.gz"
    if [ -n "$assets" ]; then
        if [ -d "$assets" ]; then echo "$assets"; return; fi
        tarball="$assets"
    else
        command -v curl >/dev/null || die "curl is required (sudo apt install curl)"
        say "Downloading Hannah Montana Linux artwork (~60 MB) from GitLab..." >&2
        curl -fL --retry 3 --progress-bar -o "$tarball" "$HML_TARBALL" ||
            die "download failed; fetch $HML_REPO yourself and pass --assets"
    fi
    mkdir -p "$work/src"
    tar -xzf "$tarball" -C "$work/src"
    echo "$work/src"
}

src_root="$(fetch_assets)"
theme_dir="$(find "$src_root" -type d -path '*/desktop-base/hannah-montana-theme' -print -quit)"
[ -n "$theme_dir" ] || die "could not find Hannah Montana Linux assets in $src_root"
share="$(dirname "$(dirname "$theme_dir")")"   # .../usr/share
for need in icons/HannahMontana color-schemes/PrettyPink.colors plasma/look-and-feel/org.hml.desktop; do
    [ -e "$share/$need" ] || die "assets incomplete: missing $need"
done

# --- 2. Stage everything into a tree that mirrors / -----------------------
say "Preparing theme files"
stage="$work/stage"
mkdir -p "$stage$PREFIX" "$stage/usr/share/icons" "$stage/usr/share/themes" \
         "$stage/usr/share/color-schemes" "$stage/usr/share/plasma/desktoptheme" \
         "$stage/usr/share/plasma/look-and-feel" "$stage/usr/share/wallpapers" \
         "$stage/usr/share/sddm/themes" "$stage/usr/share/plymouth/themes" \
         "$stage/usr/share/applications" "$stage/usr/share/kglobalaccel" \
         "$stage/etc/xdg/autostart" \
         "$stage/usr/share/qtermwidget5/color-schemes" "$stage/usr/share/qtermwidget6/color-schemes"

# The toggle script and its libraries
cp -r "$REPO_DIR/bin" "$REPO_DIR/lib" "$stage$PREFIX/"
chmod 755 "$stage$PREFIX/bin/hannah-montana-kali"

# Wallpapers, lock screen, login and GRUB backgrounds
cp -r "$theme_dir/wallpaper/contents/images" "$stage$PREFIX/wallpaper"
cp -r "$theme_dir/lockscreen/contents/images" "$stage$PREFIX/lockscreen"
cp -r "$theme_dir/login" "$stage$PREFIX/login"
mkdir -p "$stage$PREFIX/grub"
cp "$theme_dir/grub/"*.png "$stage$PREFIX/grub/"
# Small logo for notifications and the launcher
icon="$(find "$share/icons/HannahMontana" -name 'start-here*.png' -print -quit)"
cp "${icon:-$theme_dir/wallpaper/contents/images/1920x1080.png}" "$stage$PREFIX/H.png"

# Icon themes: upstream falls back to Breeze only, which XFCE Kali lacks.
for t in HannahMontana HannahMontanaDark; do
    cp -r "$share/icons/$t" "$stage/usr/share/icons/$t"
    sed -i 's/^Inherits=.*/Inherits=breeze,Flat-Remix-Blue-Dark,Adwaita,hicolor/' "$stage/usr/share/icons/$t/index.theme"
done

# GTK themes (built here from our CSS, since HML is a Qt/Plasma theme)
for v in light dark; do
    name=HannahMontana; [ "$v" = dark ] && name=HannahMontanaDark
    d="$stage/usr/share/themes/$name"
    mkdir -p "$d/gtk-3.0"
    cat "$REPO_DIR/themes/gtk/$v.css" "$REPO_DIR/themes/gtk/hannah.css" > "$d/gtk-3.0/gtk.css"
    cat > "$d/index.theme" <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=$name
Comment=Hannah Montana for Kali ($v)
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=$name
IconTheme=$name
EOF
done

# Plasma: colours, Plasma style, global theme, wallpaper package
cp "$share/color-schemes/"PrettyPink*.colors "$stage/usr/share/color-schemes/"
cp -r "$share/plasma/desktoptheme/"hannah-montana-theme* "$stage/usr/share/plasma/desktoptheme/"
cp -r "$share/plasma/look-and-feel/"org.hml*.desktop "$stage/usr/share/plasma/look-and-feel/"
cp -r "$theme_dir/wallpaper" "$stage/usr/share/wallpapers/HannahMontanaTheme"

# Login / boot themes (only switched on by "system on")
cp -r "$share/sddm/themes/hannah-montana-sddm" "$stage/usr/share/sddm/themes/"
cp -r "$share/plymouth/themes/hannah-montana" "$stage/usr/share/plymouth/themes/"

# QTerminal colour scheme (Qt5 and Qt6 builds look in different places)
cp "$REPO_DIR/themes/qterminal/HannahMontana.colorscheme" "$stage/usr/share/qtermwidget5/color-schemes/"
cp "$REPO_DIR/themes/qterminal/HannahMontana.colorscheme" "$stage/usr/share/qtermwidget6/color-schemes/"

# Launcher (also what KDE binds the shortcut to) and login hook
sed "s/^X-KDE-Shortcuts=.*/X-KDE-Shortcuts=$(HM_HOTKEY="$hotkey" HM_CONFIG_FILE=/dev/null bash -c ". '$REPO_DIR/lib/common.sh'; hm_hotkey_kde")/" \
    "$REPO_DIR/share/hannah-montana-kali-toggle.desktop" > "$stage/usr/share/applications/hannah-montana-kali-toggle.desktop"
cp "$stage/usr/share/applications/hannah-montana-kali-toggle.desktop" "$stage/usr/share/kglobalaccel/"
cp "$REPO_DIR/share/hannah-montana-kali-autostart.desktop" "$stage/etc/xdg/autostart/hannah-montana-kali.desktop"

printf 'HML_REPO=%s\nHML_COMMIT=%s\n' "$HML_REPO" "$HML_COMMIT" > "$stage$PREFIX/VERSION"
cp "$REPO_DIR/uninstall.sh" "$stage$PREFIX/uninstall.sh"
chmod 755 "$stage$PREFIX/uninstall.sh"

# Manifest of top-level paths we own, for uninstall.sh
(
    cd "$stage"
    find . -mindepth 1 \( -path ./usr/share/hannah-montana-kali -o -path './usr/share/icons/*' \
        -o -path './usr/share/themes/*' -o -path './usr/share/plasma/*/*' -o -path './usr/share/wallpapers/*' \
        -o -path './usr/share/sddm/themes/*' -o -path './usr/share/plymouth/themes/*' -o -type f \) -prune -print |
        sed 's|^\.||' | sort
    echo "$BIN_LINK"
) > "$stage$PREFIX/manifest"

# --- 3. Install ------------------------------------------------------------
say "Installing files${SUDO:+ (sudo)}"
D="${DESTDIR:-}"   # DESTDIR is for packaging/testing; normally empty
$SUDO mkdir -p "$D/usr/local/bin"
$SUDO cp -r --no-preserve=ownership "$stage/." "$D/"
# Normalise permissions whatever the umask was (theme dirs must be world-readable).
grep -v "^$BIN_LINK\$" "$stage$PREFIX/manifest" | while read -r p; do
    $SUDO chmod -R u=rwX,go=rX "$D$p"
done
$SUDO chmod 755 "$D$PREFIX/bin/hannah-montana-kali" "$D$PREFIX/uninstall.sh"
$SUDO ln -sf "$PREFIX/bin/hannah-montana-kali" "$D$BIN_LINK"
if command -v gtk-update-icon-cache >/dev/null; then
    for t in HannahMontana HannahMontanaDark; do
        $SUDO gtk-update-icon-cache -q -f -t "$D/usr/share/icons/$t" || true
    done
fi

# --- 4. Per-user setup ----------------------------------------------------
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hannah-montana-kali/config"
if [ -n "$D" ]; then
    say "Staged into $D; skipping per-user and system setup."
    exit 0
elif [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    say "Installed. Run these as $SUDO_USER (not root) inside the desktop session:"
    echo "    hannah-montana-kali hotkey on --key $hotkey && hannah-montana-kali on"
    echo "  (the hotkey is also bound automatically at the next login)"
else
    mkdir -p "$(dirname "$cfg")"
    printf 'HM_VARIANT=%q\nHM_HOTKEY=%q\n' "$variant" "$hotkey" > "$cfg"
    if [ "$want_hotkey" -eq 1 ]; then
        "$BIN_LINK" hotkey on --key "$hotkey" ||
            say "Couldn't bind the hotkey from here (no desktop session?). It will be bound at next login."
    else
        "$BIN_LINK" hotkey off >/dev/null 2>&1 || true
    fi
    if [ "$want_enable" -eq 1 ]; then
        "$BIN_LINK" on || say "Couldn't switch the theme on from here; press $hotkey once you're logged in."
    fi
fi

if [ "$want_system" -eq 1 ]; then
    $SUDO env HM_VARIANT="$variant" "$BIN_LINK" system on
fi

say "Done! Press $hotkey to switch between Kali and Hannah Montana."
say "More: hannah-montana-kali --help"
