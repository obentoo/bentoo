# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="AI coding agent CLI (prebuilt binary, bundles a static bubblewrap sandbox)"
HOMEPAGE="https://github.com/Kilo-Org/kilocode"
SRC_URI="
	amd64? ( https://github.com/Kilo-Org/kilocode/releases/download/v${PV}/kilo-linux-x64.tar.gz -> ${P}-amd64.tar.gz )
	arm64? ( https://github.com/Kilo-Org/kilocode/releases/download/v${PV}/kilo-linux-arm64.tar.gz -> ${P}-arm64.tar.gz )
"
S="${WORKDIR}"

# Upstream project is MIT. The tarball bundles third-party components under
# licenses/, each with its own terms:
#   licenses/sandbox-runtime/LICENSE  -> Apache-2.0
#   licenses/bubblewrap/COPYING       -> LGPL-2 (bundled bubblewrap 0.11.2)
#   licenses/bubblewrap/MUSL-COPYRIGHT -> MIT (musl)
LICENSE="MIT Apache-2.0 LGPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	# Not relocatable piecemeal: "kilo" expects bwrap, the sandbox worker
	# scripts, the seccomp helper and tree-sitter/ all beside it.
	insinto /opt/kilocode
	doins -r bwrap console kilo kilo-sandbox-mutation-worker.js \
		kilo-sandbox-network-relay.js kilo-sandbox-seccomp licenses \
		tree-sitter || die

	# doins strips the executable bit; restore it on the three binaries that
	# need it. bwrap stays 0755 (static-pie, unprivileged user namespaces) --
	# never setuid it.
	fperms 0755 /opt/kilocode/kilo /opt/kilocode/bwrap \
		/opt/kilocode/kilo-sandbox-seccomp || die

	dosym ../kilocode/kilo /opt/bin/kilo || die
}
