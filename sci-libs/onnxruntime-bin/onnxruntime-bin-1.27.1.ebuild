# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="${PN%-bin}"

DESCRIPTION="Cross-platform, high performance ML inferencing and training accelerator"
HOMEPAGE="
	https://onnxruntime.ai
	https://github.com/microsoft/onnxruntime
"
SRC_URI="
	amd64? (
		https://github.com/microsoft/onnxruntime/releases/download/v${PV}/${MY_PN}-linux-x64-${PV}.tgz
	)
	arm64? (
		https://github.com/microsoft/onnxruntime/releases/download/v${PV}/${MY_PN}-linux-aarch64-${PV}.tgz
	)
"
S="${WORKDIR}/${P}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# Verified with `readelf -d` on 1.27.1 (both x64 and aarch64): the DT_NEEDED
# set is libdl, librt, libpthread, libstdc++, libm, libgcc_s, libc, ld-linux.
# Everything but libstdc++/libgcc_s comes from libc, so only gcc is named here.
# Note these are glibc-linked binaries and cannot work against musl; ::gentoo
# handles that class of package with a musl profile mask rather than an
# RDEPEND on sys-libs/glibc, which would be unsolvable on musl profiles.
RDEPEND="
	sys-devel/gcc:*
"

DOCS="
	README.md
	Privacy.md
	ThirdPartyNotices.txt
	LICENSE
"

# Upstream ships the shared objects already stripped; do not let portage
# rewrite prebuilt binaries we cannot rebuild.
QA_PREBUILT="
	usr/lib*/lib*.so*
"
RESTRICT="strip"

src_unpack() {
	unpack ${A}
	mv "${WORKDIR}"/${MY_PN}-linux-* "${S}" || die
}

src_install() {
	dodir /usr/include
	cp -R include/. "${ED}"/usr/include/. || die

	dodir /usr/$(get_libdir)
	cp -R lib/. "${ED}"/usr/$(get_libdir)/. || die

	einstalldocs
}
