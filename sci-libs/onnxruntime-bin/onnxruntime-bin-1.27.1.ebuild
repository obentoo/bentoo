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
	# Upstream's libonnxruntime.pc and its CMake config both declare
	# includedir=${prefix}/include/onnxruntime, so the headers go there rather
	# than flat into /usr/include.  Installing them flat (as the source ebuild
	# did) leaves every consumer that resolves through pkg-config or
	# find_package() pointing at a directory that does not exist.
	dodir /usr/include/onnxruntime
	cp -R include/. "${ED}"/usr/include/onnxruntime/. || die

	dodir /usr/$(get_libdir)
	cp -R lib/. "${ED}"/usr/$(get_libdir)/. || die

	# The shipped .pc is generated for a /usr/local install and hardcodes
	# lib64.  Left alone, `pkg-config --libs libonnxruntime` emits
	# -L/usr/local/lib64 and the link fails.  Retarget it at the real prefix
	# and libdir.
	sed -i \
		-e "s:^prefix=/usr/local$:prefix=${EPREFIX}/usr:" \
		-e "s:^libdir=\${prefix}/lib64$:libdir=\${prefix}/$(get_libdir):" \
		"${ED}"/usr/$(get_libdir)/pkgconfig/libonnxruntime.pc || die

	einstalldocs
}
