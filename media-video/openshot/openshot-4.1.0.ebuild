# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_SINGLE_IMPL=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..14} )

inherit distutils-r1 xdg

MY_PN="openshot-qt"

DESCRIPTION="Free, open-source, non-linear video editor"
HOMEPAGE="https://www.openshot.org/ https://github.com/OpenShot/openshot-qt"
SRC_URI="https://github.com/OpenShot/${MY_PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"

# The suite is a full Qt GUI driver: it instantiates MainWindow, needs a
# libopenshot runtime and a usable QPA platform.  Not validated in a sandbox
# yet, so it is restricted rather than shipped broken behind USE=test.
RESTRICT="test"

# dev-python/pyqt6[scxml] is not optional: src/qt_api.py raises
# "PyQt6 QtStateMachine module not available" and aborts the launch without it.
# scxml is what pulls dev-qt/qtscxml in and enables the QtStateMachine binding
# (pyqt_use_enable scxml QtStateMachine); it is NOT default-on in pyqt6.
# [svg] backs the 17 QtSvg call sites; [gui] and [widgets] are default-on but
# spelled out because svg/scxml require them anyway.
#
# dev-python/sentry-sdk is deliberately absent: it is genuinely optional
# (the app logs "No sentry_sdk module detected" and continues), and telemetry
# should be opt-in, not pulled in by a dependency graph.
RDEPEND="
	>=media-libs/libopenshot-1.0.0[python,${PYTHON_SINGLE_USEDEP}]
	$(python_gen_cond_dep '
		dev-python/certifi[${PYTHON_USEDEP}]
		dev-python/defusedxml[${PYTHON_USEDEP}]
		dev-python/distro[${PYTHON_USEDEP}]
		dev-python/numpy[${PYTHON_USEDEP}]
		dev-python/pillow[${PYTHON_USEDEP}]
		dev-python/pyopengl[${PYTHON_USEDEP}]
		dev-python/pyqt6[${PYTHON_USEDEP},gui,scxml,svg,widgets]
		dev-python/pyzmq[${PYTHON_USEDEP}]
		dev-python/requests[${PYTHON_USEDEP}]
	')
"

src_prepare() {
	default

	# Upstream ships a top-level installer/__init__.py, which makes "installer"
	# a real importable package rooted at ${S}.  gpep517 install-wheel runs with
	# ${S} on sys.path, so that directory shadows dev-python/installer and the
	# wheel install dies with "cannot import name 'install' from 'installer'".
	# The directory is macOS/Windows/AppImage packaging scaffolding; setup.py
	# never reads it and nothing under src/ imports it, so drop it outright.
	[[ -f installer/__init__.py ]] \
		|| die "installer/__init__.py is gone; re-check the sys.path shadowing"
	rm -r installer || die

	# setup.py runs update-mime-database, update-mime and update-desktop-database
	# against the LIVE prefix (sys.prefix, i.e. /usr) whenever euid == 0.  With
	# FEATURES=-userpriv the build phases are root, so that fires and either trips
	# the sandbox or mutates the host outside ${D}.  Upstream only self-disarms on
	# FAKEROOTKEY, which Portage does not set.  Pin the flag to False instead.
	grep -qF 'ROOT = os.geteuid() == 0' setup.py \
		|| die "setup.py root detection changed; re-audit the update-* calls"
	sed -i 's/^ROOT = os\.geteuid() == 0$/ROOT = False  # Gentoo: never touch the live prefix/' \
		setup.py || die
}

python_install_all() {
	distutils-r1_python_install_all

	# xdg/openshot-qt is a Debian mime-support entry (update-mime reads
	# /usr/lib/mime/packages).  Gentoo has no update-mime; the file would be
	# dead weight in a non-arch-specific /usr/lib subtree.  share/mime/packages
	# is the one that matters and is kept.
	rm -r "${ED}/usr/lib/mime" || die
}
