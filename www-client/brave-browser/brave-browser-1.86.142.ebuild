# Copyright 2011-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="af am ar az bg bn ca cs da de el en-GB en-US es-419 es et fa fi fil fr
	gu he hi hr hu id it ja ka kk km kn ko lo lt lv mk ml mn mr ms my nb nl pl pt-BR
	pt-PT ro ru si sk sl sq sr-Latn sr sv sw ta te th tr uk ur uz vi zh-CN zh-TW"

inherit brave chromium-2 desktop pax-utils unpacker verify-sig xdg

DESCRIPTION="The Brave Web Browser"
HOMEPAGE="https://brave.com/"

if [[ ${PN} == brave-browser ]]; then
	MY_PN=${PN}-stable
else
	MY_PN=${PN}
fi

DEB="${PN}_${PV}_amd64.deb"
SRC_URI="
	https://github.com/brave/brave-browser/releases/download/v${PV}/${DEB}
	verify-sig? (
		https://github.com/brave/brave-browser/releases/download/v${PV}/${DEB}.sha256
		https://github.com/brave/brave-browser/releases/download/v${PV}/${DEB}.sha256.asc
	)
"
S=${WORKDIR}

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+l10n_en-US qt6 selinux"

RESTRICT="
	bindist
	mirror
	strip
	test
"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	>=dev-libs/nss-3.26
	media-fonts/liberation-fonts
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	sys-libs/libcap
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	|| (
		x11-libs/gtk+:3[X]
		gui-libs/gtk:4[X]
	)
	x11-libs/libdrm
	>=x11-libs/libX11-1.5.0
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/libxshmfence
	x11-libs/pango
	x11-misc/xdg-utils
	qt6? ( dev-qt/qtbase:6[gui,widgets] )
	selinux? ( sec-policy/selinux-chromium )
"

if [[ ${PN} == brave-browser ]]; then
	BDEPEND="verify-sig? ( >=sec-keys/openpgp-keys-brave-browser-release-20250709 )"
	VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/brave-browser-release.asc
else
	BDEPEND="verify-sig? ( >=sec-keys/openpgp-keys-brave-browser-pre-release-20250709 )"
	VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/brave-browser-pre-release.asc
fi

BDEPEND+="
	dev-util/desktop-file-utils
"

QA_PREBUILT="*"
QA_DESKTOP_FILE="usr/share/applications/brave-browser.*\\.desktop"
BRAVE_HOME="opt/brave.com/brave${PN#brave-browser}"

pkg_pretend() {
	# Protect against people using autounmask overzealously
	use amd64 || die "brave only works on amd64"
	
	# Check available disk space (~300MB required)
	local disk_space=$(df -P "${PORTAGE_TMPDIR}" 2>/dev/null | awk 'NR==2 {print $4}')
	if [[ -n ${disk_space} ]] && [[ ${disk_space} -lt 307200 ]]; then
		eerror "Insufficient disk space in ${PORTAGE_TMPDIR}"
		eerror "Required: ~300MB, Available: $((disk_space/1024))MB"
		die "Insufficient disk space"
	fi
	
	# Warn about multiple Brave versions
	if has_version "www-client/brave-browser:0" && \
	   has_version "www-client/brave-browser-beta:0"; then
		ewarn "Multiple Brave versions detected."
		ewarn "Consider using only one variant to avoid confusion."
	fi
	
	chromium_suid_sandbox_check_kernel_config
}

pkg_setup() {
	chromium_suid_sandbox_check_kernel_config
}

src_unpack() {
	if use verify-sig; then
		pushd "${DISTDIR}" > /dev/null || die
		verify-sig_verify_detached "${DEB}.sha256"{,.asc}
		{ cat "${DEB}.sha256"; echo; } | \
			verify-sig_verify_unsigned_checksums - sha256 "${DEB}"
		popd > /dev/null || die
	fi

	default
}

