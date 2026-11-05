# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517="setuptools"
# Based on ::gentoo's 2.21.3 ebuild, bumped to 2.21.6 (app-admin/ansible-14.6.0
# requires ansible-core~=2.21.6); python3_15 added, which needs the one-hunk
# backport in PATCHES below. Fold back into ::gentoo once it ships >=2.21.6
# with python3_15.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1

DESCRIPTION="Model-driven deployment, config management, and command execution framework"
HOMEPAGE="https://www.ansible.com/"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/ansible/ansible.git"
	EGIT_BRANCH="devel"
else
	inherit pypi
	KEYWORDS="~amd64"
fi

LICENSE="GPL-3"
SLOT="0"
RESTRICT="test"

RDEPEND="
	>=dev-python/paramiko-3.5.1[${PYTHON_USEDEP}]
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/cryptography[${PYTHON_USEDEP}]
	dev-python/httplib2[${PYTHON_USEDEP}]
	dev-python/six[${PYTHON_USEDEP}]
	dev-python/netaddr[${PYTHON_USEDEP}]
	dev-python/pexpect[${PYTHON_USEDEP}]
	>=dev-python/resolvelib-0.8.0[${PYTHON_USEDEP}]
	<dev-python/resolvelib-2.0.0[${PYTHON_USEDEP}]
	net-misc/sshpass
	virtual/ssh
"
BDEPEND="
	>=dev-python/packaging-16.6[${PYTHON_USEDEP}]
	test? (
		dev-python/botocore[${PYTHON_USEDEP}]
		dev-python/pytz[${PYTHON_USEDEP}]
	)"

distutils_enable_tests pytest

# BENTOO-DIVERGENCE: PATCHES - upstream's 2.22.0 fix for the Python 3.15
# import crash (dataclasses._is_type is gone), which 2.21 never received.
PATCHES=(
	"${FILESDIR}"/${P}-py315-patch-target.patch
)

python_compile() {
	export ANSIBLE_SKIP_CONFLICT_CHECK=1
	distutils-r1_python_compile
}
