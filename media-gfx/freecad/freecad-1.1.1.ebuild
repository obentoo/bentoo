# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit check-reqs cmake cuda edo flag-o-matic optfeature python-single-r1 qmake-utils toolchain-funcs xdg virtualx

DESCRIPTION="Qt based Computer Aided Design application"
HOMEPAGE="https://www.freecad.org/ https://github.com/FreeCAD/FreeCAD"

MY_PN=FreeCAD

if [[ ${PV} == *9999* ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/${MY_PN}/${MY_PN}.git"
	EGIT_SUBMODULES=( 'src/Mod/AddonManager' )
	S="${WORKDIR}/freecad-${PV}"
else
	SRC_URI="
		https://github.com/${MY_PN}/${MY_PN}/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	"
	KEYWORDS="~amd64"
	S="${WORKDIR}/FreeCAD-${PV}"
fi

# code is licensed LGPL-2
# examples are licensed CC-BY-SA (without note of specific version)
LICENSE="LGPL-2 CC-BY-SA-4.0"
SLOT="0"
IUSE="debug designer +gui netgen pcl +smesh spacenav test X"
# Modules are found in src/Mod/ and their options defined in:
# cMake/FreeCAD_Helpers/InitializeFreeCADBuildOptions.cmake
# To get their dependencies:
# 'grep REQUIRES_MODS cMake/FreeCAD_Helpers/CheckInterModuleDependencies.cmake'
IUSE+=" addonmgr assembly +bim cam cloud fem idf inspection +mesh openscad points reverse robot surface"

REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	bim? ( mesh )
	cam? ( mesh )
	gui? ( bim )
	designer? ( gui )
	fem? ( smesh )
	inspection? ( points )
	mesh? ( smesh )
	openscad? ( mesh )
	reverse? ( mesh points )
"
# Draft Workbench needs BIM
# TechDraw is always ON (required by Draft which is always ON)

RESTRICT="!test? ( test )"

# if opencascade[tbb], we link to tbb
# if vtk[cuda], we use cuda
RDEPEND="
	${PYTHON_DEPS}
	dev-cpp/tbb:=
	dev-cpp/yaml-cpp:=
	dev-libs/boost:=
	dev-libs/libfmt:=
	dev-libs/xerces-c:=[icu]
	dev-qt/qtbase:6[concurrent,network,xml]
	media-libs/freetype
	sci-libs/opencascade:=[json]
	virtual/zlib:=
	$(python_gen_cond_dep '
		dev-python/numpy[${PYTHON_USEDEP}]
		dev-python/pybind11[${PYTHON_USEDEP}]
		dev-python/pycxx[${PYTHON_USEDEP}]
		dev-python/pyyaml[${PYTHON_USEDEP}]
	')
	assembly? ( sci-libs/ondselsolver )
	cloud? (
		dev-libs/openssl:=
		net-misc/curl
	)
	fem? (
		sci-libs/vtk:=
		$(python_gen_cond_dep 'dev-python/ply[${PYTHON_USEDEP}]')
	)
	gui? (
		>=media-libs/coin-4.0.0
		dev-qt/qtbase:6[gui,opengl,widgets]
		dev-qt/qtsvg:6
		dev-qt/qttools:6[designer?,widgets]
		$(python_gen_cond_dep '
			dev-python/matplotlib[${PYTHON_USEDEP}]
			>=dev-python/pivy-0.6.5[${PYTHON_USEDEP}]
			>=dev-python/pyside-6.10.1-r5:6=[uitools(-),gui,svg,${PYTHON_USEDEP}]
		' )
		virtual/opengl
		spacenav? ( dev-libs/libspnav[X?] )
	)
	netgen? ( media-gfx/netgen[opencascade] )
	openscad? ( $(python_gen_cond_dep 'dev-python/ply[${PYTHON_USEDEP}]') )
	pcl? ( sci-libs/pcl:= )
	smesh? (
		>=sci-libs/med-4.0.0-r1
		sci-libs/vtk:=
	)
"
DEPEND="${RDEPEND}
	<dev-cpp/eigen-5:=
	dev-cpp/ms-gsl
	test? (
		$(python_gen_impl_dep '-debug')
		$(python_gen_cond_dep '
			sci-libs/vtk[python,${PYTHON_SINGLE_USEDEP}]
		' )
		gui? (
			$(python_gen_cond_dep '
				dev-python/pyside:6[tools(-),${PYTHON_USEDEP}]
			' )
		)
		dev-cpp/gtest
	)
"
BDEPEND="
	dev-lang/swig
	test? (
		gui? (
			$(python_gen_cond_dep '
				dev-python/pytest[${PYTHON_USEDEP}]
				dev-python/typing-extensions[${PYTHON_USEDEP}]
			' )
		)
	)
"

PATCHES=( )

DOCS=( CODE_OF_CONDUCT.md README.md )

CHECKREQS_DISK_BUILD="2G"

cuda_get_host_compiler() {
	if [[ -v NVCC_CCBIN ]]; then
		echo "${NVCC_CCBIN}"
		return
	fi

	if [[ -v CUDAHOSTCXX ]]; then
		echo "${CUDAHOSTCXX}"
		return
	fi

	if ! command -v nvcc >/dev/null; then
		eerror "Could not find nvcc. Is the CUDA SDK installed?"
		die "nvcc not found"
	fi

	einfo "Trying to find working CUDA host compiler"

	if ! tc-is-gcc && ! tc-is-clang; then
		die "$(tc-get-compiler-type) compiler is not supported"
	fi

	local compiler
	local compiler_type
	local compiler_version
	local package
	local package_version
	local NVCC_CCBIN_default

	compiler_type="$(tc-get-compiler-type)"
	compiler_version="$("${compiler_type}-major-version")"

	NVCC_CCBIN="$(tc-getCXX)"
	NVCC_CCBIN_default="${NVCC_CCBIN}-${compiler_version}"

	compiler="${NVCC_CCBIN/%-${compiler_version}}"

	if tc-is-gcc; then
		package="sys-devel/${compiler_type}"
	elif tc-is-clang; then
		package="llvm-core/${compiler_type}"
	else
		die "$(tc-get-compiler-type) compiler is not supported"
	fi

	package_version="${package}"

	ebegin "testing ${NVCC_CCBIN_default} (default)"

	while ! \
		nvcc "${NVCCFLAGS:-}" \
			-ccbin "${NVCC_CCBIN}" \
			- \
			-x cu \
			<<<"int main(){}" \
			&>> "${T:?}/cuda_get_host_compiler.log" ;
		do
		eend 1

		while true; do
			local package_version_next
			package_version_next="$(best_version "${package_version}")"

			if [[ -z "${package_version_next}" ]]; then
				eerror "Compiler lookup failed. Nothing installed matches: ${package_version}."
				eerror "You can use NVCC_CCBIN to specify the exact compiler to use."
				eerror "Check ${T}/cuda_get_host_compiler.log for details."
				die "Could not find a supported version of ${compiler}. Did not find \"${package_version}\". NVCC_CCBIN is unset."
			fi

			package_version="<${package_version_next}"

			NVCC_CCBIN="${compiler}-$(ver_cut 1 "${package_version/#<${package}-/}")"

			[[ "${NVCC_CCBIN}" != "${NVCC_CCBIN_default}" ]] && break
		done
		ebegin "testing ${NVCC_CCBIN}"
	done
	eend $?

	echo "${NVCC_CCBIN}"
	export NVCC_CCBIN
}

pkg_setup() {
	check-reqs_pkg_setup
	python-single-r1_pkg_setup
}

src_prepare() {
	# Gentoo-specific: don't check vcs, use UnknownControl only
	sed -i -e '/GitControl()/d' \
		-e '/DebianGitHub()/d' \
		-e '/BazaarControl()/d' \
		-e '/Subversion()/d' \
		-e '/MercurialControl()/d' \
		-e '/DebianChangelog()/d' \
		src/Tools/SubWCRev.py || die

	# Only build Qt tests when BUILD_GUI is ON
	sed -i -e 's/^setup_qt_test(InventorBuilder)/if(BUILD_GUI)\n    setup_qt_test(InventorBuilder)\nendif()/' \
		tests/src/Base/CMakeLists.txt || die
	sed -i -e 's/^setup_qt_test(QuantitySpinBox)/if(BUILD_GUI)\n    setup_qt_test(QuantitySpinBox)\nendif()/' \
		tests/src/Gui/CMakeLists.txt || die

	# Remove bundled PyCXX (older 6.2 API lacks PYCXX_UNICODE_TYPE,
	# which the system pycxx-7.x cxxsupport.cxx references).
	# -DPYCXX_INCLUDE_DIR / -DPYCXX_SOURCE_DIR already point at the system copy.
	if [[ ${PV} != *9999* ]]; then
		rm -r src/3rdParty/PyCXX || die "remove bundled pycxx"
	fi

	cmake_src_prepare
}

src_configure() {
	# -Werror=odr, -Werror=lto-type-mismatch
	# https://bugs.gentoo.org/875221
	# https://github.com/FreeCAD/FreeCAD/issues/13173
	append-flags -fno-strict-aliasing
	filter-lto

	# Fix building tests
	if tc-ld-is-bfd; then # 940524
		append-ldflags -Wl,--copy-dt-needed-entries
	fi

	local mycmakeargs=(
		-DFREECAD_USE_CCACHE="no"

		-DPYCXX_INCLUDE_DIRS="${ESYSROOT}/usr/include/${PYTHON_SINGLE_TARGET/_/.}"
		-DPYCXX_SOURCE_DIR="${ESYSROOT}/usr/share/${PYTHON_SINGLE_TARGET/_/.}/CXX"

		-DBUILD_DESIGNER_PLUGIN=$(usex designer)
		-DBUILD_FORCE_DIRECTORY=ON
		-DBUILD_GUI=$(usex gui)
		-DBUILD_SMESH=$(usex smesh)
		-DBUILD_VR=OFF
		-DBUILD_WITH_CONDA=OFF

		# Modules
		-DBUILD_ADDONMGR=$(usex addonmgr)
		-DBUILD_ASSEMBLY=$(usex assembly)
		-DBUILD_BIM=$(usex bim)
		-DBUILD_CAM=$(usex cam)
		-DBUILD_CLOUD=$(usex cloud)
		-DBUILD_DRAFT=ON
		-DBUILD_FEM=$(usex fem)
		-DBUILD_FEM_NETGEN=$(usex fem $(usex netgen))
		-DBUILD_FLAT_MESH=$(usex mesh)
		-DBUILD_HELP=ON
		-DBUILD_IDF=$(usex idf)
		-DBUILD_IMPORT=ON
		-DBUILD_INSPECTION=$(usex inspection)
		-DBUILD_JTREADER=OFF
		-DBUILD_MATERIAL=ON
		-DBUILD_MATERIAL_EXTERNAL=ON
		-DBUILD_MEASURE=ON
		-DBUILD_MESH=$(usex mesh)
		-DBUILD_MESH_PART=$(usex mesh)
		-DBUILD_OPENSCAD=$(usex openscad)
		-DBUILD_PART=ON
		-DBUILD_PART_DESIGN=ON
		-DBUILD_PLOT=ON
		-DBUILD_POINTS=$(usex points)
		-DBUILD_REVERSEENGINEERING=$(usex reverse)
		-DBUILD_ROBOT=$(usex robot)
		-DBUILD_SHOW=$(usex gui)
		-DBUILD_SKETCHER=ON
		-DBUILD_SPREADSHEET=ON
		-DBUILD_START=ON
		-DBUILD_SURFACE=$(usex surface)
		-DBUILD_TECHDRAW=ON
		-DBUILD_TEST="$(usex test)"
		-DBUILD_TUX=$(usex gui)
		-DBUILD_WEB=ON

		-DCMAKE_INSTALL_PREFIX="${EPREFIX}/usr/$(get_libdir)/${PN}"

		-DFREECAD_BUILD_DEBIAN=OFF

		-DFREECAD_USE_EXTERNAL_E57FORMAT="no"
		-DFREECAD_USE_EXTERNAL_GTEST="$(usex test)"
		-DFREECAD_USE_EXTERNAL_ONDSELSOLVER=$(usex assembly)
		-DFREECAD_USE_EXTERNAL_SMESH=OFF
		-DFREECAD_USE_EXTERNAL_ZIPIOS=OFF
		-DFREECAD_USE_EXTERNAL_FMT="yes"
		-DFREECAD_USE_EXTERNAL_KDL=OFF
		-DFREECAD_USE_FREETYPE=ON
		-DFREECAD_USE_OCC_VARIANT:STRING="Official Version"
		-DFREECAD_USE_PCL=$(usex pcl)
		-DFREECAD_USE_PYBIND11=ON
		-DFREECAD_USE_QT_FILEDIALOG=ON

		-DINSTALL_TO_SITEPACKAGES=ON

		-DPYTHON_CONFIG_SUFFIX="-${EPYTHON}"
	)

	if [[ ${PV} == *9999* ]]; then
		mycmakeargs+=(
			-DENABLE_DEVELOPER_TESTS="$(usex test)"

			-DPACKAGE_WCREF="%{release} (Git)"
			-DPACKAGE_WCURL="git://github.com/FreeCAD/FreeCAD.git main"
		)
	else
		mycmakeargs+=(
			-DENABLE_DEVELOPER_TESTS=OFF

			-DPACKAGE_WCREF="${PVR} (gentoo)"
			-DPACKAGE_WCURL="git://github.com/FreeCAD/FreeCAD.git ${PV}"
		)
	fi

	if use debug; then
		mycmakeargs+=(
			-DBUILD_SANDBOX=OFF
			-DBUILD_TEMPLATE=ON
		)
	else
		mycmakeargs+=(
			-DBUILD_SANDBOX=OFF
			-DBUILD_TEMPLATE=OFF
		)
	fi

	# fem and smesh depend on sci-lib/vtk, which looks up a cuda compiler when build with USE=cuda.
	if use fem || use smesh; then
		if has_version "sci-libs/vtk[cuda]" ; then
			cuda_add_sandbox
			addpredict "/dev/char/"
			export CUDAHOSTCXX="$(cuda_get_host_compiler)"
		fi
	fi

	if use gui; then
		mycmakeargs+=(
			-DFREECAD_QT_MAJOR_VERSION=6
			-DFREECAD_QT_VERSION=6
			-DQT_DEFAULT_MAJOR_VERSION=6
			-DQt6Core_MOC_EXECUTABLE="$(qt6_get_bindir)/moc"
			-DQt6Core_RCC_EXECUTABLE="$(qt6_get_bindir)/rcc"
			-DBUILD_QT5=OFF
			-DBUILD_DRAWING=OFF
		)
	fi

	cmake_src_configure
}

src_test() {
	cd "${BUILD_DIR}" || die

	[[ -c "/dev/udmabuf" ]] && addwrite "/dev/udmabuf"

	if use bim; then
		# No module named 'ifcopenshell' #940465
		rm "${BUILD_DIR}/Mod/BIM/nativeifc/ifc_performance_test.py" || die
	fi

	if use cam; then
		sed -e '/test46/a \        return' -i "Mod/CAM/CAMTests/TestPathOpUtil.py" || die
		sed -e '/test47/a \        return' -i "Mod/CAM/CAMTests/TestPathOpUtil.py" || die
	fi

	local -x EPYTEST_IGNORE=(
		"Mod/BIM/nativeifc/ifc_performance_test.py"
	)

	if ! use openscad ; then
		EPYTEST_IGNORE+=(
			"Mod/OpenSCAD/OpenSCADTest/app/test_importCSG.py"
			"Mod/OpenSCAD/OpenSCADTest/gui/test_dummy.py"
		)
	fi

	local -x CMAKE_SKIP_TESTS=(
		"^ConstraintPointsAccess."
	)

	local -x FREECAD_USER_HOME="${HOME}"
	local -x FREECAD_USER_DATA="${T}/data"
	local -x FREECAD_USER_TEMP="${T}/temp"

	mkdir -p "${FREECAD_USER_DATA}" "${FREECAD_USER_TEMP}" || die

	local failed=()
	local run

	if \
		! nonfatal \
		edo \
		"${BUILD_DIR}/bin/FreeCADCmd" \
			--run-test 0 \
			--set-config AppHomePath="${BUILD_DIR}/" \
			--log-file "${T}/FreeCADCmd.log"; then
		ret=$?
		eerror "FreeCADCmd failed $ret"
		failed+=( "FreeCADCmd" )
	fi

	if use gui; then
		addpredict "/dev/char/"
		addwrite "/dev/dri/renderD128"
		addwrite "/dev/dri/card0"

		[[ -c "/dev/nvidiactl" ]] && addwrite "/dev/nvidiactl"
		[[ -c "/dev/nvidia-uvm" ]] && addwrite "/dev/nvidia-uvm"
		[[ -c "/dev/nvidia-uvm-tools" ]] && addwrite "/dev/nvidia-uvm-tools"
		[[ -c "/dev/nvidia0" ]] && addwrite "/dev/nvidia0"

		[[ -c "/dev/udmabuf" ]] && addwrite "/dev/udmabuf"

		if \
			! nonfatal \
			virtx \
			edo \
			"${BUILD_DIR}/bin/FreeCAD" \
				--run-test 0 \
				--set-config AppHomePath="${BUILD_DIR}/" \
				--log-file "${T}/FreeCAD.log" ; then
			ret=$?
			eerror "FreeCAD failed $ret"
			failed+=( "FreeCAD" )
		fi

		run="virtx"
	fi

	if [[ ${PV} == *9999* ]]; then
		if ! nonfatal \
			"${run}" \
			cmake_src_test; then
			eerror "cmake failed $?"
			failed+=( "cmake" )
		fi
	fi

	if [[ "${#failed[@]}" -gt 0 ]]; then
		eerror "Tests ${failed[*]} failed"
		if ! use debug && [[ ${PV} != *9999* ]]; then
			die "${failed[@]}"
		fi
	fi
}

src_install() {
	cmake_src_install

	if use gui; then
		newbin - FreeCAD <<- _EOF_
			#!/bin/sh
			# https://github.com/coin3d/coin/issues/451
			: "\${QT_QPA_PLATFORM:=xcb}"
			export QT_QPA_PLATFORM
			exec ${EPREFIX}/usr/$(get_libdir)/${PN}/bin/FreeCAD "\${@}"
		_EOF_
	fi
	dosym -r "/usr/$(get_libdir)/${PN}/bin/FreeCADCmd" "/usr/bin/FreeCADCmd"

	if [[ -f src/Tools/freecad-thumbnailer ]]; then
		dobin src/Tools/freecad-thumbnailer
	fi

	for dir in share/{applications,icons,metainfo,mime,pixmaps,thumbnailers}; do
		mv "${ED}/usr/$(get_libdir)/${PN}/${dir}" "${ED}/usr/share/" || die "mv failed"
	done

	rm -r "${ED}/usr/$(get_libdir)/${PN}/include/E57Format" || die "failed to drop unneeded include directory E57Format"
	rmdir "${ED}/usr/$(get_libdir)/${PN}/include/" || die "failed to drop unneeded include directory"

	python_optimize "${ED}/usr/share/${PN}/data/Mod/Start/" "${ED}/usr/$(get_libdir)/${PN}/"{Ext,Mod}/
	# compile main package in python site-packages as well
	python_optimize
}

pkg_postinst() {
	xdg_pkg_postinst

	einfo "You can load a lot of additional workbenches using the integrated"
	einfo "AddonManager."

	einfo "There are a lot of additional tools, for which FreeCAD has builtin"
	einfo "support. Some of them are available in Gentoo. Take a look at"
	einfo "https://wiki.freecad.org/Installing_additional_components"
	optfeature_header "External programs used by FreeCAD"
	optfeature "dependency graphs" media-gfx/graphviz
	optfeature "importing and exporting 2D AutoCAD DWG files" media-gfx/libredwg
	optfeature "importing OpenSCAD files, Mesh booleans" media-gfx/openscad
	use bim && optfeature "working with COLLADA documents" dev-python/pycollada
	if use fem || use mesh; then
		optfeature "mesh generation" sci-libs/gmsh
	fi

	if use python_single_target_python3_13; then
		einfo "${PN} is reported to suffer from memory leaks."
		einfo "This can cause to program abortions with python-3.13"
		einfo "Fall back to python-3.12 if that happens."
		einfo "See https://github.com/FreeCAD/FreeCAD/issues/19066 for details."
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}
