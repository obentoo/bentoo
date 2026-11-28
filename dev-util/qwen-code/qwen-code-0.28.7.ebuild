# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Qwen Code, Alibaba's terminal coding agent"
HOMEPAGE="https://qwenlm.github.io/qwen-code-docs/ https://github.com/QwenLM/qwen-code"
QWEN_BASE="https://github.com/QwenLM/qwen-code/releases/download/v${PV}"
# Upstream also publishes "-opentui-preview" builds of every target; those are
# an experimental UI and are not tracked here.
SRC_URI="
	amd64? (
		${QWEN_BASE}/qwen-code-linux-x64.tar.gz
			-> ${P}-amd64.tar.gz
	)
"
S="${WORKDIR}/qwen-code"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

# The bundle is JavaScript executed by Node; the private runtime it ships with
# is discarded in src_prepare, so a system Node is required at runtime.
RDEPEND=">=net-libs/nodejs-22:*"

QA_PREBUILT="*"

src_prepare() {
	default

	# Upstream bundles a complete private Node.js -- 199 MiB of a 303 MiB
	# tarball, two thirds of the package. Shipping a second Node runtime is
	# not a distribution's job when net-libs/nodejs is right there, so the
	# bundle goes and the launcher is rewritten to use the system one.
	#
	# Asserted rather than assumed: sed exits 0 when it matches nothing, so
	# an upstream launcher change would otherwise leave a script pointing at
	# a directory this ebuild deleted.
	grep -qF 'ROOT/node/bin/node' bin/qwen ||
		die "bin/qwen no longer invokes the bundled node -- re-check it"

	rm -r node || die
}

src_install() {
	insinto /usr/share/${PN}
	doins -r lib manifest.json package.json
	# doins installs everything 0644, but qwen execs its bundled ripgrep and
	# landlock runner directly. It only tries to chmod them itself at run
	# time, which a normal user cannot do on a root-owned file, so search
	# falls back to a system rg and the landlock sandbox throws.
	fperms 0755 /usr/share/${PN}/lib/vendor/ripgrep/x64-linux/rg \
		/usr/share/${PN}/lib/vendor/landlock-run/x64-linux/qwen-landlock-run

	# A hand-written launcher instead of upstream's: theirs derives its root
	# from dirname "$0", which resolves to /usr/bin when reached through a
	# symlink and would look for lib/ in the wrong place.
	cat > "${T}"/qwen <<-EOF || die
		#!/bin/sh
		QWEN_CODE_LAUNCHER_PATH=/usr/bin/qwen \\
			exec node /usr/share/${PN}/lib/cli-entry.js "\$@"
	EOF
	dobin "${T}"/qwen

	dodoc README.md
}
