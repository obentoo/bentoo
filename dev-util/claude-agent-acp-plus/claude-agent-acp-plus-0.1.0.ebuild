# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="ACP adapter for the Claude Agent SDK, VS Code-parity fork (checkbox-capable)"
HOMEPAGE="https://github.com/lucascouts/claude-agent-acp-plus"
SRC_URI="https://github.com/lucascouts/claude-agent-acp-plus/releases/download/v${PV}/${P}.tar.gz"
S="${WORKDIR}/${P}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
# strip/bindist: the bundle ships a Bun-compiled native Claude CLI binary.
RESTRICT="mirror strip bindist"

# The Claude CLI is embedded as the SDK's native binary inside the bundle
# (node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude), so unlike
# the claude-agent-tui sibling this fork does NOT depend on dev-util/claude-code.
RDEPEND=">=net-libs/nodejs-22"

# Only prebuilt ELF in the bundle (glibc/x64; zero .node addons).
QA_PREBUILT="usr/lib/node_modules/${PN}/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude"

src_compile() {
	:
}

src_install() {
	insinto /usr/lib/node_modules/${PN}
	doins -r dist node_modules package.json
	# No NOTICE file ships in this fork (unlike claude-agent-tui).
	dodoc README.md

	# Executable wrapper: doins strips the +x bit, so the wrapper itself
	# carries it via fperms. dist/index.js is invoked through 'node'.
	# Wrapper is named 'claude-agent-acp-plus' (its own distinct path, no
	# longer colliding with the claude-agent-acp-tui sibling).
	dodir /usr/bin
	cat > "${ED}/usr/bin/claude-agent-acp-plus" <<-EOF || die
		#!/bin/sh
		exec node /usr/lib/node_modules/${PN}/dist/index.js "\$@"
	EOF
	fperms +x /usr/bin/claude-agent-acp-plus
}

pkg_postinst() {
	elog "The adapter is installed as the 'claude-agent-acp-plus' executable."
	elog ""
	elog "In Zed, point your agent_servers \"command\" at \"claude-agent-acp-plus\""
	elog "to use this VS Code-parity fork (AskUserQuestion multiSelect -> array/anyOf)."
	elog ""
	elog "The Claude CLI is bundled as the SDK's native binary (glibc/amd64)."
	elog "On musl or other arches, point CLAUDE_CODE_EXECUTABLE at an external"
	elog "claude binary."
}
