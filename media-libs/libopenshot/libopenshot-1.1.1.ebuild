# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )

inherit cmake python-single-r1 toolchain-funcs

DESCRIPTION="Video editing library used by OpenShot Video Editor"
HOMEPAGE="https://www.openshot.org/ https://github.com/OpenShot/libopenshot"
SRC_URI="https://github.com/OpenShot/libopenshot/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

# SPDX-License-Identifier: LGPL-3.0-or-later throughout the tree; COPYING is the
# LGPL v3.  Note this differs from libopenshot-audio and openshot-qt, which are
# GPL-3+ -- do not copy the license over from those packages.
LICENSE="LGPL-3+"
# Subslot tracks PROJECT_SO_VERSION (libopenshot.so.31), so revdeps rebuild on
# an ABI bump.
SLOT="0/31"
KEYWORDS="~amd64"

IUSE="babl doc +imagemagick opencv +python ruby test wayland"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"
RESTRICT="!test? ( test )"

# ZmqLogger.h does #include <zmq.hpp>, which net-libs/zeromq does not install --
# net-libs/cppzmq is mandatory even though upstream probes it with
# find_package(cppzmq QUIET).  It is header-only, hence DEPEND only.
COMMON_DEPEND="
	>=media-libs/libopenshot-audio-1.0.0
	dev-libs/jsoncpp:=
	dev-qt/qtbase:6[gui,widgets]
	dev-qt/qtsvg:6
	media-video/ffmpeg:=
	net-libs/zeromq:=
	babl? ( media-libs/babl )
	imagemagick? ( media-gfx/imagemagick:0= )
	opencv? (
		dev-libs/protobuf:=
		media-libs/opencv:0=[contrib,contribdnn]
	)
	python? ( ${PYTHON_DEPS} )
	ruby? ( dev-lang/ruby:= )
	wayland? (
		dev-libs/glib:2
		media-video/pipewire:=
	)
"
RDEPEND="${COMMON_DEPEND}"
DEPEND="
	${COMMON_DEPEND}
	net-libs/cppzmq
"
BDEPEND="
	virtual/pkgconfig
	doc? ( app-text/doxygen[dot] )
	python? ( >=dev-lang/swig-3.0 )
	ruby? ( >=dev-lang/swig-3.0 )
	test? ( >=dev-cpp/catch-3 )
"

PATCHES=(
	# Port to OpenCV 5 (this overlay ships media-libs/opencv-5.0.0, and opencv is
	# SLOT="0/${PV}", so 4 and 5 cannot coexist).  Also raises CMAKE_CXX_STANDARD to
	# 20, required by abseil/protobuf 7.x -- passing -DCMAKE_CXX_STANDARD=20 on the
	# command line does not work, the set() in CMakeLists.txt overrides it.
	# Named ${PN}, not ${P}: the autoupdate applier renames the ebuild on a bump but
	# never files/, and this patch applied unchanged from 1.0.0 to 1.0.1.  (The
	# 1.0.0 guard-tracked-object-mask patch was dropped: 1.0.1 guards
	# TrackedObjectMask() with #ifdef USE_OPENCV upstream.)
	"${FILESDIR}/${PN}-opencv5-cxx20.patch"
)

pkg_pretend() {
	if [[ ${MERGE_TYPE} != binary ]]; then
		tc-check-openmp
	fi
}

pkg_setup() {
	if [[ ${MERGE_TYPE} != binary ]]; then
		tc-check-openmp
	fi
	if use python; then
		python-single-r1_pkg_setup
	fi
}

src_configure() {
	local mycmakeargs=(
		-DCMAKE_INSTALL_DOCDIR="share/doc/${PF}"

		# Qt6 explicitly: the default is AUTO, which silently falls back to Qt5.
		-DUSE_QT6=ON

		-DUSE_SYSTEM_JSONCPP=ON
		-DDISABLE_BUNDLED_JSONCPP=ON

		-DENABLE_MAGICK=$(usex imagemagick)
		-DENABLE_OPENCV=$(usex opencv)
		-DENABLE_WAYLAND_CAPTURE=$(usex wayland)
		-DENABLE_LIB_DOCS=$(usex doc)
		-DBUILD_TESTING=$(usex test)

		-DENABLE_PYTHON=$(usex python)
		-DENABLE_RUBY=$(usex ruby)

		# Never built here: needs glslangValidator plus an FFmpeg avfilter probe,
		# and upstream still links it against Qt5.
		-DENABLE_VULKAN_BENCHMARK=OFF
		-DENABLE_IWYU=OFF
		-DENABLE_COVERAGE=OFF

		# babl is probed with a bare find_package(babl) and has no upstream option,
		# so USE=-babl has to be enforced from the outside.
		-DCMAKE_DISABLE_FIND_PACKAGE_babl=$(usex babl OFF ON)

		# Resvg is not packaged in ::gentoo or here.  Disable the probe explicitly:
		# finding it would drop Qt Svg from the component list and silently change
		# the dependency graph this ebuild declares.
		-DCMAKE_DISABLE_FIND_PACKAGE_Resvg=ON
	)

	if use python; then
		# Upstream joins PYTHON_MODULE_PATH onto CMAKE_INSTALL_PREFIX, so keep it
		# relative and take it from the eclass rather than from its sysconfig probe.
		local sitedir
		sitedir=$(python_get_sitedir)
		mycmakeargs+=(
			-DPYTHON_EXECUTABLE="${PYTHON}"
			-DPYTHON_MODULE_PATH="${sitedir#"${EPREFIX}"/usr/}"
		)
	fi

	cmake_src_configure
}

src_compile() {
	cmake_src_compile

	# doxygen_add_docs() registers the target outside ALL, so it needs an
	# explicit build; the install rule for it is already conditional.
	if use doc; then
		cmake_src_compile ${PN}-doc
	fi
}

src_install() {
	cmake_src_install

	# Byte-compile here rather than in pkg_postinst: EPYTHON is only guaranteed
	# to be set by python-single-r1_pkg_setup for source merges.
	if use python; then
		python_optimize
	fi
}
