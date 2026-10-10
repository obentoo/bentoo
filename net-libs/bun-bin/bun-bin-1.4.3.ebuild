# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="All-in-one JavaScript runtime, bundler and package manager (binary)"
HOMEPAGE="https://bun.sh https://github.com/oven-sh/bun"

SRC_URI="
	amd64? (
		cpu_flags_x86_avx2? (
			https://github.com/oven-sh/bun/releases/download/bun-v${PV}/bun-linux-x64.zip
				-> ${P}-linux-x64.zip
		)
		!cpu_flags_x86_avx2? (
			https://github.com/oven-sh/bun/releases/download/bun-v${PV}/bun-linux-x64-baseline.zip
				-> ${P}-linux-x64-baseline.zip
		)
	)
	arm64? (
		https://github.com/oven-sh/bun/releases/download/bun-v${PV}/bun-linux-aarch64.zip
			-> ${P}-linux-aarch64.zip
	)
"
S="${WORKDIR}"

# Bun (MIT) bundles JavaScriptCore (LGPL-2.1+ / BSD-2 / BSD), Zig (MIT),
# zlib (ZLIB), and many MIT/Apache-2.0 dependencies.
LICENSE="MIT BSD BSD-2 LGPL-2.1+ ZLIB Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="cpu_flags_x86_avx2"

RESTRICT="bindist mirror strip"
QA_PREBUILT="opt/${PN}/bin/bun"

BDEPEND="app-arch/unzip"

src_install() {
	local bun_dir
	if use amd64; then
		if use cpu_flags_x86_avx2; then
			bun_dir="bun-linux-x64"
		else
			bun_dir="bun-linux-x64-baseline"
		fi
	elif use arm64; then
		bun_dir="bun-linux-aarch64"
	else
		die "Unsupported architecture"
	fi

	[[ -x "${WORKDIR}/${bun_dir}/bun" ]] \
		|| die "bun binary not found at ${WORKDIR}/${bun_dir}/bun"

	exeinto /opt/${PN}/bin
	doexe "${WORKDIR}/${bun_dir}/bun"

	# bunx is just an alias for `bun x`
	dosym bun /opt/${PN}/bin/bunx

	# Expose binaries via /opt/bin (in PATH on bentoo/Gentoo profiles).
	dodir /opt/bin
	dosym ../${PN}/bin/bun /opt/bin/bun
	dosym ../${PN}/bin/bunx /opt/bin/bunx
}

pkg_postinst() {
	elog "Bun installed at /opt/${PN}/bin/bun"
	elog "Run with: bun (also available as 'bunx' for 'bun x')."
	if use amd64 && ! use cpu_flags_x86_avx2; then
		elog ""
		elog "Installed the AVX2-less 'baseline' variant for older CPUs."
	fi
}
