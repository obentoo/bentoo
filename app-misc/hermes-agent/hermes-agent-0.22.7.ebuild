# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_SINGLE_IMPL=1
DISTUTILS_USE_PEP517=setuptools
# Upstream caps requires-python at <3.14 only because PyPI lacked cp314
# wheels for its Rust-backed transitives; Portage builds those from source.
PYTHON_COMPAT=( python3_{12..14} )

inherit distutils-r1 optfeature

# Git tags are dated (vYYYY.M.D); pyproject carries the SemVer that is PV.
# Both move together on every release: bump MY_TAG with PV.
MY_TAG="0.22.7"

DESCRIPTION="Self-improving AI agent CLI by Nous Research"
HOMEPAGE="
	https://hermes-agent.nousresearch.com/
	https://github.com/NousResearch/hermes-agent/
"
# PyPI stopped at 0.19.0: upstream retired the pip channel.
SRC_URI="
	https://github.com/NousResearch/hermes-agent/archive/refs/tags/v${MY_TAG}.tar.gz
		-> ${P}.gh.tar.gz
"
S="${WORKDIR}/${PN}-${MY_TAG}"

LICENSE="MIT"
SLOT="0"
# ~arm64 is blocked by dev-python/fastapi, which ::gentoo keywords ~amd64
# only. Everything else in the graph, including the Rust extensions, builds
# on aarch64; add ~arm64 once fastapi carries it.
KEYWORDS="~amd64"
# The suite (~85 directories) mixes network, Docker, browser and gateway
# tests and expects a uv-built venv; it is not runnable in the sandbox.
RESTRICT="test"

