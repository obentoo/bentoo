# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module systemd

DESCRIPTION="Transparent model-swapping proxy for llama.cpp, vLLM and other OpenAI-compatible servers"
HOMEPAGE="https://github.com/mostlygeek/llama-swap"

# Upstream tarball only.
#
# The adopted ebuild sourced EVERYTHING — including the main source — from
# raw.githubusercontent.com/istitov/extra-stuff (mirrored to codeberg and
# gitlab), a third party's personal account. Even with three mirrors that is a
# trust domain neither the code authors nor this overlay control, and the
# bundle was demonstrably built ad-hoc: it carried a stray `proxy/` directory
# that upstream deleted several releases ago.
SRC_URI="https://github.com/mostlygeek/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-${PV}"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses. Go links
# statically, so every one of these ships inside the installed binary.
#
# Surveyed at v250 on 2026-08-16 by running `go mod vendor` and classifying all
# 85 license files across the 80 vendored modules: 50 MIT, 15 BSD-2,
# 12 Apache-2.0, 6 BSD (3-clause), 1 ISC. The only unclassified file was
# modernc.org/memory/LICENSE-LOGO, which is a Wikimedia URL for a logo, not a
# code license; that module carries its real LICENSE separately.
#
# MPL-2.0 is deliberately absent. An earlier draft listed it, copied from
# dev-util/trivy's set rather than surveyed — no vendored module here is under
# it. Re-run the survey at each bump instead of carrying this list forward.
LICENSE+=" Apache-2.0 BSD BSD-2 ISC"
SLOT="0"
# ~arm64 ships here, unlike the ggml family in this overlay, and the difference
# is real rather than a lapse: this is pure Go with no cgo. There is no
# `import "C"` anywhere in the tree and the SQLite driver is modernc.org/sqlite,
# a pure-Go implementation — so no architecture-specific code path exists to go
# unexercised. Upstream builds GOOS=linux GOARCH=arm64 as a first-class release
# target in its own Makefile.
#
# Contrast sci-ml/{llama-cpp,koboldcpp,sherpa-onnx}, which are ~amd64 only:
# those compile C++ with SIMD/NEON paths that genuinely differ per arch.
KEYWORDS="~amd64 ~arm64"
IUSE="systemd ui"

# nodejs is slotted in this overlay (SLOT 24 and 26); the unslotted atom
# deliberately accepts either, matching how the rest of the tree depends on it.
#
# EXPECTED pkgcheck finding: NonsolvableDepsInDev on the
# default/linux/amd64/23.0/x32 profile, solutions [ net-libs/nodejs[npm] ].
# It is accurate and it is not fixable from inside this ebuild: nodejs is
# simply unavailable on amd64/x32, and ::gentoo handles that by masking each
# dependent package in profiles/arch/amd64/x32/package.mask — that file is full
# of "Requires net-libs/nodejs which is unavailable on amd64/x32" entries.
#
# An overlay cannot add to a master's profile. The real fix is for bentoo to
# ship its own profile tree, which is already recorded as a follow-up in story
# 002 for the same class of problem (the arm64/ROCm solver artifact). Until
# then this finding is expected here and must not be "fixed" by dropping the
# USE flag or the dependency.
BDEPEND="
	>=dev-lang/go-1.26.1
	ui? ( net-libs/nodejs[npm] )
"

