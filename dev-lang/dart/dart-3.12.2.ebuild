# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

DESCRIPTION="The Dart SDK (official prebuilt binary)"
HOMEPAGE="https://dart.dev https://github.com/dart-lang/sdk"
SRC_URI="
	amd64? (
		https://storage.googleapis.com/dart-archive/channels/stable/release/${PV}/sdk/dartsdk-linux-x64-release.zip
			-> ${P}-amd64.zip
	)
	arm64? (
		https://storage.googleapis.com/dart-archive/channels/stable/release/${PV}/sdk/dartsdk-linux-arm64-release.zip
			-> ${P}-arm64.zip
	)
"

# The zip extracts into a top-level dart-sdk/ directory.
S="${WORKDIR}/dart-sdk"

LICENSE="BSD"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="strip"

QA_PREBUILT="*"

src_install() {
	# Install the whole SDK tree into /usr/lib/dart.
	# Use cp -r (not doins) so the executable bits set inside the official
	# zip are preserved; doins would reset every file to 0644 and break the
	# launchers.
	dodir /usr/lib/dart
	cp -r . "${ED}/usr/lib/dart/" || die

	# Defensively guarantee the launchers/utilities are executable, in case
	# upstream ever ships them without the +x bit.
	fperms +x /usr/lib/dart/bin/dart
	fperms +x /usr/lib/dart/bin/dartaotruntime
	fperms +x /usr/lib/dart/bin/utils/gen_snapshot
	if [[ -e "${ED}/usr/lib/dart/bin/utils/wasm-opt" ]]; then
		fperms +x /usr/lib/dart/bin/utils/wasm-opt
	fi

	dosym ../lib/dart/bin/dart /usr/bin/dart
	dosym ../lib/dart/bin/dartaotruntime /usr/bin/dartaotruntime
}
