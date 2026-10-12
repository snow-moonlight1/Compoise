#!/usr/bin/env bash
# Package the Flutter Linux release bundle as DEB, RPM and AppImage.
#   scripts/ci/package_linux.sh <bundle-dir> <version> <out-dir>
# Needs: fpm, rpmbuild, ImageMagick (convert), appimagetool on PATH.
set -euo pipefail
bundle="$(cd "$1" && pwd)"; version="$2"; out="$3"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
test -x "$bundle/compoise"
test -f "$bundle/lib/libcompoise_ocr.so" || { echo "OCR runtime missing from bundle" >&2; exit 1; }
work="$(mktemp -d)"
appid=com.compoise.app
icon="$work/$appid.png"
convert "$repo/assets/branding/CompoiseLogo.png" -resize 256x256 "$icon"
desktop="$work/$appid.desktop"
cat > "$desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Compoise
Name[zh_CN]=方寸
Comment=Local-first Eisenhower matrix and day planner
Exec=compoise
Icon=$appid
Terminal=false
Categories=Office;ProjectManagement;
StartupWMClass=$appid
DESK

# Shared filesystem layout for DEB and RPM.
root="$work/root"
mkdir -p "$root/opt/compoise" "$root/usr/bin" "$root/usr/share/applications" \
  "$root/usr/share/icons/hicolor/256x256/apps" "$root/usr/share/doc/compoise"
cp -a "$bundle/." "$root/opt/compoise/"
ln -s /opt/compoise/compoise "$root/usr/bin/compoise"
cp "$desktop" "$root/usr/share/applications/"
cp "$icon" "$root/usr/share/icons/hicolor/256x256/apps/"
cp "$repo/LICENSE" "$root/usr/share/doc/compoise/copyright"

common=(-s dir -C "$root" -n compoise -v "$version" --license GPL-3.0-only
  --maintainer "Compoise contributors" --url https://github.com/snow-moonlight1/Compoise
  --description "Compoise (方寸): local-first Eisenhower matrix task manager and day planner"
  -a amd64)
fpm "${common[@]}" -t deb -p "$out/compoise-$version-linux-amd64.deb" \
  -d 'libgtk-3-0t64 | libgtk-3-0' -d 'libsecret-1-0' -d 'libayatana-appindicator3-1' \
  --deb-recommends 'fonts-noto-cjk' --deb-recommends 'gnome-keyring' .
fpm "${common[@]}" -a x86_64 -t rpm -p "$out/compoise-$version-linux-x86_64.rpm" \
  --rpm-os linux -d 'gtk3' -d 'libsecret' -d 'libayatana-appindicator-gtk3' \
  --rpm-tag 'Recommends: google-noto-sans-cjk-fonts' .

# AppImage: bundles the app only; GTK, libsecret and appindicator come from the host.
appdir="$work/Compoise.AppDir"
mkdir -p "$appdir/usr/bin"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$desktop" "$appdir/"
cp "$icon" "$appdir/"
cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/bin/compoise" "$@"
RUN
chmod +x "$appdir/AppRun"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 appimagetool "$appdir" "$out/compoise-$version-linux-x86_64.AppImage"
ls -l "$out"
