# Hannah Montana Linux artwork

Everything under `usr/share/` here is copied unmodified from
[Hannah Montana Linux v26](https://gitlab.com/DecaCagle/hannahmontanalinux26) by Noah Cagle,
`config/includes.chroot/usr/share/` at commit
`4b3e191027dedea08473d4322dea20faef0855ea` (2026-08-04).

The only things left out are two symlinks that point outside this tree, the Calamares installer
launcher and a wallpaper symlink that `install.sh` recreates as a real copy.

Licence: GNU GPL v3 or later (see `LICENSE` in this folder). Parts of it are derived from KDE Breeze.

To update, replace `usr/share/` with the same folder from a newer upstream commit and change the
hash above.
