# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

MY_PN="zed"
DESCRIPTION="The fast, collaborative code editor (binary package)"
HOMEPAGE="https://zed.dev https://github.com/zed-industries/zed"
SRC_URI="
	amd64? (
		https://github.com/zed-industries/zed/releases/download/v${PV/_/-}/${MY_PN}-linux-x86_64.tar.gz
			-> ${P}-linux-x86_64.tar.gz
	)
	arm64? (
		https://github.com/zed-industries/zed/releases/download/v${PV/_/-}/${MY_PN}-linux-aarch64.tar.gz
			-> ${P}-linux-aarch64.tar.gz
	)
"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="mirror strip bindist"
IUSE="+claude-agent-acp-plus +claude-agent-acp-tui"

RDEPEND="
	app-arch/zstd:=
	dev-db/sqlite:3
	>=dev-libs/libgit2-1.9.0:=
	dev-libs/openssl:0/3
	dev-libs/wayland
	|| (
		media-fonts/dejavu
		media-fonts/cantarell
		media-fonts/noto
		media-fonts/ubuntu-font-family
	)
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/vulkan-loader[X]
	claude-agent-acp-plus? ( dev-util/claude-agent-acp-plus )
	claude-agent-acp-tui? ( dev-util/claude-agent-acp-tui )
"

QA_PREBUILT="
	opt/zed-bin/bin/*
	opt/zed-bin/libexec/*
	opt/zed-bin/lib/*
"

src_unpack() {
	default
	# Upstream tarballs unpack to a single top-level "*.app" directory whose
	# name depends on the release channel: "zed.app" (stable) or
	# "zed-preview.app" (preview, e.g. *_pre releases). Resolve S dynamically
	# so the ebuild works regardless of channel.
	S=$(echo "${WORKDIR}"/*.app)
}

src_install() {
	# Install to /opt/zed-bin
	insinto /opt/zed-bin
	doins -r bin lib libexec
	dodoc licenses.md

	# Fix permissions for executables
	fperms +x /opt/zed-bin/libexec/zed-editor
	fperms +x /opt/zed-bin/bin/zed

	# Symlink CLI to /usr/bin as 'zedit-bin' to avoid conflict with source ebuild
	dosym ../../opt/zed-bin/bin/zed /usr/bin/zedit-bin

	# Derive the runtime Wayland app_id from the bundled .desktop filename so
	# both the stable ("dev.zed.Zed") and preview ("dev.zed.Zed-Preview")
	# channels resolve their window icon correctly.
	local desktop_src appid
	desktop_src=$(echo share/applications/*.desktop)
	if [[ -f ${desktop_src} ]]; then
		appid=$(basename "${desktop_src}" .desktop)
	else
		appid="dev.zed.Zed"
	fi

	# Install icons named after the Wayland app_id so that Wayland compositors
	# resolve the window icon correctly. Without this, compositors fall back to
	# the generic Wayland icon.
	if [[ -d share/icons ]]; then
		local size icon
		for icon in share/icons/hicolor/*/apps/zed.png; do
			if [[ -f "${icon}" ]]; then
				size="${icon#share/icons/hicolor/}"
				size="${size%%x*}"
				newicon -s "${size}" "${icon}" "${appid}.png"
			fi
		done
	fi

	# Install desktop file with filename matching the runtime Wayland app_id.
	# This is what compositors look up to find the window icon.
	if [[ -f ${desktop_src} ]]; then
		sed -e "s|^Exec=.*|Exec=/opt/zed-bin/bin/zed %U|" \
			-e "s|^Icon=.*|Icon=${appid}|" \
			-e "s|^TryExec=.*|TryExec=/opt/zed-bin/bin/zed|" \
			-e "/^Actions=/i StartupWMClass=${appid}" \
			"${desktop_src}" > "${T}/${appid}.desktop" || die
		domenu "${T}/${appid}.desktop"
	else
		make_desktop_entry "/opt/zed-bin/bin/zed %U" \
			"Zed" "${appid}" \
			"Development;IDE;TextEditor;" \
			"StartupNotify=true\nStartupWMClass=${appid}\nMimeType=text/plain;inode/directory;"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Zed binary edition installed."
	elog "Launch with: zedit-bin"
	elog ""
	elog "This package conflicts with app-editors/zed (source build)."
	elog "If you want the source-compiled version, use app-editors/zed instead."

	if use claude-agent-acp-plus; then
		elog ""
		elog "The claude-agent-acp-plus ACP adapter was installed as 'claude-agent-acp-plus'."
		elog "To enable it in Zed, add to ~/.config/zed/settings.json:"
		elog ""
		elog "    \"agent_servers\": {"
		elog "        \"Claude Agent Plus\": { \"command\": \"claude-agent-acp-plus\", \"args\": [] }"
		elog "    }"
	fi

	if use claude-agent-acp-tui; then
		elog ""
		elog "The claude-agent-acp-tui ACP bridge was installed as 'claude-agent-acp-tui'."
		elog "To enable it in Zed, add to ~/.config/zed/settings.json:"
		elog ""
		elog "    \"agent_servers\": {"
		elog "        \"Claude Agent TUI\": { \"command\": \"claude-agent-acp-tui\", \"args\": [] }"
		elog "    }"
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}
