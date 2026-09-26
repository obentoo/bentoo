# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Mesh optimization library: vertex cache, overdraw, fetch and simplification"
HOMEPAGE="https://github.com/zeux/meshoptimizer"
SRC_URI="https://github.com/zeux/meshoptimizer/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

# MIT covers the library (LICENSE.md) and every header vendored under extern/
# that gltfpack compiles: cgltf and fast_obj are MIT, sdefl is dual MIT /
# public domain.  Nothing here needs a USE-conditional license.
LICENSE="MIT"

# Upstream builds the shared library with NO SONAME versioning unless
# MESHOPT_SOVERSION is given (CMakeLists.txt: "if(MESHOPT_SOVERSION)"), and it
# states in the same place that the APIs marked MESHOPTIMIZER_EXPERIMENTAL are
# not ABI-stable across releases.  A bare libmeshoptimizer.so would therefore
# let a consumer linked against 1.2 keep loading a future 1.3 whose
# experimental entry points changed shape -- a silent, run-time breakage.
#
# So the SONAME carries the full upstream version (libmeshoptimizer.so.1.2):
# every release is its own ABI, and a consumer that was not rebuilt fails
# loudly at load time instead of mismatching quietly.  The subslot repeats the
# version so that := revdeps are rebuilt automatically on a bump; consumers
# should depend on media-libs/meshoptimizer:0/${PV} via ":=".
SLOT="0/${PV}"

KEYWORDS="~amd64 ~arm64"
IUSE="gltfpack test"
RESTRICT="!test? ( test )"

src_configure() {
	local mycmakeargs=(
		# The switch is NOT BUILD_SHARED_LIBS, and it defaults to OFF: without
		# this the package would install only a static archive, which is
		# useless to media-gfx/blender -- its intern/meshoptimizer_bridge is a
		# SHARED library linking meshoptimizer::meshoptimizer.
		-DMESHOPT_BUILD_SHARED_LIBS=ON

		# See the SLOT comment above for why the SONAME is the full version.
		-DMESHOPT_SOVERSION="${PV}"

		# ON would define MESHOPTIMIZER_EXPERIMENTAL to nothing, hiding the ten
		# experimental entry points behind the hidden visibility preset.  They
		# are part of the API consumers actually call (meshopt_generateTangents,
		# meshopt_computePositionExponent, the opacity-map family), so a distro
		# library must export them.
		-DMESHOPT_STABLE_EXPORTS=OFF

		# The demo target doubles as upstream's test runner ("meshoptdemo" with
		# no arguments runs runTests()); it is built for src_test only and is
		# never installed.
		-DMESHOPT_BUILD_DEMO=$(usex test ON OFF)

		-DMESHOPT_BUILD_GLTFPACK=$(usex gltfpack ON OFF)

		# -Werror on a release build turns any new compiler warning into a
		# build failure for the user.
		-DMESHOPT_WERROR=OFF

		-DMESHOPT_INSTALL=ON
	)

	cmake_src_configure
}

src_test() {
	# Not cmake_src_test: upstream registers no CTest tests.  The suite is the
	# demo binary invoked with no arguments (demo/main.cpp: "if (argc == 1)
	# runTests();"), which aborts on the first failed assertion.
	"${BUILD_DIR}"/meshoptdemo || die "test suite failed"
}
