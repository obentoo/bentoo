# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit java-vm-2 toolchain-funcs

# Hash from the official download URL
MY_HASH="c3cc523845074aa0af4f5e1e1ed4151d"
MY_PV="${PV%_p*}"
MY_BUILD="${PV#*_p}"
BASEURI="https://download.java.net/java/GA/jdk${MY_PV}/${MY_HASH}/${MY_BUILD}/GPL"

DESCRIPTION="Prebuilt Java JDK binaries provided by the official OpenJDK project"
HOMEPAGE="https://jdk.java.net"
SRC_URI="
	amd64? ( ${BASEURI}/openjdk-${MY_PV}_linux-x64_bin.tar.gz )
	arm64? ( ${BASEURI}/openjdk-${MY_PV}_linux-aarch64_bin.tar.gz )
"
S="${WORKDIR}/jdk-${MY_PV}"

LICENSE="GPL-2-with-classpath-exception"
SLOT="${MY_PV}"
KEYWORDS="-* ~amd64 ~arm64"

IUSE="alsa cups headless-awt selinux source"

RDEPEND="
	>=sys-apps/baselayout-java-0.1.0-r1
	media-libs/fontconfig:1.0
	media-libs/freetype:2
	media-libs/harfbuzz
	elibc_glibc? ( >=sys-libs/glibc-2.2.5:* )
	virtual/zlib:=
	alsa? ( media-libs/alsa-lib )
	cups? ( net-print/cups )
	selinux? ( sec-policy/selinux-java )
	!headless-awt? (
		x11-libs/libX11
		x11-libs/libXext
		x11-libs/libXi
		x11-libs/libXrender
		x11-libs/libXtst
	)
"

RESTRICT="preserve-libs splitdebug"
QA_PREBUILT="*"

pkg_pretend() {
	if [[ "$(tc-is-softfloat)" != "no" ]]; then
		die "These binaries require a hardfloat system."
	fi
}

src_install() {
	local dest="/opt/${P}"
	local ddest="${ED}/${dest#/}"

	# https://bugs.gentoo.org/922741
	docompress "${dest}/man"

	# prefer system copy
	rm -vf lib/libfreetype.so || die
	rm -vf lib/libharfbuzz.so || die

	if ! use alsa ; then
		rm -v lib/libjsound.* || die
	fi

	if use headless-awt ; then
		rm -fv lib/lib*{[jx]awt,splashscreen}* || die
	fi

	if ! use source ; then
		rm -v lib/src.zip || die
	fi

	rm -v lib/security/cacerts || die
	dosym -r /etc/ssl/certs/java/cacerts "${dest}"/lib/security/cacerts

	dodir "${dest}"
	cp -pPR * "${ddest}" || die

	# provide stable symlink
	dosym "${P}" "/opt/${PN}-${SLOT}"

	java-vm_install-env "${FILESDIR}"/${PN}.env.sh
	java-vm_set-pax-markings "${ddest}"
	java-vm_revdep-mask
	java-vm_sandbox-predict /dev/random /proc/self/coredump_filter
}

pkg_postinst() {
	java-vm-2_pkg_postinst
}