# Upstream exact-pins every core dependency (supply-chain policy, see the
# comment block in pyproject.toml). Here they are floors where Gentoo is at
# or ahead, bare where Gentoo is behind and the API is stable.
# - openai: upstream pins 2.24.0; this overlay carries 3.x, which still
#   accepts the legacy httpx client hermes injects (runtime escape hatch
#   documented in openai's httpx2.md).
# - httpx[socks] is socksio. httpx is in ::gentoo package.deprecated
#   (upstream stopped taking bug reports), but hermes imports it directly
#   throughout; there is no drop-in until upstream moves to httpx2.
# - nemo-relay is left out: it is imported lazily, only by the
#   `hermes migrate relay` subcommand, and needs aws-lc-sys plus protoc.
# - git and ripgrep are on the default tool path (nix/hermes-agent.nix).
RDEPEND="
	dev-vcs/git
	sys-apps/ripgrep
	$(python_gen_cond_dep '
		dev-python/certifi[${PYTHON_USEDEP}]
		>=dev-python/croniter-6.0.0[${PYTHON_USEDEP}]
		>=dev-python/cryptography-50.0.0[${PYTHON_USEDEP}]
		>=dev-python/fastapi-0.104.0[${PYTHON_USEDEP}]
		>=dev-python/fire-0.7.1[${PYTHON_USEDEP}]
		>=dev-python/firecrawl-anydoc-0.2.4[${PYTHON_USEDEP}]
		>=dev-python/httptools-0.6.3[${PYTHON_USEDEP}]
		>=dev-python/httpx-0.28.1[${PYTHON_USEDEP}]
		>=dev-python/jinja2-3.1.6[${PYTHON_USEDEP}]
		>=dev-python/markdown-3.10.2[${PYTHON_USEDEP}]
		dev-python/openai[${PYTHON_USEDEP}]
		>=dev-python/packaging-26.0[${PYTHON_USEDEP}]
		>=dev-python/pathspec-1.1.1[${PYTHON_USEDEP}]
		>=dev-python/pillow-12.3.0[${PYTHON_USEDEP}]
		>=dev-python/pillow-heif-1.4.0[${PYTHON_USEDEP}]
		>=dev-python/prompt-toolkit-3.0.52[${PYTHON_USEDEP}]
		>=dev-python/psutil-7.2.2[${PYTHON_USEDEP}]
		>=dev-python/ptyprocess-0.7.0[${PYTHON_USEDEP}]
		>=dev-python/pydantic-2.13.4[${PYTHON_USEDEP}]
		>=dev-python/pyjwt-2.13.0[${PYTHON_USEDEP}]
		>=dev-python/python-dotenv-1.2.2[${PYTHON_USEDEP}]
		>=dev-python/python-multipart-0.0.9[${PYTHON_USEDEP}]
		>=dev-python/pyyaml-6.0.3[${PYTHON_USEDEP}]
		>=dev-python/requests-2.33.0[${PYTHON_USEDEP}]
		>=dev-python/rich-14.3.3[${PYTHON_USEDEP}]
		>=dev-python/ruamel-yaml-0.18.17[${PYTHON_USEDEP}]
		>=dev-python/snowballstemmer-3.1.1[${PYTHON_USEDEP}]
		dev-python/socksio[${PYTHON_USEDEP}]
		>=dev-python/tenacity-9.1.4[${PYTHON_USEDEP}]
		>=dev-python/urllib3-2.7.0[${PYTHON_USEDEP}]
		>=dev-python/uvicorn-0.31.0[${PYTHON_USEDEP}]
		>=dev-python/uvloop-0.15.1[${PYTHON_USEDEP}]
		>=dev-python/watchfiles-0.20[${PYTHON_USEDEP}]
		>=dev-python/websockets-15.0.1[${PYTHON_USEDEP}]
	')
"

# setup.py refuses to build a wheel unless HERMES_NIX_BUILD=1: upstream
# retired the pip/PyPI channels and only lets its uv2nix derivation build
# one. Portage is the same kind of sealed, pinned build, so opt in.
export HERMES_NIX_BUILD=1

src_install() {
	distutils-r1_src_install

	# The wheel puts ~50 top-level modules into site-packages, many with
	# generic names (agent, cli, cron, gateway, plugins, providers, tools,
	# utils). Move them into a private venv that still sees the system
	# site-packages for its dependencies -- the layout upstream's own
	# uv2nix build uses. sys.executable then points into the venv, so the
	# 27 places that respawn `sys.executable -m hermes_cli...` keep working,
	# and nothing leaks onto PYTHONPATH of the commands the agent runs.
	local venv=/usr/lib/${PN}
	local vsite=${venv}/lib/${EPYTHON}/site-packages
	dodir "${vsite}" "${venv}/bin"
	mv "${D}$(python_get_sitedir)"/* "${ED}${vsite}/" || die
	rmdir "${D}$(python_get_sitedir)" || die
	find "${ED}${vsite}" -name __pycache__ -type d -prune -exec rm -r {} + || die
	python_optimize "${ED}${vsite}"
	dosym -r "/usr/bin/${EPYTHON}" "${venv}/bin/python"
	cat > "${ED}${venv}/pyvenv.cfg" <<-EOF || die
		home = ${EPREFIX}/usr/bin
		include-system-site-packages = true
		version = $("${EPYTHON}" -c 'import platform; print(platform.python_version())')
	EOF

	# Assets the wheel omits; resolved at runtime via the HERMES_* overrides
	# below (hermes_constants.py, mirroring nix/hermes-agent.nix).
	# HERMES_WEB_DIST and HERMES_TUI_DIR stay unset: they point at Node
	# bundles (dashboard, TUI) this ebuild does not build.
	# cp, not doins: 39 skill/plugin scripts are 0755 and are exec'd by the
	# agent; doins -r would flatten them to 0644.
	dodir /usr/share/${PN}
	cp -dR --preserve=mode skills optional-skills plugins locales \
		optional-mcps "${ED}/usr/share/${PN}/" || die

	# Entry points: the generated /usr/bin scripts are replaced by venv
	# scripts plus shell wrappers that set the distribution policy:
	# - HERMES_DISABLE_LAZY_INSTALLS=1: tools/lazy_deps.py otherwise runs
	#   `pip install` / `uv pip install` whenever a tool needs a missing
	#   extra (the venv being root-owned is a second barrier).
	# - TIRITH_BIN: with the default value "tirith", tools/tirith_security.py
	#   downloads a binary from GitHub into ~/.hermes/bin and executes it.
	#   An explicit path is authoritative and never auto-downloaded.
	# Each is a default (${VAR:-...}), so an exported value still wins.
	local s mod
	for s in hermes:hermes_cli.main hermes-agent:agent.legacy_cli \
		hermes-acp:acp_adapter.entry; do
		mod=${s#*:}
		s=${s%%:*}
		rm "${ED}/usr/bin/${s}" || die
		cat > "${ED}${venv}/bin/${s}" <<-EOF || die
			#!${EPREFIX}${venv}/bin/python
			import sys
			from ${mod} import main
			sys.exit(main())
		EOF
		fperms +x "${venv}/bin/${s}"
		newbin - "${s}" <<-EOF
			#!/bin/sh
			export HERMES_BUNDLED_SKILLS="\${HERMES_BUNDLED_SKILLS:-${EPREFIX}/usr/share/${PN}/skills}"
			export HERMES_OPTIONAL_SKILLS="\${HERMES_OPTIONAL_SKILLS:-${EPREFIX}/usr/share/${PN}/optional-skills}"
			export HERMES_BUNDLED_PLUGINS="\${HERMES_BUNDLED_PLUGINS:-${EPREFIX}/usr/share/${PN}/plugins}"
			export HERMES_BUNDLED_LOCALES="\${HERMES_BUNDLED_LOCALES:-${EPREFIX}/usr/share/${PN}/locales}"
			export HERMES_OPTIONAL_MCPS="\${HERMES_OPTIONAL_MCPS:-${EPREFIX}/usr/share/${PN}/optional-mcps}"
			export HERMES_PYTHON="\${HERMES_PYTHON:-${EPREFIX}${venv}/bin/python}"
			export HERMES_BIN="\${HERMES_BIN:-${EPREFIX}/usr/bin/hermes}"
			export HERMES_DISABLE_LAZY_INSTALLS="\${HERMES_DISABLE_LAZY_INSTALLS:-1}"
			export TIRITH_BIN="\${TIRITH_BIN:-${EPREFIX}/usr/bin/tirith}"
			exec "${EPREFIX}${venv}/bin/${s}" "\$@"
		EOF
	done

	dodoc README.md SECURITY.md cli-config.yaml.example
}

pkg_postinst() {
	ewarn "hermes-agent runs shell commands on this host by default"
	ewarn "(terminal.backend: local). Upstream's SECURITY.md is explicit that"
	ewarn "the approval prompt is not a security boundary: only OS isolation"
	ewarn "is. Never run it as root; prefer a container/ssh terminal backend"
	ewarn "or a sandbox such as sys-apps/ai-jail or sys-apps/firejail."
	elog
	elog "Runtime package installation is disabled by the wrapper"
	elog "(HERMES_DISABLE_LAZY_INSTALLS=1). Features whose Python extras are"
	elog "not packaged report themselves unavailable instead of running pip."
	elog "The browser tool still falls back to 'npx agent-browser', which"
	elog "fetches code from the npm registry into your home directory."
	elog
	elog "Command pre-scanning uses tirith from ${EPREFIX}/usr/bin/tirith and"
	elog "is skipped (fail-open) when it is absent; the binary is never"
	elog "downloaded automatically."

	optfeature "audio/video tools" media-video/ffmpeg
	optfeature "the ssh terminal backend" virtual/openssh
	optfeature "the browser tool (npx agent-browser)" net-libs/nodejs
	optfeature "clipboard access on Wayland" gui-apps/wl-clipboard
	optfeature "clipboard access on X11" x11-misc/xclip
}