# The Go module cache is populated at src_unpack, so the network sandbox has to
# be off for the default build. This is the overlay's established pattern for
# Go packages — see dev-util/trivy and dev-util/act, both of which do the same
# for the same reason — and it is a deliberate departure from story 003 R4.1,
# which asked for a sandbox-clean default.
#
# The alternative is a generated vendor tarball, and it is not free: upstream
# publishes no vendor/ directory (verified absent at v250), so the overlay would
# have to build the tarball itself, host it on distfiles.obentoo.org, and carry
# hold = true in the autoupdate record forever after — exactly the arrangement
# dev-build/gn documents, where a bump stops being a PV swap and becomes a
# publish-then-bump. That is a maintenance commitment, not a code change; it is
# recorded as the reversal condition rather than assumed.
#
# USE=ui adds a second network consumer (npm), which is why it is named here
# too: the flag does not toggle the restriction, it only widens what uses it.
RESTRICT="network-sandbox"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	local mytags=()

	if use ui; then
		# The Svelte UI lives in ui-svelte/ and vite writes its output to
		# ../internal/server/ui_dist (see ui-svelte/vite.config.*). That path
		# is NOT shipped in the tarball, so it must be built here.
		#
		# npm ci, not npm install: upstream commits ui-svelte/package-lock.json
		# and `ci` installs exactly what the lockfile pins, failing if the two
		# disagree. `install` silently resolves newer versions instead, which
		# defeats the integrity the lockfile exists to provide. The adopted
		# ebuild ran `npm ci` under a comment claiming `npm install` was used
		# and more forgiving; the code was right and the comment was wrong.
		cd "${S}/ui-svelte" || die
		npm ci --no-audit --no-fund || die "npm ci failed"
		npm run build || die "vite build failed"
		cd "${S}" || die

		[[ -d internal/server/ui_dist ]] ||
			die "ui_dist was not produced; vite's outDir may have moved"

		# THE flag that makes USE=ui mean anything. internal/server/embed.go
		# carries `//go:build embed_ui` and is what embeds ui_dist; without the
		# tag the compiler takes embed_notag.go instead, whose uiFS serves no
		# files. The adopted ebuild omitted it, so USE=ui ran a full npm
		# install, built the Svelte app, and then shipped a binary with no UI
		# in it — the build cost with none of the benefit.
		mytags+=( embed_ui )
	fi

	# No else-branch, deliberately. The adopted ebuild wrote a placeholder
	# index.html into proxy/ui_dist for USE=-ui, which was dead code twice
	# over: upstream's embed_notag.go already provides the empty-filesystem
	# fallback, and proxy/ has not existed in this repository for several
	# releases (verified absent at v250), so the stub wrote to a path nothing
	# read.

	# -trimpath removes the build directory from the binary. Go records the
	# absolute path of every compiled file by default, which put 305 copies of
	# /var/tmp/portage/... into the installed binary. Unlike the C++ case in
	# sci-ml/sherpa-onnx these are not printed at the user, but they are still
	# the sandbox path of whoever built the package, and they defeat
	# reproducible builds: two machines produce different binaries from
	# identical input.
	#
	# ::gentoo tolerates the leak widely (docker ships 1327 of these, podman
	# 2759), so this is a deliberate improvement on the baseline rather than a
	# rule being followed.
	ego build \
		-trimpath \
		-tags "${mytags[*]}" \
		-ldflags "-s -w -X main.version=${PV} -X main.commit=gentoo -X main.date=unknown" \
		-o "${PN}" .
}

src_install() {
	dobin "${PN}"
	einstalldocs

	# OpenRC is installed unconditionally and systemd is gated behind its USE
	# flag. This asymmetry is deliberate and required by CLAUDE.md: the unit
	# costs a systemd user nothing, and the init script is the only way anyone
	# else can run the daemon.
	newinitd "${FILESDIR}/${PN}.initd" "${PN}"
	newconfd "${FILESDIR}/${PN}.confd" "${PN}"

	if use systemd; then
		# The unit is a per-user template, so it must be INSTALLED as
		# llama-swap@.service — systemd only expands %i for a name containing
		# '@'. It cannot be STORED under that name: '@' is not allowed in
		# files/ and pkgcheck rejects it (BannedCharacter). Hence newunit,
		# which renames on install. The adopted ebuild stored and installed it
		# as a plain llama-swap.service while its body used %i and User=%i,
		# so the unit could never have worked as written.
		systemd_newunit "${FILESDIR}/${PN}.service" "${PN}@.service"

		# The unit is a per-user template and reads
		# /etc/default/llama-swap@<user>, which nothing created — so it failed
		# at start until an admin guessed the format. Ship the template it
		# expects, as an example rather than as a live config: writing
		# /etc/default/llama-swap@ with no instance name would be a file
		# systemd never reads, and guessing an instance name would be worse.
		insinto /etc/default
		newins "${FILESDIR}/${PN}.env.example" "${PN}@.example"
	fi
}

pkg_postinst() {
	elog "llama-swap proxies OpenAI-compatible requests to backends it starts"
	elog "and stops on demand. It ships no config; you supply the YAML."
	elog ""
	elog "OpenRC:"
	elog "  1. set LLAMA_SWAP_USER in /etc/conf.d/llama-swap (required)"
	elog "  2. write \${HOME}/.config/llama-swap.yaml for that user,"
	elog "     or point LLAMA_SWAP_CONFIG elsewhere"
	elog "  3. rc-service llama-swap start"
	if use systemd; then
		elog ""
		elog "systemd (per-user template):"
		elog "  cp /etc/default/llama-swap@.example /etc/default/llama-swap@<user>"
		elog "  edit it, then: systemctl enable --now llama-swap@<user>"
	fi
	elog ""
	elog "Both service files bind 127.0.0.1:8080 by default. llama-swap has no"
	elog "authentication of its own — do not expose it to a network you do not"
	elog "control without putting an authenticating proxy in front of it."
	if ! use ui; then
		elog ""
		elog "Built without USE=ui: the web interface is not embedded and /ui"
		elog "will serve nothing. The API is unaffected."
	fi
}
