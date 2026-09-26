# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

DESCRIPTION="Codex CLI - OpenAI's AI-powered coding agent (prebuilt binary)"
HOMEPAGE="https://github.com/openai/codex"

SRC_URI="
	amd64? (
		https://github.com/openai/codex/releases/download/rust-v${PV}/codex-x86_64-unknown-linux-musl.tar.gz
			-> ${P}-x86_64-unknown-linux-musl.tar.gz
	)
	arm64? (
		https://github.com/openai/codex/releases/download/rust-v${PV}/codex-aarch64-unknown-linux-musl.tar.gz
			-> ${P}-aarch64-unknown-linux-musl.tar.gz
	)
"

S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="strip"

RDEPEND="!dev-util/codex"

src_install() {
	if use amd64; then
		newbin codex-x86_64-unknown-linux-musl codex
	elif use arm64; then
		newbin codex-aarch64-unknown-linux-musl codex
	else
		die "Unsupported architecture"
	fi
}
