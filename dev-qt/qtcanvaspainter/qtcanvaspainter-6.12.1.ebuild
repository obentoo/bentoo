# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qt6-build

DESCRIPTION="Accelerated 2D painting API on top of QRhi for the Qt6 framework"

if [[ ${QT6_BUILD_TYPE} == release ]]; then
	KEYWORDS="~amd64"
fi

# unlike most Qt modules, upstream ships this one GPL-3 only (no LGPL)
LICENSE="GPL-3 FDL-1.3"

# Quick and Widgets support is picked by TARGET checks; dependencies.yaml
# marks qtdeclarative and qtshadertools required, so depend on all of them
# instead of letting whatever is installed decide (Qt Creator's Tracing
# library needs the Widgets part)
RDEPEND="
	~dev-qt/qtbase-${PV}:6[gui,widgets]
	~dev-qt/qtdeclarative-${PV}:6
	~dev-qt/qtshadertools-${PV}:6
"
DEPEND="${RDEPEND}"
BDEPEND="
	~dev-qt/qtshadertools-${PV}:6
"
