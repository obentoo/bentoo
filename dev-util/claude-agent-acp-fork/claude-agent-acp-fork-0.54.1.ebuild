# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="ACP adapter for the Claude Agent SDK, checkbox-capable fork"
HOMEPAGE="https://github.com/lucascouts/claude-agent-acp-fork"
SRC_URI="https://github.com/lucascouts/claude-agent-acp-fork/releases/download/v${PV}/${P}.tar.gz"
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
	# Wrapper is named 'claude-agent-acp' (not -fork) so Zed's existing
	# agent_servers "command": "claude-agent-acp" keeps working.
	# NOTE: /usr/bin/claude-agent-acp is also currently shipped by
	# dev-util/claude-agent-tui-0.7.0; that sibling is being renamed to
	# provide /usr/bin/claude-agent-tui, freeing this path (no blocker needed).
	dodir /usr/bin
	cat > "${ED}/usr/bin/claude-agent-acp" <<-EOF || die
		#!/bin/sh
		exec node /usr/lib/node_modules/${PN}/dist/index.js "\$@"
	EOF
	fperms +x /usr/bin/claude-agent-acp
}

pkg_postinst() {
	elog "The adapter is installed as the 'claude-agent-acp' executable."
	elog ""
	elog "Zed's \"command\": \"claude-agent-acp\" agent_servers entry now uses"
	elog "this checkbox-capable fork (AskUserQuestion multiSelect -> array/anyOf)."
	elog ""
	elog "The Claude CLI is bundled as the SDK's native binary (glibc/amd64)."
	elog "On musl or other arches, point CLAUDE_CODE_EXECUTABLE at an external"
	elog "claude binary."
}
