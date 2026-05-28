# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Extra CMake modules used by the Ayatana and Ubuntu ecosystems"
HOMEPAGE="https://salsa.debian.org/debian-ayatana-team/cmake-extras"
SRC_URI="https://salsa.debian.org/debian-ayatana-team/cmake-extras/-/archive/upstream/${PV}/cmake-extras-upstream-${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-upstream-${PV}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
