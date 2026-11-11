# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Gemini CLI, Google's terminal AI agent"
HOMEPAGE="https://google-gemini.github.io/gemini-cli/ https://github.com/google-gemini/gemini-cli"
# GitHub publishes no Linux artefact for this; upstream distributes through npm
# only. The tarball is a self-contained JavaScript bundle, not a wrapper that
# downloads a platform binary.
SRC_URI="
	https://registry.npmjs.org/@google/${PN}/-/${P}.tgz
"
S="${WORKDIR}/package"

LICENSE="Apache-2.0"
SLOT="0"
# Pure JavaScript: nothing here is architecture-specific, so this is not
# restricted to the two arches the prebuilt packages in this overlay carry.
KEYWORDS="~amd64"

RDEPEND="net-libs/nodejs:*"

src_install() {
	insinto /usr/share/${PN}
	doins -r bundle

	# Upstream's package.json points bin at bundle/gemini.js, which is meant
	# to be reached through node_modules/.bin. There is no node_modules here,
	# so the launcher is written out with an absolute path.
	cat > "${T}"/gemini <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/bundle/gemini.js "\$@"
	EOF
	dobin "${T}"/gemini

	dodoc README.md
}
