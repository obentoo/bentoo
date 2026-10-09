# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Upstream ships an in-tree PEP 517 backend (backends/pep517.py) that proxies
# flit_core and additionally generates the auto-complete index (awscli/data/
# ac.index) and injects it -- plus everything under bin/ -- into the wheel.
DISTUTILS_USE_PEP517=standalone
PYTHON_COMPAT=( python3_{12..14} )

inherit distutils-r1 shell-completion

MY_P=aws-cli-${PV}
DESCRIPTION="Universal Command Line Environment for AWS, version 2"
HOMEPAGE="
	https://aws.amazon.com/cli/
	https://github.com/aws/aws-cli/
"
# AWS CLI v2 is not published on PyPI -- the only source release is the
# GitHub tag.  Do not add the pypi eclass here.
SRC_URI="
	https://github.com/aws/aws-cli/archive/${PV}.tar.gz
		-> ${MY_P}.gh.tar.gz
"
S=${WORKDIR}/${MY_P}

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# awscli/{botocore,s3transfer} are vendored *forks* in v2, not copies of the
# upstream releases: the v2-only features (SSO, the auto-prompt, the new
# `aws s3` CRT transfer manager) live in those forks.  Unlike the v1 ebuild
# they must NOT be unbundled, and dev-python/{botocore,s3transfer} must not be
# pulled in -- they would only shadow the forks.
RDEPEND="
	>=dev-python/awscrt-0.36.2[${PYTHON_USEDEP}]
	>=dev-python/colorama-0.2.5[${PYTHON_USEDEP}]
	>=dev-python/distro-1.5.0[${PYTHON_USEDEP}]
	>=dev-python/docutils-0.10[${PYTHON_USEDEP}]
	>=dev-python/jmespath-0.7.1[${PYTHON_USEDEP}]
	>=dev-python/prompt-toolkit-3.0.24[${PYTHON_USEDEP}]
	>=dev-python/python-dateutil-2.1[${PYTHON_USEDEP}]
	>=dev-python/ruamel-yaml-0.15.0[${PYTHON_USEDEP}]
	>=dev-python/ruamel-yaml-clib-0.2.0[${PYTHON_USEDEP}]
	>=dev-python/urllib3-1.25.4[${PYTHON_USEDEP}]
	dev-python/wcwidth[${PYTHON_USEDEP}]
	!app-admin/awscli
	!app-admin/awscli-bin
"
# The backend imports awscli.autocomplete.generator and walks the whole
# clidriver to emit ac.index, so every runtime dependency has to be importable
# at build time as well.
BDEPEND="
	${RDEPEND}
	>=dev-python/flit-core-3.7.1[${PYTHON_USEDEP}]
	test? (
		dev-python/jsonschema[${PYTHON_USEDEP}]
	)
"

# The test suite declares no pytest_plugins and needs none of the plugins
# distutils-r1 would otherwise autoload; jsonschema (a plain import in
# tests/functional) is the only extra it actually uses.
EPYTEST_PLUGINS=()
EPYTEST_XDIST=1
distutils_enable_tests pytest

PATCHES=(
	# Upstream pins prompt-toolkit<3.0.52 to hide a real bug in its own
	# wizard toolbar; that pin is not satisfiable here, so fix the bug.
	"${FILESDIR}"/${PN}-prompt-toolkit-toolbar-init.patch
)

python_prepare_all() {
	distutils-r1_python_prepare_all

	# Strip upstream's overzealous upper bounds.  AWS ships a locked
	# dependency closure with its own bundled interpreter; on a distro the
	# ceilings are already violated by docutils, prompt-toolkit, distro,
	# jmespath, urllib3 and wcwidth.  The first two expressions mirror what
	# ::gentoo's app-admin/awscli does to setup.py; the third one is needed
	# because "wcwidth<0.3.0" has no comma before the ceiling.
	sed -i \
		-e 's:,<[=0-9.]*::' \
		-e 's:==:>=:' \
		-e 's:"wcwidth<[=0-9.]*":"wcwidth":' \
		pyproject.toml || die

	# A surviving ceiling does not fail the build -- it fails much later, when
	# a user's resolver refuses the installed version.  Assert instead.
	local leftover
	leftover=$(grep -n '^[[:space:]]*"[^"]*<' pyproject.toml)
	if [[ -n ${leftover} ]]; then
		eerror "Unrelaxed upper bound(s) left in pyproject.toml:"
		eerror "${leftover}"
		die "dependency ceiling relaxation is incomplete"
	fi
}

python_test() {
	# Cap the xdist workers by available memory, not by core count.  Every
	# worker imports the vendored botocore, whose 1868 service models (110M
	# of JSON on disk, several times that once parsed into Python dicts)
	# plus the 20M autocomplete index cost well over 1G of RSS each -- and
	# unlike a compiler process, a worker holds that for the whole run
	# instead of freeing it between files.  Measured on a 32-thread host:
	# the eclass default of -n32 (from MAKEOPTS) peaked above 50G, more
	# than a chromium build.  Re-measured at -n11: still a 60G peak, i.e.
	# ~5G per worker.  Budget 8G each, never exceed the core count, and let
	# anyone who knows their machine better override EPYTEST_JOBS.
	if [[ -z ${EPYTEST_JOBS} ]]; then
		local mem_gib=$(( $(awk '/MemAvailable/{ print $2 }' /proc/meminfo) / 1048576 ))
		local EPYTEST_JOBS=$(( mem_gib / 8 ))
		local cores=$(get_makeopts_jobs)
		(( EPYTEST_JOBS > cores )) && EPYTEST_JOBS=${cores}
		(( EPYTEST_JOBS < 1 )) && EPYTEST_JOBS=1
		einfo "Limiting pytest to ${EPYTEST_JOBS} job(s) for ${mem_gib}G available"
	fi

	# Only two of the five test trees are runnable here:
	#   tests/integration  - needs real AWS credentials and network access
	#   tests/dependencies - asserts the pinned closure in requirements*.txt
	#                        still matches pyproject.toml, which we relax above
	#   tests/backends     - exercises upstream's standalone installer/venv
	#                        machinery (and needs the deprecated dev-python/py),
	#                        none of which this ebuild uses
	local EPYTEST_DESELECT=(
		# Needs the generated ac.index, which lives in the *installed*
		# package; the source tree in ${S} occludes it during the run
		# (portage warns about this as an occluded package).
		tests/functional/autocomplete/test_main.py::test_smoke_test_completer

		# Asserts a specific locale.getpreferredencoding() result; depends
		# on the builder's locale, not on this package.
		"tests/unit/test_compat.py::TestGetPreferredEncoding::test_getpreferredencoding_with_env_var"
	)

	epytest tests/{functional,unit}
}

python_install_all() {
	newbashcomp bin/aws_bash_completer aws
	newzshcomp bin/aws_zsh_completer.sh _aws

	distutils-r1_python_install_all

	# The in-tree backend injects *everything* under bin/ into the wheel's
	# data/scripts directory, so all five files land in /usr/bin.  Keep `aws`
	# and `aws_completer` (the latter is what `complete -C` invokes); drop the
	# Windows launcher and the two completion snippets installed above.
	rm "${ED}"/usr/bin/{aws.cmd,aws_bash_completer,aws_zsh_completer.sh} || die
}
