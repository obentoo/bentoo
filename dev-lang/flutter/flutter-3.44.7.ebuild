# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit bash-completion-r1 readme.gentoo-r1

DESCRIPTION="Google's UI toolkit for building natively compiled apps"
HOMEPAGE="https://flutter.dev/"
SRC_URI="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${PV}-stable.tar.xz"

# The tarball extracts into a top-level flutter/ directory.
S="${WORKDIR}/${PN}"

LICENSE="BSD"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="examples"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

# Flutter 3.44.4 bundles and validates Dart SDK 3.12.2; a different dart-sdk
# version triggers an "sdk mismatch" error. Pin the exact version supplied by
# the unbundled dev-lang/dart (installed at /usr/lib/dart).
RDEPEND="~dev-lang/dart-3.12.2"

src_prepare() {
	default
	# Drop Windows batch launchers; they are useless on Gentoo.
	find . -iname '*.bat' -delete || die
}

src_compile() {
	# The flutter tool needs a dart-sdk to generate completions. The bundled
	# bin/cache/dart-sdk is still present here (it is only unbundled during
	# src_install), so this works.
	einfo "Building completions"
	DOC_CONTENTS=$("bin/${PN}" bash-completion "${PN}.bash-completion") || die
	DISABLE_AUTOFORMATTING=1 readme.gentoo_create_doc
}

src_install() {
	use examples || { rm -r examples/ || die; }

	# Unbundle the Dart SDK: remove the vendored copy and point the cache at
	# the system dev-lang/dart tree (installed at /usr/lib/dart by this overlay).
	rm -r bin/cache/dart-sdk || die

	newbashcomp "${PN}.bash-completion" "${PN}"
	rm "${PN}.bash-completion" || die

	dodir /opt
	mv "${S}" "${ED}/opt/${PN}" || die

	# Absolute symlink into the system Dart SDK installed by dev-lang/dart.
	dosym /usr/lib/dart "/opt/${PN}/bin/cache/dart-sdk"
	dosym "../${PN}/bin/${PN}" "/opt/bin/${PN}"
}

pkg_postinst() {
	readme.gentoo_print_elog
}
