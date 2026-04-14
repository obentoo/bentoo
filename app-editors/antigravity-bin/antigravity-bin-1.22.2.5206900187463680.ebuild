EAPI=8

inherit bash-completion-r1 desktop xdg

DESCRIPTION="Google Antigravity AI-driven IDE (binary release)"
HOMEPAGE="https://antigravity.google/"

MY_PV="${PV%.*}-${PV##*.}"
SRC_URI="amd64? ( https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${MY_PV}/linux-x64/Antigravity.tar.gz -> ${PN}-${MY_PV}.tar.gz )"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="bindist mirror strip"

RDEPEND="
  app-accessibility/at-spi2-core
  app-crypt/libsecret
  dev-libs/glib
  dev-libs/nss
  media-libs/alsa-lib
  media-libs/libpng
  net-print/cups
  x11-libs/gtk+:3
  x11-libs/libX11
  x11-libs/libXcursor
  x11-libs/libXdamage
  x11-libs/libXext
  x11-libs/libXfixes
  x11-libs/libXi
  x11-libs/libXrandr
  x11-libs/libXrender
  x11-libs/libXScrnSaver
  x11-libs/libXtst
  x11-libs/pango
  x11-misc/xdg-utils
"
DEPEND="${RDEPEND}"
BDEPEND=""

S="${WORKDIR}/Antigravity"

QA_PREBUILT="*"

src_install() {
  local appdir="/opt/${PN}"

  dodir "${appdir}"
  cp -r "${S}"/. "${ED}${appdir}" || die "Failed to install application files"

  fperms 0755 "${appdir}/antigravity" "${appdir}/bin/antigravity" "${appdir}/chrome_crashpad_handler"
  fperms 4755 "${appdir}/chrome-sandbox"

  dosym "${appdir}/antigravity" /usr/bin/antigravity

  newbashcomp resources/completions/bash/antigravity antigravity
  insinto /usr/share/zsh/site-functions
  newins resources/completions/zsh/_antigravity _antigravity

  newicon resources/app/resources/linux/code.png antigravity.png

  cat > "${T}/${PN}.desktop" <<EOF || die "Failed to write desktop file"
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity IDE
Exec=/usr/bin/antigravity %F
Icon=antigravity
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=antigravity
EOF

  insinto /usr/share/applications
  doins "${T}/${PN}.desktop"

  dodoc resources/app/LICENSE.txt resources/app/ThirdPartyNotices.txt
  }

pkg_postinst() {
  xdg_pkg_postinst
}

pkg_postrm() {
  xdg_pkg_postrm
}
