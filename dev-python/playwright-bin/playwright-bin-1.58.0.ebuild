# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=no
DISTUTILS_SINGLE_IMPL=1
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1

MY_PN=${PN%-bin}
MY_P=${MY_PN}-${PV}
HOSTED="https://files.pythonhosted.org/packages/py3"

DESCRIPTION="Automate Chromium, Firefox and WebKit browsers with a single API (binary wheel)"
HOMEPAGE="https://github.com/microsoft/playwright-python"
SRC_URI="
	amd64? (
		${HOSTED}/${MY_P:0:1}/${MY_PN}/${MY_P}-py3-none-manylinux1_x86_64.whl
			-> ${MY_P}-amd64.whl.zip
	)
	arm64? (
		${HOSTED}/${MY_P:0:1}/${MY_PN}/${MY_P}-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.whl
			-> ${MY_P}-arm64.whl.zip
	)
"
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

# driver/node is a prebuilt ELF executable: do not strip it or fail QA on it.
QA_PREBUILT="usr/lib/python*/site-packages/playwright/driver/node"
RESTRICT="strip test"

RDEPEND="
	${PYTHON_DEPS}
	!dev-python/playwright
	>=dev-python/greenlet-3.1.1[${PYTHON_SINGLE_USEDEP}]
	<dev-python/greenlet-4.0.0[${PYTHON_SINGLE_USEDEP}]
	>=dev-python/pyee-13[${PYTHON_SINGLE_USEDEP}]
	<dev-python/pyee-14[${PYTHON_SINGLE_USEDEP}]
"
BDEPEND="app-arch/unzip"

src_compile() {
	:
}

src_install() {
	python_setup

	local sitedir
	sitedir="$(python_get_sitedir)" || die

	insinto "${sitedir}"
	doins -r "${MY_PN}"
	doins -r "${MY_P}.dist-info"

	# Keep the prebuilt node driver executable (doins drops the +x bit).
	fperms +x "${sitedir}/playwright/driver/node" || die

	# Recreate the console_scripts entry point from the wheel metadata.
	python_newscript - playwright <<-EOF || die
		#!${EPREFIX}/usr/bin/env ${EPYTHON}
		import sys
		from playwright.__main__ import main
		if __name__ == "__main__":
		    sys.exit(main())
	EOF

	python_optimize "${sitedir}/playwright"
}
