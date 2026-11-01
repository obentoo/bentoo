# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="JUCE-based audio library used by libopenshot"
HOMEPAGE="https://github.com/OpenShot/libopenshot-audio"
SRC_URI="https://github.com/OpenShot/libopenshot-audio/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
# subslot = SONAME (PROJECT_SO_VERSION in CMakeLists.txt)
SLOT="0/10"
KEYWORDS="~amd64"
IUSE="doc"

# JUCE is vendored in JuceLibraryCode/ upstream; there is no usable system JUCE
# to unbundle against, so it is deliberately built from the bundled copy.
RDEPEND="
	media-libs/alsa-lib
	virtual/zlib:=
"
DEPEND="${RDEPEND}"
BDEPEND="doc? ( app-text/doxygen[dot] )"

src_prepare() {
	# Vendored Android Oboe subproject. It is never add_subdirectory()'d -- the
	# only add_subdirectory in this build is "src" -- and only its *.h files are
	# installed, so this CMakeLists.txt is dead weight in the tarball. But
	# cmake.eclass scans every CMakeLists.txt under ${S}, finds its
	# cmake_minimum_required(VERSION 3.4.1), and reacts by passing
	# -DCMAKE_POLICY_VERSION_MINIMUM=3.5 to the *whole* build. The top-level
	# range 3.1...3.20 is accepted by CMake 4 as-is (the range's max is what
	# satisfies it), so that global policy override buys nothing here and would
	# mask exactly the kind of policy incompatibility we want to fail loudly.
	# Drop the dead file instead. It must happen before cmake_src_prepare,
	# because the scan runs inside it. rm dies if upstream ever removes the
	# file, so a version bump cannot silently turn this into a no-op.
	rm JuceLibraryCode/modules/juce_audio_devices/native/oboe/CMakeLists.txt || die

	cmake_src_prepare
}

src_configure() {
	local mycmakeargs=(
		# Upstream defaults this ON, which would pull Doxygen in for everyone.
		-DENABLE_AUDIO_DOCS=$(usex doc)
		-DAUTO_INSTALL_DOCS=$(usex doc)
		# Keep the generated API docs inside the Gentoo docdir.
		-DCMAKE_INSTALL_DOCDIR="/usr/share/doc/${PF}"
	)
	cmake_src_configure
}
