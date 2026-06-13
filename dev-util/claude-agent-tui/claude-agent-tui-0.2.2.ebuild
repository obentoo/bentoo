# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Run the Claude Code TUI in Zed's agent panel via an ACP-over-PTY bridge"
HOMEPAGE="https://github.com/lucascouts/claude-agent-tui"
SRC_URI="https://github.com/lucascouts/claude-agent-tui/releases/download/v${PV}/${P}.tar.gz"
S="${WORKDIR}/${P}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="mirror strip bindist"

RDEPEND="
	net-libs/nodejs
	dev-util/claude-code
"

QA_PREBUILT="usr/lib/node_modules/${PN}/node_modules/node-pty/build/Release/pty.node"

src_compile() {
	:
}

src_install() {
	insinto /usr/lib/node_modules/${PN}
	doins -r dist node_modules package.json
	dodoc README.md NOTICE

	# Executable wrapper: doins strips the +x bit, so the wrapper itself
	# carries it via fperms. dist/index.js is invoked through 'node' and
	# pty.node is loaded via dlopen, so neither needs +x.
	dodir /usr/bin
	cat > "${ED}/usr/bin/claude-agent-acp" <<-EOF || die
		#!/bin/sh
		exec node /usr/lib/node_modules/${PN}/dist/index.js "\$@"
	EOF
	fperms +x /usr/bin/claude-agent-acp
}

pkg_postinst() {
	elog "The bridge is installed as the 'claude-agent-acp' executable."
	elog ""
	elog "To enable it in Zed, add the following to ~/.config/zed/settings.json:"
	elog ""
	elog "    \"agent_servers\": {"
	elog "        \"Claude TUI\": { \"command\": \"claude-agent-acp\", \"args\": [] }"
	elog "    }"
}
