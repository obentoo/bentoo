# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Fortran Language Server"
HOMEPAGE="
	https://fortls.fortran-lang.org/
	https://github.com/fortran-lang/fortls
	https://pypi.org/project/fortls/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/json5[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
"
BDEPEND="
	dev-python/setuptools-scm[${PYTHON_USEDEP}]
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

EPYTEST_DESELECT=(
	# Queries pypi.org and runs `pip install --user`; disabled below.
	test/test_interface.py::test_version_update_pypi
)

src_prepare() {
	distutils-r1_src_prepare

	# Upstream self-updates on startup: it queries pypi.org and runs
	# `pip install --user --upgrade fortls` behind the package manager's back.
	# Make the updater a no-op regardless of --disable_autoupdate.
	grep -qF '        if self.disable_autoupdate:' fortls/langserver.py \
		|| die "autoupdate guard not found in fortls/langserver.py"
	sed -i \
		-e 's/^        if self\.disable_autoupdate:$/        if True:  # Gentoo: updates come from the package manager/' \
		fortls/langserver.py || die
	grep -qF 'if True:  # Gentoo' fortls/langserver.py || die "autoupdate sed did not apply"
}

python_test() {
	# pyproject.toml addopts pull in pytest-cov.
	epytest -o addopts= test
}