src_install() {
	dodir /
	cd "${ED}" || die
	unpacker

	# Clean up temporary and unnecessary files
	find "${ED}" -type f \( -name '*.tmp' -o -name '.git*' \) -delete || die

	# Move appdata to metainfo if it exists (deprecated location)
	# Upstream may have already fixed this in newer versions
	if [[ -d usr/share/appdata ]]; then
		mv usr/share/appdata usr/share/metainfo || die
	fi

	# Rename documentation directory
	mv usr/share/doc/${PN} usr/share/doc/${PF} || die

	# Remove Debian-specific cron jobs (useless on Gentoo)
	rm -r etc/cron.daily || die "Failed to remove cron scripts"
	rm -r "${BRAVE_HOME}"/cron || die "Failed to remove cron scripts"

	# Decompress files - let Portage handle compression automatically
	gzip -d usr/share/doc/${PF}/changelog.gz || die
	gzip -d usr/share/man/man1/${MY_PN}.1.gz || die
	
	# Remove ALL existing brave-browser symlinks from upstream package
	# The .deb contains a symlink pointing to .gz which we just decompressed
	rm -f usr/share/man/man1/brave-browser.1.gz || die
	rm -f usr/share/man/man1/brave-browser.1.bz2 || die
	rm -f usr/share/man/man1/brave-browser.1 || die
	
	# Create new symlink pointing to uncompressed file
	# Portage will compress both files and update symlink automatically
	dosym ${MY_PN}.1 usr/share/man/man1/brave-browser.1

	# Remove unused language packs
	pushd "${BRAVE_HOME}/locales" > /dev/null || die
	chromium_remove_language_paks
	popd > /dev/null || die

	# Remove unused Brave extension language directories
	pushd "${BRAVE_HOME}/resources/brave_extension/_locales" > /dev/null || die
	brave_remove_language_dirs
	popd > /dev/null || die

	# Remove unused Qt shims
	rm "${BRAVE_HOME}/libqt5_shim.so" || die
	if ! use qt6; then
		rm "${BRAVE_HOME}/libqt6_shim.so" || die
	fi

	# Install icons in multiple sizes
	local suffix=${PN#*browser}
	suffix=${suffix//-/_}

	local size icon_installed=0
	for size in 16 24 32 48 64 128 256 ; do
		[[ -f "${BRAVE_HOME}/product_logo_${size}${suffix}.png" ]] && \
			newicon -s ${size} "${BRAVE_HOME}/product_logo_${size}${suffix}.png" ${PN}.png && \
			icon_installed=1
	done
	[[ ${icon_installed} -eq 0 ]] && die "No program icons could be installed."

	# Validate desktop files to detect integration issues
	local desktop_file
	for desktop_file in "${ED}"/usr/share/applications/*.desktop; do
		[[ -f ${desktop_file} ]] || continue
		desktop-file-validate "${desktop_file}" || \
			ewarn "Desktop file validation failed for ${desktop_file}"
	done

	# Mark main executable with PaX (protection against exploits)
	pax-mark m "${ED}/${BRAVE_HOME}/brave"
	
	# Verify chrome-sandbox exists and set SUID permissions
	[[ ! -f "${ED}/${BRAVE_HOME}/chrome-sandbox" ]] && \
		die "chrome-sandbox not found"
	
	fperms 4755 "/${BRAVE_HOME}/chrome-sandbox"
}

pkg_postinst() {
	xdg_pkg_postinst
	
	elog "Brave browser has been installed."
	elog ""
	elog "For custom policies, create:"
	elog "  /etc/brave/policies/managed/"
	elog ""
	elog "To enable hardware acceleration:"
	elog "  brave-browser --enable-features=VaapiVideoDecoder"
	elog ""
	
	if use qt6; then
		elog "Qt6 support is enabled for better KDE/Qt integration"
		elog ""
	fi
	
	if ! use selinux; then
		ewarn "SELinux support is not enabled."
		ewarn "If you use SELinux, recompile with USE=selinux"
		ewarn ""
	fi
	
	if has_version "app-admin/eselect-browser"; then
		elog "To set Brave as your default browser:"
		elog "  eselect browser set brave-browser"
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}