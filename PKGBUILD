# Maintainer: Rochi <rochi787@gmail.com.com>
pkgname=restic-gui
pkgver=0.1.2
pkgrel=1
pkgdesc="GTK4 + libadwaita desktop app for managing restic repositories, scheduled backups, and snapshots"
arch=('x86_64' 'aarch64')
url="https://github.com/Rochi787/Restic-GUI"
license=('MIT')
depends=('gtk4' 'libadwaita' 'json-glib' 'libsecret' 'glib2' 'restic')
makedepends=('vala' 'meson' 'ninja')
optdepends=(
  'gnome-keyring: Secret Service provider for storing repo passwords (non-GNOME desktops)'
  'cronie: cron scheduling backend support'
)

# --- Local build (this variant) ---
# This PKGBUILD assumes it lives in the repo root next to meson.build and
# builds straight from that source tree — no download, no AUR needed yet.
# See the bottom of this file for the two changes needed to instead pull
# from a GitHub release tarball or git, for AUR publishing.
source=()
sha256sums=()

build() {
  arch-meson "$startdir" build
  meson compile -C build
}

package() {
  meson install -C build --destdir "$pkgdir"
  install -Dm644 "$startdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}

# --- To publish on the AUR instead, swap the block above for ONE of: ---
#
# (A) Tagged GitHub releases (recreate this PKGBUILD per release):
#   source=("$pkgname-$pkgver.tar.gz::https://github.com/Rochi787/Restic-GUI/archive/refs/tags/v$pkgver.tar.gz")
#   sha256sums=('REPLACE_WITH_REAL_CHECKSUM')
#   build()   { cd "Restic-GUI-$pkgver"; arch-meson . build; meson compile -C build; }
#   package() { cd "Restic-GUI-$pkgver"; meson install -C build --destdir "$pkgdir"; install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"; }
#
# (B) Always-latest "-git" VCS package (common for AUR while there are no tags yet):
#   pkgname=restic-gui-git
#   provides=('restic-gui')
#   conflicts=('restic-gui')
#   makedepends+=('git')
#   source=("$pkgname::git+https://github.com/Rochi787/Restic-GUI.git")
#   sha256sums=('SKIP')
#   pkgver() { cd "$pkgname"; git describe --long --tags 2>/dev/null | sed 's/^v//;s/-/.r/;s/-/./' || printf "0.1.0.r%s.g%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"; }
#   build()   { cd "$pkgname"; arch-meson . build; meson compile -C build; }
#   package() { cd "$pkgname"; meson install -C build --destdir "$pkgdir"; install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"; }
