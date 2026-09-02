#!/usr/bin/env bash
#
# Lays out the file tree the Linux packages are built from, so the DEB and the RPM contain the same
# thing: the binary, the desktop entry that puts the application in the launcher, and the themed
# icons that entry names.
#
# The icons go in as an icon *theme* rather than as one file the desktop entry points at: hicolor is
# where every desktop looks, and installing each size lets the dock, the app grid and the window
# switcher pick the one they need. Refreshing the icon cache and the desktop database afterwards is
# left to the package manager - dpkg and rpm both run those through triggers when
# desktop-file-utils/hicolor-icon-theme are present, and there is nothing to refresh when they
# are not.
#
# Usage: package-tree.sh <built-binary> <package-dir> [app-name]

set -euo pipefail

binary=${1:?usage: package-tree.sh <built-binary> <package-dir> [app-name]}
package_dir=${2:?usage: package-tree.sh <built-binary> <package-dir> [app-name]}
app_name=${3:-euclid-rui}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
branding="$here/../branding"

# Installed under the package name rather than the build's ("euclid_rui"), since that is the name
# the desktop entry's Exec= and StartupWMClass= both assume.
install -D -m 755 "$binary" "$package_dir/usr/bin/$app_name"
install -D -m 644 "$here/$app_name.desktop" "$package_dir/usr/share/applications/$app_name.desktop"

# The scalable icon is the one most desktops prefer; the bitmaps are what the rest fall back to.
install -D -m 644 "$branding/euclid-icon.svg" "$package_dir/usr/share/icons/hicolor/scalable/apps/$app_name.svg"
for size in 16 24 32 64 256 512; do
    install -D -m 644 "$branding/euclid-$size.png" \
        "$package_dir/usr/share/icons/hicolor/${size}x${size}/apps/$app_name.png"
done

echo "Packaged tree under $package_dir:"
find "$package_dir" -type f | sort
