# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Packages which get releases together:
# app-emacs/nxml-libvirt-schemas
# dev-python/libvirt-python
# dev-perl/Sys-Virt
# app-emulation/libvirt
# Please bump them together!

# Based on ::gentoo's 12.7.0 ebuild, bumped to 12.9.0 to match app-emulation/libvirt-12.9.0
# here: the release pins app-emulation/libvirt:0/${PV}, so 12.7.0 cannot sit next to it.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )
inherit distutils-r1 verify-sig

if [[ ${PV} == *9999* ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://gitlab.com/libvirt/libvirt-python.git"
	RDEPEND="app-emulation/libvirt:="
else
	MY_P="${P/-/_}"
	SRC_URI="https://download.libvirt.org/python/${MY_P}.tar.gz
		verify-sig? ( https://download.libvirt.org/python/${MY_P}.tar.gz.asc )"
	KEYWORDS="~amd64"
	RDEPEND="app-emulation/libvirt:0/${PV}"
	S="${WORKDIR}/${MY_P}"
fi

DESCRIPTION="libvirt Python bindings"
HOMEPAGE="https://www.libvirt.org"

LICENSE="LGPL-2"
SLOT="0"
IUSE="examples test"
RESTRICT="!test? ( test )"

BDEPEND="
	virtual/pkgconfig
	test? (
		dev-python/lxml[${PYTHON_USEDEP}]
	)
	verify-sig? ( >=sec-keys/openpgp-keys-libvirt-20260831 )
"

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/libvirt.asc

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

python_compile() {
	# setuptools is broken for C extensions, bug #907718
	distutils-r1_python_compile -j1
}

python_install_all() {
	if use examples; then
		dodoc -r examples
		docompress -x /usr/share/doc/${PF}/examples
	fi

	distutils-r1_python_install_all
}
