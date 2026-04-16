# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson

DESCRIPTION="SSH/SFTP library based on libfilezilla"
HOMEPAGE="https://fzssh.filezilla-project.org/"
SRC_URI="https://distfiles.obentoo.org/${P}.tar.xz"

LICENSE="AGPL-3+"
SLOT="0/10"
KEYWORDS="~amd64 ~arm ~arm64 ~ppc ~ppc64 ~riscv ~x86"

RDEPEND="
	>=dev-libs/libfilezilla-0.55.3:=
	>=dev-libs/nettle-3.10:=
	dev-libs/gmp:=
	app-crypt/argon2
"
DEPEND="${RDEPEND}"
BDEPEND="virtual/pkgconfig"

src_configure() {
	local emesonargs=(
		-Dwith_server=false
	)
	meson_src_configure
}
